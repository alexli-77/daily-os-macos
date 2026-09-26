import Foundation

/// One past day: the plan it ended with, the state each row was left in, and
/// what the evening review made of it.
///
/// Read-only by construction. Ticking yesterday's row would record feedback
/// against today's date (the service stamps the ledger with the day it
/// receives the event), so a past day is something you look at, not something
/// you edit — the view has no controls that write.
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
  /// In the day's final order, each carrying the state it was left in.
  public let items: [TodoItem]
  public let review: DayReview?
  /// A plan from before the structured format, as its original text. Shown
  /// instead of pretending the day had no plan.
  public let rawPlan: String?

  public init(
    date: String,
    dates: [String],
    today: String,
    hasPlan: Bool,
    generatedAt: Date? = nil,
    items: [TodoItem],
    review: DayReview? = nil,
    rawPlan: String? = nil
  ) {
    self.date = date
    self.dates = dates
    self.today = today
    self.hasPlan = hasPlan
    self.generatedAt = generatedAt
    self.items = items
    self.review = review
    self.rawPlan = rawPlan
  }

  /// "6 条 · 完成 2 · 部分 1 · 顺延 1". Counts the ticks as they were left,
  /// which is what the Today page itself showed at the end of the day.
  public var summary: String {
    guard !items.isEmpty else { return hasPlan ? "旧格式计划，按原文显示" : "这天没有计划" }
    let count = { (state: TodoState) in items.filter { $0.state == state }.count }
    var parts = ["\(items.count) 条", "完成 \(count(.done))"]
    if count(.partial) > 0 { parts.append("部分 \(count(.partial))") }
    if count(.deferred) > 0 { parts.append("顺延 \(count(.deferred))") }
    return parts.joined(separator: " · ")
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
