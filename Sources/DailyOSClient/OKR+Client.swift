import Foundation
import DailyOSCore

// The OKR files, recovered from the markdown `/api/state` hands back.
//
// The service does not model OKRs on the wire. `okr.files[]` carries each file
// as one string, byte for byte off disk, because the console's OKR surface is a
// raw-markdown editor (`src/okr/editor.ts`) — so the structure the OKR screen
// draws has to be rebuilt here. This is a port of the service's own reader,
// `src/ui/okr-lite.ts`, rather than a second opinion about the format: where the
// two disagree, the web console is right and this file is wrong.
//
// Two things in `KeyResult` have no source in the markdown at all — `priority`
// and `health`. Both are marked as inventions where they are produced.

// MARK: - Wire

/// Only `okr` is declared out of the two dozen keys `/api/state` returns, so a
/// change anywhere else in that response cannot fail this decode.
///
/// `Today+Client.swift` decodes the same endpoint through its own `StatePayload`
/// naming the two branches Today needs. One shared type for the whole response
/// would couple the two screens: a key the OKR screen never looks at could then
/// fail the Today fetch, and vice versa.
///
/// No date decoding strategy is set because nothing here is a date — the table's
/// `Updated` column is hand-typed text and stays text.
private struct StateResponse: Decodable {
  let okr: OkrPayload?
}

private struct OkrPayload: Decodable {
  let files: [OkrFileEntry]?
}

/// Every field is optional even though the service builds these entries from a
/// fixed three-row table. A file it could not read is still listed, with
/// `markdown: ""` — that empty string has to survive as a file with no
/// objectives rather than as a failure.
private struct OkrFileEntry: Decodable {
  let level: String?
  let label: String?
  let fileName: String?
  let markdown: String?
}

// MARK: - Parser

/// A port of `src/ui/okr-lite.ts`.
///
/// Its tolerances are deliberate and are kept: an unreadable file is an empty
/// file, a row that does not look like a KR is skipped instead of aborting the
/// objective, and a heading that does not match the shape below simply never
/// opens an objective. Nothing in here throws, so a file somebody is halfway
/// through rewriting costs you the objectives you cannot parse and not the
/// screen.
///
/// The shape it understands:
///
///     ---
///     title: ...            # optional frontmatter, `key: value` lines
///     ---
///     ## Objective O1: 把 daily-os 做成每天真会开的东西
///     Parent: none
///     Priority: P0
///     | KR ID | Description | Target | Current | Progress | Updated |
///     | --- | --- | --- | --- | --- | --- |
///     | O1-KR1 | 连续 8 周不缺期 | 8 期 | 6 期 | 75% | 2026-08-30 |
enum OkrMarkdown {
  struct Parsed {
    /// `title:` from the frontmatter, else the first `# ` heading. Only ever a
    /// fallback: the service names the three files itself, and its names are
    /// the ones the console shows.
    let title: String?
    let objectives: [Objective]
  }


  static func parse(_ markdown: String) -> Parsed {
    // Normalising CRLF up front is a deliberate divergence. Every regex in
    // okr-lite is `\n`-anchored, so a file that has been through a Windows
    // editor parses there as zero objectives — a blank screen with no
    // explanation. The service rewrites line endings on its next save
    // (`writeOkrFile`), so such a file is temporary; it should still be
    // readable while it lasts.
    let lines = markdown
      .replacingOccurrences(of: "\r\n", with: "\n")
      .components(separatedBy: "\n")

    let (frontmatter, body) = splitFrontmatter(lines)
    return Parsed(
      title: frontmatterTitle(frontmatter) ?? firstHeading(body),
      objectives: objectives(in: body)
    )
  }

  // MARK: Frontmatter

  private static func splitFrontmatter(_ lines: [String]) -> (frontmatter: [String], body: [String]) {
    guard lines.first == "---", let end = lines.dropFirst().firstIndex(of: "---") else {
      return ([], lines)
    }
    return (Array(lines[1..<end]), Array(lines[(end + 1)...]))
  }

