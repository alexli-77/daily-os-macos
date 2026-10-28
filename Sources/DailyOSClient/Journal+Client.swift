import Foundation
import DailyOSCore

// 日记 (LEO-350): `GET /api/journal`, `GET /api/journal/list`,
// `POST /api/journal/save`, `POST /api/journal/delete`.
//
// Private by construction — these are the only calls that read or write the
// journal, and the service keeps the entries in its own data dir, out of team
// sync, Feishu and the chat sandbox.

private struct JournalEntryResponse: Decodable {
  let date: String
  /// The service's today, so the screen can default to it without its own clock.
  let today: String?
  let content: String
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

extension DailyOSClient {
  public func journalEntry(date: String?) async throws -> JournalEntry {
    let tz = journalDeviceTimeZone.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    let query = date.map { "date=\($0)&tz=\(tz)" } ?? "tz=\(tz)"
    let response: JournalEntryResponse = try await get("/api/journal?\(query)")
    return JournalEntry(date: response.date, content: response.content)
  }

  public func journalList() async throws -> [JournalSummary] {
    let response: JournalListResponse = try await get("/api/journal/list")
    return response.entries.map { JournalSummary(date: $0.date, preview: $0.preview) }
  }

  /// Returns the entry as the service now holds it: empty content means the day
  /// was cleared.
  public func saveJournal(date: String, content: String) async throws -> JournalEntry {
    let response: JournalEntryResponse = try await post(
      "/api/journal/save",
      body: JournalSaveRequest(date: date, content: content, tz: journalDeviceTimeZone)
    )
    return JournalEntry(date: response.date, content: response.content)
  }

  public func deleteJournal(date: String) async throws {
    let _: JournalAck = try await post("/api/journal/delete", body: JournalDeleteRequest(date: date))
  }
}
