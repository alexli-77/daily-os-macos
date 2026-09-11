import Foundation
import Observation
import DailyOSCore

/// Whether the app is talking to a service, and why not when it is not.
///
/// Kept as an explicit state rather than as an optional client, because every
/// failure here has a different remedy and the screen has to say which one. The
/// old prototype collapsed all of these into "could not connect", which is the
/// least useful sentence available: it is true whether the service is stopped,
/// the folder is wrong, or the app has never been pointed at anything.
public enum ConnectionState: Sendable, Equatable {
  /// No repo picked yet. First launch.
  case unconfigured
  case connecting
  case connected(endpoint: String)
  case failed(reason: String)

  public var isConnected: Bool {
    if case .connected = self { return true }
    return false
  }

  /// Still looking. The only state that gets a full-window wall, because it is
  /// the only one where waiting is the correct thing for the user to do.
  public var isConnecting: Bool {
    if case .connecting = self { return true }
    return false
  }

  public var label: String {
    switch self {
    case .unconfigured: "未连接"
    case .connecting: "连接中…"
    case .connected: "已连接"
    case .failed: "连接失败"
    }
  }

  public var tone: Tone {
    switch self {
    case .unconfigured: .neutral
    case .connecting: .neutral
    case .connected: .ok
    case .failed: .danger
    }
  }
}

/// Owns the repo path and hands out a client for it.
///
/// The path is the one piece of configuration this app genuinely needs: the
/// service writes its address and token into `data/runtime/ui.json` inside its
/// own checkout, so knowing where that checkout is turns into knowing
/// everything else. Nothing else has to be configured, and nothing else should
/// be — a second setting here would be a second thing to get wrong.
@Observable
@MainActor
public final class ServiceConnection {
  public private(set) var state: ConnectionState
  public private(set) var repoRoot: URL?
  public private(set) var client: DailyOSClient?

  /// True when the folder was found rather than chosen, so the setup screen can
  /// say so. A path that appears on its own with no explanation is unsettling in
  /// a way that costs more trust than the picker it replaced.
  public private(set) var wasDiscovered = false

  /// Cheap on purpose: one `UserDefaults` read and nothing else.
  ///
  /// This used to call `RepoRoot.discover()`, which touches the filesystem and
  /// can shell out to `mdfind`. `ServiceConnection()` is a `@State` initialiser
  /// in `DailyOSApp`, so that ran **synchronously on the main thread before any
  /// window existed** — and on a machine where the launch agent was missing, so
  /// the cheap first branch did not short-circuit it, the directory scan hung
  /// and the app never drew anything at all. No window, no error, just a Dock
  /// icon. Discovery moved to `bringUp`, which is async and can say what it is
  /// doing while it works.
  public init(repoRoot: URL? = RepoRoot.stored()) {
    self.repoRoot = repoRoot
    self.state = repoRoot == nil ? .unconfigured : .connecting
    if let repoRoot {
      self.client = DailyOSClient(repoRoot: repoRoot)
    }
  }

  /// Point at a checkout. Rejects an obviously wrong folder here rather than
  /// letting it fail later as a confusing decode error.
  public func use(repoRoot url: URL) {
    guard RepoRoot.isUsable(url) else {
      state = .failed(reason: "这个文件夹里既没有 daily-os 服务代码，也没有 data/runtime/ui.json。选服务代码所在的那个文件夹，或者 App 自己管理的数据目录。")
      return
    }
    wasDiscovered = false
    RepoRoot.store(url)
    repoRoot = url
    client = DailyOSClient(repoRoot: url)
    state = .connecting
  }

  /// What the app is doing right now, for the setup screen to say out loud.
  public private(set) var activity = ""

