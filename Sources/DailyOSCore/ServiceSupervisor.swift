import Foundation

#if os(macOS)

/// Starts and stops the daily-os service's launch agent.
///
/// **The app does not own the service process, and should not.** Making the
/// service a child of this app would be the obvious reading of "let the Mac app
/// start it", and it would quietly break the product: the service is what runs
/// the morning `daily_plan`, the evening review and every other scheduled
/// workflow. Tie its lifetime to a window and those only happen on days you
/// remembered to open the app — and the whole point of a daily briefing is that
/// it arrives without being asked.
///
/// So the app supervises rather than hosts. launchd keeps owning the process:
/// it starts at login, survives the app quitting, and restarts on crash. What
/// changes is that the app now *checks and fixes* that on launch instead of
/// showing a wall and leaving you to run `launchctl` yourself.
///
/// Lives in `DailyOSCore` rather than in `DailyOSClient` because both the
/// screens and the transport need it and only one of them can import the other.
/// It is process control, not transport — there is no HTTP here — so the
/// module boundary the split protects is not the one being crossed.
public enum ServiceSupervisor {
  public static let label = "com.daily-os-feishu.agent"

  public static var plistURL: URL {
    URL.homeDirectory.appending(path: "Library/LaunchAgents/\(label).plist")
  }

  /// The agent has been registered by `npm run service:install`.
  public static var isInstalled: Bool {
    FileManager.default.fileExists(atPath: plistURL.path(percentEncoded: false))
  }

  private static var domain: String { "gui/\(getuid())" }

  /// Whether launchd currently has the job loaded. Not the same as "the HTTP
  /// server is answering" — a job can be loaded and still starting up, which is
  /// exactly the window that made the app report "服务没在跑" about a service
  /// that was two seconds from being ready.
  public static func isLoaded() async -> Bool {
    await run(["print", "\(domain)/\(label)"]).status == 0
  }

  /// The service's process id, or nil when launchd has the job but nothing is
  /// running under it.
  ///
  /// The only question worth asking after a start. "Loaded" is not "running",
  /// and during a replacement launchd will answer "loaded" about a job that is
  /// on its way out — so a start that checked only for loaded reported success,
  /// left no process behind, and wrote nothing to any log.
  public static func runningPID() async -> Int? {
    let result = await run(["list"])
    guard result.status == 0 else { return nil }
    for line in result.output.split(separator: "\n") {
      let columns = line.split(separator: "\t")
      guard columns.count >= 3, columns[2] == label else { continue }
      return Int(columns[0])
    }
    return nil
  }

  /// Bring the service up, whatever state it is in.
  ///
  /// `kickstart` starts a loaded job and does nothing useful for one that was
  /// never bootstrapped, so an unloaded job is bootstrapped first. Both are
  /// idempotent enough to call on every launch.
  ///
  /// **Succeeds only when a process is actually running.** That distinction is
  /// the whole reason this is more than two launchctl calls. Replacing an
  /// existing agent — which is what an app update does — hits a window where
  /// launchd keeps answering questions about the outgoing job: `bootout`
  /// returned, the poll for the label to disappear timed out, `isLoaded` said
  /// yes, so bootstrap was skipped, `kickstart` reached the dying job and exited
  /// 0, and every check passed. Nothing was running, no log file was ever
  /// created, and the install announced that it had started the service.
  ///
  /// So: settle, then ask for a pid, and on a retry stop trusting anything
  /// launchd said before and tear the label down first.
  public static func start() async throws {
    var lastError = "launchctl 没能启动服务"
    for attempt in 1...5 {
      if attempt > 1 { _ = await bootout() }

      if await !isLoaded() {
        let bootstrap = await run(["bootstrap", domain, plistURL.path(percentEncoded: false)])
        // Exit 5 — "Input/output error" — used to be excused here as "already
        // bootstrapped". It is not: launchd says that about a label it is still
        // tearing down, and excusing it turned a failed bootstrap into a silent
        // one. "Already bootstrapped" never reaches this line anyway, because
        // `isLoaded` above is exactly that question.
        if bootstrap.status != 0 {
          lastError = "launchctl bootstrap 失败：\(bootstrap.output)"
          try? await Task.sleep(for: .seconds(1))
          continue
        }
      }
      _ = await run(["kickstart", "\(domain)/\(label)"])

      // Long enough for launchd to finish whatever it was doing to the old job
      // and for the new one to be spawned. A check taken immediately is the
      // check that was already being passed by a service that did not exist.
      try? await Task.sleep(for: .milliseconds(1500))
      if await runningPID() != nil { return }
      lastError = "服务已登记，但 launchd 里没有它的进程号——没能真正跑起来"
    }
    throw Failure(lastError)
  }

  /// Restart, for picking up a rebuilt `dist/`.
  public static func restart() async throws {
    let result = await run(["kickstart", "-k", "\(domain)/\(label)"])
    if result.status != 0 {
      throw Failure("重启失败：\(result.output)")
    }
  }

  /// Unregister the job entirely.
  ///
  /// Only used when replacing an agent that points at an older app bundle:
  /// `bootstrap` refuses a label that is already loaded, and that refusal reads
  /// as "the install did nothing" while the stale job carries on running the
  /// previous version's code. Returns success rather than throwing, because
  /// "there was nothing loaded" is the normal case on a first install.
  ///
  /// Waits for the label to actually go away. `launchctl bootout` returns while
  /// launchd is still tearing the job down, and for that moment every question
  /// about the job gets the pre-teardown answer — which is how an install that
  /// replaced a working agent ended up with no agent loaded at all.
  @discardableResult
  public static func bootout() async -> Bool {
    let ok = await run(["bootout", "\(domain)/\(label)"]).status == 0
    // Up to 15s. Two seconds looked like plenty — from a terminal the label is
    // gone in twenty milliseconds — and was not: the service has a database to
    // close, and the app's own poll timed out while launchd still considered
    // the job present, which is precisely the state `start` must not act on.
    for _ in 1...150 {
      if await !isLoaded() { return ok }
      try? await Task.sleep(for: .milliseconds(100))
    }
    return ok
  }

  /// Stop until the next login. Deliberately not `bootout` — that unregisters
  /// the job, and someone stopping the service for an hour does not mean they
  /// want it gone after a reboot.
  public static func stop() async throws {
    let result = await run(["kill", "SIGTERM", "\(domain)/\(label)"])
    if result.status != 0 {
      throw Failure("停止失败：\(result.output)")
    }
  }

  public struct Failure: LocalizedError {
    public let errorDescription: String?
    init(_ message: String) { errorDescription = message }
  }

  /// `launchctl` only. Never a shell, and never a string the caller composed:
  /// arguments go to `Process` as an array, so a path with a space in it is a
  /// path with a space in it rather than two arguments.
  private static func run(_ arguments: [String]) async -> (status: Int32, output: String) {
    await withCheckedContinuation { continuation in
      let process = Process()
      process.executableURL = URL(filePath: "/bin/launchctl")
      process.arguments = arguments
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = pipe
      do {
        try process.run()
      } catch {
        continuation.resume(returning: (-1, error.localizedDescription))
        return
      }
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      let output = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      continuation.resume(returning: (process.terminationStatus, output))
    }
  }
}

#endif
