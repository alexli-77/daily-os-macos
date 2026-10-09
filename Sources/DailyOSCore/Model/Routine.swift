import Foundation

/// 作息 — the frame a period of the user's life runs on.
///
/// A period (a residency, a semester) has day types (workday, weekend), each
/// with one or more modes (作品集日 / Cutto 日), each a list of blocks. A block
/// is `fixed` (getting up, meals, meetings: nothing else goes there) or a
/// `slot` kept for one category, which that category's to-dos go into. A slot
/// can be a floor: the least that category gets on a busy day. The service
/// stores it in the vault (`00_System/routines.json`); the plan and the cycle
/// schedule follow it.
public struct RoutineBlock: Codable, Sendable, Equatable, Identifiable {
  public enum Kind: String, Codable, Sendable { case fixed, slot }

  public var id: String
  public var start: String
  public var end: String
  public var title: String
  public var note: String?
  public var category: String?
  public var kind: Kind
  public var floor: Bool?

  public init(id: String, start: String, end: String, title: String, note: String? = nil, category: String? = nil, kind: Kind = .fixed, floor: Bool? = nil) {
    self.id = id
    self.start = start
    self.end = end
    self.title = title
    self.note = note
    self.category = category
    self.kind = kind
    self.floor = floor
  }

  public var startMinute: Int { DayStart.minute(fromClock: start) ?? 0 }
  public var endMinute: Int { end == "24:00" ? 24 * 60 : (DayStart.minute(fromClock: end) ?? startMinute) }
  public var minutes: Int { max(0, endMinute - startMinute) }
}

public struct RoutineMode: Codable, Sendable, Equatable, Identifiable {
  public var id: String
  public var label: String
  public var blocks: [RoutineBlock]

  public init(id: String, label: String, blocks: [RoutineBlock]) {
    self.id = id
    self.label = label
    self.blocks = blocks
  }

  /// Minutes per category in this mode, slots and fixed blocks alike, largest
  /// first — the bars beside the day ("作品集 5.0h").
  public func minutesByCategory() -> [(key: String, minutes: Int)] {
    var totals: [String: Int] = [:]
    for block in blocks { if let category = block.category { totals[category, default: 0] += block.minutes } }
    return totals.map { ($0.key, $0.value) }.sorted { $0.minutes > $1.minutes || ($0.minutes == $1.minutes && $0.key < $1.key) }
  }
}

public struct RoutineDayType: Codable, Sendable, Equatable, Identifiable {
  public var id: String
  public var label: String
  /// `MON` … `SUN`.
  public var weekdays: [String]
  public var defaultMode: String
  public var modes: [RoutineMode]

  public init(id: String, label: String, weekdays: [String], defaultMode: String, modes: [RoutineMode]) {
    self.id = id
    self.label = label
    self.weekdays = weekdays
    self.defaultMode = defaultMode
    self.modes = modes
  }
}

public struct RoutineCategory: Codable, Sendable, Equatable, Identifiable {
  public var key: String
  public var label: String
  /// A `Palette.rowColorNames` name.
  public var color: String
  /// A habit category: each slot of it is a to-do on Today, not a band.
  public var habit: Bool?
  public var id: String { key }

  public init(key: String, label: String, color: String, habit: Bool? = nil) {
    self.key = key
    self.label = label
    self.color = color
    self.habit = habit
  }
}

public struct RoutinePeriod: Codable, Sendable, Equatable, Identifiable {
  public var id: String
  public var name: String
  public var subtitle: String?
  /// `YYYY-MM-DD`, inclusive.
  public var from: String
  public var to: String
  public var wake: String?
  public var sleep: String?
  public var summary: String?
  public var categories: [RoutineCategory]
  public var dayTypes: [RoutineDayType]
  public var rules: [String]

  public init(
    id: String, name: String, subtitle: String? = nil, from: String, to: String, wake: String? = nil, sleep: String? = nil,
    summary: String? = nil, categories: [RoutineCategory] = [], dayTypes: [RoutineDayType] = [], rules: [String] = []
  ) {
    self.id = id
    self.name = name
    self.subtitle = subtitle
    self.from = from
    self.to = to
    self.wake = wake
    self.sleep = sleep
    self.summary = summary
    self.categories = categories
    self.dayTypes = dayTypes
    self.rules = rules
  }

  public func category(_ key: String?) -> RoutineCategory? {
    guard let key else { return nil }
    return categories.first { $0.key == key }
  }

  public func contains(_ date: String) -> Bool { from <= date && date <= to }
}

/// Everything the 作息 page needs.
public struct RoutineState: Sendable, Equatable {
  public var today: String
  public var periods: [RoutinePeriod]
  public var dayModes: [String: String]
  /// Anything the service dropped on the last save, in words.
  public var problems: [String]

  public init(today: String, periods: [RoutinePeriod], dayModes: [String: String] = [:], problems: [String] = []) {
    self.today = today
    self.periods = periods
    self.dayModes = dayModes
    self.problems = problems
  }
}

/// Today's slice of the 作息, as the Today screen draws it.
public struct TodayRoutine: Sendable, Equatable {
  public struct Slot: Sendable, Equatable, Identifiable {
    public let start: Int
    public let end: Int
    public let title: String
    public let category: String?
    public let color: String?
    public let floor: Bool
    /// A habit slot: the Today sheet has a row for it, so no band is drawn.
    public let habit: Bool
    /// The 作息 block this slot is; Today can move it for the day.
    public let blockID: String?
    public var id: String { "\(start)-\(title)" }

    public init(start: Int, end: Int, title: String, category: String?, color: String?, floor: Bool, habit: Bool = false, blockID: String? = nil) {
      self.blockID = blockID
      self.start = start
      self.end = end
      self.title = title
      self.category = category
      self.color = color
      self.floor = floor
      self.habit = habit
    }
  }

  public let period: String
  public let dayType: String
  public let mode: (id: String, label: String)
  public let modes: [(id: String, label: String)]
  public let slots: [Slot]

  public init(period: String, dayType: String, mode: (id: String, label: String), modes: [(id: String, label: String)], slots: [Slot]) {
    self.period = period
    self.dayType = dayType
    self.mode = mode
    self.modes = modes
    self.slots = slots
  }

  public static func == (lhs: TodayRoutine, rhs: TodayRoutine) -> Bool {
    lhs.period == rhs.period && lhs.dayType == rhs.dayType && lhs.mode == rhs.mode
      && lhs.modes.map(\.id) == rhs.modes.map(\.id) && lhs.slots == rhs.slots
  }
}

public struct RoutineError: Error, Sendable, Equatable {
  public let message: String
  public init(_ message: String) { self.message = message }
}

public enum RoutineWeekday {
  public static let codes = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
  public static func label(_ code: String) -> String {
    ["MON": "一", "TUE": "二", "WED": "三", "THU": "四", "FRI": "五", "SAT": "六", "SUN": "日"][code] ?? code
  }
}
