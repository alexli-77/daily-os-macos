import Foundation

/// One cell of the day's progress bar.
///
/// Split out from the view because the two interesting rules — what order the
/// cells go in, and how wide each one is — are arithmetic, and arithmetic in a
/// `body` can only be checked by looking at it. A bar of coloured rectangles
/// always looks like a bar of coloured rectangles: cells in the wrong order, or
/// an unknown duration quietly presented at the same width as a measured one,
/// would never announce themselves on screen.
public struct PlanSegment: Identifiable, Sendable, Equatable {
  public let id: String
  public let text: String
  /// The estimate, when there is one. `nil` is not zero — see `isEstimated`.
  public let minutes: Int?
  public let state: TodoState
  /// Relative width. Not always the minutes: an item with no estimate borrows
  /// the median of the items that have one.
  public let weight: Double

  /// Whether `weight` is a measurement or a stand-in. The bar draws the
  /// difference, because a guess presented with the same authority as the real
  /// numbers next to it is worse than no bar.
  public var isEstimated: Bool { (minutes ?? 0) > 0 }

  public init(id: String, text: String, minutes: Int?, state: TodoState, weight: Double) {
    self.id = id
    self.text = text
    self.minutes = minutes
    self.state = state
    self.weight = weight
  }

  /// Order the day's items into progress-bar cells.
  ///
  /// **Finished work goes left**, then open, then deferred, each group holding
  /// plan order. Progress in a list you keep reordering is unreadable when the
  /// done cells are scattered through it: the eye reads a bar left to right and
  /// wants one boundary between what is behind you and what is ahead, not five.
  ///
  /// Deferred sits last rather than mixed into the open run, because it is not
  /// work waiting for you today — leaving it in place makes the remaining bar
  /// look longer than the day actually is.
  ///
  /// **Width follows the estimate.** Equal cells claim four things are left
  /// when three of them are ten minutes and the fourth is the whole afternoon.
  /// With no estimates anywhere every cell is equal, which is the honest
  /// rendering of knowing nothing about duration.
  public static func layout(_ items: [TodoItem]) -> [PlanSegment] {
    let estimates = items.compactMap(\.estimatedMinutes).filter { $0 > 0 }.sorted()
    // The median, not the mean: a single three-hour outlier would otherwise
    // stretch every unknown cell to match it.
    let placeholder = estimates.isEmpty ? 1.0 : Double(estimates[estimates.count / 2])

    return items
      .enumerated()
      .sorted { left, right in
        let (a, b) = (order(left.element.state), order(right.element.state))
        return a == b ? left.offset < right.offset : a < b
      }
      .map { _, item in
        let minutes = item.estimatedMinutes ?? 0
        return PlanSegment(
          id: item.id,
          text: item.text,
          minutes: item.estimatedMinutes,
          state: item.state,
          weight: minutes > 0 ? Double(minutes) : placeholder
        )
      }
  }

  private static func order(_ state: TodoState) -> Int {
    switch state {
    case .done: 0
    case .open: 1
    case .deferred: 2
    case .deleted: 3
    }
  }
}
