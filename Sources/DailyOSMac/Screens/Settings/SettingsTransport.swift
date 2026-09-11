import Foundation

// MARK: - JSON

/// A JSON tree kept exactly as the service sent it.
///
/// Two jobs. Reading: every accessor answers a default instead of an optional,
/// so a key that moved costs one row rather than the whole screen. Writing:
/// `POST /api/config` re-parses and rewrites the entire config file and its zod
/// schema strips keys it does not recognise, so a client changing `llm.model`
/// has to hand every other key back untouched — a typed mirror would delete
/// anything this app had not been taught about, permanently.
enum JSONNode: Codable, Equatable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONNode])
  case object([String: JSONNode])

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONNode].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: JSONNode].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "不认识的 JSON 值")
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }

  subscript(key: String) -> JSONNode {
    if case .object(let members) = self, let value = members[key] { return value }
    return .null
  }

  var string: String {
    if case .string(let value) = self { return value }
    return ""
  }

  var bool: Bool {
    if case .bool(let value) = self { return value }
    return false
  }

  var int: Int? {
    if case .number(let value) = self { return Int(value) }
    return nil
  }

  var array: [JSONNode] {
    if case .array(let value) = self { return value }
    return []
  }

  /// Replace one leaf. A path that runs into something other than an object is
  /// left alone rather than overwritten — better to save nothing than to reshape
  /// somebody's config file.
  func setting(_ path: [String], to value: JSONNode) -> JSONNode {
    guard let key = path.first else { return value }
    guard case .object(var members) = self else { return self }
    let child = members[key] ?? .object([:])
    members[key] = child.setting(Array(path.dropFirst()), to: value)
    return .object(members)
  }

  /// One line per element, which is how every list in the config reads best in a
  /// text box: repositories, open ids, workspace paths. Blank lines and repeats
  /// are dropped exactly the way the web console's `parseLines` drops them, so a
  /// list typed here and a list typed there produce the same file.
  static func lines(_ text: String) -> JSONNode {
    var seen = Set<String>()
    var rows: [JSONNode] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
      rows.append(.string(trimmed))
    }
    return .array(rows)
  }

  /// The inverse of `lines`, for seeding the text box from the config.
  var lineText: String {
    array.map(\.string).joined(separator: "\n")
  }
}

/// One leaf of the config tree, addressed by path.
///
/// A section builds the same list from `draft` and from `original` and compares
/// them to decide whether its 保存 button appears. That makes "dirty" mean the
/// only thing it can honestly mean here — *this save would change the file* —
/// rather than "some field somewhere on the screen was touched", which is what
/// comparing whole drafts gives you and why every panel's Save button used to
/// light up at once.
struct ConfigEdit: Equatable {
  let path: [String]
  let value: JSONNode
}

/// Everything one section's 保存 writes: config leaves, and plain `.env` keys.
/// Secrets never appear here — they have their own single-key write.
struct ConfigEdits: Equatable {
  var config: [ConfigEdit] = []
  var env: [String: String] = [:]

  var isEmpty: Bool { config.isEmpty && env.isEmpty }
}

// MARK: - Transport

/// The smallest thing that can talk to the local service.
///
/// Discovery is the same as `DailyOSClient`'s and for the same reason: the
/// service rewrites `data/runtime/ui.json` on every start with its address and a
/// fresh admin token, so knowing where the checkout is means knowing everything
/// else. This copy exists only because `DailyOSMac` has no dependency edge to
/// `DailyOSClient` in `Package.swift`; it re-reads the runtime file on every
/// request instead of caching it, which costs one small file read and removes
/// the retry-after-restart case entirely.
enum ServiceLink {
  /// Duplicated from `RepoRoot.defaultsKey` for the same module reason. Changing
  /// one without the other points this screen at a different service than the
  /// rest of the app.
  static let repoRootDefaultsKey = "com.dailyos.mac.repoRoot"

