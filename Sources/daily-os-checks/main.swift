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

// MARK: - Regression checks
//
// One block per bug that actually shipped. Each names the symptom, because a
// check whose only description is what it asserts tells the next person nothing
// about why breaking it matters.
//
// What this harness can and cannot cover is worth being blunt about. It runs as
// a plain executable — the repo targets machines with only Command Line Tools,
// so there is no XCTest and no view host. Everything below is pure logic that
// was *extracted* from a view for exactly this reason. Bugs that lived in
// SwiftUI's own state (a `@State` flag that never reset, a selection that
// followed focus) are listed at the bottom as explicitly uncovered rather than
// quietly omitted.

// 11a. 产物类型被改名（log 显示成 Markdown，binary 显示成 PDF）
//
// The client's enum was smaller than the service's, so the decoder mapped the
// missing kinds onto their nearest neighbour and renamed six of the user's
// seven artifacts. The service's list is the contract; `unknown` is what a
// future eighth kind must land on.
let serviceArtifactKinds = ["markdown", "text", "json", "log", "image", "pdf", "binary"]
for kind in serviceArtifactKinds {
  check(ArtifactType(rawValue: kind) != nil, "服务端的 \(kind) 在客户端没有对应的类型，会被改名")
}
check(ArtifactType(rawValue: "parquet") == nil, "未知类型必须解不出来，由解码器落到 .unknown")
check(ArtifactType.log.label != ArtifactType.markdown.label, "log 和 markdown 不能显示成同一个名字")
check(ArtifactType.binary.label != ArtifactType.pdf.label, "binary 和 pdf 不能显示成同一个名字")

// 11b. 没标记过状态的周期被画成 0%
//
// `markedCount` is the gate. Covered above in §8; restated here only so the
// regression list reads as a list of shipped bugs.
check(PrioritiesDocument(markdown: "- 甲\n- 乙").markedCount == 0, "全未标记时 markedCount 必须是 0")
check(PrioritiesDocument(markdown: "- 甲 ✅\n- 乙").markedCount == 1, "标记过一条就不再是「无数据」")

// 11c. 天气一天刷三次，而不是按固定间隔
//
// A fixed interval drifts: refreshing every N hours eventually lands at 3am and
// never at 8am. The slots are the three a day actually has.
let calendar = Calendar(identifier: .gregorian)
func at(_ hour: Int) -> Date {
  calendar.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
}
check(WeatherSnapshot.Slot.current(at(7), calendar: calendar) == .morning, "早上 7 点属于 morning")
check(WeatherSnapshot.Slot.current(at(11), calendar: calendar) == .morning, "11 点仍是 morning")
check(WeatherSnapshot.Slot.current(at(12), calendar: calendar) == .afternoon, "12 点进入 afternoon")
check(WeatherSnapshot.Slot.current(at(17), calendar: calendar) == .afternoon, "17 点仍是 afternoon")
check(WeatherSnapshot.Slot.current(at(18), calendar: calendar) == .evening, "18 点进入 evening")
check(WeatherSnapshot.Slot.current(at(23), calendar: calendar) == .evening, "深夜属于 evening")

func snapshot(at date: Date) -> WeatherSnapshot {
  WeatherSnapshot(code: 0, temperatureC: 20, high: 22, low: 15, isDay: true, place: "x", fetchedAt: date)
}
check(snapshot(at: at(8)).isFresh(at: at(10), calendar: calendar), "同一个时段内不该重新请求")
check(!snapshot(at: at(8)).isFresh(at: at(13), calendar: calendar), "跨时段必须重新请求")
check(!snapshot(at: at(8)).isFresh(at: at(8).addingTimeInterval(86_400), calendar: calendar),
      "昨天同一时段的数据不算新鲜")

// 11d. 新建周期「什么都不填」要能被识别
//
// The empty form means "decide for me"; the service fills it from the previous
// cycle. A request that cannot tell empty from explicit would have to guess.
check(NewCycleRequest().isDefault, "什么都不填就是走默认策略")
check(NewCycleRequest(note: "").isDefault, "空备注等于没填")
check(!NewCycleRequest(days: 14).isDefault, "填了长度就不是默认")
check(!NewCycleRequest(note: "下周出差").isDefault, "填了备注就不是默认")

// 11e. 选错服务目录时要当场拒绝
//
// `looksValid` is what turns "you picked the wrong folder" into a sentence at
// pick time instead of a decode error three screens later.
check(!RepoRoot.looksValid(URL(filePath: "/tmp")), "/tmp 显然不是服务目录")
check(!RepoRoot.looksValid(URL(filePath: "/definitely/not/here")), "不存在的路径必须被拒绝")

// 11f. 重要程度只由位置决定
//
// The list is the ranking, so the tier has to fall out of the position and out
// of nothing else. Two orderings that could disagree — a rank and a separate
// priority — is a list sorted one way and coloured the other.
check(PlanImportance.forRank(1) == .mit, "第一条是最重要的那条")
check(PlanImportance.forRank(2) == .high && PlanImportance.forRank(3) == .high, "二三条是重要")
check(PlanImportance.forRank(4) == .normal, "第四条起是一般")
// Rank is 1-based everywhere in the plan; a 0 would mean somebody passed an
// array index, and it must not silently become a different tier than rank 1.
check(PlanImportance.forRank(0) == .mit, "越界的 0 归到最上面一档，不另开一档")

// 11g. 拖动重排的算术
//
// The one part of drag-and-drop that is not visual. A drop gives an index in
// the list *as it is now*, and moving a row downwards shifts every index after
// it — the classic off-by-one, and it is invisible on screen because a list
// with the wrong row in the wrong place still looks like a list.
@MainActor
func planOrder(_ ids: [String], move id: String, before destination: Int) -> [String] {
  let state = AppState.previewOwner()
  state.plan = ids.map { TodoItem(id: $0, text: $0, kind: .priority) }
  return state.movePlanItem(id, before: destination)
}
check(planOrder(["a", "b", "c"], move: "c", before: 0) == ["c", "a", "b"], "拖到最前面")
check(planOrder(["a", "b", "c"], move: "a", before: 3) == ["b", "c", "a"], "拖到最后面")
// Dropping onto the gap just below yourself is the most common accidental
// drag there is, and it has to be a no-op rather than a one-place shuffle.
check(planOrder(["a", "b", "c"], move: "b", before: 1) == ["a", "b", "c"], "落回原位不算移动")
check(planOrder(["a", "b", "c"], move: "b", before: 2) == ["a", "b", "c"], "落到自己下沿也不算移动")
check(planOrder(["a", "b", "c", "d"], move: "a", before: 3) == ["b", "c", "a", "d"], "向下移动要补偿索引")
check(planOrder(["a", "b", "c"], move: "c", before: 99) == ["a", "b", "c"], "越界的目标要被夹住而不是崩")
check(planOrder(["a", "b", "c"], move: "zzz", before: 0) == ["a", "b", "c"], "不认识的 id 不动列表")

