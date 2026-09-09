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
    guard RepoRoot.looksValid(url) else {
      state = .failed(reason: "这个目录看起来不是 daily-os 服务仓库（缺 package.json 或 src/ui）。")
      return
    }
    RepoRoot.store(url)
    repoRoot = url
    client = DailyOSClient(repoRoot: url)
    state = .connecting
  }

  /// Confirm the service answers. Cheap on purpose — the point is to fail fast
  /// with a specific reason, not to fetch anything.
  public func probe() async {
    guard let client else {
      state = .unconfigured
      return
    }
    state = .connecting
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