  /// The last `title:` wins, because the port builds a dictionary and the last
  /// assignment to a key is the one that survives.
  private static func frontmatterTitle(_ lines: [String]) -> String? {
    var found: String?
    for line in lines {
      guard let colon = line.firstIndex(of: ":") else { continue }
      guard line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces) == "title" else { continue }
      let value = stripQuotes(line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
      found = value.isEmpty ? nil : value
    }
    return found
  }

  /// One quote character off each end — not a YAML string parser, and not
  /// pretending to be one. The frontmatter here is written by hand and by the
  /// service's own templates, never by a YAML emitter.
  private static func stripQuotes(_ value: String) -> String {
    var text = value
    if let first = text.first, first == "\"" || first == "'" { text.removeFirst() }
    if let last = text.last, last == "\"" || last == "'" { text.removeLast() }
    return text
  }

  /// `# Heading`, and only one hash: `## Objective ...` must not be mistaken
  /// for the document title.
  private static func firstHeading(_ lines: [String]) -> String? {
    for line in lines where line.hasPrefix("#") {
      let rest = line.dropFirst()
      guard let first = rest.first, first == " " || first == "\t" else { continue }
      let title = rest.trimmingCharacters(in: .whitespaces)
      if !title.isEmpty { return title }
    }
    return nil
  }

  // MARK: Objectives

  private static func objectives(in lines: [String]) -> [Objective] {
    // Built once outside the loop rather than stored: `Regex` is not `Sendable`,
    // so it cannot be a `static let`, and rebuilding it per line would compile
    // the same pattern for every row of every file.
    //
    // Exactly two hashes, and a colon in either width — these files are written
    // in Chinese and `：` is what a Chinese keyboard produces.
    let headingPattern = /##\s+Objective\s+([A-Za-z0-9_.-]+)\s*[:：]\s*(.*)/
    let priorityPattern = /(?i)^Priority\s*[:：]\s*(P[0-4])/

    var objectives: [Objective] = []
    var openID: String?
    var openTitle = ""
    var openPriority: String?
    var openRows: [KeyResult] = []

    func close() {
      guard let id = openID else { return }
      // Priority belongs to the objective and may be written after the table,
      // so it is stamped onto the rows once the block ends rather than as each
      // row is read.
      let keyResults = openRows.map { row -> KeyResult in
        var row = row
        row.priority = openPriority
        return row
      }
      objectives.append(Objective(id: id, title: openTitle, keyResults: keyResults))
      openID = nil
      openTitle = ""
      openPriority = nil
      openRows = []
    }

    for line in lines {
      // Only an `## Objective` line ends the open block. Any other heading is
      // just a line, so rows under it keep attaching to the objective above —
      // surprising, but it is what the port does and therefore what the console
      // shows for the same file.
      if let match = line.wholeMatch(of: headingPattern) {
        close()
        openID = String(match.1).trimmingCharacters(in: .whitespaces)
        openTitle = String(match.2).trimmingCharacters(in: .whitespaces)
        continue
      }
      // Anything before the first heading is dropped, as in the port: a KR row
      // with no objective over it has nowhere to go.
      guard openID != nil else { continue }

      if let match = line.firstMatch(of: priorityPattern) {
        openPriority = String(match.1).uppercased()
        continue
      }
      // `Parent:` is read by the port and dropped here — `Objective` has no
      // field for it, and inventing a parent chain the UI does not draw would
      // be worse than losing the line.
      if let row = keyResult(fromRow: line) { openRows.append(row) }
    }
    close()
    return objectives
  }

