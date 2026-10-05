import Foundation

/// A dated thing you want to see the distance to.
///
/// The day count is **not** computed here. `daysLeft` and `occurrence` arrive
/// already resolved from the service, because the service is the only side that
/// knows which timezone the user configured — and because two implementations
/// of calendar arithmetic is two chances to disagree about what day it is. What
/// this type does own is how a resolved count reads and which group a row
/// belongs to, both of which are presentation.
public struct Countdown: Identifiable, Sendable, Hashable {
  /// `until` counts down to something ahead; `since` counts up from something
  /// behind. The distinction is not only wording: a `since` entry is never
  /// "upcoming", so it is never overdue either, and it stays out of the morning
  /// card unless it was pinned on purpose.
  public enum Direction: String, Sendable, CaseIterable {
    case until
    case since

    public var label: String {
      switch self {
      case .until: "倒数"
      case .since: "正数"
      }
    }
  }

  public enum Recurrence: String, Sendable, CaseIterable {
    case none
    case yearly

    public var label: String {
      switch self {
      case .none: "只有一次"
      case .yearly: "每年"
      }
    }
  }

  public let id: String
  public var title: String
  /// The anchor date, `YYYY-MM-DD`. For a yearly entry, the first occurrence —
  /// which is what makes "第 36 年" computable.
  public var date: String
  public var direction: Direction
  public var recurrence: Recurrence
  public var pinned: Bool
  public var note: String?
  /// The occurrence currently being counted to. Equals `date` unless yearly.
  public var occurrence: String
  /// Calendar days from today to `occurrence`. Negative once it is behind.
  public var daysLeft: Int
  /// Which anniversary `occurrence` is. Only a yearly entry has one.
  public var ordinal: Int?

  public init(
    id: String,
    title: String,
    date: String,
    direction: Direction = .until,
    recurrence: Recurrence = .none,
    pinned: Bool = false,
    note: String? = nil,
    occurrence: String,
    daysLeft: Int,
    ordinal: Int? = nil
  ) {
    self.id = id
    self.title = title
    self.date = date
    self.direction = direction
    self.recurrence = recurrence
    self.pinned = pinned
    self.note = note
    self.occurrence = occurrence
    self.daysLeft = daysLeft
    self.ordinal = ordinal
  }

  public var isPast: Bool { daysLeft < 0 }

  /// "还有 23 天" / "就是今天" / "已经 517 天".
  ///
  /// A `since` entry that has passed reads "已经", not "已过去": nothing about
  /// the 517th day of a PhD is overdue, and the overdue wording is the whole
  /// reason the direction is stored rather than inferred from the sign.
  public var daysLabel: String {
    if daysLeft == 0 { return "就是今天" }
    if daysLeft > 0 { return "还有 \(daysLeft) 天" }
    return direction == .since ? "已经 \(-daysLeft) 天" : "已过去 \(-daysLeft) 天"
  }

  /// The number alone, for the places that set it in a larger face.
  public var dayNumber: Int { abs(daysLeft) }

  /// What the number sits under: "还有" / "已经" / "已过去", or nothing today.
  public var dayCaption: String {
    if daysLeft == 0 { return "就是今天" }
    if daysLeft > 0 { return "还有" }
    return direction == .since ? "已经" : "已过去"
  }

  /// "第 36 年", for a yearly entry. Nil for everything else.
  public var ordinalLabel: String? {
    guard recurrence == .yearly, let ordinal, ordinal > 0 else { return nil }
    return "第 \(ordinal) 年"
  }

  /// Colour is reserved for the near edge.
  ///
  /// Only an `until` entry inside a week gets a warm tone, and only the last
  /// three days get the red one. Tinting everything would make the palette mean
  /// "this is a countdown", which the screen already says.
  public var tone: Tone {
    guard direction == .until, daysLeft >= 0 else { return .neutral }
    if daysLeft <= 3 { return .danger }
    if daysLeft <= 7 { return .warn }
    return .neutral
  }
}

extension Countdown {
  /// How far ahead an unpinned entry has to be before it is worth a line.
  public static let cardHorizonDays = 30
  /// How many lines the strip and the morning card will carry.
  public static let cardLimit = 3

