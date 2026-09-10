import Foundation

// The transport to the local daily-os service.
//
// Every endpoint module in this target is written against this file. It is
// deliberately small: discovery, auth, one request method, one error type.

// MARK: - Discovery

/// Where the service is and how to talk to it.
///
/// Both come from `data/runtime/ui.json`, which the service rewrites on every
/// start. That file is why this app needs no sign-in screen: the token in it
/// authenticates as admin, so a client running on the same machine as the
/// service is already the owner and does not have to prove it again. The
/// service's own comment names the Mac companion as the intended caller.
public struct ServiceEndpoint: Sendable, Equatable {
  public let url: URL
  /// 64 hex characters, regenerated on every service start. Never log it.
  public let token: String
  public let pid: Int?

  public init(url: URL, token: String, pid: Int?) {
    self.url = url
    self.token = token
    self.pid = pid
  }
}

public enum ServiceDiscovery {
  static let runtimeRelativePath = "data/runtime/ui.json"

  private struct RuntimeFile: Decodable {
    let url: String
    let token: String
    let pid: Int?
  }

  /// Read the endpoint out of a service checkout.
  ///
  /// Throws `.notRunning` rather than a file error when the file is missing,
  /// because that is what a missing file means to the person looking at the
  /// screen: the service has never started here.
  public static func endpoint(repoRoot: URL) throws -> ServiceEndpoint {
    let path = repoRoot.appending(path: runtimeRelativePath)
    guard let data = try? Data(contentsOf: path) else {
      throw ClientError.notRunning(repoRoot: repoRoot)
    }
    guard let file = try? JSONDecoder().decode(RuntimeFile.self, from: data),
          let url = URL(string: file.url),
          !file.token.isEmpty
    else {
      throw ClientError.runtimeFileUnreadable(path: path)
    }
    return ServiceEndpoint(url: url, token: file.token, pid: file.pid)
  }
}

// MARK: - Errors

public enum ClientError: Error, Sendable {
  /// No runtime file — the service has not started from this checkout.
  case notRunning(repoRoot: URL)
  case runtimeFileUnreadable(path: URL)
  /// The token was rejected even after re-reading the runtime file.
  case unauthorized
  case http(status: Int, path: String)
  /// The service answered `{ ok: false, error: ... }`. Its message is written
  /// for a person and is surfaced verbatim rather than replaced.
  case service(message: String)
  case decoding(path: String, underlying: Error)
  case transport(underlying: Error)
}

extension ClientError: LocalizedError {
  public var errorDescription: String? {
    switch self {
    case .notRunning(let root):
      "服务没在跑。在 \(root.path()) 下执行 `npm run ui`，或检查 launchd 任务。"
    case .runtimeFileUnreadable(let path):
      "读不懂 \(path.lastPathComponent)。服务可能正在启动，或者这个目录不是 daily-os 仓库。"
    case .unauthorized:
      "服务拒绝了本地令牌。它可能刚重启过——重试一次；仍然失败就确认连的是同一个仓库。"
    case .http(let status, let path):
      "\(path) 返回 HTTP \(status)。"
    case .service(let message):
      message
    case .decoding(let path, _):
      "\(path) 的响应解析失败。多半是服务端和客户端版本对不上。"
    case .transport(let underlying):
      underlying.localizedDescription
    }
  }
}

// MARK: - Envelope

/// Every endpoint answers `{ ok, error?, ...payload }`.
///
/// The payload keys sit beside `ok` rather than under a `data` key, so each
/// response type decodes the whole object and ignores `ok` — `Envelope` exists
/// only to check the flag before the real decode runs.
struct Envelope: Decodable {
  let ok: Bool
  private let error: String?
  /// Some endpoints spell the failure `message` instead — the skills module
  /// does (`src/skills/update.ts`). Reading only `error` swallowed the real
  /// reason ("工作区有未提交的改动…") and replaced it with a shrug, which is
  /// exactly the case where the service's own wording is the useful part.
  private let message: String?

  var reason: String? { error ?? message }
}

// MARK: - Client