  /// Get to a working connection, starting the service if that is what is
  /// missing.
  ///
  /// The old launch path was a single `probe()`. One probe is wrong in the most
  /// ordinary situation there is: at login, launchd starts the login items and
  /// the agent at roughly the same moment, so the app frequently asks before
  /// the service has finished binding its port — and then shows "服务没在跑" for
  /// a service that was two seconds away, with no retry and no way forward
  /// except a button the user has to know to press.
  ///
  /// So: probe, and if that fails, start the agent and keep asking for a while.
  public func bringUp() async {
    // Install first, when the app carries its own service and the machine has
    // never had it — or has an agent still pointing at an older bundle. This is
    // the one-step deployment: dragging the app to /Applications *is* the
    // install, and the second half of it happens here rather than in a terminal
    // somebody else has to be talked through.
    if ServiceInstaller.isBundled, ServiceInstaller.needsInstall() {
      await installBundledService()
      // Any outcome is final. Falling through on failure let the *next* branch
      // discover a developer checkout on this machine and report on that
      // instead — so a broken install reported "服务装好了，但现在没在跑" about
      // a completely different service, and the actual error was never shown.
      if case .failed = state { return }
      if state.isConnected { return }
    }

    // Discovery lives here rather than in `init` so it cannot block the first
    // frame, and `Task.detached` keeps the filesystem walk off the main actor
    // entirely — a scan that takes two seconds should cost two seconds of
    // "正在找服务…", not two seconds of a frozen window.
    if client == nil {
      activity = "正在找这台电脑上的服务…"
      state = .connecting
      let found = await Task.detached(priority: .userInitiated) { RepoRoot.discover() }.value
      if let found {
        RepoRoot.store(found)
        repoRoot = found
        wasDiscovered = true
        client = DailyOSClient(repoRoot: found)
      }
    }

    guard client != nil else {
      activity = ""
      state = .unconfigured
      return
    }

    activity = "正在连接服务…"
    await probe()
    if state.isConnected { activity = ""; return }

    guard ServiceSupervisor.isInstalled else {
      // Nothing to start. The service is being run by hand, so the honest
      // report is the probe's own reason plus what would fix it for good.
      activity = ""
      if case .failed(let reason) = state {
        state = .failed(reason: "\(reason)\n\n这台机器没有把服务装成开机自启的后台任务。在服务目录里执行 `npm run service:install`，之后 Daily OS 会自己把它拉起来。")
      }
      return
    }

    activity = "服务没有响应，正在启动…"
    do {
      try await ServiceSupervisor.start()
    } catch {
      state = .failed(reason: "启动服务失败：\(error.localizedDescription)")
      activity = ""
      return
    }

    // Node has to boot, read config and bind a port; a fixed sleep would either
    // be too short on a cold cache or waste time on a warm one, so this asks
    // repeatedly and stops the moment it works.
    for attempt in 1...16 {
      try? await Task.sleep(for: .milliseconds(700))
      activity = "等服务就绪…（\(attempt * 7 / 10)s）"
      await probe()
      if state.isConnected { activity = ""; return }
    }

    activity = ""
    state = .failed(reason: "服务已经启动，但十几秒后仍然没有响应。看看它的日志：logs/launchd.err.log。")
  }

  /// First run on a machine, or the first run after an app update.
  ///
  /// Points `repoRoot` at the managed data directory rather than at a checkout,
  /// and runs *before* discovery rather than after it: a bundled app that found
  /// a checkout first would keep talking to whatever the previous install left
  /// behind, and would never pick up its own newer service after an update.
  /// An existing checkout is not ignored — `ServiceInstaller` copies its data
  /// into the managed directory once, on the first install only.
  ///
  /// A developer who wants the app pointed at the tree they are editing still
  /// can: Settings 里的服务文件夹 overrides this and is remembered.
  private func installBundledService() async {
    activity = "第一次启动，正在安装本机服务…"
    state = .connecting
    do {
      try await ServiceInstaller.install { step in
        self.activity = switch step {
        case .preparingFiles: "正在准备数据目录…"
        case .registering: "正在登记后台任务…"
        case .starting: "正在启动服务…"
        case .done: "服务已启动，正在连接…"
        }
      }
    } catch {
      activity = ""
      state = .failed(reason: "安装本机服务失败：\(error.localizedDescription)")
      return
    }

    let managed = ServiceInstaller.dataDirectory
    RepoRoot.store(managed)
    repoRoot = managed
    wasDiscovered = true
    client = DailyOSClient(repoRoot: managed)

    // The service has to boot, create its config and database, and bind a port.
    // On a genuinely first run that is the slowest this app ever is, so the
    // wait is longer than the ordinary restart path and says what it is doing.
    for attempt in 1...30 {
      try? await Task.sleep(for: .milliseconds(700))
      activity = "首次启动要建数据库，稍等…（\(attempt * 7 / 10)s）"
      await probe()
      if state.isConnected { activity = ""; return }
    }
    activity = ""
    state = .failed(reason: """
      服务装好也起来了，但二十秒内没有应答。最常见的原因是系统隐私权限：\
      如果你的 vault 在桌面、文稿或 iCloud 里，后台服务读它的时候会被系统挂住——\
      既弹不出授权框，也不会报错。在「完全磁盘访问权限」里把 Daily OS 打开再试。
      日志：\(managed.path(percentEncoded: false))/logs/service.out.log
      """)
  }

  /// Re-read the stored folder and reconnect, after Settings changed it.
  public func adoptStoredRoot() async {
    guard let stored = RepoRoot.stored(), stored != repoRoot else { return }
    wasDiscovered = false
    repoRoot = stored
    client = DailyOSClient(repoRoot: stored)
    state = .connecting
    await bringUp()
  }

  /// Confirm the service answers. Cheap on purpose — the point is to fail fast
  /// with a specific reason, not to fetch anything.
  ///
  /// An already-connected connection is *not* moved back to `.connecting` while
  /// it re-checks. It was, and the window is keyed on `isConnected`: every
  /// refresh dropped the whole app back to the setup screen for one frame and
  /// then returned. From the outside that reads as the app crashing and
  /// recovering. A re-check that finds trouble still reports it — this only
  /// stops the optimistic state from flickering on the way there.
  public func probe() async {
    guard let client else {
      state = .unconfigured
      return
    }
    if !state.isConnected { state = .connecting }
    do {
      let endpoint = try await client.currentEndpoint()
      _ = try await client.serviceStatus()
      state = .connected(endpoint: endpoint.url.absoluteString)
    } catch let error as ClientError {
      state = .failed(reason: error.errorDescription ?? "未知错误")
    } catch {
      state = .failed(reason: error.localizedDescription)
    }
  }
}