// 11h. 「计划跑完了吗」问的必须是「计划变了吗」
//
// The watcher that ends the "正在生成" note used to ask whether a plan dated
// today existed — which is already true before 重新生成 is pressed, so the note
// died thirty seconds into a ten-minute run. The fingerprint is the replacement,
// and the case it has to get right is the common one: `daily_plan` rebuilds
// candidates from the same Linear issues, so a rerun usually returns the same
// ids with different wording.
@MainActor
func fingerprint(_ rows: [(String, String, Int?)], hasPlan: Bool = true, stale: String? = nil) -> String {
  let state = AppState.previewOwner()
  state.hasPlan = hasPlan
  state.planStaleDate = stale
  state.plan = rows.map { TodoItem(id: $0.0, text: $0.1, kind: .priority, estimatedMinutes: $0.2) }
  return state.planFingerprint
}
let sameRows: [(String, String, Int?)] = [("a", "写 PR", 45), ("b", "看论文", 30)]
check(fingerprint(sameRows) == fingerprint(sameRows), "同一份计划指纹必须稳定，否则第一次轮询就误报「变了」")
check(fingerprint(sameRows) != fingerprint([("a", "写 PR 并合掉", 45), ("b", "看论文", 30)]),
      "id 没变、文案变了，也必须算新计划——这正是重新生成最常见的结果")
check(fingerprint(sameRows) != fingerprint([("a", "写 PR", 90), ("b", "看论文", 30)]),
      "只改了估时也算变了")
check(fingerprint(sameRows) != fingerprint([("a", "写 PR", 45)]), "少一条算变了")
check(fingerprint([]) != fingerprint([], hasPlan: false), "从没跑过和跑出空计划是两回事")
check(fingerprint(sameRows) != fingerprint(sameRows, stale: "9月10日"), "昨天的计划和今天的不是同一份")

// 11i. 自动刷新的节流下限
//
// The window-focus refresh and the 60 s poll share one floor. Getting it wrong
// costs nothing visible — you would simply send more requests than intended,
// forever, and never notice — so the boundary is asserted here rather than left
// to a reading of the code.
let refreshedAt = ContinuousClock.now
check(TeamRefreshPolicy.isDue(since: nil, now: refreshedAt), "从没刷新过，必须放行")
check(!TeamRefreshPolicy.isDue(since: refreshedAt, now: refreshedAt), "同一瞬间的第二次请求要挡掉")
check(!TeamRefreshPolicy.isDue(since: refreshedAt, now: refreshedAt.advanced(by: .seconds(9))),
      "不到下限不再发请求——来回切窗口不能变成一次切换一次请求")
check(TeamRefreshPolicy.isDue(since: refreshedAt, now: refreshedAt.advanced(by: TeamRefreshPolicy.floor)),
      "刚好到下限要放行，否则边界上永远差一次")
// Negative elapsed time is not hypothetical: `ContinuousClock` is monotonic, but
// a stamp taken before a rewrite of this logic, or a future caller passing a
// different clock, would make it so. Refusing is the safe direction — the poll
// asks again in a minute regardless.
check(!TeamRefreshPolicy.isDue(since: refreshedAt, now: refreshedAt.advanced(by: .seconds(-30))),
      "时间倒流时宁可不刷新")
// A poll period shorter than the floor would be a poll that throttles itself:
// every other tick silently dropped, and the advertised 60 s becomes 120 s.
check(TeamRefreshPolicy.interval >= TeamRefreshPolicy.floor, "轮询周期不能短于节流下限")

// 11j. 后台刷新只许碰队友那一半
//
// The rule the auto-refresh rests on: a refresh nobody asked for must not
// revert an optimistic edit, must not move the selection, and must not talk.
// It is a rule about *which fields get written*, so it is checked as one.
@MainActor
func teammateCycle(id: String, owner: String) -> Cycle {
  Cycle(
    id: id,
    label: id,
    mode: .biweekly,
    start: .now,
    end: .now,
    ownerId: owner,
    runId: nil,
    sections: [],
    updatedAt: .now
  )
}

@MainActor
func roster(_ ids: [String], selfId: String) -> [TeamMember] {
  ids.map { TeamMember(id: $0, displayName: $0, avatarSeed: $0, isSelf: $0 == selfId, lastSyncedAt: nil) }
}

let readySync = TeamSyncState(status: "ready", reason: "", syncedAt: nil, lastError: "")

let untouched = AppState.previewOwner()
let heldPlan = untouched.plan
let heldTodos = untouched.todos
let heldCycles = untouched.cycles
let heldSelection = untouched.selectedCycleID
untouched.applyTeamToday(
  entries: [TeamTodayEntry(id: "u_partner", displayName: "partner", items: [], staleDate: nil, hasPlan: false, updatedAt: nil)],
  sync: readySync
)
untouched.applyTeamCycles(
  members: roster(["u_demo", "u_partner"], selfId: "u_demo"),
  cycles: [teammateCycle(id: "p_new", owner: "u_partner")],
  sync: readySync
)
check(untouched.plan == heldPlan, "后台刷新不能改今日计划——那里有还没落地的乐观勾选")
check(untouched.todos == heldTodos, "后台刷新不能改收件箱")
check(untouched.cycles == heldCycles, "后台刷新不能改自己的周期——编辑器就开在上面")
check(untouched.selectedCycleID == heldSelection, "后台刷新不能动选中项")
check(untouched.toast == nil, "安静刷新就是安静：不弹 toast")
check(untouched.partnerCycles.map(\.id) == ["p_new"], "队友的周期确实换上了新的")
check(untouched.teamToday.count == 1, "队友的今日计划确实换上了新的")

// The roster moves with the cycles, but not when moving it would pull the
// member being viewed out from under the picker — a segmented control whose
// selection matches no tag renders as nothing selected, which reads as the app
// losing its place while you were looking at it.
let viewingPartner = AppState.previewOwner()
viewingPartner.viewingMemberID = "u_partner"
viewingPartner.applyTeamCycles(
  members: roster(["u_demo"], selfId: "u_demo"),
  cycles: [],
  sync: readySync
)
check(viewingPartner.members.contains { $0.id == "u_partner" }, "正在看的成员不能被后台刷新从名单里删掉")
viewingPartner.applyTeamCycles(
  members: roster(["u_demo", "u_partner", "u_third"], selfId: "u_demo"),
  cycles: [],
  sync: readySync
)
check(viewingPartner.members.count == 3, "名单里还有正在看的那个人时，要接受新名单")

// 11k. 看队友时只看这一个队友
//
// `partnerCycles` is every teammate's cycles flattened into one list, so
// returning it whole showed *everybody's* cycles under whichever name was
// picked. Two people is exactly the size at which that is invisible: one other
// name, and the unfiltered answer happens to be right.
@MainActor
func visibleIDs(viewing: String, owners: [(String, String)]) -> [String] {
  let state = AppState.previewOwner()
  state.partnerCycles = owners.map { teammateCycle(id: $0.0, owner: $0.1) }
  state.viewingMemberID = viewing
  return state.visibleCycles.map(\.id)
}
let threePerson = [("p_a", "u_a"), ("p_b", "u_b")]
check(visibleIDs(viewing: "u_a", owners: threePerson) == ["p_a"], "看 A 就只看 A 的周期")
check(visibleIDs(viewing: "u_b", owners: threePerson) == ["p_b"], "看 B 就只看 B 的周期")
check(visibleIDs(viewing: "u_gone", owners: threePerson).isEmpty, "看一个没有周期的人，答案是空，不是别人的")
// Self is still self: the filter must not leak into the owner's own list, which
// is keyed on `account.id` and not on any cycle's `ownerId`.
check(AppState.previewOwner().visibleCycles.map(\.id) == AppState.previewOwner().cycles.map(\.id),
      "看自己时还是自己的全部周期")

