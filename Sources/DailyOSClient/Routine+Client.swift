import Foundation
import DailyOSCore

// 作息: `/api/routines`.

struct RoutinesResponse: Decodable {
  let today: String?
  let periods: [RoutinePeriod]
  let dayModes: [String: String]?
  let problems: [String]?
}

extension DailyOSClient {
  public func routines() async throws -> RoutineState {
    let response: RoutinesResponse = try await get("/api/routines")
    return RoutineState(today: response.today ?? "", periods: response.periods, dayModes: response.dayModes ?? [:])
  }

  public func saveRoutines(_ periods: [RoutinePeriod]) async throws -> RoutineState {
    struct Request: Encodable { let periods: [RoutinePeriod] }
    let response: RoutinesResponse = try await post("/api/routines", body: Request(periods: periods))
    return RoutineState(today: response.today ?? "", periods: response.periods, dayModes: response.dayModes ?? [:], problems: response.problems ?? [])
  }

  public func setDayMode(date: String?, mode: String) async throws -> String? {
    struct Request: Encodable { let date: String?; let mode: String }
    struct Response: Decodable { let text: String? }
    let response: Response = try await post("/api/routines/day-mode", body: Request(date: date, mode: mode))
    return response.text
  }
}

/// `state.rhythm.today.routine` — today's slice of the 作息.
struct DayRoutinePayload: Decodable {
  struct Mode: Decodable { let id: String; let label: String }
  struct Slot: Decodable {
    let id: String?
    let start: String
    let end: String
    let title: String
    let category: String?
    let color: String?
    let floor: Bool?
    let habit: Bool?
  }
  let period: String
  let dayType: String
  let mode: Mode
  let modes: [Mode]
  let slots: [Slot]

  var model: TodayRoutine {
    TodayRoutine(
      period: period,
      dayType: dayType,
      mode: (mode.id, mode.label),
      modes: modes.map { ($0.id, $0.label) },
      slots: slots.compactMap { slot in
        guard let start = DayStart.minute(fromClock: slot.start) else { return nil }
        let end = slot.end == "24:00" ? 24 * 60 : (DayStart.minute(fromClock: slot.end) ?? start)
        return .init(start: start, end: end, title: slot.title, category: slot.category, color: slot.color, floor: slot.floor ?? false, habit: slot.habit ?? false, blockID: slot.id)
      }
    )
  }
}
