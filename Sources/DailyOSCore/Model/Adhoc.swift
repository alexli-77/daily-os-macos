import Foundation

/// 临时安排 — something that came up today (badminton tonight).
///
/// It goes on today's sheet at its time; today's 作息 makes room for it (the
/// template is untouched); a 要务 counts as one of the cycle's — the next one
/// is taken — unless `extra`; and the rows it pushes out go to tomorrow or are
/// dropped, as the user chose. The service hands back an `AdhocUndo` that
/// reverses all of it.
public struct AdhocRequest: Sendable, Equatable {
  public enum Displace: String, Sendable { case tomorrow = "defer", drop = "remove" }

  public struct Displaced: Sendable, Equatable {
    public let candidateID: String
    public let rank: Int
    public let action: Displace
    public init(candidateID: String, rank: Int, action: Displace) {
      self.candidateID = candidateID
      self.rank = rank
      self.action = action
    }
  }

  public let title: String
  /// The cycle 要务 this is, when it is one.
  public let itemKey: String?
  public let start: String
  public let end: String
  public let extra: Bool
  public let displaced: [Displaced]

  public init(title: String, itemKey: String?, start: String, end: String, extra: Bool, displaced: [Displaced]) {
    self.title = title
    self.itemKey = itemKey
    self.start = start
    self.end = end
    self.extra = extra
    self.displaced = displaced
  }
}

public struct AdhocUndo: Codable, Sendable, Equatable {
  public struct Displaced: Codable, Sendable, Equatable {
    public let candidateId: String
    public let rank: Int
  }

  public let captureId: String
  public let clearId: String?
  public let sessionId: String?
  public let displaced: [Displaced]
}
