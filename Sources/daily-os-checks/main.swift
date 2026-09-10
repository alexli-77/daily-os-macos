import Foundation
import SwiftUI
import DailyOSCore

// Cross-platform parity checks, runnable with `swift run daily-os-checks`.
//
// Only one thing in this repository can be wrong in a way that a screenshot
// would not catch: the pixel avatar. It is a port of `pixelAvatarSvg()` from the
// daily-os service (`src/ui/avatar.ts`), and it is only worth porting if it
// produces byte-identical output — an account whose avatar changes between the
// Mac app and the browser is worse than no avatar at all.
//
// The expected values below were read off the real JavaScript implementation,
// not re-derived from the algorithm, so this compares two independent
// implementations rather than one implementation against itself.

var failures: [String] = []

@MainActor
func check(_ condition: Bool, _ message: @autoclosure () -> String) {
  if !condition { failures.append(message()) }
}

struct Fixture {
  let seed: String
  let hue: Int
  let cells: Set<PixelAvatarArt.Cell>

  init(_ seed: String, hue: Int, _ pairs: [(Int, Int)]) {
    self.seed = seed
    self.hue = hue
    self.cells = Set(pairs.map { PixelAvatarArt.Cell(x: $0.0, y: $0.1) })
  }
}

let fixtures: [Fixture] = [
  Fixture("kq7d2f1m", hue: 345, [
    (1, 0), (3, 0), (2, 0),
    (0, 2), (4, 2),
    (0, 3), (4, 3), (1, 3), (3, 3), (2, 3),
    (0, 4), (4, 4), (1, 4), (3, 4),
  ]),
  Fixture("z4h8bn02", hue: 236, [
    (0, 0), (4, 0),
    (1, 1), (3, 1), (2, 1),
    (2, 2),
    (0, 3), (4, 3), (1, 3), (3, 3), (2, 3),
    (0, 4), (4, 4),
  ]),
  Fixture("daily-os", hue: 166, [
    (0, 0), (4, 0),
    (1, 1), (3, 1), (2, 1),
    (0, 2), (4, 2), (1, 2), (3, 2),
    (0, 3), (4, 3), (2, 3),
    (0, 4), (4, 4), (1, 4), (3, 4),
  ]),
  Fixture("demo", hue: 287, [
    (1, 0), (3, 0), (2, 0),
    (0, 1), (4, 1), (1, 1), (3, 1),
    (0, 2), (4, 2), (2, 2),
    (1, 3), (3, 3),
    (2, 4),
  ]),
]

// 1. The generated grid matches the web implementation.
for fixture in fixtures {
  let art = PixelAvatarArt(seed: fixture.seed)
  check(
    Set(art.litCells) == fixture.cells,
    "avatar cells differ for seed '\(fixture.seed)'"
  )
  check(
    art.hue == fixture.hue,
    "avatar hue differs for seed '\(fixture.seed)': got \(art.hue), expected \(fixture.hue)"
  )
}

// 2. An empty seed falls back to the house avatar rather than to an empty grid.
check(
  PixelAvatarArt(seed: "").litCells == PixelAvatarArt(seed: "daily-os").litCells,
  "an empty seed should fall back to 'daily-os'"
)

// 3. No seed produces a blank or solid grid. The web implementation redraws up
//    to eight times to guarantee this; a port that dropped the retry loop would
//    still pass the fixtures above, so it is checked separately.
let half = (PixelAvatarArt.grid + 1) / 2
let totalHalfCells = PixelAvatarArt.grid * half
for index in 0..<400 {
  let seed = "seed-\(index)"
  let generated = PixelAvatarArt(seed: seed).litCells.filter { $0.x < half }.count
  check(generated >= 4, "'\(seed)' came out nearly blank (\(generated) cells)")
  check(generated <= totalHalfCells - 2, "'\(seed)' came out nearly solid (\(generated) cells)")
}

// 4. Formatting, which is shared by every screen and is easy to break silently.
check(Fmt.duration(.seconds(1.4)).hasPrefix("1.4"), "sub-10s durations should keep one decimal")
check(Fmt.duration(.seconds(128)) == "2m 08s", "minute durations should pad seconds")
check(Fmt.compactCount(940) == "940", "counts below 1k should be exact")
check(Fmt.compactCount(12_400) == "12.4k", "thousands should be compacted")
check(Fmt.money(0.0312) == "$0.0312", "sub-dollar cost needs four decimals to be readable")