public actor DailyOSClient {
  private let repoRoot: URL
  private let session: URLSession
  private var cached: ServiceEndpoint?
  private var recentGets: [String: (at: ContinuousClock.Instant, data: Data)] = [:]

  /// How long a GET body may be reused.
  ///
  /// Not a cache in any general sense — it exists so that one refresh is one
  /// round trip. `/api/state` is a single large blob and three unrelated
  /// readers want three slices of it, so a naive pass costs four fetches of an
  /// endpoint that re-runs the service's doctor checks every time: measured at
  /// 430–745 ms each, about 2.5 seconds of duplicated work per refresh.
  ///
  /// Three seconds is chosen to be shorter than any human refresh and longer
  /// than one `reload()`. Writes clear it outright, so nobody reads their own
  /// edit back stale.
  private static let getReuseWindow = Duration.seconds(3)

  public init(repoRoot: URL, session: URLSession = .shared) {
    self.repoRoot = repoRoot
    self.session = session
  }

  /// Drop reusable bodies. Called after every write.
  public func invalidate() {
    recentGets.removeAll()
  }

  public func currentEndpoint() throws -> ServiceEndpoint {
    if let cached { return cached }
    let endpoint = try ServiceDiscovery.endpoint(repoRoot: repoRoot)
    cached = endpoint
    return endpoint
  }

  public func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
    try await send(path: path, method: "GET", body: Optional<Never>.none)
  }

  public func post<T: Decodable>(
    _ path: String,
    body: some Encodable,
    as type: T.Type = T.self
  ) async throws -> T {
    try await send(path: path, method: "POST", body: body)
  }

  /// POST where the answer carries nothing but `ok`.
  @discardableResult
  public func post(_ path: String, body: some Encodable) async throws -> Bool {
    let envelope: Envelope = try await send(path: path, method: "POST", body: body)
    return envelope.ok
  }

  // MARK: Internals

  /// Join a base and a `path?query` string.
  ///
  /// Not `URL.appending(path:)`: that percent-escapes the `?`, so
  /// `/api/env-secret?key=…` was requested as `…%3Fkey=…` and answered 404.
  /// Nothing in the app noticed, because the only endpoints with a query
  /// string arrived later than the transport did.
  static func url(base: URL, path: String) -> URL? {
    let parts = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
    var components = URLComponents(url: base.appending(path: String(parts[0])), resolvingAgainstBaseURL: false)
    if parts.count == 2, !parts[1].isEmpty { components?.percentEncodedQuery = String(parts[1]) }
    return components?.url
  }

  private func send<T: Decodable>(
    path: String,
    method: String,
    body: (some Encodable)?
  ) async throws -> T {
    do {
      return try await attempt(path: path, method: method, body: body)
    } catch ClientError.unauthorized {
      // The service mints a new token on every start, so a 401 usually means it
      // restarted under us rather than that anything is wrong. Re-read the file
      // once and retry; a second 401 is a real failure.
      cached = nil
      return try await attempt(path: path, method: method, body: body)
    }
  }

  private func attempt<T: Decodable>(
    path: String,
    method: String,
    body: (some Encodable)?
  ) async throws -> T {
    if method == "GET", let hit = recentGets[path],
       hit.at.duration(to: .now) < Self.getReuseWindow {
      do {
        return try JSONDecoder().decode(T.self, from: hit.data)
      } catch {
        throw ClientError.decoding(path: path, underlying: error)
      }
    }
    let endpoint = try currentEndpoint()
    guard let url = Self.url(base: endpoint.url, path: path) else {
      throw ClientError.http(status: 0, path: path)
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 30
    // No Origin header on purpose. The service treats a request without one as
    // a non-browser client and skips the CSRF check; sending a fabricated one
    // would fail the hostname allow-list.
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(body)
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      throw ClientError.transport(underlying: error)
    }

    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    if status == 401 || status == 403 { throw ClientError.unauthorized }

    // Check the envelope before the real decode: a failed call still answers
    // 200 with `{ ok: false, error }`, and the service's message is more useful
    // than "expected Cycle, found nothing".
    if let envelope = try? JSONDecoder().decode(Envelope.self, from: data), !envelope.ok {
      throw ClientError.service(message: envelope.reason ?? "服务返回了失败但没说原因。")
    }
    guard (200..<300).contains(status) else {
      throw ClientError.http(status: status, path: path)
    }

    do {
      let decoded = try JSONDecoder().decode(T.self, from: data)
      if method == "GET" {
        recentGets[path] = (at: .now, data: data)
      } else {
        // A write can change anything; keeping any body would mean the next
        // read might not see the edit that just happened.
        recentGets.removeAll()
      }
      return decoded
    } catch {
      throw ClientError.decoding(path: path, underlying: error)
    }
  }
}

// MARK: - Repo root

public enum RepoRoot {
  /// Where the service checkout is.
  ///
  /// Stored rather than guessed. The old companion prototype searched
  /// `DAILY_OS_REPO_ROOT`, a `--repo` flag and its own bundle location, which
  /// works for something launched from a build directory and not for an app in
  /// `/Applications`. A path the user picked once and the app remembers is both
  /// simpler and correct in more places.
  public static let defaultsKey = "com.dailyos.mac.repoRoot"