// 11l. 分块读取失败：第一次失败要清空，后来失败要留着
//
// `AppState.init` seeds every collection from `MockData` so the first frame is
// populated. That is a claim about the first frame only — the moment a read
// fails and its collection is left alone, the fixture stops being a placeholder
// and becomes an answer. The demo teammate and their demo tasks are plausible
// enough to act on, which is exactly the mistake `clearForDisconnected()` was
// written to prevent for the whole app; a failed chunk is the same problem one
// panel at a time.
let neverLoaded = AppState.previewOwner()
check(!neverLoaded.partnerCycles.isEmpty, "前提：fixture 里确实有 demo 队友的周期")
neverLoaded.markFailed(.cycles, reason: "404")
check(neverLoaded.cycles.isEmpty, "周期从没读成功过就失败了，要空着")
check(neverLoaded.partnerCycles.isEmpty, "队友的周期也要空着——demo 队友就是从这里冒出来的")
check(neverLoaded.members.isEmpty, "名单要空着，不然切换器里还站着 partner")
check(neverLoaded.teamSync == nil, "同步状态跟着走")
check(neverLoaded.selectedCycleID == nil, "选中的周期已经不在了")
check(neverLoaded.loadFailures[.cycles] == "404", "失败原因要记下来，横幅要读它")

// The other six chunks empty their own fields and nothing else: a failed OKR
// read costing you the cycle you were reading is the thing `load()` splits the
// reload up to avoid.
let okrFailed = AppState.previewOwner()
okrFailed.markFailed(.okr, reason: "读不到")
check(okrFailed.okrFiles.isEmpty, "OKR 首次失败要空着")
check(!okrFailed.cycles.isEmpty, "OKR 失败不能带走周期")
check(okrFailed.loadFailures.count == 1, "只记这一块失败了")

let planFailed = AppState.previewOwner()
planFailed.markFailed(.plan, reason: "读不到")
check(planFailed.plan.isEmpty && !planFailed.hasPlan, "今日计划首次失败要空着")
let todosFailed = AppState.previewOwner()
todosFailed.markFailed(.todos, reason: "读不到")
check(todosFailed.todos.isEmpty, "待办首次失败要空着")
let teamFailed = AppState.previewOwner()
teamFailed.markFailed(.teamToday, reason: "读不到")
check(teamFailed.teamToday.isEmpty && teamFailed.teamTodaySync == nil, "团队今天首次失败要空着")
let artifactsFailed = AppState.previewOwner()
artifactsFailed.markFailed(.artifacts, reason: "读不到")
check(artifactsFailed.artifacts.isEmpty && artifactsFailed.selectedArtifactID == nil, "产物首次失败要空着")
// Degraded, not stopped: the connection answered a moment ago. What is false is
// the fixture's "运行中，已跑 4 小时 12 分".
let serviceFailed = AppState.previewOwner()
serviceFailed.markFailed(.service, reason: "读不到")
check(serviceFailed.service.state == .degraded, "服务状态读不到就是降级，不是停了")
check(serviceFailed.service.uptime == .zero, "别继续报 fixture 那个运行时长")

// The other half, and the one that is easy to get wrong by fixing the first:
// a refresh that fails must not take away what is already on screen. It is real
// data — a few minutes old, still yours.
let refreshFailed = AppState.previewOwner()
refreshFailed.markLoaded(.cycles)
let realCycles = refreshFailed.cycles
let realSelection = refreshFailed.selectedCycleID
refreshFailed.markFailed(.cycles, reason: "服务重启中")
check(refreshFailed.cycles == realCycles, "已经读到过真数据，刷新失败要留着旧的")
check(refreshFailed.selectedCycleID == realSelection, "刷新失败不能把选中项也带走")
check(refreshFailed.loadFailures[.cycles] == "服务重启中", "旧数据留着，但失败照样报")

// And a read that comes back clears its own failure — a banner that keeps
// naming a chunk which has since loaded is worse than no banner.
let recovered = AppState.previewOwner()
recovered.markFailed(.artifacts, reason: "读不到")
recovered.markLoaded(.artifacts)
check(recovered.loadFailures.isEmpty, "这一块读回来了，失败标记要撤掉")

// MARK: - What this harness cannot cover
//
// Written down rather than left implicit, because a green run is read as "the
// regressions are covered" and for these it is not true.
//
// The first four shipped, all four were found by driving the installed app, and
// none of them can be reached from here: they lived in SwiftUI's own state, and
// this is a plain executable with no view host. The repo targets machines with
// only Command Line Tools, which is why there is no XCTest bundle to put them
// in.
//
//  - **勾选两次后失灵.** `TaskRow.isCompleting` was set and never reset, so it
//    latched on: the circle stayed filled through an un-tick and the guard then
//    swallowed every later press. Needs a view host to observe `@State` across
//    a mutation.
//  - **启动时第一行自己选中.** Selection followed focus two ways, so SwiftUI's
//    own first-responder assignment highlighted a finished row on launch.
//    Needs a focus system.
//  - **点行没反应.** `.onTapGesture` under `.focusable()` and four buttons never
//    fired; a background `Button` did. Needs real hit-testing.
//  - **头像被菜单裁掉.** `.menuStyle(.borderlessButton)` clamps its label to text
//    height, cropping a 20pt canvas to nothing. Needs layout.
//
// §11l above is the rule a failed chunk follows, and the rule is all of it. Two
// things stand between that rule and what a person sees, and neither is here:
//
//  - **接线.** `markLoaded` / `markFailed` are called from `LiveAppState.load()`,
//    which lives in DailyOSClient; this target depends on DailyOSCore only, so
//    the checks drive the two methods directly. A chunk whose read forgets to go
//    through `load()` — or a new endpoint added without a `ReloadChunk` — passes
//    every check above and still paints the fixture. The 分块 checks prove the
//    rule, not that the reload obeys it.
//  - **横幅.** Whether `loadFailures` reaches the screen is `MacRootView`'s
//    `else if`, i.e. a view, i.e. out of reach for the same reason as the four
//    above. That branch has already been wrong once: it hangs off
//    `wiredSections` being non-empty, and a `wiredSections` that was cleared on
//    disconnect and never restored kept `LoadFailureBanner` off screen for the
//    whole session (LEO-310). The restore is in `LiveAppState.reload()`; nothing
//    here can tell if it is removed again.
//
// Covering these means an XCTest UI target and a machine with full Xcode, which
// is a real trade against the "clone and `swift build`" property this repo has.
// Until that trade is made, the honest procedure is the one that found them:
// build Release, install, and drive the app.


// MARK: - 通告单时段推算
//
// 每一条都是数字：起点、每行的槽、超时判定、预计结束。一屏时间看起来永远像一屏时间，
// 游标错一格、late 从不触发、结束时间悄悄漏掉半张单子——没有一个会在界面上自己现形。

