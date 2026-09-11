import DailyOSCore
import Foundation

// The cycles endpoints: `GET /api/cycles/state`, `POST /api/cycles/section`,
// `POST /api/cycles/create` and `POST /api/cycles/review`.
//
// The service reads and writes hand-editable markdown in the user's vault, and
// its parser is deliberately forgiving — missing sections, missing frontmatter
// and unrecognised words all survive as a readable document rather than an
// error. This file is the client half of that promise: nothing here throws on a
// value it does not recognise, because the alternative is a screen that goes
// blank over one word somebody typed into their own file.

// MARK: - Wire types

/// `{ ok, cycles, team }`. Both halves are optional so that a service that has
/// never had team sync configured still yields a usable cycles list.
struct CyclesStateDTO: Decodable {
  let cycles: CyclesBlockDTO?
  let team: TeamBlockDTO?
}

struct CyclesBlockDTO: Decodable {
  let dir: String?
  let items: [CycleDTO]?
}

/// Timestamps stay `String` here rather than `Date`.
///
/// Two reasons, both about the transport: `DailyOSClient` decodes with a plain
/// `JSONDecoder`, so this file cannot install a `dateDecodingStrategy`; and the
/// service writes `""` for a timestamp its file never recorded, which no date
/// strategy can turn into a `Date`. Parsing at the mapping step lets a missing
/// stamp degrade to a fallback instead of failing the whole response.
struct CycleDTO: Decodable {
  let id: String
  let startDate: String?
  let cycle: String?
  let mode: String?
  let updatedAt: String?
  let path: String?
  /// Set when the file's YAML could not be parsed. The service refuses to save
  /// such a cycle; there is nowhere in the domain model to show that yet.
  let frontmatterError: String?
  /// Keyed by the service's own section names — `要务`, `retro`, `review` — and
  /// containing only the sections the file actually has.
  let sections: [String: CycleSectionDTO]?
}

struct CycleSectionDTO: Decodable {
  let content: String?
  let source: String?
  let updatedAt: String?
}

struct TeamBlockDTO: Decodable {
  let status: String?
  let reason: String?
  let cacheDir: String?
  let signedIn: TeamSelfDTO?
  let members: [TeamMemberDTO]?
  let syncedAt: String?
  let lastCheckedAt: String?
  let lastError: String?

  enum CodingKeys: String, CodingKey {
    // `self` cannot be a property name, so the one key that would collide with
    // the language is the one key that gets renamed.
    case signedIn = "self"
    case status, reason, cacheDir, members, syncedAt, lastCheckedAt, lastError
  }
}

/// Null — not merely empty — until the user has signed in to team sync.
struct TeamSelfDTO: Decodable {
  let userId: String
  let memberId: String?
  let displayName: String?
}

struct TeamMemberDTO: Decodable {
  let userId: String
  let memberId: String?
  let displayName: String?
  /// The service's own display fallback (`displayName || memberId || 成员 xxxx`),
  /// which is better than anything this client could reconstruct.
  let label: String?
  /// A teammate's cycles, read from the local sync cache. This is the only
  /// place in the response where a cycle is attributed to somebody.
  let cycles: [CycleDTO]?
}

/// Field names taken from `saveCycleSection` in the service's `src/ui/server.ts`.
///
/// `owner` is deliberately not sent. A request that names an owner must name the
/// signed-in account or the service rejects it; one that names none targets
/// `20_CYCLES`, which belongs to whoever is at this machine — exactly what this
/// client is.
struct SaveCycleSectionRequest: Encodable {
  let id: String
  let section: String
  let content: String
}

/// Field names taken from `createCycle` in the service's `src/ui/server.ts`.
///
/// Every field is optional on both sides, and an omitted one is how the request
/// says 按默认策略来 — the service answers a blank from the previous cycle. The
/// synthesised encoder drops `nil` keys rather than writing `null`, which is the
/// same thing to the service and the reason this can be a plain struct.
struct CreateCycleRequest: Encodable {
  let days: Int?
  let taskCount: Int?
  let note: String?
}

/// `text` describes the file that now exists; `planning.reason` describes a run
/// that has only just started. They are two separate facts and are kept apart,
/// because the second one is the part that is not finished yet.
struct CreateCycleResponse: Decodable {
  let id: String?
  let cycle: String?
  let text: String?
  let planning: CyclePlanningDTO?
}

struct CyclePlanningDTO: Decodable {
  /// `started` or `unavailable`. Anything else is treated as "cannot say".
  let status: String?
  let reason: String?
}

/// `save: true` makes the service write the draft itself — see the endpoint's
/// own comment. Without it the prose is only ever a return value, and this
/// client hangs up long before there is one.
struct GenerateCycleReviewRequest: Encodable {
  let id: String
  let save: Bool
}

struct GenerateCycleReviewResponse: Decodable {
  let review: String?
  let chars: Int?
}

// MARK: - Retro scaffold

