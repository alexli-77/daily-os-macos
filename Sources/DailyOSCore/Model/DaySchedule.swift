import Foundation

/// Today's call sheet: what runs when, what is late, and where "now" falls.
///
/// Pure arithmetic, deliberately separated from the view. Every interesting rule
/// here is a *number* — where a row starts, which rows are behind, what time the
/// day ends — and a screen full of times always looks like a screen full of
/// times. A slot computed from the wrong cursor, a late flag that never fires, an
/// end time that quietly excludes half the list: none of those announce
/// themselves, so they are checked in `daily-os-checks` rather than looked at.
///
/// ## The rules, and why each one
///
/// - **Deferred rows take no time.** They get no slot and do not move the
///   cursor, so pushing something to tomorrow actually gives today's remaining
///   rows their time back. A deferred row that still occupied its hour would
///   make deferring cosmetic.
/// - **Done rows keep their slot and still move the cursor.** The morning
///   happened; erasing a finished row's hour would rewrite the day so that
///   everything left appears to start earlier than it can.
/// - **Partial counts half.** Half the work is behind you, so half the estimate
///   is behind you too.
/// - **Only unfinished work counts toward `remaining`.** Done rows advance the
///   clock but are not "still to do" — those are two different questions and one
///   number cannot answer both.
/// - **A row with no estimate gets no slot.** Inventing a duration would make
///   the projected end time a fiction, and the end time is the one number on the
///   screen you are supposed to be able to act on. It is counted in
///   `missingEstimates` instead, so a short total is visibly short rather than
///   silently wrong.
public struct DaySchedule: Sendable, Equatable {
  /// One line of the call sheet.
  public struct Row: Sendable, Equatable, Identifiable {
    public let item: TodoItem
    public var id: String { item.id }
    /// Position in the sheet, 1-based. Also the ledger key half that says
    /// *where* the row was when it was acted on.
    public let rank: Int
    /// Minutes from midnight. `nil` for a deferred row or one with no estimate.
    public let start: Int?
    public let end: Int?
    /// The estimate this row actually contributes — halved when partial.
    public let minutes: Int?
    /// Open (or partial) and its slot already ended. Resolved rows are never late.
    public let isLate: Bool

    public init(item: TodoItem, rank: Int, start: Int?, end: Int?, minutes: Int?, isLate: Bool) {
      self.item = item
      self.rank = rank
      self.start = start
      self.end = end
      self.minutes = minutes
      self.isLate = isLate
    }
  }

