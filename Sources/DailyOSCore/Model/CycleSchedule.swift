import Foundation

/// 双周排期: a cycle's 要务 laid out over its days, before any day is planned.
///
/// Big rocks — each role's most important thing — hold a concrete slot; the
/// rest only a day. The daily plan takes its slice from here, so a fix to how
/// the cycle is spread belongs here too, not on the Today page. Stored by the
/// service beside the cycle file (`<id>.schedule.json`).
public struct CycleScheduleState: Sendable, Equatable {
  public struct Item: Sendable, Equatable, Identifiable {
    /// The 8-hex key sessions refer to — the same one the plan's weekly ids end in.
    public let key: String
    public let text: String
    /// The OKR objective it serves; its opening word is the role.
    public let okr: String
    public let mit: Bool
    public var id: String { key }

    public init(key: String, text: String, okr: String, mit: Bool) {
      self.key = key
      self.text = text
      self.okr = okr
      self.mit = mit
    }
  }

  public struct Day: Sendable, Equatable, Identifiable {
    /// A meal or a fixed routine from the rhythm settings.
    public struct Block: Sendable, Equatable {
      public let label: String
      public let start: Int
      public let end: Int
      public init(label: String, start: Int, end: Int) {
        self.label = label
        self.start = start
        self.end = end
      }
    }

    /// `YYYY-MM-DD`.
    public let date: String
    public let weekday: String
    public let restDay: Bool
    /// Minutes from midnight.
    public let workStart: Int
    public let workEnd: Int
    public let blocks: [Block]
    /// The day's 固定日程: 作息 slots, each holding the 要务 assigned to it.
    public let fixed: [Fixed]
    public var id: String { date }

    /// One 固定日程 on the day, as the calendar draws it.
    public struct Fixed: Sendable, Equatable {
      public let candidateID: String
      public let start: Int
      public let end: Int
      public let title: String
      /// The title and what it holds that day.
      public let text: String
      public let floor: Bool
      public let color: String?
      /// The 要务 inside it that day.
      public let itemKeys: [String]
      /// complete / partial / missed / defer, up to today.
      public let state: String?
      public init(candidateID: String, start: Int, end: Int, title: String, text: String, floor: Bool = false, color: String? = nil, itemKeys: [String] = [], state: String? = nil) {
        self.candidateID = candidateID
        self.start = start
        self.end = end
        self.title = title
        self.text = text
        self.floor = floor
        self.color = color
        self.itemKeys = itemKeys
        self.state = state
      }
    }

    public init(date: String, weekday: String, restDay: Bool, workStart: Int = 9 * 60 + 30, workEnd: Int = 18 * 60 + 30, blocks: [Block] = [], fixed: [Fixed] = []) {
      self.fixed = fixed
      self.date = date
      self.weekday = weekday
      self.restDay = restDay
      self.workStart = workStart
      self.workEnd = workEnd
      self.blocks = blocks
    }
  }

  /// An event on the user's calendar (Feishu). Not editable here.
  public struct Event: Sendable, Equatable {
    public let date: String
    /// Minutes from midnight; nil for an all-day event.
    public let start: Int?
    public let end: Int?
    public let title: String
    public init(date: String, start: Int?, end: Int?, title: String) {
      self.date = date
      self.start = start
      self.end = end
      self.title = title
    }
  }

  public let cycleID: String
  /// The service's today, so "past" and "today" agree with the plan's calendar.
  public let today: String
  public let items: [Item]
  public let days: [Day]
  public var schedule: CycleSchedule?
  /// A generation is in flight.
  public let running: Bool
  /// Why the last generation failed, if it did.
  public let error: String?
  public let events: [Event]
  /// The service's clock now, minutes from midnight, for the now line.
  public let nowMinute: Int?
  /// How each session was left, by session id, up to today.
  public let states: [String: String]