/// The empty 复盘, copied from `src/cycles/retro-template.ts`.
///
/// Not decoration and not a suggestion: life-review-os splits a retro back apart
/// on exactly these three headings and feeds the pieces to the next planning run
/// as the previous cycle's context. A retro typed without them still reads fine
/// to a human and arrives at the planner as one undifferentiated blob.
///
/// Duplicated across the two repositories rather than fetched, because the one
/// thing worse than two copies of eleven lines is a 复盘 that cannot be started
/// while the service is down.
enum RetroScaffold {
  static let body = """
    😄状态
    情绪/精力/外部压力：
    情绪：
    精力：
    外部压力：
    计划外吃掉时间的事：

    👍🏻做的好

    💪🏻待改进
    """
}

// MARK: - Dates

/// ISO-8601 parsing that accepts both shapes the service emits.
///
/// `updatedAt` carries fractional seconds (`...T01:21:44.317Z`) while other
/// stamps do not, and a formatter configured for one rejects the other outright
/// — a mismatch that reads as "the whole cycles screen is broken" rather than
/// as "one timestamp is unparseable". `Date.ISO8601FormatStyle` is used rather
/// than `ISO8601DateFormatter` because it is a `Sendable` value and can sit in a
/// `static let` under Swift 6 concurrency checking.
enum CycleWireDate {
  private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
  private static let withoutFraction = Date.ISO8601FormatStyle()
  private static let dayOnly = Date.ISO8601FormatStyle(timeZone: .current).year().month().day()

  /// `nil` for the empty string, which is how the service says "the file never
  /// recorded one" — not an error, and not a date.
  static func timestamp(_ raw: String?) -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    return (try? Date(raw, strategy: withFraction)) ?? (try? Date(raw, strategy: withoutFraction))
  }

  /// `2026-08-24`, read in the local time zone: a cycle is a span of the user's
  /// days, so midnight here is the boundary they mean.
  static func day(_ raw: String?) -> Date? {
    guard let raw, !raw.isEmpty else { return nil }
    return try? Date(raw, strategy: dayOnly)
  }
}

// MARK: - Mapping

extension CycleSectionKind {
  /// The service's section names, which are the literal markdown headings in the
  /// user's file. Mixed Chinese and English because the file is, and renaming
  /// them here would write a heading the service no longer recognises.
  var wireName: String {
    switch self {
    case .priorities: "要务"
    case .retro: "retro"
    case .review: "review"
    }
  }

  /// The author a section has when its frontmatter does not say.
  ///
  /// The service seeds each section from a different writer — planner, then the
  /// user, then the model — so the kind is the best available guess. Guessing
  /// beats both throwing and picking one value for all three: labelling a
  /// hand-written retro "自动规划" invites the user to expect it to regenerate.
  var presumedSource: SectionSource {
    switch self {
    case .priorities: .planner
    case .retro: .user
    case .review: .ai
    }
  }
}

extension CycleDTO {
  func domain(ownerId: String) -> Cycle {
    // `mode` is whatever the file said; the service preserves words it does not
    // generate. Falling back to its own default (`biweekly`) keeps an odd file
    // on screen instead of failing the list it appears in.
    let mode = CycleMode(rawValue: self.mode ?? "") ?? .biweekly
    // A start date always accompanies a server-validated id. If one is somehow
    // unreadable, today keeps the cycle visible and sortable; year one would
    // bury it under everything else.
    let start = CycleWireDate.day(startDate) ?? .now
    let span = mode == .weekly ? 6 : 13
    let end = Calendar.current.date(byAdding: .day, value: span, to: start) ?? start
    // The file's own stamp when it has one, else the day the cycle began: a
    // date inside the cycle is the least misleading stand-in for "unknown" in a
    // UI that only ever renders this as "更新于 …".
    let updated = CycleWireDate.timestamp(updatedAt) ?? start

    return Cycle(
      id: id,
      label: cycle ?? id,
      mode: mode,
      start: start,
      end: end,
      ownerId: ownerId,
      // The state endpoint does not project the file's `run_id`, so there is
      // nothing to link a cycle back to the planner run that wrote it.
      runId: nil,
      sections: domainSections(fallbackUpdatedAt: updated),
      updatedAt: updated,
      // Empty string means "parsed fine" on the wire; the domain wants nil, so
      // that `isWritable` is a straight nil check rather than a check plus a
      // check-for-empty that someone will eventually forget.
      frontmatterError: frontmatterError.flatMap { $0.isEmpty ? nil : $0 }
    )
  }

  /// Driven by `allCases` rather than by the dictionary, so the three sections
  /// keep one order everywhere however the JSON happened to serialise them.
  private func domainSections(fallbackUpdatedAt: Date) -> [CycleSection] {
    let raw = sections ?? [:]
    return CycleSectionKind.allCases.compactMap { kind in
      guard let section = raw[kind.wireName] else { return nil }
      return CycleSection(
        kind: kind,
        body: section.content ?? "",
        // `unknown` is a fourth value the service writes for a file that never
        // said, and hand-edited frontmatter can hold anything at all.
        source: SectionSource(rawValue: section.source ?? "") ?? kind.presumedSource,
        updatedAt: CycleWireDate.timestamp(section.updatedAt) ?? fallbackUpdatedAt,
        // Neither endpoint reports a pending planner draft or whether the body
        // is still the seeded placeholder.
        pendingDraft: nil,
        isTemplate: false
      )
    }
  }
}