func sheetItem(_ id: String, _ minutes: Int?, _ state: TodoState = .open) -> TodoItem {
  TodoItem(id: id, text: id, kind: .priority, state: state, estimatedMinutes: minutes)
}

let t0 = 10 * 60 + 30   // 10:30 起
let noon = 12 * 60      // 现在 12:00

// 顺推：每行从上一行结束接着排
let basic = DaySchedule.build(
  items: [sheetItem("a", 120), sheetItem("b", 60), sheetItem("c", 15)],
  startMinute: t0, nowMinute: noon)
check(basic.rows[0].start == t0 && basic.rows[0].end == t0 + 120, "第一行从起点开始")
check(basic.rows[1].start == t0 + 120, "第二行接着第一行结束")
check(basic.rows[2].end == t0 + 195, "第三行结束等于三段估时之和")
check(basic.endOfDay == t0 + 195, "预计结束就是最后一行的结束")
check(DaySchedule.clock(basic.endOfDay) == "13:45", "10:30 加 3h15m 是 13:45")

// 延期不占时间，后面的行往前挪
let deferred = DaySchedule.build(
  items: [sheetItem("a", 120, .deferred), sheetItem("b", 60)],
  startMinute: t0, nowMinute: noon)
check(deferred.rows[0].start == nil, "延期的行没有时段")
check(deferred.rows[1].start == t0, "延期不占时间，后面的行拿回这段时间")

// 完成保留自己的时段，照常占用时间——早上确实发生过
let done = DaySchedule.build(
  items: [sheetItem("a", 120, .done), sheetItem("b", 60)],
  startMinute: t0, nowMinute: noon)
check(done.rows[0].start == t0 && done.rows[0].end == t0 + 120, "完成的行保留时段")
check(done.rows[1].start == t0 + 120, "完成的行照常把游标往后推")
check(done.remaining == 60, "已完成的不算在「还需」里")

// 部分按一半算
let partial = DaySchedule.build(
  items: [sheetItem("a", 120, .partial), sheetItem("b", 60)],
  startMinute: t0, nowMinute: noon)
check(partial.rows[0].end == t0 + 60, "部分完成的估时按一半算")
check(partial.remaining == 120, "部分仍算未完成，只是少了一半")

// 超时：未做且槽已结束
let late = DaySchedule.build(
  items: [sheetItem("a", 60), sheetItem("b", 60)],
  startMinute: t0, nowMinute: 13 * 60)
check(late.lateRows.count == 2, "13:00 时 10:30 起的两个一小时槽都过了")
let lateResolved = DaySchedule.build(
  items: [sheetItem("a", 60, .done), sheetItem("b", 60, .deferred)],
  startMinute: t0, nowMinute: 13 * 60)
check(lateResolved.lateRows.isEmpty, "标了完成或延期的行不算超时——这正是超时提醒要人做的事")

// 现在线落在第一条还没开始的行上面
let nowline = DaySchedule.build(
  items: [sheetItem("a", 60), sheetItem("b", 60), sheetItem("c", 60)],
  startMinute: t0, nowMinute: 11 * 60 + 45)
check(nowline.nowIndex == 2, "11:45 时前两行已开始，线画在第三行上面")
let allPast = DaySchedule.build(items: [sheetItem("a", 30)], startMinute: t0, nowMinute: 23 * 60)
check(allPast.nowIndex == allPast.rows.count, "整张单子都在身后时，线落在末尾")

// 没估时的行不编时间
let noEstimate = DaySchedule.build(
  items: [sheetItem("a", nil), sheetItem("b", 60)],
  startMinute: t0, nowMinute: noon)
check(noEstimate.rows[0].start == nil, "没估时就没有时段——编一个会让预计结束变成假的")
check(noEstimate.rows[1].start == t0, "没估时的行不推游标")
check(noEstimate.missingEstimates == 1, "没估时的条数要报出来，短的总数才是明着短")

// 清完了：延期也算
check(DaySchedule.build(items: [sheetItem("a", 30, .done), sheetItem("b", 30, .deferred)],
                        startMinute: t0, nowMinute: noon).isClear,
      "全部完成或延期就算清完了——诚实顺延的一天也是结束了的一天")
check(!DaySchedule.build(items: [sheetItem("a", 30, .done), sheetItem("b", 30)],
                         startMinute: t0, nowMinute: noon).isClear, "还有未做就没清完")
check(!DaySchedule.build(items: [], startMinute: t0, nowMinute: noon).isClear, "空单子不算清完")

// 起点：没有「几点开工」字段，退回计划生成时间
check(DayStart.resolve(generatedAt: nil) == DayStart.fallbackMinute, "没有计划时间就用兜底")

// 起点：作息的 working_hours.start 优先于计划生成时刻（07:43 的 cron 不该决定开工点）
let cron = Calendar.current.date(bySettingHour: 7, minute: 43, second: 0, of: .now)
check(DayStart.resolve(generatedAt: cron, workStart: 9 * 60 + 30) == 9 * 60 + 30, "有作息起点就用它，不用 cron 时刻")
check(DayStart.resolve(generatedAt: cron, workStart: nil) == 7 * 60 + 43, "没作息起点才退回计划生成时刻")
check(DayStart.minute(fromClock: "09:30") == 570 && DayStart.minute(fromClock: "24:61") == nil, "HH:mm 解析，非法返回 nil")

// 吃饭块：能在午餐前排下的照排，排不下的顶到午餐之后，午餐作为 fixedBlock 暴露
let lunch = DaySchedule.FixedBlock(id: "meal:午餐", label: "午餐", start: 12 * 60, end: 13 * 60)
let mealed = DaySchedule.build(
  items: [sheetItem("a", 30), sheetItem("b", 120)],
  startMinute: 11 * 60, nowMinute: 11 * 60, meals: [lunch])
check(mealed.rows[0].start == 11 * 60 && mealed.rows[0].end == 11 * 60 + 30, "短任务在午餐前排下：11:00–11:30")
check(mealed.rows[1].start == 13 * 60, "放不进午餐前的长任务顶到 13:00 之后，而不是骑在午餐上")
check(mealed.fixedBlocks.count == 1 && mealed.fixedBlocks[0].label == "午餐", "午餐作为 fixedBlock 暴露给视图渲染")
// 起点之前的餐（早于 startMinute 结束）被丢弃
let staleMeal = DaySchedule.build(
  items: [sheetItem("a", 60)],
  startMinute: 14 * 60, nowMinute: 14 * 60, meals: [lunch])
check(staleMeal.fixedBlocks.isEmpty, "计划从 14:00 起时，12:00 的午餐与今天无关，不显示")
// 首尾相接的固定块（会议 11:00–12:30 紧接午餐 12:30–13:00、Session 13:00–15:00）：
// 跨过一个块后游标正好落在下一个块上，任务必须继续往后推，不能骑在第二个块上（LEO-330）
let chain = DaySchedule.build(
  items: [sheetItem("a", 45), sheetItem("b", 60)],
  startMinute: 10 * 60, nowMinute: 10 * 60,
  meals: [
    DaySchedule.FixedBlock(id: "m1", label: "会议", start: 11 * 60, end: 12 * 60 + 30, kind: .meeting),
    DaySchedule.FixedBlock(id: "l", label: "午餐", start: 12 * 60 + 30, end: 13 * 60),
    DaySchedule.FixedBlock(id: "m2", label: "Session", start: 13 * 60, end: 15 * 60, kind: .meeting),
  ])
