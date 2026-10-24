import Foundation
import DailyOSCore

// 回收: `GET /api/day/wrapups`, `POST /api/day/wrapup`, `POST /api/day/move-to-today`.

struct WrapupsResponse: Decodable {
  struct Day: Decodable {
    struct Row: Decodable {
      let candidateId: String
      let rank: Int
      let text: String
      let fixed: Bool?
      let state: String?
    }
    let date: String
    let todos: [Row]
  }
  let today: String
  let pending: [Day]
}

extension DailyOSClient {
  public func pendingWrapups() async throws -> [WrapupDay] {
    let response: WrapupsResponse = try await get("/api/day/wrapups")
    return response.pending.map { day in
      WrapupDay(
        date: day.date,
        today: response.today,
        rows: day.todos.map { row in
          WrapupDay.Row(id: row.candidateId, rank: row.rank, text: row.text, state: Self.wrapupState(row.state), isFixed: row.fixed ?? false)
        }
      )
    }
  }

  /// Returns the service's line for the toast.
  public func resolveWrapup(date: String, action: String) async throws -> String? {
    struct Body: Encodable { let date: String; let action: String }
    struct Response: Decodable { let text: String? }
    let response: Response = try await post("/api/day/wrapup", body: Body(date: date, action: action))
    return response.text
  }

  public func moveRowToToday(date: String, candidateID: String, rank: Int) async throws -> String? {
    struct Body: Encodable { let date: String; let candidateId: String; let rank: Int }
    struct Response: Decodable { let text: String?; let schedule: String? }
    let response: Response = try await post("/api/day/move-to-today", body: Body(date: date, candidateId: candidateID, rank: rank))
    return [response.text, response.schedule].compactMap { $0 }.joined(separator: "；")
  }

  private static func wrapupState(_ event: String?) -> TodoState {
    switch event {
    case "complete": .done
    case "partial": .partial
    case "missed": .missed
    case "defer": .deferred
    default: .open
    }
  }
}
