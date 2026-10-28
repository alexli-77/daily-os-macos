import Foundation

/// 日记 — a free-text entry for one day.
///
/// This is the diary, not the task wrap-up or the model's 复盘: whatever the user
/// felt like writing. Private — it is stored only in the service's own data dir
/// and never leaves it. One entry per day, keyed by `YYYY-MM-DD`.
public struct JournalEntry: Sendable, Equatable {
  /// `YYYY-MM-DD` in the service's timezone.
  public let date: String
  /// Markdown. Empty means there is no entry for the day (the service deletes a
  /// day whose content is cleared).
  public var content: String

  public init(date: String, content: String) {
    self.date = date
    self.content = content
  }
}

/// One row of the browse list: a day that has an entry, with a one-line preview.
public struct JournalSummary: Sendable, Equatable, Identifiable {
  public let date: String
  public let preview: String
  public var id: String { date }

  public init(date: String, preview: String) {
    self.date = date
    self.preview = preview
  }
}