  struct Failure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
  }

  static func repoRootPath() -> String {
    UserDefaults.standard.string(forKey: repoRootDefaultsKey) ?? ""
  }

  private static func endpoint() throws -> (url: URL, token: String) {
    let root = repoRootPath()
    guard !root.isEmpty else {
      throw Failure("还没有选择 daily-os 服务仓库。退出重开会回到「选择仓库目录」那一屏。")
    }
    let path = URL(filePath: root).appending(path: "data/runtime/ui.json")
    guard let data = try? Data(contentsOf: path) else {
      throw Failure("服务没在跑：\(root) 下没有 data/runtime/ui.json。在那里执行 `npm run ui`，或检查 launchd 任务。")
    }
    guard let node = try? JSONDecoder().decode(JSONNode.self, from: data),
          let url = URL(string: node["url"].string),
          !node["token"].string.isEmpty
    else {
      throw Failure("读不懂 ui.json。服务可能正在启动，或者这个目录不是 daily-os 仓库。")
    }
    return (url, node["token"].string)
  }

  /// The console URL with the runtime token attached. See
  /// `SettingsStore.openWebConsole` for why the token rides in the query string
  /// and what that costs.
  static func endpointForConsole() throws -> URL {
    let endpoint = try endpoint()
    var components = URLComponents(url: endpoint.url, resolvingAgainstBaseURL: false)
    components?.queryItems = [URLQueryItem(name: "token", value: endpoint.token)]
    guard let url = components?.url else { throw Failure("拼不出控制台地址。") }
    return url
  }

  static func get(_ path: String) async throws -> JSONNode {
    try await send(path: path, method: "GET", body: nil)
  }

  @discardableResult
  static func post(_ path: String, body: JSONNode) async throws -> JSONNode {
    try await send(path: path, method: "POST", body: body)
  }

  /// Only `/api/logs` answers DELETE, and it is the one write on this screen
  /// with no config or env behind it — the log file is the thing being emptied.
  @discardableResult
  static func delete(_ path: String) async throws -> JSONNode {
    try await send(path: path, method: "DELETE", body: nil)
  }

  private static func send(path: String, method: String, body: JSONNode?) async throws -> JSONNode {
    let endpoint = try endpoint()
    // Concatenated rather than `URL.appending(path:)`, which percent-encodes `?`
    // into `%3F` — `/api/env-secret?key=…` would then arrive as a path with no
    // route behind it and come back as a 404 that reads like a missing endpoint
    // rather than an eaten query string.
    let base = endpoint.url.absoluteString.hasSuffix("/")
      ? String(endpoint.url.absoluteString.dropLast())
      : endpoint.url.absoluteString
    guard let url = URL(string: base + path) else {
      throw Failure("拼不出请求地址：\(base)\(path)")
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
    // Long enough for the slowest thing behind /api/action. `collect` walks every
    // enabled source and `plan` runs a model end to end; at 30s those came back
    // as "请求超时" while the service was still working, which reads as the button
    // being broken and invites a second run of the same workflow.
    request.timeoutInterval = 300
    // No Origin header on purpose: the service treats a request without one as a
    // non-browser client and skips the CSRF check, while a fabricated one would
    // fail its hostname allow-list.
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(body)
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw Failure(error.localizedDescription)
    }

    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    if status == 401 || status == 403 {
      throw Failure("服务拒绝了本地令牌。它可能刚重启过——重试一次；仍然失败就确认连的是同一个仓库。")
    }
    guard let node = try? JSONDecoder().decode(JSONNode.self, from: data) else {
      throw Failure("\(path) 的响应解析失败。多半是服务端和客户端版本对不上。")
    }
    // A refused call still answers 200 with `{ ok: false }`, and the sentence
    // beside it is written for a person. `error` is what most handlers set;
    // `message` is what the skills endpoints set instead, and reading only the
    // first would replace "工作区有未提交的改动" with "服务返回了失败但没说原因".
    if case .bool(false) = node["ok"] {
      let reason = [node["error"].string, node["message"].string].first { !$0.isEmpty }
      throw Failure(reason ?? "服务返回了失败但没说原因。")
    }
    guard (200..<300).contains(status) else {
      throw Failure("\(path) 返回 HTTP \(status)。")
    }
    return node
  }
}
