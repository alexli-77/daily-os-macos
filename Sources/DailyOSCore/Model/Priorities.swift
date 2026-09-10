import Foundation

/// The 要务 section, parsed out of its markdown.
///
/// The markdown *is* the truth — the service reads and writes
/// `20_CYCLES/<cycle>.md` and the web console renders the same file. So this is
/// a parser and a line rewriter, not a second model: a status click has to edit
/// the line it came from and leave everything else byte-identical, which is why
/// every item carries its source line index rather than being matched by text.
/// Two items reading the same would otherwise overwrite each other.
///
/// Mirrors `cycleRenderPriorities` / `cycleSetLineStatus` in the service's
/// `src/ui/pages.ts`. `daily-os-checks` pins the round trip.

// MARK: - Status

/// 完成 / 部分 / 未做 — the three dots in front of every item.
///
/// Stored in the file as a trailing emoji. One marker per state on write; a few
/// extra are accepted on read because older hand-written cells used them.
public enum CycleTaskStatus: String, Sendable, CaseIterable, Identifiable {
  case done
  case partial
  case missed

  public var id: String { rawValue }

  /// What gets written to the file.
  public var marker: String {
    switch self {
    case .done: "✅"
    case .partial: "🚧"
    case .missed: "❌"
    }
  }

  public var label: String {
    switch self {
    case .done: "完成"
    case .partial: "部分"
    case .missed: "未做"
    }
  }

  public var tone: Tone {
    switch self {
    case .done: .ok
    case .partial: .warn
    case .missed: .danger
    }
  }

  /// Read side is deliberately wider than write side. `⭕` appears in older
  /// hand-written rows and means the same as ❌.
  static func from(marker: Character) -> CycleTaskStatus? {
    switch marker {
    case "✅": .done
    case "🚧": .partial
    case "❌", "⭕": .missed
    default: nil
    }
  }

  static let allMarkers: Set<Character> = ["✅", "🚧", "❌", "⭕"]
}

// MARK: - Items

public struct PriorityItem: Sendable, Equatable, Identifiable {
  /// Index of the line this came from, in the section body. The identity of an
  /// item *is* its line — see the type's doc comment.
  public let sourceLine: Int
  /// The sentence, with the MIT marker and the status emoji taken out; both are
  /// rendered as chrome instead, and leaving them in would show them twice.
  public let text: String
  public let status: CycleTaskStatus?
  /// 最重要的一件事. Written as `**MIT**` (or a bare `MIT` token) in the file.
  public let isMIT: Bool
  /// `LEO-102` and friends, lifted out so they can be rendered as chips.
  public let refs: [String]

  public var id: Int { sourceLine }

  public init(sourceLine: Int, text: String, status: CycleTaskStatus?, isMIT: Bool, refs: [String]) {
    self.sourceLine = sourceLine
    self.text = text
    self.status = status
    self.isMIT = isMIT
    self.refs = refs
  }
}

public struct PriorityGroup: Sendable, Equatable, Identifiable {
  /// The OKR row this group hangs off — "工作 · 技术专家".
  public let title: String
  public let items: [PriorityItem]

  public var id: String { title }

  public init(title: String, items: [PriorityItem]) {
    self.title = title
    self.items = items
  }
}

// MARK: - Document

public struct PrioritiesDocument: Sendable, Equatable {
  /// Items that appeared before any heading. Rendered above the groups rather
  /// than dropped — a file people hand-edit will have them.
  public let loose: [PriorityItem]
  public let groups: [PriorityGroup]

  public var isEmpty: Bool { loose.isEmpty && groups.isEmpty }

  public var allItems: [PriorityItem] { loose + groups.flatMap(\.items) }

  public var doneCount: Int { allItems.filter { $0.status == .done }.count }
  public var trackedCount: Int { allItems.count }

  /// How many items carry any status marker at all.
  ///
  /// The gate for "has this cycle been reviewed": `doneCount / trackedCount`
  /// puts unmarked lines in the denominator — deliberately, since an item you
  /// never marked is an item you did not finish — but that makes a cycle nobody
  /// ever touched indistinguishable from one that failed completely. Anything
  /// comparing cycles has to be able to tell those apart.
  public var markedCount: Int { allItems.filter { $0.status != nil }.count }

  // MARK: Parse

  public init(markdown: String) {
    var loose: [PriorityItem] = []
    var groups: [PriorityGroup] = []
    var currentTitle: String?
    var currentItems: [PriorityItem] = []

    func closeGroup() {
      if let title = currentTitle {
        groups.append(PriorityGroup(title: title, items: currentItems))
      }
      currentTitle = nil
      currentItems = []
    }

    for (index, rawLine) in markdown.components(separatedBy: "\n").enumerated() {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.isEmpty { continue }

      if let heading = Self.heading(in: line) {
        closeGroup()
        currentTitle = heading
        continue
      }

      let body = Self.bullet(in: line) ?? line
      let item = Self.item(from: body, sourceLine: index)
      if currentTitle != nil {
        currentItems.append(item)
      } else {
        loose.append(item)
      }
    }
    closeGroup()

    self.loose = loose
    self.groups = groups
  }

