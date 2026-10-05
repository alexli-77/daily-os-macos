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
  /// The zone the service actually counted in — normally the one this app
  /// asked for. Optional so an older service that does not send it costs the
  /// footer line rather than the screen.
  let timezone: String?
  /// The zone the morning Feishu card will be counted in: the service's
  /// `user.timezone`, which it has to use because the card is sent on a
  /// schedule keyed to that zone with no client to ask.
  let cardTimezone: String?
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
  let tz: String
}

private struct CountdownDeleteRequest: Encodable {
  let id: String
  let tz: String
}

/// This machine's zone, reported on every countdown call.
///
/// Read fresh each time rather than captured once. `TimeZone.current` follows
/// the system, and the whole point of sending it is that it can change — fly
/// to Shanghai and the next read counts Shanghai days without anything being
/// reconfigured.
private var deviceTimeZone: String { TimeZone.current.identifier }

extension DailyOSClient {
  public func countdowns() async throws -> CountdownList {
    // Percent-encoded: an IANA identifier contains a `/`, which would otherwise
    // read as another path segment.
    let tz = deviceTimeZone.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    let response: CountdownListResponse = try await get("/api/countdowns?tz=\(tz)")
    return Self.list(response)
  }

  /// Returns the whole list as the service now holds it, not just the saved row.
  public func saveCountdown(_ draft: CountdownDraft) async throws -> CountdownList {
    let response: CountdownListResponse = try await post(
      "/api/countdowns/save",
      body: CountdownSaveRequest(
        id: draft.id,
        title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
        date: draft.date,
        direction: draft.direction.rawValue,
        repeat: draft.recurrence.rawValue,
        pinned: draft.pinned,
        note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines),
        tz: deviceTimeZone
      )
    )
    return Self.list(response)
  }

  public func deleteCountdown(id: String) async throws -> CountdownList {
    let response: CountdownListResponse = try await post(
      "/api/countdowns/delete",
      body: CountdownDeleteRequest(id: id, tz: deviceTimeZone)
    )
    return Self.list(response)
  }

  private static func list(_ response: CountdownListResponse) -> CountdownList {
    CountdownList(
      items: response.items.map(countdown),
      timezone: response.timezone ?? "",
      cardTimezone: response.cardTimezone ?? ""
    )
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
