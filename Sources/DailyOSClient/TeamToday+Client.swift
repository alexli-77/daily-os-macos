import Foundation
import DailyOSCore

// Teammates' plans for today.
//
// `/api/team/today` reads the service's sync cache on disk — the same cache the
// Cycles screen's teammate view comes from — and never the network, so it is
// as cheap as `/api/today/plan` and just as safe to call on every refresh. The
// 60 s sync loop inside the service is what fills it.

struct TeamTodayResponse: Decodable {
  struct Member: Decodable {
    struct Plan: Decodable {
      /// Same object the owner's `/api/today/plan` returned, minus `plan`/`today`.
      struct Payload: Decodable {
        let generatedAt: String?
        let todos: [TodayPlanResponse.Todo]?
        let feedback: [String: String]?

        enum CodingKeys: String, CodingKey {
          case todos, feedback
          case generatedAt = "generated_at"
        }
      }

      let date: String
      let updatedAt: String?
      let payload: Payload
    }

    let userId: String
    let displayName: String
    let label: String
    let plan: Plan?
    let stale: Bool
  }

  let status: String
  let reason: String
  let today: String
  let members: [Member]
  let syncedAt: String
  let lastError: String
}

extension DailyOSClient {
  public func teamToday() async throws -> (entries: [TeamTodayEntry], sync: TeamSyncState) {
    let response: TeamTodayResponse = try await get("/api/team/today")
    let entries = response.members.map { member -> TeamTodayEntry in
      let feedback = member.plan?.payload.feedback ?? [:]
      let items = (member.plan?.payload.todos ?? [])
        .sorted { $0.rank < $1.rank }
        .map { todo in
          TodoItem(
            id: todo.candidateId,
            text: todo.text,
            kind: .priority,
            state: Self.state(for: feedback[todo.candidateId]),
            estimatedMinutes: todo.minutes
          )
        }
      return TeamTodayEntry(
        id: member.userId,
        displayName: member.label.isEmpty ? member.displayName : member.label,
        items: items,
        staleDate: member.stale ? member.plan?.date : nil,
        hasPlan: member.plan != nil,
        updatedAt: member.plan?.updatedAt.flatMap(TodoWireDate.timestamp)
      )
    }
    let sync = TeamSyncState(
      status: response.status,
      reason: response.reason,
      syncedAt: TodoWireDate.timestamp(response.syncedAt),
      lastError: response.lastError
    )
    return (entries, sync)
  }

  /// The same mapping `todayPlan()` uses for your own rows. Kept in step by
  /// being the same function, not by a comment saying so.
  private static func state(for event: String?) -> TodoState {
    switch event {
    case "complete": .done
    case "defer": .deferred
    default: .open
    }
  }
}
