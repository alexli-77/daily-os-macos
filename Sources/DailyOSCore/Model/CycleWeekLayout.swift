import Foundation

/// One day of the 双周排期 drawn as a calendar column.
///
/// The schedule only gives big rocks a time; everything else is "this day".
/// A calendar of one block per big rock and a pile of untimed chips would be
/// the table again, so the untimed sessions are laid into the day's free time
/// — after meetings, meals, routines and big rocks — and drawn as suggestions
/// (dashed) rather than as reservations. Dragging one to a time reserves it.
public enum CycleWeekLayout {
  public enum Kind: Sendable, Equatable {
    /// On the user's calendar; not ours to move.
    case event
    /// A meal or routine from the rhythm settings.
    case routine
    /// A reserved slot.
    case bigRock
    /// An untimed session, placed in free time as a suggestion.
    case suggested
  }

  public struct Placed: Sendable, Equatable, Identifiable {
    public let id: String
    public let kind: Kind
    public let title: String
    public let start: Int
    public let end: Int
    public let session: ScheduleSession?
  }

  public struct DayLayout: Sendable, Equatable {
    public let blocks: [Placed]
    /// Sessions that found no free time before the end of the day.
    public let unplaced: [ScheduleSession]
    /// All-day events and deadlines, for the strip above the hours.
    public let allDay: [String]
  }

  static let lastMinute = 23 * 60 + 30

  public static func layout(_ day: CycleScheduleState.Day, in state: CycleScheduleState) -> DayLayout {
    let events = state.events.filter { $0.date == day.date }
    let sessions = state.schedule?.sessions.filter { $0.date == day.date } ?? []
    var blocks: [Placed] = []
    var busy: [(Int, Int)] = []

    for (index, event) in events.enumerated() {
      guard let start = event.start else { continue }
      let end = max(event.end ?? start + 30, start + 15)
      blocks.append(Placed(id: "event:\(day.date):\(index)", kind: .event, title: event.title, start: start, end: end, session: nil))
      busy.append((start, end))
    }
    for (index, block) in day.blocks.enumerated() {
      blocks.append(Placed(id: "routine:\(day.date):\(index)", kind: .routine, title: block.label, start: block.start, end: block.end, session: nil))
      busy.append((block.start, block.end))
    }
    for session in sessions {
      guard session.bigRock, let start = session.start.flatMap(DayStart.minute(fromClock:)) else { continue }
      blocks.append(Placed(id: session.id, kind: .bigRock, title: session.title, start: start, end: start + session.minutes, session: session))
      busy.append((start, start + session.minutes))
    }

    // Untimed sessions in 要务 order (MIT first), into the first free gap from
    // the start of the work day — or from now, today.
    let order = Dictionary(uniqueKeysWithValues: state.items.enumerated().map { ($1.key, ($1.mit ? 0 : 1000) + $0) })
    let untimed = sessions
      .filter { !($0.bigRock && $0.start != nil) }
      .sorted { (order[$0.itemKey] ?? 9999) < (order[$1.itemKey] ?? 9999) }
    var from = day.workStart
    if day.date == state.today, let now = state.nowMinute { from = max(from, (now + 14) / 15 * 15) }
    var unplaced: [ScheduleSession] = []
    for session in untimed {
      if let start = firstFree(from: from, minutes: session.minutes, busy: busy) {
        blocks.append(Placed(id: session.id, kind: .suggested, title: session.title, start: start, end: start + session.minutes, session: session))
        busy.append((start, start + session.minutes))
      } else {
        unplaced.append(session)
      }
    }

    var allDay = events.filter { $0.start == nil }.map(\.title)
    for deadline in state.schedule?.deadlines ?? [] where deadline.date == day.date {
      allDay.append("截止 · \(deadline.label)")
    }
    return DayLayout(blocks: blocks.sorted { $0.start < $1.start }, unplaced: unplaced, allDay: allDay)
  }

  static func firstFree(from: Int, minutes: Int, busy: [(Int, Int)]) -> Int? {
    var start = from
    while start + minutes <= lastMinute {
      if let clash = busy.first(where: { $0.0 < start + minutes && start < $0.1 }) {
        start = max(start + 15, (clash.1 + 14) / 15 * 15)
      } else {
        return start
      }
    }
    return nil
  }
}
