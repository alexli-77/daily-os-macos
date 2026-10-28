import Foundation

/// The weather a journal day was written under (LEO-351), frozen into the entry
/// so a past page shows its own weather, not today's.
public struct JournalWeather: Sendable, Equatable {
  /// WMO code, mapped to a drawing in the view (same as `WeatherSnapshot`).
  public let code: Int
  public let temp: Double
  public let high: Double?
  public let low: Double?
  public let isDay: Bool?
  public let place: String

  public init(code: Int, temp: Double, high: Double? = nil, low: Double? = nil, isDay: Bool? = nil, place: String) {
    self.code = code
    self.temp = temp
    self.high = high
    self.low = low
    self.isDay = isDay
    self.place = place
  }
}

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
  /// The weather the day was written under, frozen on first write. Nil for a
  /// day written before this existed, or a today page not yet saved.
  public var weather: JournalWeather?
  /// When the day was first written, frozen. Nil as for `weather`.
  public var writtenAt: Date?

  public init(date: String, content: String, weather: JournalWeather? = nil, writtenAt: Date? = nil) {
    self.date = date
    self.content = content
    self.weather = weather
    self.writtenAt = writtenAt
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