  public init(cycleID: String, today: String, items: [Item], days: [Day], schedule: CycleSchedule?, running: Bool, error: String? = nil, events: [Event] = [], nowMinute: Int? = nil, states: [String: String] = [:]) {
    self.states = states
    self.cycleID = cycleID
    self.today = today
    self.items = items
    self.days = days
    self.schedule = schedule
    self.running = running
    self.error = error
    self.events = events
    self.nowMinute = nowMinute
  }

  /// The cycle's days in weeks of seven, for the week view.
  public var weeks: [[Day]] {
    stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
  }

  /// Items grouped by role, in the cycle file's order.
  public var roles: [(role: String, items: [Item])] {
    var order: [String] = []
    var groups: [String: [Item]] = [:]
    for item in items {
      let role = Self.role(of: item.okr)
      if groups[role] == nil { order.append(role) }
      groups[role, default: []].append(item)
    }
    return order.map { ($0, groups[$0] ?? []) }
  }

  /// "工作-UX designer。探索…" → "工作"; the objective's opening word is the role.
  public static func role(of okr: String) -> String {
    let trimmed = okr.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return "其他" }
    let separators = CharacterSet(charactersIn: "-－·・:：。， ")
    let head = trimmed.unicodeScalars.split(whereSeparator: { separators.contains($0) }).first.map { String(String.UnicodeScalarView($0)) } ?? trimmed
    return head.isEmpty ? trimmed : head
  }

  /// Total minutes planned on a day, for the column's load line.
  public func minutes(on date: String) -> Int {
    (schedule?.sessions ?? []).filter { $0.date == date }.reduce(0) { $0 + $1.minutes }
  }
}

public struct CycleSchedule: Sendable, Equatable {
  public var generatedAt: Date?
  public var editedAt: Date?
  public var sessions: [ScheduleSession]
  public var deadlines: [ScheduleDeadline]
  public var note: String?

  public init(generatedAt: Date? = nil, editedAt: Date? = nil, sessions: [ScheduleSession], deadlines: [ScheduleDeadline], note: String? = nil) {
    self.generatedAt = generatedAt
    self.editedAt = editedAt
    self.sessions = sessions
    self.deadlines = deadlines
    self.note = note
  }

  public func sessions(item key: String, on date: String) -> [ScheduleSession] {
    sessions.filter { $0.itemKey == key && $0.date == date }
  }

  public func deadline(item key: String) -> String? {
    deadlines.first { $0.itemKey == key }?.date
  }
}

public struct ScheduleSession: Sendable, Equatable, Identifiable {
  public let id: String
  public var itemKey: String
  public var label: String
  public var date: String
  /// `HH:mm`, big rocks only.
  public var start: String?
  public var minutes: Int
  public var bigRock: Bool
  /// What this session does — one step of the 要务, e.g. "整理回访表格，分析国内外用户".
  public var step: String?
  /// Not happening (dropped on Today, or taken by an ad-hoc session). Kept so
  /// saving from here does not bring it back, and so Today can undo it.
  public var skipped: Bool = false
  public var movedFrom: String?
  public var adhoc: Bool = false
  public var takenBy: String?

  /// The step when there is one, else the 要务 itself.
  public var title: String { step.flatMap { $0.isEmpty ? nil : $0 } ?? label }

  public init(id: String, itemKey: String, label: String, date: String, start: String? = nil, minutes: Int, bigRock: Bool = false, step: String? = nil, skipped: Bool = false, movedFrom: String? = nil, adhoc: Bool = false, takenBy: String? = nil) {
    self.skipped = skipped
    self.movedFrom = movedFrom
    self.adhoc = adhoc
    self.takenBy = takenBy
    self.id = id
    self.itemKey = itemKey
    self.label = label
    self.date = date
    self.start = start
    self.minutes = minutes
    self.bigRock = bigRock
    self.step = step
  }
}

public struct ScheduleDeadline: Sendable, Equatable {
  public var itemKey: String
  public var label: String
  public var date: String

  public init(itemKey: String, label: String, date: String) {
    self.itemKey = itemKey
    self.label = label
    self.date = date
  }
}

public struct CycleScheduleError: Error, Sendable, Equatable {
  public let message: String
  public init(_ message: String) { self.message = message }
}
