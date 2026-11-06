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
}

struct StickyListResponse: Decodable {
  let items: [StickyDTO]
}

private struct StickySaveRequest: Encodable {
  let id: String?
  let text: String
  let color: String
  let tz: String
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

  public func saveSticky(_ draft: StickyDraft) async throws -> [Sticky] {
    let response: StickyListResponse = try await post(
      "/api/stickies/save",
      body: StickySaveRequest(
        id: draft.id,
        text: draft.text.trimmingCharacters(in: .whitespacesAndNewlines),
        color: draft.color.rawValue,
        tz: deviceTimeZone
      )
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
  /// row — the same forgiveness the countdown decoder extends.
  private static func sticky(_ dto: StickyDTO) -> Sticky {
    Sticky(
      id: dto.id,
      text: dto.text,
      color: Sticky.Color(rawValue: dto.color ?? "") ?? .yellow,
      box: dto.box ?? 0,
      nextSurface: dto.nextSurface,
      surfacing: dto.surfacing ?? false
    )
  }
}
