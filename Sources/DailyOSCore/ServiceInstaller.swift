import Foundation

#if os(macOS)

/// Brings the bundled service up on a machine that has never seen it.
///
/// The whole point: installing is dragging the app to /Applications. No clone,
/// no `npm install`, no `npm run service:install`. A product that asks someone
/// to stand up a Node service before its window is useful is a product with two
/// installers, and the second one is the one that fails.
///
/// **Code and data are deliberately in different places.** The service lives
/// read-only in `Daily OS.app/Contents/Resources/service`; everything it writes
/// goes to `~/Library/Application Support/DailyOS`. An app bundle is replaced
/// wholesale on update, so anything written inside it is destroyed the first
/// time the app is upgraded — config, `.env`, the SQLite database, all of it.
///
/// **launchd still owns the process, not this app.** The service runs the
/// morning plan and the evening review; tying it to a window means those only
/// happen on days someone remembered to open one. What changed is that the app
/// now writes the launch agent itself, pointing at its own bundled payload,
/// instead of asking a person to run an installer script.
public enum ServiceInstaller {
  /// Where the service keeps everything it writes.
  public static var dataDirectory: URL {
    URL.homeDirectory.appending(path: "Library/Application Support/DailyOS")
  }

  /// The service payload inside this app bundle, or nil in a build that has
  /// none — the SwiftPM `swift build` output, for one, which is the form every
  /// test and preview runs in.
  public static var bundledPayload: (node: URL, entry: URL)? {
    guard let resources = Bundle.main.resourceURL else { return nil }
    let node = resources.appending(path: "node")
    let entry = resources.appending(path: "service/dist/index.js")
    let fm = FileManager.default
    // `percentEncoded: false` is load-bearing, not tidiness. `URL.path()`
    // escapes by default, so this app's own bundle — "/Applications/Daily
    // OS.app", which has a space in it and always will — became
    // "Daily%20OS.app", no such file, payload reported missing. `isBundled`
    // then said false, the installer was skipped with no error at all, and the
    // app fell through to hunting for a developer checkout. A bug that only
    // appears when a path contains a space is a bug that never appears on the
    // machine it was written on.
    guard fm.isExecutableFile(atPath: node.path(percentEncoded: false)),
          fm.fileExists(atPath: entry.path(percentEncoded: false))
    else {
      return nil
    }
    return (node, entry)
  }

  public static var isBundled: Bool { bundledPayload != nil }

  /// What the installed launch agent currently points at. Used to notice that
  /// the app moved or was updated — a plist naming a bundle that is no longer
  /// there is a service that will never start again, and launchd reports that
  /// as a job which simply keeps failing.
  public static func installedPayloadPath() -> String? {
    guard let data = try? Data(contentsOf: ServiceSupervisor.plistURL),
          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
          let root = plist as? [String: Any],
          let args = root["ProgramArguments"] as? [String],
          args.count >= 2
    else { return nil }
    return args[1]
  }

  public enum Step: Equatable {
    case preparingFiles
    case registering
    case starting
    case done
  }

  /// Make the data directory, write the launch agent, start the service.
  ///
  /// Idempotent: safe to run on every launch, and it has to be, because that is
  /// how an app update gets the agent repointed at the new bundle.
  public static func install(progress: @MainActor (Step) -> Void = { _ in }) async throws {
    guard let payload = bundledPayload else {
      throw Failure("这个 App 里没有打包服务，装不了。用 scripts/package.sh 重新打一个包。")
    }

    await MainActor.run { progress(.preparingFiles) }
    let fm = FileManager.default
    try fm.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
    note("开始安装 · \(payload.entry.path(percentEncoded: false))")

    // Stop whatever is running under this label before touching any of its
    // files. Two reasons, and the second is the one that bites: `bootstrap` on
    // an already-loaded label fails, so a stale job would keep running while
    // the install looked like it had done nothing — and a live SQLite database
    // copied out from under its own writer is a database with a torn WAL.
    note(await ServiceSupervisor.bootout() ? "已停掉原有的后台任务" : "没有原有的后台任务需要停")
    // The service creates config, .env and its database itself on first start
    // (`ensureLocalSetup`), sourcing the templates from the payload — so a
    // machine that has never run it needs nothing seeded here.
    //
    // A machine that *has* is the other half of the story, and the half that
    // bites: pointing the service at a brand-new working directory would leave
    // an existing user staring at an empty app while their config, database and
    // notes sat untouched in a checkout the app no longer reads.
    adoptLegacyData()

    await MainActor.run { progress(.registering) }
    do {
      try writeLaunchAgent(node: payload.node, entry: payload.entry)
    } catch {
      note("✗ 写 launchd 配置失败：\(error.localizedDescription)")
      throw error
    }
    note("已写 launchd 配置 \(ServiceSupervisor.plistURL.path(percentEncoded: false))")

    primeProtectedFolders()

    await MainActor.run { progress(.starting) }
    do {
      try await ServiceSupervisor.start()
    } catch {
      note("✗ 启动失败：\(error.localizedDescription)")
      throw error
    }
    // Only after a start that actually produced a process. Writing the marker
    // earlier would make a failed install look done, and the next launch would
    // skip the retry that would have fixed it.
    try? currentBuild.write(to: buildMarkerURL, atomically: true, encoding: .utf8)
    note("✓ 服务已启动 · \(currentBuild)")
    await MainActor.run { progress(.done) }
  }

