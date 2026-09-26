import Foundation
import DailyOSCore

// Past days: `GET /api/day/plan?date=YYYY-MM-DD`.
//
// Same row shape as `/api/today/plan`, plus the evening review and the list of
// days that have a plan. Decoded here rather than by widening
// `TodayPlanResponse`, because that type is Today's contract and a field added
// for history would become a field Today depends on.

struct DayPlanResponse: Decodable {
  struct Plan: Decodable {
    let date: String
    let generatedAt: String?

    enum CodingKeys: String, CodingKey {
      case date
      case generatedAt = "generated_at"
    }
  }

  struct Review: Decodable {
    struct Item: Decodable {
      let candidateId: String
      let text: String
      let status: String
      let evidence: String?
    }

    let reconciliation: [Item]
    let note: String?
  }

  let date: String
  let dates: [String]
  let today: String
  let plan: Plan?
  let todos: [TodayPlanResponse.Todo]
  let feedback: [String: String]
  let review: Review?
  let rawPlan: String?
}

extension DailyOSClient {
  /// `date` nil asks the service for the most recent day before today with a plan.
  public func dayHistory(date: String?) async throws -> DayHistory {
    let path = date.map { "/api/day/plan?date=\($0)" } ?? "/api/day/plan"
    let response: DayPlanResponse = try await get(path)
    let items = response.todos
      .sorted { $0.rank < $1.rank }
      .map { todo in
        TodoItem(
          id: todo.candidateId,
          text: todo.text,
          kind: .priority,
          state: Self.planState(for: response.feedback[todo.candidateId]),
          sourceRef: Self.sourceRef(for: todo.candidateId),
          estimatedMinutes: todo.minutes
        )
      }
    let review = response.review.map { review in
      DayReview(
        items: review.reconciliation.enumerated().map { index, item in
          DayReview.Item(
            // A review line may have no candidate id (it reconciled something
            // the plan did not list); the index keeps those unique.
            id: item.candidateId.isEmpty ? "review-\(index)" : "\(item.candidateId)#\(index)",
            text: item.text,
            // An unknown status reads as "没动", the one that claims nothing.
            status: DayReview.Item.Status(rawValue: item.status) ?? .open,
            evidence: item.evidence?.isEmpty == false ? item.evidence : nil
          )
        },
        note: review.note?.isEmpty == false ? review.note : nil
      )
    }
    return DayHistory(
      date: response.date,
      dates: response.dates,
      today: response.today,
      hasPlan: response.plan != nil,
      generatedAt: response.plan?.generatedAt.flatMap { $0.isEmpty ? nil : TodoWireDate.timestamp($0) },
      items: items,
      review: review,
      rawPlan: response.rawPlan
    )
  }

  /// Same mapping as Today's plan rows: the ledger's last event for the day.
  private static func planState(for event: String?) -> TodoState {
    switch event {
    case "complete": .done
    case "partial": .partial
    case "defer": .deferred
    default: .open
    }
  }

  /// `linear:CUTTO-1038` → `CUTTO-1038`; other sources carry no reference worth showing.
  private static func sourceRef(for candidateID: String) -> String? {
    candidateID.hasPrefix("linear:") ? String(candidateID.dropFirst("linear:".count)) : nil
  }
}