  /// A fixed, non-task band on the timeline — a meal, a routine or a fixed
  /// meeting. It comes from the user's rhythm (`user.rhythm.meal_blocks` and
  /// `fixed_blocks`), sits at a wall-clock time the tasks flow around, and is
  /// never checkable/draggable. Kept out of `rows` so the task invariants (drag
  /// indices, now-line, plan count) are untouched.
  public struct FixedBlock: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
      case meal, routine, meeting
    }

    public let id: String
    public let label: String
    public let start: Int
    public let end: Int
    public let kind: Kind
    /// A second line, e.g. what the routine is for. Nil when there is none.
    public let note: String?

    public init(id: String, label: String, start: Int, end: Int, kind: Kind = .meal, note: String? = nil) {
      self.id = id
      self.label = label
      self.start = start
      self.end = end
      self.kind = kind
      self.note = note
    }
  }

  public let rows: [Row]
  /// Meal/break bands that fell within the planned day, in start order. The view
  /// draws these between task rows; the arithmetic already pushed tasks past them.
  public let fixedBlocks: [FixedBlock]
  /// Index in `rows` where the now-line is drawn — the first row that starts at
  /// or after `now`. Equal to `rows.count` when the whole sheet is behind you.
  public let nowIndex: Int
  /// Minutes from midnight for the now-line's label.
  public let now: Int
  /// Unfinished minutes still on the sheet.
  public let remaining: Int
  /// Where the cursor lands after the last row — the projected finish.
  public let endOfDay: Int
  public let doneCount: Int
  public let partialCount: Int
  public let deferredCount: Int
  public let openCount: Int
  /// Rows that are late, in sheet order. The overdue banner's contents.
  public let lateRows: [Row]
  /// Unfinished rows the planner gave no estimate, so the totals can say so.
  public let missingEstimates: Int

  public var total: Int { rows.count }

  /// Every row is either done or deferred — the "today is clear" state.
  ///
  /// Deferred counts. A day you finished by honestly pushing two things to
  /// tomorrow is still a day you are done with, and withholding the marker until
  /// everything is ticked would only teach people to tick things they did not do.
  public var isClear: Bool { !rows.isEmpty && doneCount + deferredCount == rows.count }

  /// Build the sheet.
  ///
  /// - Parameters:
  ///   - items: in sheet order. The caller owns the ordering (drag, rank).
  ///   - startMinute: when the day's first slot begins — see `DayStart`.
  ///   - nowMinute: minutes from midnight.
  ///   - meals: fixed wall-clock bands (from `user.rhythm.meal_blocks`) that
  ///     tasks must not run through. Default empty keeps the plain accumulate.
  public static func build(items: [TodoItem], startMinute: Int, nowMinute: Int, meals: [FixedBlock] = []) -> DaySchedule {
    var cursor = startMinute
    var rows: [Row] = []
    var late: [Row] = []
    var remaining = 0
    var missing = 0
    // Sorted, and dropped if they end before the day even starts (a lunch at
    // 12:00 is irrelevant to a plan that begins at 14:00). Consumed as the cursor
    // passes them; whatever is left over never happened within the planned day.
    var pendingMeals = meals.filter { $0.end > startMinute }.sorted { $0.start < $1.start }
    var placedMeals: [FixedBlock] = []

    /// The length a row occupies: its estimate, halved when partial. A pinned
    /// row with no estimate still needs a length to sit on the clock.
    func length(of item: TodoItem) -> Int? {
      guard let estimate = item.estimatedMinutes ?? (item.pinnedStart != nil ? 30 : nil), estimate > 0 else { return nil }
      return item.state == .partial ? Int((Double(estimate) / 2).rounded()) : estimate
    }

    // Rows the user pinned (LEO-331) sit where they were put, and the rows that
    // are laid out automatically flow around them exactly as around a meal.
    // Deferred rows take no time, pinned or not.
    var pendingPins: [(start: Int, end: Int)] = items
      .compactMap { item in
        guard item.state != .deferred, let start = item.pinnedStart, let minutes = length(of: item) else { return nil }
        return (start, start + minutes)
      }
      .filter { $0.end > startMinute }
      .sorted { $0.start < $1.start }
    let latestPinnedEnd = pendingPins.map(\.end).max()

    func append(_ row: Row) {
      rows.append(row)
      if row.isLate { late.append(row) }
      if let minutes = row.minutes, row.item.state != .done { remaining += minutes }
    }

    for (index, item) in items.enumerated() {
      let rank = index + 1

      if item.state == .deferred {
        rows.append(Row(item: item, rank: rank, start: nil, end: nil, minutes: nil, isLate: false))
        continue
      }

      if let start = item.pinnedStart, let minutes = length(of: item) {
        let end = start + minutes
        let isLate = (item.state == .open || item.state == .partial) && end < nowMinute
        append(Row(item: item, rank: rank, start: start, end: end, minutes: minutes, isLate: isLate))
        continue
      }

      guard let minutes = length(of: item) else {
        // No slot, and the cursor does not move. Counted so the footer can admit
        // the total is incomplete.
        if item.state != .done { missing += 1 }
        rows.append(Row(item: item, rank: rank, start: nil, end: nil, minutes: nil, isLate: false))
        continue
      }

      // A meal (or a pinned row) is fixed on the clock; a task may not run
      // through one. Step past anything the cursor has already reached, then —
      // if this task would spill into the next obstacle — let the obstacle go
      // first and start the task after it. The gap this can leave is real free
      // time, not an error.
      //
      // Repeated until the task fits: stepping past one block can land the
      // cursor on the next (a meeting that ends as lunch begins), and checking
      // only once put the task on top of the second block.
      while true {
        while let meal = pendingMeals.first, meal.start <= cursor {
          placedMeals.append(meal)
          cursor = max(cursor, meal.end)
          pendingMeals.removeFirst()
        }
        while let pin = pendingPins.first, pin.start <= cursor {
          cursor = max(cursor, pin.end)
          pendingPins.removeFirst()
        }
        let nextMeal = pendingMeals.first.map(\.start) ?? Int.max
        let nextPin = pendingPins.first?.start ?? Int.max
        // Stepping past a pin can land the cursor on a meal, and the other way
        // round: go again until neither is behind the cursor.
        if nextMeal <= cursor || nextPin <= cursor { continue }
        guard min(nextMeal, nextPin) < cursor + minutes else { break }
        if nextMeal <= nextPin, let meal = pendingMeals.first {
          placedMeals.append(meal)
          cursor = max(cursor, meal.end)
          pendingMeals.removeFirst()
        } else if let pin = pendingPins.first {
          cursor = max(cursor, pin.end)
          pendingPins.removeFirst()
        }
      }

      let end = cursor + minutes
      let isLate = (item.state == .open || item.state == .partial) && end < nowMinute
      append(Row(item: item, rank: rank, start: cursor, end: end, minutes: minutes, isLate: isLate))
      cursor = end
    }

    // The first row, in sheet order, that has not started yet — the line lands
    // above it whatever its state.
    let nowIndex = rows.firstIndex { ($0.start ?? Int.min) >= nowMinute } ?? rows.count

    return DaySchedule(
      rows: rows,
      fixedBlocks: placedMeals,
      nowIndex: nowIndex,
      now: nowMinute,
      remaining: remaining,
      endOfDay: max(cursor, latestPinnedEnd ?? cursor),
      doneCount: items.filter { $0.state == .done }.count,
      partialCount: items.filter { $0.state == .partial }.count,
      deferredCount: items.filter { $0.state == .deferred }.count,
      openCount: items.filter { $0.state == .open }.count,
      lateRows: late,
      missingEstimates: missing
    )
  }

}

