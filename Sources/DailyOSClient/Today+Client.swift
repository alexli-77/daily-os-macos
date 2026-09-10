import Foundation
import DailyOSCore

// The Today screen's half of `/api/state`, plus the two writes it can perform.
//
// `/api/state` is one big object rebuilt from disk on every call — config,
// doctor, OKR, cycles, team, and much more. Nothing here asks for a narrower
// endpoint because none exists; the DTOs below name only the two branches the
// Today screen reads and let `JSONDecoder` drop the rest.

// MARK: - Date parsing

/// ISO-8601 parsing that accepts both shapes the ledger holds.
///
/// Items written by the service come from `Date.toISOString()`, which always
/// emits milliseconds (`...T01:21:44.317Z`), and a parser configured for the
/// plain form rejects those outright — one unparseable stamp would read as "the
/// whole inbox is broken". Trying the plain form second keeps hand-written
/// ledger lines working too.
///
/// `Date.ISO8601FormatStyle` rather than `ISO8601DateFormatter`: it is a
/// `Sendable` value, so it can sit in a `static let` under Swift 6 concurrency
/// checking instead of being rebuilt for every item on every refresh.
enum TodoWireDate {
  private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
  private static let withoutFraction = Date.ISO8601FormatStyle()

  static func timestamp(_ raw: String) -> Date? {
    (try? Date(raw, strategy: withFraction)) ?? (try? Date(raw, strategy: withoutFraction))
  }
}

// MARK: - Wire types

/// Only `todoInbox` and `service` are declared. Adding a key here is the one
/// thing that can break this file, so the type doubles as the list of what Today
/// actually depends on.
struct StatePayload: Decodable {
  let todoInbox: TodoInboxPayload
  let service: LaunchAgentPayload
}

struct TodoInboxPayload: Decodable {
  let open: [TodoInboxItemPayload]
  let recent: [TodoInboxItemPayload]
}

/// Snake_case, unlike the rest of the API.
///
/// These items are appended verbatim to a JSONL ledger by the Feishu side, so
/// their keys are the ledger's keys rather than the console's. Spelling them out
/// here instead of setting `keyDecodingStrategy` keeps that local: a converting
/// strategy would also rewrite `todoInbox` and `plistPath` and then fail to find
/// them.
struct TodoInboxItemPayload: Decodable {
  let id: String
  let text: String
  let type: String
  let status: String
  let updatedAt: Date

  enum CodingKeys: String, CodingKey {
    case id, text, type, status
    case updatedAt = "updated_at"
  }

  // Hand-written because the transport decodes with a stock `JSONDecoder` that
  // this file does not own, so the fractional-second problem has to be solved on
  // the one property that has it rather than by a decoder-wide strategy.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    text = try container.decode(String.self, forKey: .text)
    type = try container.decode(String.self, forKey: .type)
    status = try container.decode(String.self, forKey: .status)

    let stamp = try container.decode(String.self, forKey: .updatedAt)
    guard let date = TodoWireDate.timestamp(stamp) else {
      throw DecodingError.dataCorruptedError(
        forKey: .updatedAt,
        in: container,
        debugDescription: "不是 ISO-8601 时间：\(stamp)"
      )
    }
    updatedAt = date
  }
}

struct LaunchAgentPayload: Decodable {
  let installed: Bool
  let registered: Bool
}

struct CaptureRequest: Encodable {
  let text: String
}

/// `/api/todo-inbox` also accepts `text`, `type` and `note`. Sending only the two
/// fields a state change needs means a checkbox tap carrying stale text cannot
/// undo a rename that landed between the fetch and the tap.
struct TodoInboxUpdateRequest: Encodable {
  let id: String
  let status: String
}

// MARK: - Mapping

