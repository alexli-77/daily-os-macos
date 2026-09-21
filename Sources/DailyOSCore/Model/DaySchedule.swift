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

  public let rows: [Row]
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
  public static func build(items: [TodoItem], startMinute: Int, nowMinute: Int) -> DaySchedule {
    var cursor = startMinute
    var rows: [Row] = []
    var late: [Row] = []
    var remaining = 0
    var missing = 0
    var nowIndex = -1

    for (index, item) in items.enumerated() {
      let rank = index + 1

      if item.state == .deferred {
        rows.append(Row(item: item, rank: rank, start: nil, end: nil, minutes: nil, isLate: false))
        continue
      }

      guard let estimate = item.estimatedMinutes, estimate > 0 else {
        // No slot, and the cursor does not move. Counted so the footer can admit
        // the total is incomplete.
        if item.state != .done { missing += 1 }
        rows.append(Row(item: item, rank: rank, start: nil, end: nil, minutes: nil, isLate: false))
        continue
      }

      let minutes = item.state == .partial ? Int((Double(estimate) / 2).rounded()) : estimate
      let end = cursor + minutes

      // Checked before the row is appended, and before the done-row shortcut, so
      // the line lands above the first row that has not started yet whatever its
      // state. Using `rows.count` here is the index this row is about to take.
      if nowIndex < 0 && cursor >= nowMinute { nowIndex = rows.count }

      let isLate = (item.state == .open || item.state == .partial) && end < nowMinute
      let row = Row(item: item, rank: rank, start: cursor, end: end, minutes: minutes, isLate: isLate)
      rows.append(row)
      if isLate { late.append(row) }
      if item.state != .done { remaining += minutes }
      cursor = end
    }

    if nowIndex < 0 { nowIndex = rows.count }

    return DaySchedule(
      rows: rows,
      nowIndex: nowIndex,
      now: nowMinute,
      remaining: remaining,
      endOfDay: cursor,
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
/// Kept as one function with one input so that adding `rhythm.start_time`
/// upstream is a single line here and changes nothing else.
public enum DayStart {
  /// 09:30 — used only when there is no plan timestamp at all.
  public static let fallbackMinute = 9 * 60 + 30

  public static func resolve(generatedAt: Date?, calendar: Calendar = .current) -> Int {
    guard let generatedAt else { return fallbackMinute }
    return DaySchedule.minute(of: generatedAt, calendar: calendar)
  }
}