check(chain.rows[0].start == 10 * 60 && chain.rows[0].end == 10 * 60 + 45, "45 分钟的任务在 11:00 会议前排下")
check(chain.rows[1].start == 15 * 60, "1 小时的任务跨过首尾相接的三个固定块，排到 15:00")
check(chain.fixedBlocks.map(\.id) == ["m1", "l", "m2"], "三个固定块都按顺序放置")

// 钉住的行（LEO-331）：待在用户放的钟点，自动排的行绕开它，就像绕开吃饭
func pinnedItem(_ id: String, _ minutes: Int?, at start: Int, _ state: TodoState = .open) -> TodoItem {
  TodoItem(id: id, text: id, kind: .priority, state: state, estimatedMinutes: minutes, pinnedStart: start)
}
let pinned = DaySchedule.build(
  items: [sheetItem("a", 45), pinnedItem("p", 60, at: 14 * 60), sheetItem("b", 45), sheetItem("c", 30)],
  startMinute: 13 * 60, nowMinute: 13 * 60)
check(pinned.rows[1].start == 14 * 60 && pinned.rows[1].end == 15 * 60, "钉住的行在 14:00–15:00，不管它排第几")
check(pinned.rows[0].start == 13 * 60, "自动排的第一行从起点开始")
check(pinned.rows[2].start == 15 * 60, "13:45 起放不下 45 分钟，绕到钉住的行之后")
check(pinned.rows[3].start == 15 * 60 + 45, "后面的行接着往下排")
check(pinned.endOfDay == 16 * 60 + 15, "预计结束算到最后一行")
let pinnedNoEstimate = DaySchedule.build(items: [pinnedItem("p", nil, at: 9 * 60)], startMinute: 8 * 60, nowMinute: 8 * 60)
check(pinnedNoEstimate.rows[0].end == 9 * 60 + 30, "钉住但没估时的行按 30 分钟占位")
let pinnedLate = DaySchedule.build(
  items: [sheetItem("a", 30), pinnedItem("p", 60, at: 20 * 60)],
  startMinute: 9 * 60, nowMinute: 9 * 60)
check(pinnedLate.endOfDay == 21 * 60, "钉在晚上的行把预计结束拉到 21:00")
let pinnedDeferred = DaySchedule.build(
  items: [pinnedItem("p", 60, at: 9 * 60, .deferred), sheetItem("a", 60)],
  startMinute: 9 * 60, nowMinute: 9 * 60)
check(pinnedDeferred.rows[0].start == nil && pinnedDeferred.rows[1].start == 9 * 60, "顺延的行钉住了也不占时间")
let pinnedOnLunch = DaySchedule.build(
  items: [pinnedItem("p", 30, at: 12 * 60 + 15), sheetItem("a", 60)],
  startMinute: 11 * 60 + 30, nowMinute: 11 * 60, meals: [lunch])
check(pinnedOnLunch.rows[0].start == 12 * 60 + 15, "用户可以把任务钉在午餐上，照放不误")
check(pinnedOnLunch.rows[1].start == 13 * 60, "自动排的行绕开午餐和钉住的行，从 13:00 开始")

// 新记的 todo 排在最后（LEO-334）：整天都钉住了，后面追加的自动行不能跑到早上的空档里
let appended = DaySchedule.build(
  items: [pinnedItem("p1", 60, at: 11 * 60), pinnedItem("p2", 60, at: 14 * 60), sheetItem("new", 30)],
  startMinute: 9 * 60 + 30, nowMinute: 9 * 60)
check(appended.rows[2].start == 15 * 60, "排在钉住行后面的新 todo 从最后一个钉住行结束开始，而不是 09:30")
let ahead = DaySchedule.build(
  items: [sheetItem("first", 30), pinnedItem("p", 60, at: 14 * 60)],
  startMinute: 9 * 60 + 30, nowMinute: 9 * 60)
check(ahead.rows[0].start == 9 * 60 + 30, "排在钉住行前面的自动行照旧从起点开始")

// 重叠的块并排：一组互相重叠的块按最忙时刻的数量分列，不重叠的占满宽度
let columns = TimelineColumns.assign([
  .init(id: "meet", start: 9 * 60, end: 10 * 60),
  .init(id: "task", start: 9 * 60 + 30, end: 10 * 60 + 30),
  .init(id: "next", start: 10 * 60, end: 11 * 60),
  .init(id: "alone", start: 12 * 60, end: 13 * 60),
])
check(columns["meet"] == .init(column: 0, count: 2) && columns["task"] == .init(column: 1, count: 2), "9:00 的会和 9:30 的任务左右分开")
check(columns["next"] == .init(column: 0, count: 2), "10:00 开始的块用回左边那一列（会议已经结束）")
check(columns["alone"] == .init(column: 0, count: 1), "不和任何块重叠的占满宽度")
check(TimelineColumns.assign([.init(id: "a", start: 60, end: 120), .init(id: "b", start: 120, end: 180)])["b"]?.count == 1, "首尾相接不算重叠")

// 没有餐块时行为和以前完全一样（默认参数护栏）
let noMeal = DaySchedule.build(items: [sheetItem("a", 60), sheetItem("b", 60)], startMinute: t0, nowMinute: noon)
check(noMeal.fixedBlocks.isEmpty && noMeal.rows[1].start == t0 + 60, "不传餐块时和旧的零间隙顺推一致")

// 格式
check(DaySchedule.duration(120) == "2h" && DaySchedule.duration(90) == "1h30m"
      && DaySchedule.duration(45) == "45m", "时长按原型的紧凑写法")
check(DaySchedule.clock(25 * 60) == "01:00", "跨过午夜要绕回去，不能打印 25:00")

// MARK: - 往日
//
// 日期标签要按服务的"今天"算，跨月、跨年都不能错位；摘要要和那天结束时今天页的勾一致。

check(DayLabel.text(for: "2026-09-24", today: "2026-09-25") == "昨天", "前一天叫昨天")
check(DayLabel.text(for: "2026-09-23", today: "2026-09-25") == "前天", "前两天叫前天")
check(DayLabel.text(for: "2026-09-22", today: "2026-09-25") == "9月22日 周二", "再往前写日期和星期")
check(DayLabel.text(for: "2026-09-30", today: "2026-10-01") == "昨天", "跨月的昨天")
check(DayLabel.text(for: "2025-12-31", today: "2026-01-01") == "昨天", "跨年的昨天")
check(DayLabel.text(for: "2026-03-07", today: "2026-03-09") == "前天", "跨夏令时切换也按日历天算")
check(DayLabel.text(for: "not-a-date", today: "2026-09-25") == "not-a-date", "认不出的日期原样显示，不崩")

