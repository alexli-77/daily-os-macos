import Foundation

/// One past day: the plan it ended with, the state each row was left in, and
/// what the evening review made of it.
///
/// Editable the way a calendar's past events are: still the same rows, so a
/// tick forgotten in the evening, a wording that turned out wrong, or a note
/// on what actually happened can be put right afterwards. The edit goes to the
/// service with the day's date and lands on that day only. `editable` is false
/// against a service that predates dated edits — it would have stamped a past
/// tick onto today — and the view stays read-only then.
public struct DayHistory: Sendable, Equatable {
  /// `YYYY-MM-DD`, the day on screen.
  public let date: String
  /// Every day that has a plan, newest first. Drives the day list.
  public let dates: [String]
  /// The service's today, so "昨天" is computed against the same calendar day
  /// the service stamps its ledger with, not the Mac's clock.
  public let today: String
  /// False when this day never had a plan — distinct from a plan with no rows.
  public let hasPlan: Bool
  /// Absent for plans only recoverable from the daily memory file.
  public let generatedAt: Date?
  /// In the day's final order, each carrying the state it was left in. `var`
  /// so an edit shows at once, before the service answers.
  public var items: [TodoItem]
  public let review: DayReview?
  /// A plan from before the structured format, as its original text. Shown
  /// instead of pretending the day had no plan.
  public let rawPlan: String?
  /// The service takes edits for this day (see the type's note).
  public let editable: Bool

  public init(
    date: String,
    dates: [String],
    today: String,
    hasPlan: Bool,
    generatedAt: Date? = nil,
    items: [TodoItem],
    review: DayReview? = nil,
    rawPlan: String? = nil,
    editable: Bool = false
  ) {
    self.date = date
    self.dates = dates
    self.today = today
    self.hasPlan = hasPlan
    self.generatedAt = generatedAt
    self.items = items
    self.review = review
    self.rawPlan = rawPlan
    self.editable = editable
  }

  /// A row's rank on that day's sheet — its position, as Today counts it.
  public func rank(of id: TodoItem.ID) -> Int? {
    items.firstIndex { $0.id == id }.map { $0 + 1 }
  }

  /// The row a 排期 block stands for on this day: a 固定日程 by its own id, a
  /// 要务 session by its 要务 key (`weekly:<n>:<key>` — the `<n>` is the 要务's
  /// place in that cycle's list, which the calendar does not know).
  public func row(candidateID: String?, itemKey: String?) -> TodoItem? {
    if let candidateID, let item = items.first(where: { $0.id == candidateID }) { return item }
    guard let itemKey, !itemKey.isEmpty else { return nil }
    return items.first { $0.id.hasPrefix("weekly:") && $0.id.hasSuffix(":\(itemKey)") }
  }

  /// "6 条 · 完成 2 · 部分 1 · 顺延 1". Counts the ticks as they were left,
  /// which is what the Today page itself showed at the end of the day.
  public var summary: String {
    guard !items.isEmpty else { return hasPlan ? "旧格式计划，按原文显示" : "这天没有计划" }
    let count = { (state: TodoState) in items.filter { $0.state == state }.count }
    var parts = ["\(items.count) 条", "完成 \(count(.done))"]
    if count(.partial) > 0 { parts.append("部分 \(count(.partial))") }
    if count(.missed) > 0 { parts.append("未做 \(count(.missed))") }
    if count(.deferred) > 0 { parts.append("顺延 \(count(.deferred))") }
    return parts.joined(separator: " · ")
  }
}

/// What a past day's row can still be told, and how each answer goes on the wire.
///
/// The same four-state vocabulary as Today, minus 顺延 and 删除: those
/// reschedule (push the 要务 to the next day, skip its session), and a day
/// that is over has nothing left to schedule. The service refuses them for a
/// past date too; leaving them out here means no button that can only fail.
public enum PastRowEdit {
  public static let choices: [TodoState] = [.done, .partial, .missed]

  /// The circle: tick, or take the tick back. Any other state ticks — a row
  /// marked 未做 and then clicked was done after all.
  public static func toggled(_ state: TodoState) -> TodoState {
    state == .done ? .open : .done
  }

  /// Picking the state the row is already in takes it back, as on Today.
  public static func picked(_ target: TodoState, from current: TodoState) -> TodoState {
    target == current ? .open : target
  }

  /// The ledger event that puts a row in `state`. Untouched is `reopen`, which
  /// clears whatever the row was left in.
  public static func event(for state: TodoState) -> String {
    switch state {
    case .done: "complete"
    case .partial: "partial"
    case .missed: "missed"
    case .deferred: "defer"
    case .open, .deleted: "reopen"
    }
  }

  /// The toast after a change, naming the day so it is clear which sheet moved.
  public static func said(_ state: TodoState, day: String) -> String {
    switch state {
    case .done: "\(day)记为完成"
    case .partial: "\(day)记为做了一部分"
    case .missed: "\(day)记为未做"
    case .deferred: "\(day)记为顺延"
    case .open, .deleted: "\(day)的标记撤回了"
    }
  }
}

/// Why a past day could not be loaded, worded for the screen.
public struct DayHistoryError: Error, Sendable, Equatable {
  public let message: String
  public init(_ message: String) { self.message = message }
}

/// The evening `daily_review` reconciliation.
public struct DayReview: Sendable, Equatable {
  public struct Item: Sendable, Equatable, Identifiable {
    public enum Status: String, Sendable, Equatable {
      case done, progressed, open

      public var label: String {
        switch self {
        case .done: "完成"
        case .progressed: "推进了"
        case .open: "没动"
        }
      }
    }

    public let id: String
    public let text: String
    public let status: Status
    public let evidence: String?

    public init(id: String, text: String, status: Status, evidence: String? = nil) {
      self.id = id
      self.text = text
      self.status = status
      self.evidence = evidence
    }
  }

  public let items: [Item]
  public let note: String?

  public init(items: [Item], note: String? = nil) {
    self.items = items
    self.note = note
  }
}

public enum DayLabel {
  /// "昨天" / "前天" for the two days people actually mean, "9月22日 周二"
  /// otherwise. Relative to `today` as the service reports it, not the Mac's
  /// clock, so the two cannot disagree about which day is yesterday.
  public static func text(for date: String, today: String) -> String {
    guard let day = parse(date), let reference = parse(today) else { return date }
    let offset = calendar.dateComponents([.day], from: day, to: reference).day ?? 0
    switch offset {
    case 0: return "今天"
    case 1: return "昨天"
    case 2: return "前天"
    default:
      let parts = calendar.dateComponents([.month, .day, .weekday], from: day)
      let weekday = ["日", "一", "二", "三", "四", "五", "六"][(parts.weekday ?? 1) - 1]
      return "\(parts.month ?? 0)月\(parts.day ?? 0)日 周\(weekday)"
    }
  }

  /// Fixed UTC so a day never shifts across a DST change or a time zone —
  /// these are calendar labels, not instants.
  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  static func parse(_ value: String) -> Date? {
    let parts = value.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
  }
}
