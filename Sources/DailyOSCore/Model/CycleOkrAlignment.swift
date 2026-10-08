import Foundation

/// Lining a cycle's 要务 up against the objectives they were planned under.
///
/// The join key already exists and costs nothing to use: the service writes each
/// 要务 group's heading from the objective's own title (`okrRowLabels` in
/// `src/cycles/writeback.ts` returns `objectives.map(\.title)`), so a cycle
/// planned against today's OKR file has headings that match it word for word.
///
/// It is not guaranteed to hold, which is the whole reason this is a join rather
/// than an index. A cycle file freezes the titles that were current when it was
/// planned; rename an objective afterwards and every older cycle stops matching.
/// That is not hypothetical — this vault's cycles up to 2026-08-24 carry
/// `工作-技术专家。完成 AI 工程职业/研究路径的季度验证…` where the current file
/// says `工作 · 技术专家`.
///
/// So the contract is: **要务 are never hidden.** They are what the user came to
/// read; the objective is the annotation. A group that matches nothing still
/// renders, with its own recorded heading, flagged as unmatched.
public enum CycleOkrAlignment {
  /// One row of the aligned view: an objective, the 要务 planned under it, or
  /// both. Never neither.
  public struct Row: Sendable, Equatable, Identifiable {
    /// Nil when the cycle names an objective the current OKR file no longer has.
    public let objective: Objective?
    /// Nil when an objective had nothing planned this cycle.
    public let group: PriorityGroup?
    /// The heading the cycle file actually recorded, kept even when unmatched so
    /// the row can still say which objective the 要务 were planned under.
    public let recordedHeading: String?

    public var id: String { objective?.id ?? recordedHeading ?? UUID().uuidString }
    /// True when the cycle planned 要务 under an objective that no longer exists.
    public var isOrphanedGroup: Bool { objective == nil }
    /// True when an objective exists but this cycle planned nothing under it.
    public var hasNoPriorities: Bool { group?.items.isEmpty ?? true }

    public init(objective: Objective?, group: PriorityGroup?, recordedHeading: String?) {
      self.objective = objective
      self.group = group
      self.recordedHeading = recordedHeading
    }
  }

  public struct Result: Sendable, Equatable {
    public let rows: [Row]
    /// Every group failed to match. Worth saying once at the top rather than on
    /// each row — a cycle planned before an OKR rename looks like nothing but
    /// warnings otherwise.
    public let isWhollyUnmatched: Bool

    public init(rows: [Row], isWhollyUnmatched: Bool) {
      self.rows = rows
      self.isWhollyUnmatched = isWhollyUnmatched
    }
  }

  /// Mirrors the service's `shortLabel`: first non-empty line, capped at 60.
  ///
  /// The cycle file stores headings through it, so a long objective title is
  /// truncated there and whole here. Matching has to try both — the same two-step
  /// the service's own `parsePrioritiesByOkr` does.
  public static func shortLabel(_ value: String) -> String {
    let first = value
      .split(separator: "\n", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .first(where: { !$0.isEmpty }) ?? ""
    guard !first.isEmpty else { return "" }
    return first.count > 60 ? String(first.prefix(60)) + "…" : first
  }

  /// Rows in the cycle's own order, with objectives that had nothing planned
  /// appended after them.
  ///
  /// Cycle order, not OKR order: the user opened a cycle, so its 要务 are the
  /// spine. An objective with no 要务 this cycle is a footnote to that, not a
  /// gap to be preserved in the middle of it.
  public static func align(objectives: [Objective], priorities: PrioritiesDocument) -> Result {
    var byExactTitle: [String: Objective] = [:]
    var byShortLabel: [String: Objective] = [:]
    for objective in objectives {
      let title = objective.title.trimmingCharacters(in: .whitespaces)
      guard !title.isEmpty else { continue }
      if byExactTitle[title] == nil { byExactTitle[title] = objective }
      let short = shortLabel(title)
      if !short.isEmpty, byShortLabel[short] == nil { byShortLabel[short] = objective }
    }

    var rows: [Row] = []
    var matchedIDs: Set<String> = []
    var matchedAny = false
    for group in priorities.groups {
      let heading = group.title.trimmingCharacters(in: .whitespaces)
      // Exact first, then short-label — the heading may be either, depending on
      // whether the title was long enough for the service to truncate it.
      let objective = byExactTitle[heading] ?? byShortLabel[heading] ?? byShortLabel[shortLabel(heading)]
      if let objective {
        matchedIDs.insert(objective.id)
        matchedAny = true
      }
      rows.append(Row(objective: objective, group: group, recordedHeading: heading))
    }

    for objective in objectives where !matchedIDs.contains(objective.id) {
      guard !objective.title.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
      rows.append(Row(objective: objective, group: nil, recordedHeading: nil))
    }

    // Only a cycle that planned something and matched none of it is "wholly
    // unmatched". An empty cycle has nothing to fail at.
    let unmatched = !priorities.groups.isEmpty && !matchedAny
    return Result(rows: rows, isWhollyUnmatched: unmatched)
  }
}

/// The short label shown before a KR's title in the cycle's OKR column.
///
/// KR ids carry their objective's number ("01-KR1"), which the column already
/// shows once above them — repeated on every KR it was noise. And most titles
/// already open with "KR1", so the label is dropped when it would only say
/// the same thing twice.
public enum KeyResultLabel {
  public static func text(id: String, title: String) -> String? {
    var label = id.trimmingCharacters(in: .whitespaces)
    if let dash = label.firstIndex(of: "-"), label[..<dash].allSatisfy(\.isNumber), !label[..<dash].isEmpty {
      label = String(label[label.index(after: dash)...])
    }
    guard !label.isEmpty else { return nil }
    let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
    if trimmedTitle.lowercased().hasPrefix(label.lowercased()) { return nil }
    return label
  }
}
