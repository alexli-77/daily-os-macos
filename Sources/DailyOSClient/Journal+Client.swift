import Foundation
import DailyOSCore

// 日记 (LEO-350/351): `GET /api/journal`, `GET /api/journal/list`,
// `POST /api/journal/save`, `POST /api/journal/delete`.
//
// Private by construction — these are the only calls that read or write the
// journal, and the service keeps the entries in its own data dir, out of team
// sync, Feishu and the chat sandbox. A save carries the moment's weather and the
// device's local time; the service freezes them onto the day the first time it
// is written.

private struct JournalWeatherWire: Codable {
  let code: Int
  let temp: Double
  let high: Double?
  let low: Double?
  let isDay: Bool?
  let place: String
}

private struct JournalEntryResponse: Decodable {
  let date: String
  /// The service's today, so the screen can default to it without its own clock.
  let today: String?
  let content: String
  let writtenAt: String?
  let weather: JournalWeatherWire?

  enum CodingKeys: String, CodingKey {
    case date, today, content, weather
    case writtenAt = "written_at"
  }
}

private struct JournalSummaryDTO: Decodable {
  let date: String
  let preview: String
}

private struct JournalListResponse: Decodable {
  let entries: [JournalSummaryDTO]
}

private struct JournalSaveRequest: Encodable {
  let date: String
  let content: String
  let tz: String
  let writtenAt: String?
  let weather: JournalWeatherWire?

  enum CodingKeys: String, CodingKey {
    case date, content, tz, weather
    case writtenAt = "written_at"
  }
}

private struct JournalDeleteRequest: Encodable {
  let date: String
}

/// Decodes the save/delete acknowledgement; the fields are not needed, only that
/// it parsed as a 2xx JSON body.
private struct JournalAck: Decodable {
  let ok: Bool
}

/// This machine's zone, so the service resolves "today" on the clock the user is
/// looking at — the same reason countdowns send it.
private var journalDeviceTimeZone: String { TimeZone.current.identifier }

/// Internet date-time with the offset, which the service parses back to a Date.
/// `nonisolated(unsafe)`: a date formatter is not `Sendable`, but this one is a
/// constant used only for formatting here, never reconfigured.
nonisolated(unsafe) private let journalISO: ISO8601DateFormatter = {
  let formatter = ISO8601DateFormatter()
  formatter.formatOptions = [.withInternetDateTime]
  return formatter
}()

private func decodeJournalEntry(_ response: JournalEntryResponse) -> JournalEntry {
  JournalEntry(
    date: response.date,
    content: response.content,
    weather: response.weather.map {
      JournalWeather(code: $0.code, temp: $0.temp, high: $0.high, low: $0.low, isDay: $0.isDay, place: $0.place)
    },
    writtenAt: response.writtenAt.flatMap(journalISO.date(from:))
  )
}

extension DailyOSClient {
  public func journalEntry(date: String?) async throws -> JournalEntry {
    let tz = journalDeviceTimeZone.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    let query = date.map { "date=\($0)&tz=\(tz)" } ?? "tz=\(tz)"
    let response: JournalEntryResponse = try await get("/api/journal?\(query)")
    return decodeJournalEntry(response)
  }

  public func journalList() async throws -> [JournalSummary] {
    let response: JournalListResponse = try await get("/api/journal/list")
    return response.entries.map { JournalSummary(date: $0.date, preview: $0.preview) }
  }

  /// Returns the entry as the service now holds it: empty content means the day
  /// was cleared. `weather`/`writtenAt` are the current snapshot; the service
  /// keeps them only the first time the day is written.
  public func saveJournal(date: String, content: String, weather: JournalWeather?, writtenAt: Date?) async throws -> JournalEntry {
    let response: JournalEntryResponse = try await post(
      "/api/journal/save",
      body: JournalSaveRequest(
        date: date,
        content: content,
        tz: journalDeviceTimeZone,
        writtenAt: writtenAt.map(journalISO.string(from:)),
        weather: weather.map {
          JournalWeatherWire(code: $0.code, temp: $0.temp, high: $0.high, low: $0.low, isDay: $0.isDay, place: $0.place)
        }
      )
    )
    return decodeJournalEntry(response)
  }

  public func deleteJournal(date: String) async throws {
    let _: JournalAck = try await post("/api/journal/delete", body: JournalDeleteRequest(date: date))
  }
}
