import Foundation
import DailyOSCore

// Teammates' shared sticky boards (LEO-358).
//
// `/api/team/stickies` reads the service's sync cache on disk — the same cache
// the Cycles and Today teammate views come from — never the network, so it is
// cheap to call on every refresh. The 60 s sync loop inside the service fills
// it, and only for teammates who turned sharing on.

struct TeamStickiesResponse: Decodable {
  struct Member: Decodable {
    struct Board: Decodable {
      struct Payload: Decodable {
        let items: [StickyDTO]?
      }
      let updatedAt: String?
      let payload: Payload

      enum CodingKeys: String, CodingKey {
        case payload
        case updatedAt = "updatedAt"
      }
    }

    let userId: String
    let displayName: String
    let label: String
    let board: Board?
  }

  let status: String
  let reason: String
  let members: [Member]
  let syncedAt: String
  let lastError: String
}

extension DailyOSClient {
  public func teamStickies() async throws -> (entries: [TeamStickyEntry], sync: TeamSyncState) {
    let response: TeamStickiesResponse = try await get("/api/team/stickies")
    let entries = response.members.map { member -> TeamStickyEntry in
      let stickies = (member.board?.payload.items ?? []).map(Self.sticky)
      return TeamStickyEntry(
        id: member.userId,
        displayName: member.label.isEmpty ? member.displayName : member.label,
        stickies: stickies,
        hasBoard: member.board != nil,
        updatedAt: member.board?.updatedAt.flatMap(TodoWireDate.timestamp)
      )
    }
    let sync = TeamSyncState(
      status: response.status,
      reason: response.reason,
      syncedAt: TodoWireDate.timestamp(response.syncedAt),
      lastError: response.lastError
    )
    return (entries, sync)
  }
}
