import Foundation

#if os(macOS)

/// Why the app cannot reach the service, in the words of whoever is looking.
///
/// "没有连接到 daily-os 服务" and "读不到服务的配置" are both true of four
/// completely different situations, and the fix is different in each. Handing
/// someone a sentence that covers all four means handing them nothing: the one
/// this shipped with sent a person to "去设置里指定服务文件夹" on a machine
/// where the service had never been installed, so there was no folder to
///指定 and the advice was a dead end.
///
/// Everything here is a local filesystem read. Nothing asks the network, which
/// is the point — the network is the thing that already failed.
public enum ServiceDiagnosis: Equatable {
  /// Nothing found anywhere. Most likely the service was never installed on
  /// this machine.
  case notFound
  /// A checkout exists but has never been started, so it has no `ui.json` and
  /// therefore no address to dial.
  case neverStarted(root: URL)
  /// It has run before and there is a runtime file, but nothing answered. The
  /// service is installed and stopped, or crashed.
  case notRunning(root: URL, isManagedByLaunchd: Bool)
  /// Found, running, answering — a failure somewhere past discovery.
  case reachable

  public static func evaluate(root: URL?) -> ServiceDiagnosis {
    guard let root else { return .notFound }
    guard RepoRoot.hasRun(root) else { return .neverStarted(root: root) }
    return .notRunning(root: root, isManagedByLaunchd: ServiceSupervisor.isInstalled)
  }

  /// One line, for a banner.
  public var headline: String {
    switch self {
    case .notFound: "这台电脑上没找到 daily-os 服务"
    case .neverStarted: "找到了服务，但它从来没启动过"
    case .notRunning: "服务装好了，但现在没在跑"
    case .reachable: "已连接"
    }
  }

  /// What to actually do, written for whoever is standing at the machine —
  /// which, on a teammate's Mac, is not the person who set any of this up.
  public var advice: String {
    switch self {
    case .notFound:
      """
      Daily OS 是本机那个 daily-os 服务的客户端，它自己不存数据。这台电脑上还没有那个服务：\
      launchd 里没有登记，常见的代码目录里没有，Spotlight 也没搜到。
      先把服务装起来（在服务目录里跑 npm install 和 npm run service:install），\
      装完这个 App 会自己找到它。如果服务其实装在别处，用下面的按钮手动指一下。
      """
    case .neverStarted(let root):
      """
      \(root.path(percentEncoded: false)) 看起来是服务目录，但它从来没启动过——\
      data/runtime/ui.json 还不存在，而 App 就是靠那个文件知道服务的地址和令牌的。
      在那个目录里跑一次 npm run service:install（或者先 npm run ui 手动起一次），之后回来重试。
      """
    case .notRunning(let root, let managed):
      managed
        ? """
        服务在 \(root.path(percentEncoded: false))，已经登记成开机自启，但现在没有应答。\
        Daily OS 会在启动时试着把它拉起来；如果反复失败，看看 logs/launchd.err.log。
        """
        : """
        服务在 \(root.path(percentEncoded: false))，但没有装成后台任务，所以只有你手动开着的时候才活着。\
        在那个目录里跑 npm run service:install，之后它会开机自启，Daily OS 也能自己把它拉起来。
        """
    case .reachable:
      ""
    }
  }

  /// Whether offering "手动指定文件夹" makes any sense. It does not when the
  /// problem is that the service has never been started — the folder is already
  /// correct, and picking it again changes nothing.
  public var wantsFolderPicker: Bool {
    if case .notFound = self { return true }
    return false
  }
}

#endif
