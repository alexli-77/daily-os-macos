import Foundation
import DailyOSCore

// Today's plan.
//
// Separate from the todo inbox, which is what this app showed before and which
// is a different set of rows: the inbox is what you captured, the plan is what
// the planner decided this morning. They overlap enough to look right and
// differ enough to be wrong, which is the worst combination — the web showed
// one list and the Mac app showed another, both plausible.

struct TodayPlanResponse: Decodable {
  struct Plan: Decodable {
    let date: String
    let workflow: String
    /// The newest plan is from an earlier day — today's has not run yet.
    let stale: Bool
  }

  struct Todo: Decodable {
    let rank: Int
    let text: String
    let candidateId: String
    /// Absent on every plan written before the prompt asked for it, and absent
    /// whenever the model declined to guess. Optional the whole way down so
    /// "no estimate" stays distinguishable from "zero minutes".
    let minutes: Int?
  }

  let plan: Plan?
  let todos: [Todo]
  /// candidateId → `complete` / `defer` / `update`, today's entries only.
  let feedback: [String: String]
  let today: String
}

/// What Today needs to draw its plan column.
public struct TodayPlan: Sendable, Equatable {
  public let items: [TodoItem]
  /// Present when a plan exists but is not from today.
  public let staleDate: String?
  public let hasPlan: Bool

  public init(items: [TodoItem], staleDate: String?, hasPlan: Bool) {
    self.items = items
    self.staleDate = staleDate
    self.hasPlan = hasPlan
  }
}

extension DailyOSClient {
  public func todayPlan() async throws -> TodayPlan {
    let response: TodayPlanResponse = try await get("/api/today/plan")
    guard let plan = response.plan else {
      return TodayPlan(items: [], staleDate: nil, hasPlan: false)
    }

    let items = response.todos
      .sorted { $0.rank < $1.rank }
      .map { todo -> TodoItem in
        // The identity is the candidate id, because that is what feedback is
        // recorded against. Using the rank or the text would break the moment
        // the planner reorders or rewords a line, and the tick the user made
        // this morning would land on a different row.
        TodoItem(
          id: todo.candidateId,
          text: todo.text,
          kind: .priority,
          state: Self.state(for: response.feedback[todo.candidateId]),
          // Already the user's own number when they have corrected one: the
          // service merges the newest ledger edit over the model's guess, so
          // this client never has to know an override mechanism exists.
          estimatedMinutes: todo.minutes
        )
      }

    return TodayPlan(
      items: items,
      staleDate: plan.stale ? plan.date : nil,
      hasPlan: true
    )
  }

  /// Record how the user reacted to one ranked plan row.
  ///
  /// `rank` travels with the event because the ledger is keyed on
  /// (date, candidateId, rank) — it is a feedback signal for the scorer, not
  /// just a status flag, and dropping the rank would throw away the half of it
  /// that says *where in the list* the row was when it was acted on.
  ///
  /// `minutes` is only meaningful on `update` — the service ignores it on the
  /// other two, because completing something says nothing about how long it
  /// took and a duration riding along on a tick would silently rewrite the
  /// estimate.
  public func recordPlanFeedback(
    candidateID: String,
    rank: Int,
    event: String,
    note: String?,
    minutes: Int? = nil
  ) async throws {
    struct Request: Encodable {
      let candidateId: String
      let rank: Int
      let event: String
      let note: String?
      let minutes: Int?
    }
    try await post(
      "/api/today/todo-feedback",
      body: Request(candidateId: candidateID, rank: rank, event: event, note: note, minutes: minutes)
    )
  }

  private static func state(for event: String?) -> TodoState {
    switch event {
    case "complete": .done
    case "defer": .deferred
    // `update` means the row was edited, not resolved — it is still open.
    default: .open
    }
  }
}
