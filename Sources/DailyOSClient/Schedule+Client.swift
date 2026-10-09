import Foundation
import DailyOSCore

// 双周排期: `/api/cycles/schedule`.

struct CycleScheduleResponse: Decodable {
  struct Item: Decodable { let key: String; let text: String; let okr: String; let mit: Bool }
  struct Day: Decodable {
    struct Hours: Decodable { let start: String; let end: String }
    struct Block: Decodable { let label: String; let start: String; let end: String }
    let date: String
    let weekday: String
    let restDay: Bool
    let workingHours: Hours?
    let blocks: [Block]?
    let fixed: [Fixed]?
    struct Fixed: Decodable {
      let candidateId: String
      let start: String
      let end: String
      let title: String
      let text: String
      let floor: Bool?
      let color: String?
      let itemKeys: [String]?
      let state: String?
    }
  }
  struct Event: Decodable { let date: String; let start: String?; let end: String?; let title: String }
  let id: String
  let today: String
  let schedule: ScheduleWire?
  let items: [Item]
  let days: [Day]
  let running: Bool
  let error: String?
  let events: [Event]?
  let now: String?
  let states: [String: String]?
}

struct ScheduleWire: Codable {
  struct Session: Codable {
    let id: String?
    let itemKey: String
    let label: String
    let date: String
    let start: String?
    let minutes: Int
    let bigRock: Bool?
    let step: String?
    var skipped: Bool? = nil
    var movedFrom: String? = nil
    var adhoc: Bool? = nil
    var takenBy: String? = nil
  }
  struct Deadline: Codable { let itemKey: String; let label: String; let date: String }
  let generatedAt: String?
  let editedAt: String?
  let sessions: [Session]
  let deadlines: [Deadline]
  let note: String?

  var model: CycleSchedule {
    CycleSchedule(
      generatedAt: generatedAt.flatMap(TodoWireDate.timestamp),
      editedAt: editedAt.flatMap(TodoWireDate.timestamp),
      sessions: sessions.map {
        ScheduleSession(id: $0.id ?? UUID().uuidString, itemKey: $0.itemKey, label: $0.label, date: $0.date, start: $0.start, minutes: $0.minutes, bigRock: $0.bigRock ?? false, step: $0.step, skipped: $0.skipped ?? false, movedFrom: $0.movedFrom, adhoc: $0.adhoc ?? false, takenBy: $0.takenBy)
      },
      deadlines: deadlines.map { ScheduleDeadline(itemKey: $0.itemKey, label: $0.label, date: $0.date) },
      note: note
    )
  }
}

extension DailyOSClient {
  public func cycleSchedule(cycleID: String) async throws -> CycleScheduleState {
    let id = cycleID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cycleID
    let response: CycleScheduleResponse = try await get("/api/cycles/schedule?id=\(id)")
    return CycleScheduleState(
      cycleID: response.id,
      today: response.today,
      items: response.items.map { .init(key: $0.key, text: $0.text, okr: $0.okr, mit: $0.mit) },
      days: response.days.map { day in
        .init(
          date: day.date,
          weekday: day.weekday,
          restDay: day.restDay,
          workStart: day.workingHours.flatMap { DayStart.minute(fromClock: $0.start) } ?? 9 * 60 + 30,
          workEnd: day.workingHours.flatMap { DayStart.minute(fromClock: $0.end) } ?? 18 * 60 + 30,
          blocks: (day.blocks ?? []).compactMap { block in
            guard let start = DayStart.minute(fromClock: block.start), let end = DayStart.minute(fromClock: block.end) else { return nil }
            return .init(label: block.label, start: start, end: end)
          },
          fixed: (day.fixed ?? []).compactMap { row in
            guard let start = DayStart.minute(fromClock: row.start) else { return nil }
            let end = row.end == "24:00" ? 24 * 60 : (DayStart.minute(fromClock: row.end) ?? start)
            return .init(candidateID: row.candidateId, start: start, end: end, title: row.title, text: row.text, floor: row.floor ?? false, color: row.color, itemKeys: row.itemKeys ?? [], state: row.state)
          }
        )
      },
      schedule: response.schedule?.model,
      running: response.running,
      error: response.error,
      events: (response.events ?? []).map { event in
        .init(
          date: event.date,
          start: event.start.flatMap(DayStart.minute(fromClock:)),
          // "24:00" is not a clock DayStart accepts; it is the end of the day.
          end: event.end == "24:00" ? 24 * 60 : event.end.flatMap(DayStart.minute(fromClock:)),
          title: event.title
        )
      },
      nowMinute: response.now.flatMap(DayStart.minute(fromClock:)),
      states: response.states ?? [:]
    )
  }

  public func generateCycleSchedule(cycleID: String) async throws -> String? {
    struct Request: Encodable { let id: String }
    struct Response: Decodable { let text: String? }
    let response: Response = try await post("/api/cycles/schedule/generate", body: Request(id: cycleID))
    return response.text
  }

  public func saveCycleSchedule(cycleID: String, sessions: [ScheduleSession], deadlines: [ScheduleDeadline]) async throws -> CycleSchedule? {
    struct Request: Encodable {
      let id: String
      let sessions: [ScheduleWire.Session]
      let deadlines: [ScheduleWire.Deadline]
    }
    struct Response: Decodable { let schedule: ScheduleWire? }
    let response: Response = try await post(
      "/api/cycles/schedule",
      body: Request(
        id: cycleID,
        sessions: sessions.map {
          .init(
            id: $0.id, itemKey: $0.itemKey, label: $0.label, date: $0.date, start: $0.start, minutes: $0.minutes, bigRock: $0.bigRock, step: $0.step,
            skipped: $0.skipped ? true : nil, movedFrom: $0.movedFrom, adhoc: $0.adhoc ? true : nil, takenBy: $0.takenBy
          )
        },
        deadlines: deadlines.map { .init(itemKey: $0.itemKey, label: $0.label, date: $0.date) }
      )
    )
    return response.schedule?.model
  }
}
