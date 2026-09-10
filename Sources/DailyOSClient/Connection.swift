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

  /// Falls back to `RepoRoot.discover()` — the launch agent knows where the
  /// service lives, so on a machine where it is installed there is nothing to
  /// ask. Asking anyway is how the first screen ended up demanding a word
  /// ("仓库") from the one person most likely not to have set any of it up.
  public init(repoRoot: URL? = RepoRoot.stored()) {
    let resolved = repoRoot ?? RepoRoot.discover()
    self.wasDiscovered = repoRoot == nil && resolved != nil
    self.repoRoot = resolved
    self.state = resolved == nil ? .unconfigured : .connecting
    if let resolved {
      // Remembered immediately, so a discovery that works once is not repeated
      // on every launch — and so moving the folder later still means one picker.
      RepoRoot.store(resolved)
      self.client = DailyOSClient(repoRoot: resolved)
    }
  }

  /// Point at a checkout. Rejects an obviously wrong folder here rather than
  /// letting it fail later as a confusing decode error.
  public func use(repoRoot url: URL) {
    guard RepoRoot.looksValid(url) else {
      state = .failed(reason: "这个文件夹里没有 daily-os 服务（找不到 package.json 和 src/ui）。选服务代码所在的那个文件夹，不是它里面的某一层。")
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
    guard client != nil else {
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