  public static func stored(in defaults: UserDefaults = .standard) -> URL? {
    guard let path = defaults.string(forKey: defaultsKey), !path.isEmpty else { return nil }
    return URL(filePath: path)
  }

  public static func store(_ url: URL?, in defaults: UserDefaults = .standard) {
    if let url {
      defaults.set(url.path(percentEncoded: false), forKey: defaultsKey)
    } else {
      defaults.removeObject(forKey: defaultsKey)
    }
  }

  /// Does this look like a daily-os checkout? Used to reject a wrong folder at
  /// pick time rather than as a confusing failure on the first request.
  public static func looksValid(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.appending(path: "package.json").path())
      && FileManager.default.fileExists(atPath: url.appending(path: "src/ui").path())
  }

  /// Find the service folder without asking.
  ///
  /// The comment above used to justify not doing this, and it was arguing
  /// against the wrong thing: the old prototype *guessed* from an env var and
  /// its own bundle path, which is indeed useless for an app in `/Applications`.
  /// Reading the launch agent's own `WorkingDirectory` is not a guess — it is
  /// the path the service was installed with, written by the service itself.
  ///
  /// This matters most for the person who did not set any of it up. "选择服务仓库
  /// 目录" asks someone to know a word they have no reason to know, about a
  /// folder they may never have opened.
  public static func discover() -> URL? {
    if let url = fromLaunchAgent(), looksValid(url) { return tidy(url) }
    return fromCommonLocations().map(tidy)
  }

  /// Directory URLs from `contentsOfDirectory` carry a trailing slash, which is
  /// harmless to every path operation and looks like a typo on the setup screen
  /// — the one place the path is shown to somebody.
  private static func tidy(_ url: URL) -> URL {
    URL(filePath: (url.path(percentEncoded: false) as NSString).standardizingPath)
  }

  /// `~/Library/LaunchAgents/com.daily-os-feishu.agent.plist` → `WorkingDirectory`.
  ///
  /// Authoritative when it exists: `npm run service:install` writes that key
  /// with the checkout it was run from, and launchd starts the service there.
  /// Exposed so a diagnostic can report *which* of the two sources answered.
  /// "Found it" and "found it by guessing at folder names" are different levels
  /// of confidence and the difference is worth being able to see.
  public static func discoverViaLaunchAgent() -> URL? {
    fromLaunchAgent().map(tidy)
  }

  private static func fromLaunchAgent() -> URL? {
    let plist = URL.homeDirectory
      .appending(path: "Library/LaunchAgents/com.daily-os-feishu.agent.plist")
    guard let data = try? Data(contentsOf: plist),
          let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
          let root = object as? [String: Any],
          let directory = root["WorkingDirectory"] as? String,
          !directory.isEmpty
    else { return nil }
    return URL(filePath: directory)
  }

  /// A bounded look in the handful of places people keep code.
  ///
  /// Only for the case where the service is run by hand rather than under
  /// launchd; the agent's plist covers everyone else and covers them exactly.
  ///
  /// Four levels, not two. Two was chosen to keep this cheap and would have
  /// missed `~/code/github/<workspace>/daily-os-feishu` — the layout on the
  /// machine this was written on, which is a strong hint about the layout on
  /// any machine set up the same way. Bounded by a visit budget instead of by
  /// depth alone, so an unusually wide folder cannot turn a cold launch into a
  /// disk crawl.
  ///
  /// Prefers a folder that has actually been run: `data/runtime/ui.json` exists
  /// only after the service has started there at least once, which distinguishes
  /// a live checkout from an abandoned clone.
  private static func fromCommonLocations() -> URL? {
    let home = URL.homeDirectory
    var queue: [(url: URL, depth: Int)] = ["code", "Code", "Developer", "Projects", "src", "Documents", "Desktop", ""]
      .map { ($0.isEmpty ? home : home.appending(path: $0), 0) }

    var candidates: [URL] = []
    var budget = 400

    while !queue.isEmpty, budget > 0 {
      let (directory, depth) = queue.removeFirst()
      budget -= 1
      guard let entries = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      ) else { continue }

      for entry in entries {
        guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
        if entry.lastPathComponent.hasPrefix("daily-os"), looksValid(entry) {
          // A folder that has run wins outright; nothing further to look at.
          if hasRun(entry) { return entry }
          candidates.append(entry)
        } else if depth < 3 {
          queue.append((entry, depth + 1))
        }
      }
    }

    return candidates.first
  }

  /// The service has started here at least once, so its address and token file
  /// is present — which is the only thing the app actually reads.
  public static func hasRun(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.appending(path: "data/runtime/ui.json").path())
  }
}
