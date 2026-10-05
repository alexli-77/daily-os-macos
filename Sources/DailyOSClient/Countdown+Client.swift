import Foundation
import DailyOSCore

// Countdown days: `GET /api/countdowns`, `POST /api/countdowns/save`,
// `POST /api/countdowns/delete`.
//
// Every response carries the full list, already resolved against the service's
// idea of today. That is deliberate on both sides: the day count depends on the
// user's configured timezone, which this app never sees, and a write can move a
// row between bands — pinning it, or pushing its date past today — so the
// cheapest correct thing a write can return is the list.

struct CountdownDTO: Decodable {
  let id: String
  let title: String
  let date: String
  let direction: String?
  /// `repeat` is a keyword; the wire name is mapped below.
  let recurrence: String?
  let pinned: Bool?
  let note: String?
  let occurrence: String
  let daysLeft: Int
  let ordinal: Int?

  enum CodingKeys: String, CodingKey {
    case id, title, date, direction, pinned, note, occurrence, ordinal
    case recurrence = "repeat"
    case daysLeft
  }
}

struct CountdownListResponse: Decodable {
  let today: String
  let items: [CountdownDTO]
}

/// The save payload. `id` absent means create.
struct CountdownSaveRequest: Encodable {
  let id: String?
  let title: String
  let date: String
  let direction: String
  let `repeat`: String
  let pinned: Bool
  let note: String
}

private struct CountdownDeleteRequest: Encodable {
  let id: String
}

extension DailyOSClient {
  public func countdowns() async throws -> [Countdown] {
    let response: CountdownListResponse = try await get("/api/countdowns")
    return response.items.map(Self.countdown)
  }

  /// Returns the whole list as the service now holds it, not just the saved row.
  public func saveCountdown(_ draft: CountdownDraft) async throws -> [Countdown] {
    let response: CountdownListResponse = try await post(
      "/api/countdowns/save",
      body: CountdownSaveRequest(
        id: draft.id,
        title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
        date: draft.date,
        direction: draft.direction.rawValue,
        repeat: draft.recurrence.rawValue,
        pinned: draft.pinned,
        note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
      )
    )
    return response.items.map(Self.countdown)
  }

  public func deleteCountdown(id: String) async throws -> [Countdown] {
    let response: CountdownListResponse = try await post(
      "/api/countdowns/delete",
      body: CountdownDeleteRequest(id: id)
    )
    return response.items.map(Self.countdown)
  }

  /// An unrecognised direction or repeat reads as the quiet default rather than
  /// failing the row — the same forgiveness the cycles decoder extends, for the
  /// same reason: a newer service that learns a third repeat rule should cost
  /// this app a wrong label, not a blank screen.
  private static func countdown(_ dto: CountdownDTO) -> Countdown {
    Countdown(
      id: dto.id,
      title: dto.title,
      date: dto.date,
      direction: Countdown.Direction(rawValue: dto.direction ?? "") ?? .until,
      recurrence: Countdown.Recurrence(rawValue: dto.recurrence ?? "") ?? .none,
      pinned: dto.pinned ?? false,
      note: dto.note?.isEmpty == false ? dto.note : nil,
      occurrence: dto.occurrence,
      daysLeft: dto.daysLeft,
      ordinal: dto.ordinal
    )
  }
}