let pastDay = DayHistory(
  date: "2026-09-24", dates: [], today: "2026-09-25", hasPlan: true,
  items: [sheetItem("a", 30, .done), sheetItem("b", 30, .partial), sheetItem("c", 30, .deferred), sheetItem("d", 30)]
)
check(pastDay.summary == "4 条 · 完成 1 · 部分 1 · 顺延 1", "摘要按那天留下的状态计数: \(pastDay.summary)")
check(DayHistory(date: "2026-09-24", dates: [], today: "2026-09-25", hasPlan: true, items: [sheetItem("a", nil)]).summary == "1 条 · 完成 0",
      "没有部分和顺延就不写这两项")
check(DayHistory(date: "2026-09-10", dates: [], today: "2026-09-25", hasPlan: false, items: []).summary == "这天没有计划",
      "没计划和有计划但没条目要说得不一样")

// MARK: - 倒数日
//
// The day counts come resolved from the service, so what is testable here is
// only the presentation of one: how a count reads, which band a row falls into,
// and which rows are worth a line on Today. That last one is a hand-kept
// duplicate of `cardCountdowns` in the service — these checks are what make the
// duplication survivable.

func countdown(
  _ id: String,
  _ daysLeft: Int,
  direction: Countdown.Direction = .until,
  recurrence: Countdown.Recurrence = .none,
  pinned: Bool = false,
  ordinal: Int? = nil
) -> Countdown {
  Countdown(
    id: id, title: id, date: "2026-01-01", direction: direction, recurrence: recurrence,
    pinned: pinned, occurrence: "2026-01-01", daysLeft: daysLeft, ordinal: ordinal
  )
}

check(countdown("a", 23).daysLabel == "还有 23 天", "倒数读作「还有」")
check(countdown("a", 0).daysLabel == "就是今天", "当天不说天数")
check(countdown("a", -9).daysLabel == "已过去 9 天", "过期的截止日读作「已过去」")
check(countdown("a", -517, direction: .since).daysLabel == "已经 517 天", "正数日不是逾期，读作「已经」")
check(countdown("a", 110, recurrence: .yearly, ordinal: 60).ordinalLabel == "第 60 年", "周年序数")
check(countdown("a", 110).ordinalLabel == nil, "不重复的条目没有周年")

// Colour only at the near edge: three days red, a week amber, the rest plain.
check(countdown("a", 2).tone == .danger, "三天以内是红的")
check(countdown("a", 7).tone == .warn, "一周以内是黄的")
check(countdown("a", 8).tone == .neutral, "再远就不上色")
check(countdown("a", -2).tone == .neutral, "过去的不上色")
check(countdown("a", -2, direction: .since).tone == .neutral, "正数日从不上色")

let bands = CountdownGroup.group([
  countdown("pinned", 400, pinned: true),
  countdown("soon", 5),
  countdown("phd", -300, direction: .since),
  countdown("gone", -19),
])
check(bands.map(\.kind) == [.pinned, .running, .past], "三段：置顶 / 进行中 / 已经过去")
check(bands[1].items.map(\.id) == ["soon", "phd"], "正数日算进行中，它在往上数: \(bands[1].items.map(\.id))")
check(bands[2].items.map(\.id) == ["gone"], "只有过了期的一次性事件算过去")
check(CountdownGroup.group([countdown("soon", 5)]).map(\.kind) == [.running], "空的段不出现")

// The strip's filter, which has to keep agreeing with the service's.
let forCard = Countdown.forCard([
  countdown("pinned-far", 400, pinned: true),
  countdown("near", 9),
  countdown("edge", 30),
  countdown("far", 31),
  countdown("gone", -1),
])
check(forCard.map(\.id) == ["pinned-far", "near", "edge"], "置顶的 + 三十天内的，最多三条: \(forCard.map(\.id))")
check(Countdown.forCard([countdown("phd", -300, direction: .since)]).isEmpty, "不置顶的正数日不上卡片")
check(Countdown.forCard([countdown("phd", -300, direction: .since, pinned: true)]).count == 1, "置顶的正数日上卡片")

// Saying which clock the counts are on. Read at an instant, because a zone
// that observes daylight saving is not one offset — Montreal is UTC-5 in
// January and UTC-4 in July, and printing either year-round is a wrong fact
// dressed as a precise one. China observes none, which is what makes the pair
// below a 13-hour gap in winter and a 12-hour one in summer.
let january = Date(timeIntervalSince1970: 1_767_225_600)  // 2026-01-01T00:00:00Z
let july = Date(timeIntervalSince1970: 1_782_950_400)     // 2026-07-01T00:00:00Z
let montreal = TimeZone(identifier: "America/Toronto")!
let shanghai = TimeZone(identifier: "Asia/Shanghai")!

check(CountdownZone.offset(montreal, at: january) == "UTC-5", "蒙特利尔冬天是 -5: \(CountdownZone.offset(montreal, at: january))")
check(CountdownZone.offset(montreal, at: july) == "UTC-4", "夏令时要跟着变: \(CountdownZone.offset(montreal, at: july))")
check(CountdownZone.offset(shanghai, at: january) == "UTC+8", "中国不过夏令时")
check(CountdownZone.offset(shanghai, at: july) == "UTC+8", "全年都是 +8")
check(CountdownZone.offset(TimeZone(identifier: "UTC")!, at: july) == "UTC", "零偏移不写 +0")
check(CountdownZone.offset(TimeZone(identifier: "Asia/Kolkata")!, at: july) == "UTC+5:30", "半小时时区要写出分钟")

check(CountdownZone.label("America/Toronto", at: july) == "America/Toronto（UTC-4）", "标签带上当下的偏移")
check(CountdownZone.label("Mars/Olympus", at: july) == "Mars/Olympus", "认不出的时区只印名字，不编偏移")

// The counts follow this machine; the note mentions the card's zone only when
// the offset actually differs — which is to say, only while you are away.
check(CountdownZone.note(counting: "America/Toronto", card: "America/Toronto", at: july)
        == "天数按 America/Toronto（UTC-4）计",
      "在家时只说一句: \(CountdownZone.note(counting: "America/Toronto", card: "America/Toronto", at: july))")
check(CountdownZone.note(counting: "America/Toronto", card: "America/New_York", at: july)
        == "天数按 America/Toronto（UTC-4）计",
      "名字不同但日界相同，不提")
check(CountdownZone.note(counting: "Asia/Shanghai", card: "America/Toronto", at: july)
        == "天数按 Asia/Shanghai（UTC+8）计，早上的卡片按 America/Toronto（UTC-4）算",
      "人在中国：屏幕跟本机，卡片还按配置的时区: \(CountdownZone.note(counting: "Asia/Shanghai", card: "America/Toronto", at: july))")
check(CountdownZone.note(counting: "Mars/Olympus", card: "America/Toronto", at: july) == "天数按 Mars/Olympus 计",
      "认不出的时区不拿去比偏移")
check(CountdownZone.note(counting: "Asia/Shanghai", card: "", at: july) == "天数按 Asia/Shanghai（UTC+8）计",
      "老服务不回 cardTimezone，就只说一句")

// The date picker's round trip. Pinned to UTC on both sides — reading a
// calendar date in a western timezone and writing it back loses a day.
check(CountdownDate.day(from: CountdownDate.date(from: "2026-04-24") ?? .distantPast) == "2026-04-24",
      "日期串往返不掉一天")