  /// Ask macOS for the folders the service will need — from the app, while the
  /// app is in front and can actually show the dialog.
  ///
  /// This is not a nicety. The service reads a vault that normally lives in
  /// `~/Desktop` or `~/Documents`, and a launchd job that touches one without
  /// permission does not get an error: the read **hangs**, indefinitely,
  /// because the consent dialog has nowhere to appear. The service then answers
  /// no requests at all while looking perfectly alive — one process, one open
  /// port, an empty error log.
  ///
  /// TCC records the grant against `com.example.dailyos.mac` — the bundled
  /// `node` is attributed to the app that contains it, which `tccd` confirms in
  /// its own log — so a "好" clicked here is what lets the background service
  /// read the vault later.
  ///
  /// Both folders, rather than the one the config names: config belongs to the
  /// service, this runs before the service has ever started, and two dialogs
  /// once beats a service that silently does nothing.
  ///
  /// Started and **not waited for**, on a detached task. Both halves of that
  /// matter. The call blocks until the dialog is answered,
  /// so on the main thread it is a beachball behind a dialog asking the user to
  /// trust the app — and awaiting it anywhere would hang the whole install on a
  /// question nobody is obliged to answer right now. Walking away from the
  /// dialog would then mean walking away from a half-installed service.
  ///
  /// Letting it run unattended is also what makes a late "好" useful: a read
  /// blocked on an undecided grant resumes the moment the decision is made, so
  /// a service that wedged on the vault un-wedges itself when the user answers,
  /// without anything having to notice.
  private static func primeProtectedFolders() {
    Task.detached(priority: .utility) {
      for name in ["Desktop", "Documents"] {
        let folder = URL.homeDirectory.appending(path: name)
        _ = try? FileManager.default.contentsOfDirectory(
          at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )
      }
      note("桌面／文稿访问权限已有结论")
    }
    note("已向系统申请桌面／文稿访问权限（不等待回答）")
  }

  /// A line in `logs/install.log`.
  ///
  /// The install is four steps deep in someone else's `~/Library`, and when it
  /// goes wrong the app can show one sentence about it at most — on a machine
  /// whose owner did not write any of this and cannot be walked through
  /// `launchctl print`. Nothing here is secret: paths and launchctl's own words.
  static func note(_ line: String) {
    let stamp = ISO8601DateFormatter().string(from: .now)
    guard let data = "\(stamp) \(line)\n".data(using: .utf8) else { return }
    let url = dataDirectory.appending(path: "logs/install.log")
    try? FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    if let handle = try? FileHandle(forWritingTo: url) {
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
    } else {
      try? data.write(to: url)
    }
  }

  /// Carry an existing checkout's data across, once.
  ///
  /// Only for someone who ran the old two-step install: their `.env`, their
  /// `config.yaml` and eleven megabytes of memory, ledgers and SQLite live in a
  /// git checkout, and the bundled service works somewhere else entirely. Doing
  /// nothing here would not lose that data, but it would hide it, which the
  /// person on the other end cannot tell apart from losing it.
  ///
  /// **Copies, never moves.** The checkout stays exactly as it was, so a
  /// migration that goes wrong costs nothing but disk. It stops being written to
  /// — the launch agent is repointed a moment later — so treat it as a snapshot
  /// of the day you upgraded, not as a second live copy.
  ///
  /// Silent on failure by design. This is a convenience on top of an install
  /// that is complete without it; a permissions error on one file should not
  /// turn "your app is ready" into "installation failed".
  ///
  /// One thing it deliberately does not fix: config values written relative to
  /// the checkout's *parent* (`workdir: ../calendar-planning-os`) now resolve
  /// against `~/Library/Application Support`. Rewriting somebody's config by
  /// pattern-match is a worse bet than leaving one setting to be repaired by
  /// hand — `./data/...` paths, which is nearly all of them, travel fine.
  private static func adoptLegacyData() {
    let fm = FileManager.default
    // Anything already here means this is not a first run — an app update, a
    // reinstall, a second account. Re-copying then would overwrite live data
    // with a snapshot, which is the one outcome worse than doing nothing.
    guard !fm.fileExists(atPath: dataDirectory.appending(path: "data").path(percentEncoded: false)),
          !fm.fileExists(atPath: dataDirectory.appending(path: "config/config.yaml").path(percentEncoded: false)),
          let legacy = RepoRoot.discover(),
          // Discovery now legitimately answers with the managed directory
          // itself, on any machine where a previous install already ran.
          legacy.path(percentEncoded: false) != dataDirectory.path(percentEncoded: false),
          fm.fileExists(atPath: legacy.appending(path: "config/config.yaml").path(percentEncoded: false))
    else { return }

    note("从 \(legacy.path(percentEncoded: false)) 迁移原有数据")
    // memory-vault holds OKR, cycles, commitments and decision rules. It is not
    // under data/, and the service resolves it relative to its working directory
    // (the managed dir), so leaving it behind silently emptied every one of them
    // after a checkout → package upgrade. See daily-os-macos #3.
    for item in ["data", "config", ".env", "memory-vault"] {
      let source = legacy.appending(path: item)
      guard fm.fileExists(atPath: source.path(percentEncoded: false)) else { continue }
      do {
        try fm.copyItem(at: source, to: dataDirectory.appending(path: item))
      } catch {
        note("  ✗ \(item)：\(error.localizedDescription)")
      }
    }

    // `ui.json` is the address and token of the service that *was* running
    // there. Carrying it over would hand the app a stale port to dial and a
    // token for a process that no longer exists; the new service writes its own
    // within a second of starting.
    try? fm.removeItem(at: dataDirectory.appending(path: "data/runtime/ui.json"))
  }