  /// A KR row is any table row whose first cell mentions "KR" and is not the
  /// header. That is looser than matching `O1-KR1`, and on purpose: these
  /// tables are hand-edited, ids drift, and the alternative is silently losing
  /// rows somebody can see with their own eyes.
  private static func keyResult(fromRow line: String) -> KeyResult? {
    // The pipe must be the first character, untrimmed — an indented table is
    // not recognised by the port either, and a client that accepted one would
    // show KRs the console does not.
    guard line.hasPrefix("|") else { return nil }
    let cells = tableCells(line)
    guard cells.count >= 5 else { return nil }

    let id = cells[0]
    guard id.range(of: "KR", options: .caseInsensitive) != nil,
          id.wholeMatch(of: /(?i)KR\s*ID/) == nil
    else { return nil }

    // Column 5 (`Updated`) has nowhere to go in `KeyResult` and is dropped
    // rather than folded into `detail`, where it would read as part of the
    // number.
    let value = progress(in: cells[4])
    return KeyResult(
      id: id,
      title: cells[1],
      // Stamped in at block close, because `Priority:` belongs to the objective
      // and may be written after the table.
      priority: nil,
      progress: value ?? 0,
      detail: detail(target: cells[2], current: cells[3]),
      // The format carries no health, status or at-risk notion — verified
      // against the service's own reader. Deriving one from progress alone
      // would paint a fresh quarter red: at 0% on day one a key result looks
      // exactly like one at 0% on the last day.
      health: nil
    )
  }

  private static func tableCells(_ line: String) -> [String] {
    var row = Substring(line.trimmingCharacters(in: .whitespaces))
    if row.hasPrefix("|") { row = row.dropFirst() }
    if row.hasSuffix("|") { row = row.dropLast() }
    return row
      .split(separator: "|", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
  }

  /// The first number anywhere in the cell, clamped to 0…100 and returned as a
  /// fraction. Taking the first number rather than requiring the whole cell to
  /// be one is what lets `40% (blocked)` and `about 40` both read as 40.
  private static func progress(in cell: String) -> Double? {
    guard let match = cell.firstMatch(of: /(-?\d+(?:\.\d+)?)\s*%?/),
          let value = Double(match.1),
          value.isFinite
    else { return nil }
    return min(max(value.rounded(), 0), 100) / 100
  }

  /// Target and Current as one line — "6 期 / 8 期".
  private static func detail(target: String, current: String) -> String? {
    switch (filled(current), filled(target)) {
    case let (current?, target?): "\(current) / \(target)"
    case let (current?, nil): current
    case let (nil, target?): target
    case (nil, nil): nil
    }
  }

  /// An em dash is what the normalizer seeds an unfilled cell with
  /// (`src/okr/normalize.ts`), so it means "nothing here", not a value.
  private static func filled(_ cell: String) -> String? {
    let text = cell.trimmingCharacters(in: .whitespaces)
    if text.isEmpty || text == "—" || text == "–" || text == "-" { return nil }
    return text
  }

}

// MARK: - Endpoint

extension DailyOSClient {
  /// The OKR files behind the OKR screen.
  ///
  /// One `/api/state` round trip for all of them: the service has no OKR-only
  /// GET, and that response already carries every file whole, so a narrower
  /// endpoint would not save a byte.
  ///
  /// A file the service could not read comes back with empty markdown and is
  /// kept rather than dropped. A level with nothing in it is worth showing —
  /// "you have never written a north star" is the answer to a real question —
  /// and dropping it would quietly change which entries the file picker has.
  public func okrFiles() async throws -> [OkrFile] {
    let state: StateResponse = try await get("/api/state")
    return (state.okr?.files ?? []).enumerated().map { index, entry in
      let parsed = OkrMarkdown.parse(entry.markdown ?? "")
      let label = [entry.label, parsed.title, entry.fileName]
        .compactMap { $0 }
        .first { !$0.isEmpty }
      return OkrFile(
        // `level` is the service's own stable key for the file. The positional
        // fallback only matters if that key ever goes missing: `OkrFile` is
        // Identifiable, and two files sharing an id break the picker rather
        // than just looking odd.
        id: entry.level ?? entry.fileName ?? "okr-\(index)",
        label: label ?? "OKR",
        fileName: entry.fileName ?? "",
        objectives: parsed.objectives
      )
    }
  }
}