  private static func heading(in line: String) -> String? {
    guard line.hasPrefix("#") else { return nil }
    let hashes = line.prefix { $0 == "#" }
    guard hashes.count <= 6 else { return nil }
    let rest = line.dropFirst(hashes.count)
    guard rest.first == " " || rest.first == "\t" else { return nil }
    let title = rest.trimmingCharacters(in: .whitespaces)
    return title.isEmpty ? nil : title
  }

  private static func bullet(in line: String) -> String? {
    guard let first = line.first, first == "-" || first == "*" || first == "+" else { return nil }
    let rest = line.dropFirst()
    guard rest.first == " " || rest.first == "\t" else { return nil }
    return rest.trimmingCharacters(in: .whitespaces)
  }

  private static func item(from body: String, sourceLine: Int) -> PriorityItem {
    let status = body.compactMap(CycleTaskStatus.from(marker:)).last
    var text = String(body.filter { !CycleTaskStatus.allMarkers.contains($0) })

    let isMIT = text.contains("**MIT**") || Self.hasBareMIT(text)
    text = text.replacingOccurrences(of: "**MIT**", with: "")
    if isMIT { text = Self.stripBareMIT(text) }

    let refs = Self.refs(in: text)
    text = Self.collapseSpaces(text)

    return PriorityItem(sourceLine: sourceLine, text: text, status: status, isMIT: isMIT, refs: refs)
  }

  /// `MIT` as its own word, not as part of `MITIGATION` or a Chinese run.
  private static func hasBareMIT(_ text: String) -> Bool {
    ranges(of: "MIT", in: text).contains { isStandalone($0, in: text) }
  }

  private static func stripBareMIT(_ text: String) -> String {
    var result = text
    for range in ranges(of: "MIT", in: result).reversed() where isStandalone(range, in: result) {
      result.replaceSubrange(range, with: "")
    }
    return result
  }

  private static func ranges(of needle: String, in text: String) -> [Range<String.Index>] {
    var found: [Range<String.Index>] = []
    var search = text.startIndex..<text.endIndex
    while let range = text.range(of: needle, range: search) {
      found.append(range)
      search = range.upperBound..<text.endIndex
    }
    return found
  }

  private static func isStandalone(_ range: Range<String.Index>, in text: String) -> Bool {
    let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
    let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
    func isBoundary(_ char: Character?) -> Bool {
      guard let char else { return true }
      return !char.isLetter && !char.isNumber
    }
    return isBoundary(before) && isBoundary(after)
  }

  /// `LEO-102`. Uppercase-letters-then-digits, which is what every tracker this
  /// talks to produces.
  static func refs(in text: String) -> [String] {
    var found: [String] = []
    var current = ""
    var sawDash = false

    func flush() {
      if sawDash, current.contains("-"),
         let dash = current.firstIndex(of: "-"),
         current[current.startIndex..<dash].count >= 2,
         current[current.index(after: dash)...].allSatisfy(\.isNumber),
         !current[current.index(after: dash)...].isEmpty {
        found.append(current)
      }
      current = ""
      sawDash = false
    }

    for char in text {
      if char.isUppercase && !sawDash {
        current.append(char)
      } else if char == "-" && !current.isEmpty && !sawDash {
        current.append(char)
        sawDash = true
      } else if char.isNumber && sawDash {
        current.append(char)
      } else {
        flush()
      }
    }
    flush()
    return found
  }

  private static func collapseSpaces(_ text: String) -> String {
    text.split(separator: " ", omittingEmptySubsequences: true)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespaces)
  }

  // MARK: Write

  /// Rewrite one source line to carry `status` (nil clears it).
  ///
  /// The marker goes at the end — where the service's own writeback appends it
  /// and where the Feishu cells this format came from put it. Indentation is
  /// preserved so a hand-nested list stays nested.
  public static func markdown(
    _ markdown: String,
    settingLine line: Int,
    to status: CycleTaskStatus?
  ) -> String {
    var lines = markdown.components(separatedBy: "\n")
    guard lines.indices.contains(line) else { return markdown }

    let original = lines[line]
    let indent = String(original.prefix { $0 == " " || $0 == "\t" })
    var body = String(original.filter { !CycleTaskStatus.allMarkers.contains($0) })
    body = collapseSpaces(body)

    lines[line] = status.map { "\(indent)\(body) \($0.marker)" } ?? "\(indent)\(body)"
    return lines.joined(separator: "\n")
  }
}