// 5. Dates render in the UI's language, not the device's.
//
// This shipped wrong once: the simulator's en_US locale produced
// "Wednesday, Sep 9 · 当前周期 8.24-9.6" — one sentence in two languages. Asserted
// on language markers rather than exact strings so the check survives a machine
// in a different timezone. Delete this block when the UI is actually localised.
let heading = Fmt.dayHeading(.now)
check(heading.contains("月") && heading.contains("星期"), "dayHeading fell back to the device locale: \(heading)")

let old = Date.now.addingTimeInterval(-30 * 86_400)
check(Fmt.stamp(old).contains("月"), "stamp fell back to the device locale: \(Fmt.stamp(old))")

let clock = Fmt.time(.now)
check(clock.contains(":"), "time should render a clock: \(clock)")
check(!clock.contains("AM") && !clock.contains("PM"), "time fell back to the device locale: \(clock)")

// 5. The 要务 parser and its line rewriter.
//
// This one earns its checks: the markdown file is the source of truth, the web
// console renders the same file, and a status click has to edit exactly one
// line and leave every other byte alone. A parser that drops a heading or a
// rewriter that reflows the list would silently corrupt someone's hand-written
// cycle, and neither would fail to compile.

let sample = """
### 工作 · 技术专家
- **MIT** 把周期数据落成本地 markdown ✅
- 把配置台面收敛到 owner-only DEMO-12 🚧
- 回归测试覆盖读写往返 DEMO-15 ❌

### 金钱 · 家庭理财
- 决定二次换汇金额并执行
"""

let doc = PrioritiesDocument(markdown: sample)
check(doc.groups.count == 2, "expected 2 groups, got \(doc.groups.count)")
check(doc.groups.first?.title == "工作 · 技术专家", "first group title wrong")
check(doc.groups.first?.items.count == 3, "first group should hold 3 items")
check(doc.loose.isEmpty, "nothing sits before the first heading")
check(doc.trackedCount == 4, "4 items across both groups, got \(doc.trackedCount)")
check(doc.doneCount == 1, "one item is ✅, got \(doc.doneCount)")

if let mit = doc.groups.first?.items.first {
  check(mit.isMIT, "**MIT** should lift into a badge")
  check(mit.status == .done, "trailing ✅ should read as done")
  check(!mit.text.contains("MIT"), "MIT must not also stay in the sentence: '\(mit.text)'")
  check(!mit.text.contains("✅"), "the marker must not also stay in the sentence")
}
if let partial = doc.groups.first?.items.dropFirst().first {
  check(partial.status == .partial, "🚧 should read as partial")
  check(partial.refs == ["DEMO-12"], "expected a DEMO-12 chip, got \(partial.refs)")
}
check(doc.groups.last?.items.first?.status == nil, "an unmarked line has no status")

// Round trip: set, read back, and confirm the untouched lines are byte-identical.
// Line 6 is the only item under the second heading — line 5 is the heading
// itself, which is exactly the confusion the source-line index exists to avoid.
let targetLine = 6
let marked = PrioritiesDocument.markdown(sample, settingLine: targetLine, to: .done)
check(PrioritiesDocument(markdown: marked).groups.last?.items.first?.status == .done,
      "setting a status should survive a re-parse")
let before = sample.components(separatedBy: "\n")
let after = marked.components(separatedBy: "\n")
check(before.count == after.count, "rewriting a line must not add or remove lines")
for index in before.indices where index != targetLine {
  check(before[index] == after[index], "line \(index) changed but should not have")
}

// Clearing, and re-marking a line that already carries a marker.
let cleared = PrioritiesDocument.markdown(sample, settingLine: 1, to: nil)
check(PrioritiesDocument(markdown: cleared).groups.first?.items.first?.status == nil,
      "passing nil should clear the marker")
check(!cleared.contains("✅"), "the cleared marker should be gone from the text")
let reMarked = PrioritiesDocument.markdown(sample, settingLine: 1, to: .missed)
let reParsed = PrioritiesDocument(markdown: reMarked)
check(reParsed.groups.first?.items.first?.status == .missed, "re-marking should replace, not append")
// Count on the rewritten *line*, not the document — line 3 carries its own ❌
// and always did.
let reMarkedLine = reMarked.components(separatedBy: "\n")[1]
check(reMarkedLine.filter { $0 == "❌" }.count == 1, "exactly one marker on the rewritten line")
check(!reMarkedLine.contains("✅"), "the old marker must not survive a re-mark")
check(reMarked.components(separatedBy: "\n")[3] == before[3], "re-marking must not touch other lines")