check(CountdownDate.heading("2026-04-24").contains("4月24日"), "长日期按日历日渲染: \(CountdownDate.heading("2026-04-24"))")
check(CountdownDate.heading("not-a-date") == "not-a-date", "认不出的日期原样显示")


// MARK: - 周期要务与 OKR 对齐
//
// The join key is the group heading, which the service writes from the
// objective's own title. What matters here is the failure mode: a cycle planned
// before an OKR rename must still show every 要务 it recorded. This vault has
// real ones — cycles up to 2026-08-24 say `工作-技术专家。完成 AI 工程…` where
// the current file says `工作 · 技术专家`.

func okrObjective(_ id: String, _ title: String, krs: Int = 1) -> Objective {
  Objective(
    id: id,
    title: title,
    keyResults: (1...max(krs, 1)).map { KeyResult(id: "\(id)-KR\($0)", title: "KR\($0)", priority: nil, progress: 0, health: nil) }
  )
}

/// Built from markdown, the way a cycle file actually arrives — so these checks
/// exercise the parser's own heading handling rather than a hand-made document.
func okrPriorities(_ groups: [(String, Int)]) -> PrioritiesDocument {
  let body = groups
    .map { title, count in (["### \(title)"] + (0..<count).map { "- 任务 \($0)" }).joined(separator: "\n") }
    .joined(separator: "\n\n")
  return PrioritiesDocument(markdown: body)
}

let alignedCurrent = CycleOkrAlignment.align(
  objectives: [okrObjective("O1", "工作 · 技术专家", krs: 4), okrObjective("O2", "金钱 · 家庭理财规划师", krs: 3)],
  priorities: okrPriorities([("工作 · 技术专家", 4), ("金钱 · 家庭理财规划师", 2)])
)
check(alignedCurrent.rows.count == 2, "两个 O 两条要务组，对出两行")
check(alignedCurrent.rows.allSatisfy { $0.objective != nil }, "标题一致时全部匹配上")
check(!alignedCurrent.isWhollyUnmatched, "匹配上了就不是整期失配")

// The rename case. Every group is orphaned, and every 要务 still has a row.
let renamed = CycleOkrAlignment.align(
  objectives: [okrObjective("O1", "工作 · 技术专家")],
  priorities: okrPriorities([("工作-技术专家。完成 AI 工程职业/研究路径的季度验证。", 4)])
)
check(renamed.isWhollyUnmatched, "改过 OKR 标题的旧周期是整期失配")
check(renamed.rows.contains { $0.isOrphanedGroup && $0.group?.items.count == 4 }, "失配的组照样带着它的 4 条要务")
check(renamed.rows.contains { $0.recordedHeading?.hasPrefix("工作-技术专家") == true }, "失配时留着周期当时记的标题")
check(renamed.rows.contains { $0.objective?.id == "O1" && $0.hasNoPriorities }, "没被认领的 O 也要有一行")

// An objective nobody planned under — O7 配偶 this cycle.
let emptyObjective = CycleOkrAlignment.align(
  objectives: [okrObjective("O1", "工作 · 技术专家"), okrObjective("O7", "配偶 · 伙伴")],
  priorities: okrPriorities([("工作 · 技术专家", 2)])
)
check(emptyObjective.rows.count == 2, "有 O 没要务也占一行")
check(emptyObjective.rows.last?.objective?.id == "O7" && emptyObjective.rows.last?.hasNoPriorities == true,
      "没要务的 O 排在后面")
check(!emptyObjective.isWhollyUnmatched, "有一个对上就不算整期失配")

// Long titles: the cycle file stores them through shortLabel, the OKR file whole.
let longTitle = String(repeating: "工", count: 80)
check(CycleOkrAlignment.shortLabel(longTitle).count == 61, "超长标题截到 60 加省略号")
let truncated = CycleOkrAlignment.align(
  objectives: [okrObjective("O1", longTitle)],
  priorities: okrPriorities([(CycleOkrAlignment.shortLabel(longTitle), 1)])
)
check(truncated.rows.first?.objective?.id == "O1", "截断过的标题也要能匹配回原 O")

check(CycleOkrAlignment.align(objectives: [], priorities: okrPriorities([])).rows.isEmpty,
      "两边都空就没有行")
check(!CycleOkrAlignment.align(objectives: [okrObjective("O1", "工作 · 技术专家")],
                               priorities: okrPriorities([])).isWhollyUnmatched,
      "空周期不算失配，它没东西可失配")

// MARK: - 计划来源列
//
// 以前除了带 Linear 引用的行，全都显示「日程」；而计划行从来不带引用，所以每一行都是「日程」。

check(PlanSource(candidateID: "linear:ABC-12").label == "ABC-12" && PlanSource(candidateID: "linear:ABC-12").isIssue,
      "Linear 行显示 issue 编号，并当成引用")
check(PlanSource(candidateID: "weekly:3:a1b2c3d4").label == "要务", "周期要务行显示「要务」")
check(PlanSource(candidateID: "todo_inbox:todo-1").label == "随手记", "随手记行显示「随手记」")
check(PlanSource(candidateID: "rhythm:meal:午餐").label == "作息", "服务端加上的吃饭行显示「作息」")
check(PlanSource(candidateID: "vault:notes/a.md").label == "笔记", "vault 行显示「笔记」")
check(!PlanSource(candidateID: "weekly:0:x").isIssue, "要务不是链接，不加下划线")
check(PlanSource(candidateID: "p1", sourceRef: "DEMO-12").label == "DEMO-12", "已经带引用的行照旧用引用")
check(PlanSource(candidateID: "something-else").label == "日程", "认不出的前缀才回到「日程」")

// MARK: - 自己定 MIT
//
// MIT 以前永远是计划第一条，用户改不了；第一条常常是个会。现在服务端可以说哪条是 MIT，
// 用户也可以自己加、自己拿掉。

let mitState = AppState.previewOwner()
mitState.plan = ["a", "b", "c"].map { TodoItem(id: $0, text: $0, kind: .priority) }
_ = await mitState.updatePlanRow(candidateID: "c", rank: 3, text: nil, color: nil, note: nil, mit: true)
check(mitState.plan.map { $0.isMIT } == [true, false, true], "把第三条设成 MIT，第一条按排序建议的 MIT 留着，不会跟着变")
check(mitState.plan[2].mitByUser && !mitState.plan[0].mitByUser, "自己定的和计划建议的分得开")
_ = await mitState.updatePlanRow(candidateID: "a", rank: 1, text: nil, color: nil, note: nil, mit: false)
check(mitState.plan.map { $0.isMIT } == [false, false, true], "建议的那条也能拿掉")
_ = await mitState.updatePlanRow(candidateID: "b", rank: 2, text: "改个说法", color: nil, note: nil)
check(mitState.plan.map { $0.isMIT } == [false, false, true], "只改文字不碰 MIT")

// MARK: - 双周排期
//
// 角色就是 OKR 目标标题开头那个词；排期视图按它分组。

