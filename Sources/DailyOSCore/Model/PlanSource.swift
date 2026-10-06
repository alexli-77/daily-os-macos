import Foundation

/// Where a plan row came from, as the source column shows it.
///
/// The column used to say 「日程」 for every row that was not carrying a
/// Linear reference — which, since the client never set one on plan rows, was
/// every row. A plan mixing Linear issues, cycle 要务 and inbox captures read
/// as seven calendar entries, and the one question the column exists to answer
/// — "is this something I put in my cycle?" — could not be answered from it.
///
/// The candidate id already says: the planner prefixes every id with its
/// source (`linear:` / `weekly:` / `todo_inbox:` / `vault:`).
public struct PlanSource: Sendable, Equatable {
  public let label: String
  /// A Linear issue key — the one kind of source worth styling as a reference.
  public let isIssue: Bool

  public init(candidateID: String, sourceRef: String? = nil) {
    if let sourceRef, !sourceRef.isEmpty {
      self.init(label: sourceRef, isIssue: true)
      return
    }
    let prefix = candidateID.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
    switch prefix {
    case "linear":
      self.init(label: String(candidateID.dropFirst("linear:".count)), isIssue: true)
    case "weekly":
      self.init(label: "要务", isIssue: false)
    case "todo_inbox":
      self.init(label: "随手记", isIssue: false)
    case "vault":
      self.init(label: "笔记", isIssue: false)
    default:
      self.init(label: "日程", isIssue: false)
    }
  }

  private init(label: String, isIssue: Bool) {
    self.label = label
    self.isIssue = isIssue
  }
}