// 6. Planned-effort formatting, which the Today header reads.
check(Fmt.minutes(0) == "0m", "zero minutes")
check(Fmt.minutes(45) == "45m", "sub-hour stays in minutes")
check(Fmt.minutes(60) == "1h", "a round hour drops the minutes")
check(Fmt.minutes(135) == "2h15m", "hours and minutes")

// 7. Cycle grouping, which decides what the sidebar calls each cycle.
//
// Worth checking rather than eyeballing: every interesting case is a *date*
// case, and the fixture will happily look correct on the day you write it and
// wrong three weeks later. These pin the boundaries instead.
func cycle(_ id: String, _ startOffset: Int, _ endOffset: Int) -> Cycle {
  let day = 24.0 * 3600
  return Cycle(
    id: id,
    label: id,
    mode: .biweekly,
    start: Date(timeIntervalSinceNow: Double(startOffset) * day),
    end: Date(timeIntervalSinceNow: Double(endOffset) * day),
    ownerId: "u",
    runId: nil,
    sections: [],
    updatedAt: .now
  )
}

let current = cycle("current", -3, 10)
let previous = cycle("previous", -17, -4)
let older = cycle("older", -31, -18)
let next = cycle("next", 11, 24)

let groups = CycleGroup.group([older, next, previous, current])
check(groups.map(\.kind) == [.current, .upcoming, .past], "expected 本期 / 计划中 / 往期, got \(groups.map(\.title))")
check(groups.first?.cycles.map(\.id) == ["current"], "the cycle containing today is 本期")
check(groups.last?.cycles.map(\.id) == ["previous", "older"], "往期 is newest first, got \(groups.last?.cycles.map(\.id) ?? [])")

// The last day of a cycle still counts as inside it — the day you are most
// likely to be looking at it is the day a midnight-vs-instant comparison would
// file it under 往期.
check(cycle("today-is-last-day", -13, 0).contains(.now), "the final day is still inside the cycle")
check(cycle("today-is-first-day", 0, 13).contains(.now), "the first day is inside the cycle")
check(!cycle("today-is-first-day", 0, 13).isUpcoming(), "a cycle starting today has already started")

// A gap between cycles must not promote a finished one to 本期.
let gapped = CycleGroup.group([older, previous])
check(gapped.first?.kind == .latest, "with nothing around today the head group is 最近一期")
check(gapped.first?.cycles.map(\.id) == ["previous"], "the most recently ended cycle takes the head slot")

// 8. Cycle completion, which the trend line plots.
//
// The distinction that matters is nil vs 0%: a cycle nobody ticked has not
// failed, and plotting it as zero would draw a collapse out of an absence.
func cycleWithPriorities(_ id: String, _ body: String) -> Cycle {
  var cycle = cycle(id, -14, -1)
  cycle.sections = [CycleSection(kind: .priorities, body: body, source: .planner, updatedAt: .now)]
  return cycle
}

check(cycle("no-sections", -14, -1).completion == nil, "a cycle with no 要务 section has no completion")
check(cycleWithPriorities("never-marked", "- 甲\n- 乙").completion == nil,
      "a cycle nobody ever marked is no data, not 0%")
check(cycleWithPriorities("all-missed", "- 甲 ❌\n- 乙 ❌").completion == CycleCompletion(done: 0, tracked: 2),
      "explicitly missed items *are* 0% — that is a fact, not an absence")
// The denominator is every item, matching the 要务 panel's own progress bar: a
// line you never came back to is a line you did not finish. One marker anywhere
// is enough to make the whole cycle countable.
check(cycleWithPriorities("mixed", "- 甲 ✅\n- 乙 ❌\n- 丙 🚧\n- 丁").completion == CycleCompletion(done: 1, tracked: 4),
      "unmarked lines stay in the denominator once the cycle has been marked at all")
check(CycleCompletion(done: 1, tracked: 3).percentText == "33%", "percentage rounds to whole numbers")
check(CycleCompletion(done: 0, tracked: 0).fraction == 0, "a zero denominator must not divide")

check(CycleGroup.group([]).isEmpty, "no cycles means no headings")
check(CycleGroup.group([current]).map(\.kind) == [.current], "one cycle means one heading, not three empty ones")

// 9. Donut geometry.
//
// The one part of a chart that can be *silently* wrong: a ring always looks
// like a ring, so arcs that fail to span a full turn, or a small slice eaten by
// its own separator, would never announce themselves on screen.
func slice(_ id: String, _ value: Double) -> DonutSlice {
  DonutSlice(id: id, label: id, value: value, color: Palette.moss)
}