  /// Whether the agent on disk describes *this* bundle.
  ///
  /// False after the app is updated or moved, which is exactly when the service
  /// would otherwise keep running yesterday's code — or stop starting at all,
  /// if the old bundle is gone.
  public static func needsInstall() -> Bool {
    guard let payload = bundledPayload else { return false }
    guard let installed = installedPayloadPath() else { return true }
    if installed != payload.entry.path(percentEncoded: false) { return true }
    // Same path, different build. An app update replaces the bundle in place,
    // so the plist keeps naming a file that is now a *newer* service — and
    // launchd, having no reason to think anything changed, keeps the old
    // process running indefinitely. Shipping a service fix and watching the
    // machine run yesterday's copy of it is not an update.
    return installedBuild() != currentBuild
  }

  /// Identifies the build whose service is currently registered.
  ///
  /// Recorded next to the data rather than derived from the bundle, because the
  /// question is "which build's install ran here", and after the bundle is
  /// replaced it can no longer answer that about itself.
  private static var buildMarkerURL: URL {
    dataDirectory.appending(path: "logs/installed-build")
  }

  private static func installedBuild() -> String? {
    try? String(contentsOf: buildMarkerURL, encoding: .utf8)
  }

  /// Version plus commit plus build time. The commit alone is not enough: an
  /// uncommitted build is the one being tested, and two of those in a row have
  /// the same hash and different code.
  private static var currentBuild: String {
    let info = Bundle.main.infoDictionary ?? [:]
    return [
      info["CFBundleShortVersionString"] as? String,
      info["DailyOSBuildCommit"] as? String,
      info["DailyOSBuildDate"] as? String,
    ]
    .compactMap { $0 }
    .joined(separator: " ")
  }

  private static func writeLaunchAgent(node: URL, entry: URL) throws {
    let agents = URL.homeDirectory.appending(path: "Library/LaunchAgents")
    try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)

    let plist: [String: Any] = [
      "Label": ServiceSupervisor.label,
      // The *data* directory, not the payload. Every relative path the service
      // resolves — data/runtime/ui.json, the database, config/config.yaml —
      // hangs off this.
      "WorkingDirectory": dataDirectory.path(percentEncoded: false),
      "ProgramArguments": [
        node.path(percentEncoded: false),
        entry.path(percentEncoded: false),
        "start",
        "--no-open",
      ],
      "RunAtLoad": true,
      "KeepAlive": true,
      "StandardOutPath": dataDirectory.appending(path: "logs/service.out.log").path(percentEncoded: false),
      "StandardErrorPath": dataDirectory.appending(path: "logs/service.err.log").path(percentEncoded: false),
      // A GUI app inherits a minimal PATH, and a launchd job inherits less than
      // that. The service shells out (git, and the skill CLIs when present), so
      // without this those lookups fail in ways that read as the feature being
      // broken rather than as a missing PATH.
      "EnvironmentVariables": [
        "PATH": "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin",
      ],
    ]

    try FileManager.default.createDirectory(
      at: dataDirectory.appending(path: "logs"),
      withIntermediateDirectories: true
    )
    let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    try data.write(to: ServiceSupervisor.plistURL, options: .atomic)
  }

  public struct Failure: LocalizedError {
    public let errorDescription: String?
    init(_ message: String) { errorDescription = message }
  }
}

#endif
