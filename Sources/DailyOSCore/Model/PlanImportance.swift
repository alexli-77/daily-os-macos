import Foundation

/// How much a planned item matters today.
///
/// **Derived from position, because position is the only thing that carries it.**
/// `daily_plan` emits a ranked list and nothing else — no priority field, no
/// flag — and the rank is not incidental: the prompt asks the model to put the
/// most important thing first. Inventing a separate priority the user could set
/// independently would create two orderings that disagree, and then a list
/// sorted one way and coloured the other.
///
/// This also makes dragging mean something. Moving a row up is not a cosmetic
/// preference about where it sits — it *is* the act of saying this matters more
/// today, and the colour changing under the cursor is the feedback that says so.
///
/// The cuts are absolute rather than proportional. A plan is three to six rows;
/// scaling the tiers to its length would mean the same task changed colour
/// because something unrelated got added to the day.
public enum PlanImportance: Sendable, Hashable, CaseIterable {
  /// The one thing. `daily_plan` calls this the MIT.
  case mit
  case high
  case normal

  /// `rank` is 1-based, as it is everywhere else in the plan.
  public static func forRank(_ rank: Int) -> PlanImportance {
    switch rank {
    case ..<2: .mit
    case 2...3: .high
    default: .normal
    }
  }

  public var label: String {
    switch self {
    case .mit: "最重要"
    case .high: "重要"
    case .normal: "一般"
    }
  }

  /// Long enough to say what the tier *means*, for a tooltip. "重要" alone does
  /// not tell you it came from the row's position, so it reads as a property
  /// someone set rather than as something dragging would change.
  public var explanation: String {
    switch self {
    case .mit: "今天最重要的一件事——排在第一位的那条"
    case .high: "重要：排在前三"
    case .normal: "其余的安排"
    }
  }
}