/// `displayName`, `reason` and `memberId` come back as `""` rather than `null`
/// when the service has nothing to put there, so every fallback chain in this
/// file has to test for emptiness and not just for `nil`.
private func firstNonEmpty(_ candidates: String?...) -> String? {
  candidates.compactMap { $0 }.first { !$0.isEmpty }
}

// MARK: - Client

extension DailyOSClient {
  /// Everything the cycles screen needs, in one round trip.
  ///
  /// The split is by provenance, not by comparing ids: `cycles.items` carries no
  /// owner field at all, because those files are `20_CYCLES` in the vault on
  /// this machine and belong to whoever is sitting at it — so they are all
  /// `mine`. Teammate cycles arrive already grouped by owner under
  /// `team.members[].cycles`, read from the local sync cache; that array is
  /// empty until team sync is configured, which is the common case, so an empty
  /// `teammates` is the normal answer rather than a failure.
  public func cycles() async throws -> (mine: [Cycle], teammates: [Cycle], members: [TeamMember], sync: TeamSyncState) {
    let state: CyclesStateDTO = try await get("/api/cycles/state", as: CyclesStateDTO.self)
    let team = state.team
    let selfId = team?.signedIn?.userId ?? ""
    let syncedAt = CycleWireDate.timestamp(team?.syncedAt)

    let mine = (state.cycles?.items ?? []).map { $0.domain(ownerId: selfId) }
    let teammates = (team?.members ?? []).flatMap { member in
      (member.cycles ?? []).map { $0.domain(ownerId: member.userId) }
    }

    var members: [TeamMember] = []
    if let signedIn = team?.signedIn {
      members.append(
        TeamMember(
          id: signedIn.userId,
          displayName: firstNonEmpty(signedIn.displayName, signedIn.memberId) ?? "我",
          // Seeded from the account id, never from the name: a rename must not
          // change the face beside it.
          avatarSeed: signedIn.userId,
          isSelf: true,
          lastSyncedAt: syncedAt
        )
      )
    }
    members += (team?.members ?? []).map { member in
      TeamMember(
        id: member.userId,
        displayName: firstNonEmpty(member.displayName, member.label, member.memberId) ?? member.userId,
        avatarSeed: member.userId,
        isSelf: false,
        lastSyncedAt: syncedAt
      )
    }

    return (
      mine,
      teammates,
      members,
      TeamSyncState(
        status: team?.status ?? "disabled",
        reason: team?.reason ?? "",
        syncedAt: syncedAt,
        lastError: team?.lastError ?? ""
      )
    )
  }

  /// Write one section of one of *your* cycles.
  ///
  /// There is no owner parameter on purpose — see `SaveCycleSectionRequest`.
  /// The service stamps every write from here as `source: user`, which is what
  /// stops the next planner run from overwriting it.
  public func saveCycleSection(cycleID: String, kind: CycleSectionKind, body: String) async throws {
    let request = SaveCycleSectionRequest(id: cycleID, section: kind.wireName, content: body)
    try await post("/api/cycles/section", body: request)
  }

  /// Create the cycle after the current one.
  ///
  /// The dates are the service's to decide, not this app's: it reads the
  /// previous cycle off disk and copies its length, which is the only way to
  /// get a vault that alternates weekly and biweekly right. So nothing is
  /// computed here, and both sentences of the answer are handed back as the
  /// service wrote them — the second one is about a planning run that is still
  /// going when this returns.
  public func createCycle(days: Int?, taskCount: Int?, note: String?) async throws -> (id: String?, message: String) {
    let request = CreateCycleRequest(days: days, taskCount: taskCount, note: note)
    let response: CreateCycleResponse = try await post("/api/cycles/create", body: request, as: CreateCycleResponse.self)
    let lines = [response.text, response.planning?.reason].compactMap { $0 }.filter { !$0.isEmpty }
    return (response.id, lines.joined(separator: "\n"))
  }

  /// Draft the 总结 for one cycle and let the service save it.
  ///
  /// The generation runs a model for one to two minutes and this client gives up
  /// on the socket after thirty seconds, so the returned prose is usually prose
  /// nobody receives. `save: true` is what makes the work survive that: the
  /// service writes it as `source: ai`, and the section appears on the next
  /// read. A thrown timeout here therefore does not mean the review was lost —
  /// see the caller, which says so rather than reporting a failure.
  @discardableResult
  public func generateCycleReview(cycleID: String) async throws -> Int {
    let request = GenerateCycleReviewRequest(id: cycleID, save: true)
    let response: GenerateCycleReviewResponse = try await post(
      "/api/cycles/review",
      body: request,
      as: GenerateCycleReviewResponse.self
    )
    return response.chars ?? (response.review?.count ?? 0)
  }
}