private extension TodoInboxItemPayload {
  /// The service's four `type` values against the UI's three kinds.
  ///
  /// `time_boundary` ("21:00 前离开公司") and `reminder` are both pinned to a clock,
  /// so both read as 日程. `note` has no counterpart — it is a captured remark,
  /// not a task — and falls through with every unrecognised value, because a
  /// `type` this client has not heard of should still appear in the list rather
  /// than take the whole fetch down. `.habit` is never produced: the inbox has no
  /// recurring item today.
  var kind: TodoKind {
    switch type {
    case "time_boundary", "reminder": .schedule
    default: .priority
    }
  }

  /// `deleted` is the ledger's tombstone, and `/api/state` filters those out of
  /// both lists before we see them. Mapping it to 暂缓 alongside the unknown case
  /// only exists so one strange value cannot throw away the rest of the list.
  var state: TodoState {
    switch status {
    case "done": .done
    case "deferred", "deleted": .deferred
    default: .open
    }
  }

  var todoItem: TodoItem {
    // `due`, `sourceRef` and `estimatedMinutes` stay nil. The inbox does carry a
    // `due_hint`, but it is a natural-language fragment ("明天", "下午") rather than
    // a date and would need a parser to become one. `estimatedMinutes` is a
    // client-side concept the service does not supply yet.
    TodoItem(id: id, text: text, kind: kind, state: state)
  }
}

// MARK: - Endpoints

extension DailyOSClient {
  /// `open` is everything still to do; `recent` is the last 40 items in any state
  /// bar deleted, which is what the history strip shows.
  public func todoInbox() async throws -> (open: [TodoItem], recent: [TodoItem]) {
    let payload: StatePayload = try await get(statePath)
    // The endpoint's ordering is a side effect of how it slices the ledger. The
    // history strip promises newest-first, so sort on the timestamp rather than
    // inherit that.
    let recent = payload.todoInbox.recent
      .sorted { $0.updatedAt > $1.updatedAt }
      .map(\.todoItem)
    return (payload.todoInbox.open.map(\.todoItem), recent)
  }

  public func serviceStatus() async throws -> ServiceStatus {
    let payload: StatePayload = try await get(statePath)
    let endpoint = try currentEndpoint()

    // `.stopped` is unreachable from here on purpose: a stopped service cannot
    // answer `/api/state`, so that case arrives as a thrown `ClientError` and is
    // the caller's to render. What is left to decide is whether an answering
    // service is *durable*, and that is what `installed`/`registered` describe —
    // they are about launchd, not about this process. A service someone started
    // by hand answers every request and is still not registered, which is exactly
    // 降级: working now, gone after the next logout. Worth saying before the
    // morning it quietly does not run.
    let managed = payload.service.installed && payload.service.registered
    return ServiceStatus(
      state: managed ? .running : .degraded,
      endpoint: endpoint.url.absoluteString,
      // The service reports no start time, and reading one off the runtime
      // file's mtime would be a guess wearing the costume of a fact.
      uptime: .zero,
      note: managed ? nil : "服务在跑，但没注册成 launchd 任务——退出登录或重启之后不会自己起来。"
    )
  }

  /// Hands the raw sentence over rather than pre-parsing it: the grammar that
  /// works in Feishu ("完成 周报", "提醒我 …") is the service's, and reimplementing
  /// it here would give the Mac app a second dialect that drifts from the first.
  public func capture(_ text: String) async throws {
    try await post("/api/capture", body: CaptureRequest(text: text))
  }

  public func setTodo(id: String, to state: TodoState) async throws {
    // `TodoState.rawValue` happens to match the service's `status` on all three
    // spellings, but the wire value is written out so that renaming a case for
    // the UI's sake cannot silently change what gets POSTed.
    let status = switch state {
    case .open: "open"
    case .done: "done"
    case .deferred: "deferred"
    case .deleted: "deleted"
    }
    try await post("/api/todo-inbox", body: TodoInboxUpdateRequest(id: id, status: status))
  }

  private var statePath: String { "/api/state" }
}