  /// The few entries worth one line of ambient space: pinned ones, plus
  /// anything arriving inside 30 days.
  ///
  /// A deliberate duplicate of `cardCountdowns` in the service
  /// (`src/countdown/store.ts`), which decides the same thing for the Feishu
  /// card. They are kept in step by hand, and they have to be: the strip on
  /// Today and the first line of the morning card are supposed to be the same
  /// sentence, and the moment they disagree the screen is quietly lying about
  /// what the card said. The *day counts* are not duplicated — those arrive
  /// resolved, because getting them wrong is silent and getting a filter wrong
  /// is visible.
  public static func forCard(_ items: [Countdown], limit: Int = cardLimit) -> [Countdown] {
    items
      .filter { item in
        if item.direction == .since { return item.pinned }
        if item.isPast { return false }
        return item.pinned || item.daysLeft <= cardHorizonDays
      }
      .prefix(limit)
      .map { $0 }
  }
}

/// What the editor sheet sends back.
///
/// Separate from `Countdown` because the two carry different things: a draft
/// has no resolved day count — that is the service's answer, not the user's
/// input — and an `id` of `nil` is how "create" is said.
/// `Identifiable` so a sheet can be presented from one: the synthesised `ID` is
/// `String?`, and `nil` — a draft that has not been saved yet — is as valid an
/// identity as any other, which is what lets create and edit share the sheet.
public struct CountdownDraft: Sendable, Equatable, Identifiable {
  public var id: String?
  public var title: String
  public var date: String
  public var direction: Countdown.Direction
  public var recurrence: Countdown.Recurrence
  public var pinned: Bool
  public var note: String

  public init(
    id: String? = nil,
    title: String = "",
    date: String,
    direction: Countdown.Direction = .until,
    recurrence: Countdown.Recurrence = .none,
    pinned: Bool = false,
    note: String = ""
  ) {
    self.id = id
    self.title = title
    self.date = date
    self.direction = direction
    self.recurrence = recurrence
    self.pinned = pinned
    self.note = note
  }

  public init(editing item: Countdown) {
    self.init(
      id: item.id,
      title: item.title,
      date: item.date,
      direction: item.direction,
      recurrence: item.recurrence,
      pinned: item.pinned,
      note: item.note ?? ""
    )
  }

  /// A title you can save. The date is always well-formed — it comes from a
  /// picker, never from typing.
  public var isValid: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

/// The three bands the page reads in: what you pinned, what is running, what is
/// behind you.
///
/// A `since` entry is always "running" even though its day count is negative —
/// it is counting up, which is the point of it. Only a one-off `until` can
/// actually be *over*, and that band exists so those can be found and deleted
/// rather than quietly padding the list forever.
public struct CountdownGroup: Identifiable, Sendable {
  public enum Kind: String, Sendable {
    case pinned
    case running
    case past

    public var title: String {
      switch self {
      case .pinned: "置顶"
      case .running: "进行中"
      case .past: "已经过去"
      }
    }
  }

  public let kind: Kind
  public let items: [Countdown]

  public var id: String { kind.rawValue }
}

extension CountdownGroup {
  /// Band the list, dropping bands that came out empty.
  ///
  /// Order inside a band is left as given: the service already sorted by how
  /// near each entry is, and re-sorting here would be a second opinion about
  /// something that is not this side's to decide.
  public static func group(_ items: [Countdown]) -> [CountdownGroup] {
    let pinned = items.filter(\.pinned)
    let rest = items.filter { !$0.pinned }
    let running = rest.filter { $0.direction == .since || !$0.isPast }
    let past = rest.filter { $0.direction == .until && $0.isPast }
    return [
      CountdownGroup(kind: .pinned, items: pinned),
      CountdownGroup(kind: .running, items: running),
      CountdownGroup(kind: .past, items: past),
    ].filter { !$0.items.isEmpty }
  }
}

// MARK: - Wire dates

/// `YYYY-MM-DD` ↔ `Date`, for the one place a date picker needs the other form.
///
/// Fixed to UTC on both sides. These strings are calendar dates, not instants:
/// reading "2026-04-24" in `America/Toronto` and writing it back out would
/// return "2026-04-23" for anyone west of Greenwich, which is the same class of
/// bug as slicing a day off a UTC timestamp.
public enum CountdownDate {
  private static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
  }

  private static let formatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  public static func date(from day: String) -> Date? {
    formatter.date(from: day)
  }

  public static func day(from date: Date) -> String {
    formatter.string(from: date)
  }

  /// "2026年4月24日 星期五" — the long form under the number.
  public static func heading(_ day: String) -> String {
    guard let date = date(from: day) else { return day }
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    formatter.locale = Locale(identifier: "zh_Hans")
    formatter.dateFormat = "yyyy年M月d日 EEEE"
    return formatter.string(from: date)
  }
}
