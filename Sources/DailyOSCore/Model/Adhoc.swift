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
  /// 算进本期要务: file it under this cycle's 要务 first.
  public let promote: Bool

  public init(title: String, itemKey: String?, start: String, end: String, extra: Bool, displaced: [Displaced], promote: Bool = false) {
    self.title = title
    self.itemKey = itemKey
    self.start = start
    self.end = end
    self.extra = extra
    self.displaced = displaced
    self.promote = promote
  }
}

/// The service's question after an add: this 计划外 thing is on its second day
/// (or two hours in) — is it one of the cycle's 要务? Asked once per cycle.
public struct PromoteSuggestion: Sendable, Equatable {
  public let cycleID: String
  public let text: String
  public let days: Int
  public let minutes: Int?

  public init(cycleID: String, text: String, days: Int, minutes: Int?) {
    self.cycleID = cycleID
    self.text = text
    self.days = days
    self.minutes = minutes
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

// MARK: - 计划外 and 结束本期

/// One thing a cycle's days went to outside its 要务.
public struct UnplannedItem: Sendable, Equatable, Identifiable {
  public let key: String
  public let text: String
  public let days: [String]
  public let minutes: Int?
  public let done: Bool

  public var id: String { key }

  public init(key: String, text: String, days: [String], minutes: Int?, done: Bool) {
    self.key = key
    self.text = text
    self.days = days
    self.minutes = minutes
    self.done = done
  }
}

public struct UnplannedRollup: Sendable, Equatable {
  public let items: [UnplannedItem]
  /// 「逛街（2 天，3h）、见朋友（1 天）」, for the retro.
  public let summary: String

  public init(items: [UnplannedItem], summary: String) {
    self.items = items
    self.summary = summary
  }
}

/// Where 结束本期 is. `running` false with neither text nor error: never started.
public struct CloseCycleStatus: Sendable, Equatable {
  public let running: Bool
  public let text: String?
  public let error: String?

  public init(running: Bool, text: String?, error: String?) {
    self.running = running
    self.text = text
    self.error = error
  }
}

extension RetroText {
  /// The line the retro template asks this of.
  public static let unplannedLabel = "计划外吃掉时间的事："
}

/// Filling the retro's 计划外 line from the system's count.
public enum RetroText {
  /// `retro` with its 「计划外吃掉时间的事：」 line set to `summary`, or the line
  /// added at the end when the retro has none.
  public static func fillingUnplanned(_ retro: String, with summary: String) -> String {
    var lines = retro.components(separatedBy: "\n")
    if let index = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix(unplannedLabel) }) {
      let indent = String(lines[index].prefix(while: { $0 == " " }))
      lines[index] = indent + unplannedLabel + summary
      return lines.joined(separator: "\n")
    }
    let trimmed = retro.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? unplannedLabel + summary : trimmed + "\n\n" + unplannedLabel + summary
  }
}