// MARK: - Formatting

extension DaySchedule {
  /// `13:40`, from minutes-since-midnight. Wraps past midnight rather than
  /// printing `26:10` — a day that overruns is still a clock.
  public static func clock(_ minute: Int) -> String {
    let m = ((minute % 1440) + 1440) % 1440
    return String(format: "%02d:%02d", m / 60, m % 60)
  }

  /// `2h` / `1h30m` / `45m`, matching the prototype's compact form.
  public static func duration(_ minutes: Int) -> String {
    guard minutes >= 60 else { return "\(minutes)m" }
    let h = minutes / 60, m = minutes % 60
    return m == 0 ? "\(h)h" : "\(h)h\(m)m"
  }

  /// Minutes since midnight for a `Date`, in the current calendar.
  public static func minute(of date: Date, calendar: Calendar = .current) -> Int {
    let parts = calendar.dateComponents([.hour, .minute], from: date)
    return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
  }
}

// MARK: - Where the day starts

/// When the first slot begins.
///
/// **There is no "start of day" setting.** `user.rhythm` carries `enabled`,
/// `file`, `rest_days` and `work_task_cap_on_rest_days` and nothing about the
/// clock, so this resolves from what the service does expose.
///
/// The interaction prototype hardcodes `START = 10:30`, which is the shape of a
/// working day rather than anything the app can read today. `generatedAt` is the
/// documented fallback in the handoff — and it is a genuine compromise, not an
/// equivalent: a plan written by the 07:43 scheduler starts the sheet at 07:43,
/// so by mid-morning the first rows read as late for no better reason than that
/// a cron job is an early riser.
///
/// `workStart` (from `user.rhythm.working_hours.start`) is now that upstream
/// input: when the user has told us their day begins at 09:30, the sheet begins
/// at 09:30 regardless of when the 07:43 scheduler happened to write the plan.
/// Falls back to the plan timestamp, then to a fixed 09:30, when it is absent.
public enum DayStart {
  /// 09:30 — used only when there is neither a work start nor a plan timestamp.
  public static let fallbackMinute = 9 * 60 + 30

  public static func resolve(generatedAt: Date?, workStart: Int? = nil, calendar: Calendar = .current) -> Int {
    if let workStart { return workStart }
    guard let generatedAt else { return fallbackMinute }
    return DaySchedule.minute(of: generatedAt, calendar: calendar)
  }

  /// Parse "HH:mm" to minutes-from-midnight. `nil` on anything malformed, so a
  /// bad value falls through to the timestamp rather than to 00:00.
  public static func minute(fromClock clock: String) -> Int? {
    let parts = clock.split(separator: ":")
    guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
          (0...23).contains(h), (0...59).contains(m) else { return nil }
    return h * 60 + m
  }
}

// MARK: - Overlap columns

/// Side-by-side columns for blocks that overlap on the timeline, the way a
/// calendar draws two meetings at the same hour (LEO-331).
///
/// Blocks that overlap, directly or through a chain, form one group; each group
/// gets as many columns as it needs at its busiest, and every block takes the
/// leftmost column free at its start. A block that overlaps nothing gets the
/// full width.
public enum TimelineColumns {
  public struct Placement: Sendable, Equatable {
    public let column: Int
    public let count: Int

    public init(column: Int, count: Int) {
      self.column = column
      self.count = count
    }
  }

  public struct Span: Sendable {
    public let id: String
    public let start: Int
    public let end: Int

    public init(id: String, start: Int, end: Int) {
      self.id = id
      self.start = start
      self.end = end
    }
  }

  public static func assign(_ spans: [Span]) -> [String: Placement] {
    let sorted = spans.sorted { $0.start < $1.start || ($0.start == $1.start && $0.end > $1.end) }
    var result: [String: Placement] = [:]
    var group: [(id: String, column: Int)] = []
    var columnEnds: [Int] = []
    var groupEnd = Int.min

    func close() {
      for entry in group { result[entry.id] = Placement(column: entry.column, count: max(columnEnds.count, 1)) }
      group = []
      columnEnds = []
    }

    for span in sorted {
      if span.start >= groupEnd { close() }
      if let free = columnEnds.firstIndex(where: { $0 <= span.start }) {
        columnEnds[free] = span.end
        group.append((span.id, free))
      } else {
        columnEnds.append(span.end)
        group.append((span.id, columnEnds.count - 1))
      }
      groupEnd = max(groupEnd, span.end)
    }
    close()
    return result
  }
}
