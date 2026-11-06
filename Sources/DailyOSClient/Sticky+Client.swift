import Foundation
import DailyOSCore

// 便签 / 提醒卡 (LEO-355): `GET /api/stickies`, `POST /api/stickies/save`,
// `POST /api/stickies/surface`, `POST /api/stickies/archive`.
//
// Every response carries the whole list, already resolved against the service's
// idea of today — same contract as countdowns, and for the same reason: which
// notes are "surfacing" depends on the user's timezone, which this app reports
// on every call but never computes against. A write can move notes between the
// awake and sleeping bands, so the cheapest correct thing to return is the list.

struct StickyDTO: Decodable {
  let id: String
  let text: String
  let color: String?
  let box: Int?
  let nextSurface: String
  let surfacing: Bool?
  let x: Double?
  let y: Double?
  let w: Double?
  let h: Double?
}

struct StickyListResponse: Decodable {
  let items: [StickyDTO]
}

/// Coordinates are `encodeIfPresent`, never `null`: the service reads `x`/`y`
/// with `Number(...)`, and `Number(null)` is `0` — sending null on an edit would
/// silently teleport the note to the origin. Omitting the keys leaves position
/// untouched, which is exactly what an edit (vs a drag) should do.
private struct StickySaveRequest: Encodable {
  let id: String?
  let text: String
  let color: String
  let tz: String
  let x: Double?
  let y: Double?

  enum CodingKeys: String, CodingKey { case id, text, color, tz, x, y }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(id, forKey: .id)
    try c.encode(text, forKey: .text)
    try c.encode(color, forKey: .color)
    try c.encode(tz, forKey: .tz)
    try c.encodeIfPresent(x, forKey: .x)
    try c.encodeIfPresent(y, forKey: .y)
  }
}

private struct StickySurfaceRequest: Encodable {
  let id: String
  let response: String
  let tz: String
}

private struct StickyArchiveRequest: Encodable {
  let id: String
  let tz: String
}

private struct StickyMoveRequest: Encodable {
  let id: String
  let x: Double
  let y: Double
  let tz: String
}

private struct StickyResizeRequest: Encodable {
  let id: String
  let w: Double
  let h: Double
  let tz: String
}

/// This machine's zone, read fresh on every call — fly somewhere and the next
/// read decides "today" there, with nothing reconfigured. Same rationale as the
/// countdown client's `deviceTimeZone`.
private var deviceTimeZone: String { TimeZone.current.identifier }

extension DailyOSClient {
  public func stickies() async throws -> [Sticky] {
    let tz = deviceTimeZone.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    let response: StickyListResponse = try await get("/api/stickies?tz=\(tz)")
    return response.items.map(Self.sticky)
  }

  /// `at` is the spot the board picked for a brand-new note; nil on an edit,
  /// which leaves the existing position alone.
  public func saveSticky(_ draft: StickyDraft, at position: (x: Double, y: Double)? = nil) async throws -> [Sticky] {
    let response: StickyListResponse = try await post(
      "/api/stickies/save",
      body: StickySaveRequest(
        id: draft.id,
        text: draft.text.trimmingCharacters(in: .whitespacesAndNewlines),
        color: draft.color.rawValue,
        tz: deviceTimeZone,
        x: position?.x,
        y: position?.y
      )
    )
    return response.items.map(Self.sticky)
  }

  public func moveSticky(_ id: String, x: Double, y: Double) async throws -> [Sticky] {
    let response: StickyListResponse = try await post(
      "/api/stickies/move",
      body: StickyMoveRequest(id: id, x: x, y: y, tz: deviceTimeZone)
    )
    return response.items.map(Self.sticky)
  }

  public func resizeSticky(_ id: String, w: Double, h: Double) async throws -> [Sticky] {
    let response: StickyListResponse = try await post(
      "/api/stickies/resize",
      body: StickyResizeRequest(id: id, w: w, h: h, tz: deviceTimeZone)
    )
    return response.items.map(Self.sticky)
  }

  public func surfaceSticky(_ id: String, response surfaceResponse: SurfaceResponse) async throws -> [Sticky] {
    let response: StickyListResponse = try await post(
      "/api/stickies/surface",
      body: StickySurfaceRequest(id: id, response: surfaceResponse.rawValue, tz: deviceTimeZone)
    )
    return response.items.map(Self.sticky)
  }

  public func archiveSticky(_ id: String) async throws -> [Sticky] {
    let response: StickyListResponse = try await post(
      "/api/stickies/archive",
      body: StickyArchiveRequest(id: id, tz: deviceTimeZone)
    )
    return response.items.map(Self.sticky)
  }

  /// An unrecognised colour reads as the quiet default rather than failing the
  /// row — the same forgiveness the countdown decoder extends. Internal, not
  /// private, so the teammate-board client (`TeamStickies+Client`) maps rows the
  /// same way your own board does.
  static func sticky(_ dto: StickyDTO) -> Sticky {
    Sticky(
      id: dto.id,
      text: dto.text,
      color: Sticky.Color(rawValue: dto.color ?? "") ?? .yellow,
      box: dto.box ?? 0,
      nextSurface: dto.nextSurface,
      surfacing: dto.surfacing ?? false,
      x: dto.x,
      y: dto.y,
      w: dto.w,
      h: dto.h
    )
  }
}