let evenArcs = DonutArc.layout([slice("a", 1), slice("b", 1), slice("c", 1), slice("d", 1)])
check(evenArcs.count == 4, "four equal slices produce four arcs")
check(abs(evenArcs[0].startDegrees - (-90 + 1)) < 0.001, "the first slice starts at twelve o'clock plus half a gap")
// Span from the first slice's nominal start to the last one's nominal end must
// be a full turn, gaps included — they are cut out of slices, not inserted.
check(abs((evenArcs[3].endDegrees + 1) - (evenArcs[0].startDegrees - 1) - 360) < 0.001,
      "arcs span exactly one turn")
for arc in evenArcs {
  check(abs(arc.sweep - (90 - 2)) < 0.001, "an equal quarter sweeps 90° less one gap, got \(arc.sweep)")
}

// A tiny slice next to a huge one is the case the gap rule exists for: a fixed
// 2° separator would leave it with nothing to draw.
let lopsided = DonutArc.layout([slice("tiny", 1), slice("huge", 359)])
check(lopsided.count == 2, "both slices survive")
check(lopsided[0].sweep > 0, "a 1/360 slice still has a positive sweep, got \(lopsided[0].sweep)")
check(lopsided[0].sweep >= 0.75, "the gap never takes more than a quarter of its own slice")

check(DonutArc.layout([]).isEmpty, "no slices, no arcs")
check(DonutArc.layout([slice("z", 0)]).isEmpty, "a zero-valued slice is not drawn")
check(DonutArc.layout([slice("neg", -5)]).isEmpty, "a negative value cannot invert the ring")
check(DonutArc.layout([slice("only", 42)]).count == 1, "one slice is a whole ring")

// 10. Progress-bar segments.
//
// Both rules here are invisible when wrong: a bar of coloured rectangles always
// looks like a bar of coloured rectangles, so cells in the wrong order, or a
// guessed width presented with the same authority as a measured one, would
// never announce themselves.
func todo(_ id: String, _ state: TodoState, _ minutes: Int? = nil) -> TodoItem {
  TodoItem(id: id, text: id, kind: .priority, state: state, estimatedMinutes: minutes)
}

let mixed = PlanSegment.layout([
  todo("open-a", .open, 30),
  todo("done-a", .done, 60),
  todo("deferred", .deferred, 15),
  todo("open-b", .open),
  todo("done-b", .done, 45),
])
check(mixed.map(\.id) == ["done-a", "done-b", "open-a", "open-b", "deferred"],
      "done left, then open, then deferred — got \(mixed.map(\.id))")

// Plan order has to survive inside each group, or finishing one task would
// reshuffle the ones around it.
let ordered = PlanSegment.layout([todo("c", .open), todo("a", .done), todo("d", .open), todo("b", .done)])
check(ordered.map(\.id) == ["a", "b", "c", "d"], "plan order holds within a group, got \(ordered.map(\.id))")

// Median, not mean: one outlier must not stretch every unknown cell.
let widths = PlanSegment.layout([todo("x", .open, 15), todo("y", .open, 30), todo("z", .open, 240), todo("none", .open)])
check(widths.first(where: { $0.id == "none" })?.weight == 30,
      "an unestimated item borrows the median, got \(String(describing: widths.first { $0.id == "none" }?.weight))")
check(widths.first(where: { $0.id == "z" })?.weight == 240, "an estimated item keeps its own minutes")
check(widths.first(where: { $0.id == "none" })?.isEstimated == false, "a borrowed width is not an estimate")
check(widths.first(where: { $0.id == "x" })?.isEstimated == true, "a real estimate reports itself as one")

// Knowing nothing about duration means equal cells, not zero-width ones.
let untimed = PlanSegment.layout([todo("a", .open), todo("b", .open), todo("c", .done)])
check(Set(untimed.map(\.weight)) == [1], "with no estimates anywhere every cell is equal")
check(untimed.allSatisfy { $0.weight > 0 }, "no cell may be zero-width")

check(PlanSegment.layout([]).isEmpty, "an empty plan has no segments")

if failures.isEmpty {
  print("ok — 4 avatar fixtures, 400 generated seeds, formatting, locale, 要务 parser round-trip, 周期分组与完成率, 环形图角度, 进度条排序与宽度")
} else {
  for failure in failures { print("FAIL: \(failure)") }
  print("\(failures.count) check(s) failed")
  exit(1)
}