check(CycleScheduleState.role(of: "工作-UX designer。探索并开创全新的工作方式") == "工作", "「工作-」开头的目标归到「工作」")
check(CycleScheduleState.role(of: "朋友：正能量闺蜜。建立人脉网档案") == "朋友", "全角冒号也能切出角色")
check(CycleScheduleState.role(of: "") == "其他", "没有目标的要务归到「其他」")
let scheduleState = CycleScheduleState(
  cycleID: "c", today: "2026-10-08",
  items: [
    .init(key: "a", text: "写方案 **MIT**", okr: "工作-设计", mit: true),
    .init(key: "b", text: "打球", okr: "享乐-生活", mit: false),
    .init(key: "c", text: "作品集", okr: "工作-设计", mit: false),
  ],
  days: [.init(date: "2026-10-08", weekday: "星期四", restDay: false)],
  schedule: CycleSchedule(sessions: [
    ScheduleSession(id: "1", itemKey: "a", label: "写方案", date: "2026-10-08", start: "10:00", minutes: 120, bigRock: true),
    ScheduleSession(id: "2", itemKey: "b", label: "打球", date: "2026-10-08", minutes: 90),
  ], deadlines: []),
  running: false
)
check(scheduleState.roles.map(\.role) == ["工作", "享乐"], "角色按要务在文件里出现的顺序排")
check(scheduleState.roles.first?.items.map(\.key) == ["a", "c"], "同一角色的要务排在一起")
check(scheduleState.minutes(on: "2026-10-08") == 210, "一天的合计把这天的格子都加上")

// MARK: - 排期周视图
//
// 没定时段的格子要摆进当天的空档里：避开飞书日程、吃饭和大石头；今天从现在往后摆；摆不下的进「全天」。

let weekState = CycleScheduleState(
  cycleID: "c", today: "2026-10-09",
  items: [
    .init(key: "x", text: "速写", okr: "名利", mit: false),
    .init(key: "m", text: "方案 **MIT**", okr: "工作", mit: true),
  ],
  days: [
    .init(date: "2026-10-09", weekday: "星期五", restDay: false, workStart: 9 * 60, workEnd: 18 * 60, blocks: [.init(label: "午餐", start: 12 * 60, end: 13 * 60)]),
    .init(date: "2026-10-10", weekday: "星期六", restDay: true, workStart: 9 * 60, workEnd: 18 * 60),
  ],
  schedule: CycleSchedule(sessions: [
    ScheduleSession(id: "rock", itemKey: "m", label: "方案", date: "2026-10-10", start: "09:00", minutes: 120, bigRock: true),
    ScheduleSession(id: "sketch", itemKey: "x", label: "速写", date: "2026-10-10", minutes: 60),
    ScheduleSession(id: "plan", itemKey: "m", label: "方案", date: "2026-10-10", minutes: 60),
    ScheduleSession(id: "late", itemKey: "x", label: "速写", date: "2026-10-09", minutes: 60),
    ScheduleSession(id: "huge", itemKey: "x", label: "速写", date: "2026-10-09", minutes: 240),
  ], deadlines: [ScheduleDeadline(itemKey: "m", label: "方案", date: "2026-10-10")]),
  running: false,
  events: [.init(date: "2026-10-10", start: 11 * 60 + 30, end: 12 * 60, title: "日会"), .init(date: "2026-10-10", start: nil, end: nil, title: "团建")],
  nowMinute: 20 * 60 + 5
)
let saturday = CycleWeekLayout.layout(weekState.days[1], in: weekState)
let placed = Dictionary(uniqueKeysWithValues: saturday.blocks.compactMap { block in block.session.map { ($0.id, block) } })
check(placed["rock"]?.kind == .bigRock && placed["rock"]?.start == 9 * 60, "大石头就在它占的时段")
check(placed["plan"]?.start == 12 * 60, "MIT 先摆：11:00 被大石头占到、11:30 有日会，从 12:00 开始")
check(placed["sketch"]?.start == 13 * 60 && placed["sketch"]?.kind == .suggested, "其余的接在后面，标成建议时段")
check(saturday.allDay == ["团建", "截止 · 方案"], "全天日程和截止日在顶上")
let friday = CycleWeekLayout.layout(weekState.days[0], in: weekState)
check(friday.blocks.first { $0.session?.id == "late" }?.start == 20 * 60 + 15, "今天从现在（凑到下一个一刻钟）往后摆")
check(friday.unplaced.map(\.id) == ["huge"], "今天剩下的时间放不下的，进「排不下」")
check(weekState.weeks.count == 1 && weekState.weeks[0].count == 2, "按七天一周分")

// MARK: - KR 标签
// KR 前面不再带目标编号「01-」；标题本身以 KR1 开头时，标签整个省掉，不说两遍。

check(KeyResultLabel.text(id: "01-KR1", title: "KR1 完成作品集") == nil, "标题已经写了 KR1，就不再重复")
check(KeyResultLabel.text(id: "02-KR3", title: "坚持每日一画") == "KR3", "去掉目标编号，只留 KR3")
check(KeyResultLabel.text(id: "KR2", title: "做分享") == "KR2", "本来就没编号的照旧")

// MARK: - 作息
// 每类一天多少时间：时间块按类别加起来；24:00 结束的块也算对；侧栏里作息排在周期后面。

let routineMode = RoutineMode(id: "m", label: "作品集日", blocks: [
  RoutineBlock(id: "a", start: "07:00", end: "08:00", title: "口语", category: "habit", kind: .slot),
  RoutineBlock(id: "b", start: "13:00", end: "18:00", title: "作品集", category: "portfolio", kind: .slot),
  RoutineBlock(id: "c", start: "20:00", end: "21:30", title: "画画", category: "habit", kind: .slot),
  RoutineBlock(id: "d", start: "12:30", end: "13:00", title: "休息"),
  RoutineBlock(id: "e", start: "23:00", end: "24:00", title: "睡前", category: "rest"),
])
check(routineMode.minutesByCategory().map(\.key) == ["portfolio", "habit", "rest"], "类别按时长从多到少")
check(routineMode.minutesByCategory().first { $0.key == "habit" }?.minutes == 150, "同类的几块加在一起")
check(routineMode.blocks.last?.minutes == 60, "到 24:00 结束的块是 60 分钟，不是负数")
check(AppSection.workGroup == [.today, .cycles, .routine, .okr, .countdown], "作息在周期后面")
check(AppSection.routine.shortcut == "3" && AppSection.schedules.shortcut == "8", "快捷键跟着侧栏顺序走")

if failures.isEmpty {
  print("ok — 4 avatar fixtures, 400 generated seeds, formatting, locale, 要务 parser round-trip, 周期分组与完成率, 环形图角度, 进度条排序与宽度, 重要程度分档, 拖动重排, 计划指纹, 刷新节流, 后台刷新写入面, 队友周期归属, 分块读取失败, 通告单时段推算, 钉住的行, 重叠分列, 往日, 倒数日, 要务与 OKR 对齐, 计划来源列, 自己定 MIT, 双周排期, 排期周视图, KR 标签, 作息, 回归集")
} else {
  for failure in failures { print("FAIL: \(failure)") }
  print("\(failures.count) check(s) failed")
  exit(1)
}
