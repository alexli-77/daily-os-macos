import SwiftUI
import Combine
import DailyOSCore

/// The screen you open by reflex.
///
/// One call sheet, not two lists. The plan and the inbox used to sit in separate
/// panels side by side, which meant the day's work was split across two columns
/// that each looked complete and neither was — you could read "three things
/// left" off one of them while four more sat in the other. They are one sheet
/// now, in four columns: **when / state / what / where it came from**.
///
/// The other change is that the sheet has a clock. Every row carries the slot it
/// occupies, computed forward from the start of the day through the estimates,
/// so "six things" is legible as "until 16:00" before the day starts rather than
/// at 18:00 when it has already failed. See `DaySchedule`.
struct TodayScreen: View {
  @Environment(AppState.self) private var state
  /// One selection for the whole screen. Plan ids are `daily_plan` candidate ids
  /// and inbox ids are ledger ids, so they cannot collide.
  @State private var selectedTaskID: TodoItem.ID?
  @State private var showsExecution = false
  @State private var showsPastDays = false
  /// The rail (随手记 + 记过的 + 团队) sits beside the call sheet on a wide window and
  /// drops under it on a narrow one. This flag lets the user force the stacked
  /// form even when there is room — some people want the call sheet full-width.
  @AppStorage("today.railStacked") private var railStacked = false
  /// Measured content width, so the layout follows the window rather than the
  /// platform. Below the breakpoint two columns would crush the call sheet's
  /// task text (the slot/source columns are fixed-width), so the rail stacks.
  @State private var contentWidth: CGFloat = 0
  private static let railBreakpoint: CGFloat = 800
  /// Ticked every minute so the now-line and the late flags actually track the
  /// clock. Without it "现在 15:28" was frozen at whenever the view last drew.
  @State private var now = Date()
  private let clock = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

  var body: some View {
    ScreenScaffold("今天", subtitle: subtitle) {
      let sideBySide = contentWidth >= Self.railBreakpoint && !railStacked
      // Above the split rather than inside a column: it is one line about the
      // day, the same line the morning card opened with, and it belongs to the
      // whole screen rather than to the call sheet.
      CountdownStrip()
      Group {
        if sideBySide {
          HStack(alignment: .top, spacing: Metrics.md) {
            mainColumn.frame(maxWidth: .infinity, alignment: .top)
            rail.frame(width: Metrics.listIdeal)
          }
        } else {
          VStack(alignment: .leading, spacing: Metrics.md) {
            mainColumn
            rail
          }
        }
      }
      .background(widthReader)
    } toolbar: {
      HStack(spacing: Metrics.sm) {
        WeatherStrip()
        if contentWidth >= Self.railBreakpoint {
          // Icon reflects the current layout: a right panel when the rail is
          // beside the plan, a bottom strip when it is stacked under it.
          Button {
            withAnimation(.snappy(duration: 0.2)) { railStacked.toggle() }
          } label: {
            Image(systemName: railStacked ? "rectangle.bottomthird.inset.filled" : "rectangle.trailinghalf.inset.filled")
          }
          .buttonStyle(MossButtonStyle(prominent: false))
          .accessibilityLabel(railStacked ? "并排侧栏" : "收起侧栏")
          .accessibilityAddTraits(railStacked ? [] : [.isSelected])
          .help(railStacked ? "把「记过的 / 团队」放回右侧" : "把「记过的 / 团队」收到主列下方")
        }
        Button {
          showsPastDays = true
        } label: {
          Image(systemName: "clock.arrow.circlepath")
        }
        .buttonStyle(MossButtonStyle(prominent: false))
        .accessibilityLabel("往日")
        .help("看前几天的计划和复盘")
        Button {
          withAnimation(.snappy(duration: 0.2)) { showsExecution.toggle() }
        } label: {
          Image(systemName: "chart.bar.xaxis")
        }
        .buttonStyle(MossButtonStyle(prominent: false))
        .accessibilityLabel(showsExecution ? "收起执行情况" : "执行情况")
        .accessibilityAddTraits(showsExecution ? [.isSelected] : [])
        .help(showsExecution ? "收起执行情况" : "查看执行情况")
      }
    }
    .onReceive(clock) { now = $0 }
    .sheet(isPresented: $showsPastDays) { PastDaysSheet() }
  }

  /// The day itself: the plan as a call sheet, optionally under the execution
  /// panel. The inbox and the team used to live here too; they moved to the rail
  /// so this column stays "one screen of today's plan".
  @ViewBuilder private var mainColumn: some View {
    VStack(alignment: .leading, spacing: Metrics.md) {
      if showsExecution { ExecutionPanel(schedule: schedule) }
      CallSheetPanel(schedule: schedule, selectedID: $selectedTaskID)
    }
  }

  /// 随手记 + 记过的 + 团队今天. Secondary but always-glanceable, so it rides
  /// alongside the plan rather than sinking to the bottom of one scroll.
  ///
  /// The capture field stayed; the list under it did not. A capture now lands on
  /// the call sheet, so a second list of the same open items would be the same
  /// work shown twice — what is left here is what the sheet no longer carries.
  @ViewBuilder private var rail: some View {
    VStack(alignment: .leading, spacing: Metrics.md) {
      DayTimePanel(schedule: schedule, blocks: state.planMealBlocks)
      QuickCapturePanel()
      TodoPanel(selectedID: $selectedTaskID)
      TeamTodayPanel()
    }
  }

  private var widthReader: some View {
    GeometryReader { proxy in
      Color.clear
        .onAppear { contentWidth = proxy.size.width }
        .onChange(of: proxy.size.width) { contentWidth = proxy.size.width }
    }
  }

  /// The plan only. Inbox captures are a scratchpad, not scheduled work — they
  /// have their own panel in the rail and no longer get folded into the clock
  /// (which is what made the call sheet long and the "预计结束" projection lie).
  private var items: [TodoItem] { state.plan }

  private var schedule: DaySchedule {
    DaySchedule.build(
      items: items,
      startMinute: DayStart.resolve(generatedAt: state.planGeneratedAt, workStart: state.planWorkStartMinute),
      nowMinute: DaySchedule.minute(of: now),
      meals: state.planMealBlocks
    )
  }

  private var subtitle: String {
    let date = Fmt.dayHeading()
    guard let cycle = state.currentCycle else { return date }
    return "\(date) · 当前周期 \(Fmt.cycleTitle(cycle))"
  }
}

// MARK: - Call sheet

/// Today, as one sheet.
private struct CallSheetPanel: View {
  @Environment(AppState.self) private var state
  let schedule: DaySchedule
  @Binding var selectedID: TodoItem.ID?

  @State private var isStarting = false
  /// Where an empty-time click asked to add something, minutes from midnight.
  @State private var addAt: Int?
  /// A 作息 block being dragged or stretched for today: its shown start / end.
  @State private var fixedDrag: (id: String, start: Int, end: Int)?
  /// A drag in progress on the timeline, so the block can follow the pointer
  /// (snapped) before anything is sent.
  @State private var drag: TimelineDrag?

  var body: some View {
    Panel("今天的通告单", subtitle: subtitle) {
      VStack(alignment: .leading, spacing: Metrics.sm) {
        if let startedAt = state.planRunStartedAt { StartedNote(at: startedAt) }

        if schedule.rows.isEmpty {
          EmptyState(
            icon: "tray",
            title: isRunning ? "计划正在生成" : "今天还没有计划",
            message: isRunning
              ? "daily_plan 在后台跑，通常一两分钟。跑完计划会自己出现在这里，飞书也会收到一条。"
              : "计划由 daily_plan 工作流生成——早上的定时任务会跑，在飞书里发一句「daily-os plan」也会跑。也可以现在就在这里跑一次：会花模型额度，跑完还会往飞书发一条。",
            actionTitle: isRunning ? nil : "生成计划",
            action: isRunning ? nil : (generate as () -> Void)
          )
        } else {
          // The day's progress right under the subtitle, above the banners and
          // the timeline, where it is read first (LEO-336).
          SheetFooter(schedule: schedule)
          if !schedule.lateRows.isEmpty {
            OverdueBanner(rows: schedule.lateRows, pushAll: pushLateToNow)
          }
          if !state.staleCaptures.isEmpty {
            StaleCaptureBanner(captures: state.staleCaptures, abandon: abandon)
          }
          sheet
        }
      }
    } actions: {
      if let routine = state.todayRoutine, routine.modes.count > 1 {
        // 作品集日 / Cutto 日: decided at the morning meeting, switched here.
        Picker("", selection: Binding(get: { routine.mode.id }, set: { switchMode(to: $0, in: routine) })) {
          ForEach(routine.modes, id: \.id) { mode in Text(mode.label).tag(mode.id) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .help("今天按哪种作息过。切换后时段格子跟着变；已经排好的 to-do 不会自己挪，要按新格子重排就点「重新生成」。")
      }
      if !schedule.rows.isEmpty {
        Button(isRunning ? "正在生成…" : "重新生成", action: generate)
          .buttonStyle(QuietButtonStyle())
          .disabled(isStarting || isRunning)
          .help(isRunning
            ? "已经有一次 daily_plan 在跑了，跑完计划会自己出现。"
            : "再跑一次 daily_plan：会花模型额度，跑完还会往飞书发一条。")
      }
    }
  }

  /// The day on a clock (LEO-330): every hour is the same height, so a block's
  /// height *is* its length and a 15-minute break is a sliver. Meals, routines
  /// and fixed meetings sit at their own wall-clock times.
  ///
  /// Tasks can be dragged anywhere on it (LEO-331): the start snaps to the half
  /// hour and the row is pinned there; rows nobody has moved are still laid out
  /// from order + estimate around everything fixed. Dragging the bottom edge
  /// changes the length in 15-minute steps. Overlapping blocks share the width.
  @ViewBuilder private var sheet: some View {
    let range = timelineRange
    let origin = range.lowerBound
    let blocks = state.planMealBlocks.filter { $0.end > range.lowerBound && $0.start < range.upperBound }
    let slotted = schedule.rows.enumerated().filter { $0.element.start != nil && $0.element.end != nil }
    let unslotted = schedule.rows.enumerated().filter { $0.element.start == nil || $0.element.end == nil }
    let columns = TimelineColumns.assign(
      blocks.map { .init(id: "block:\($0.id)", start: $0.start, end: $0.end) }
        + slotted.map { .init(id: "row:\($0.element.id)", start: shownStart($0.element), end: shownEnd($0.element)) }
    )
    VStack(alignment: .leading, spacing: Metrics.sm) {
      GeometryReader { geo in
        let lane = max(geo.size.width - Timeline.gutter, 1)
        ZStack(alignment: .topLeading) {
          HourGrid(range: range)
          // The 作息's slots, behind everything: the time kept for each
          // category, which that category's rows go into.
          ForEach(state.todayRoutine?.slots ?? []) { slot in
            RoutineSlotBand(slot: slot)
              .frame(width: lane, height: max(Timeline.y(slot.end, from: slot.start) - 2, 12))
              .offset(x: Timeline.gutter, y: Timeline.y(slot.start, from: origin) + 1)
              .allowsHitTesting(false)
          }
          // Empty time is the add button, like a calendar: click, write or
          // pick a 要务 from this cycle, done.
          Color.clear
            .contentShape(Rectangle())
            .frame(width: lane, height: Timeline.y(range.upperBound, from: origin))
            .offset(x: Timeline.gutter)
            .onTapGesture(coordinateSpace: .local) { point in
              let minute = origin + Int(point.y / Timeline.pointsPerMinute)
              addAt = min(23 * 60 + 30, max(origin, minute / 30 * 30))
            }
          if let addAt {
            Color.clear
              .frame(width: 1, height: 1)
              .offset(x: Timeline.gutter + 60, y: Timeline.y(addAt, from: origin))
              .popover(isPresented: Binding(get: { self.addAt != nil }, set: { if !$0 { self.addAt = nil } }), arrowEdge: .trailing) {
                QuickAdd(start: addAt) { self.addAt = nil }
                  .environment(state)
              }
          }
          ForEach(blocks) { block in
            let shown = fixedDrag?.id == block.id ? (fixedDrag!.start, fixedDrag!.end) : (block.start, block.end)
            RoutineFixedBlock(block: block)
              .overlay(alignment: .bottom) {
                if block.routineBlockID != nil {
                  ResizeHandle(onChanged: { stretchFixed(block, by: $0) }, onEnded: { commitFixed(block) })
                }
              }
              .gesture(
                DragGesture(minimumDistance: 4)
                  .onChanged { value in moveFixed(block, by: value.translation.height) }
                  .onEnded { _ in commitFixed(block) },
                including: block.routineBlockID == nil ? .none : .all
              )
              .timelineSlot(start: shown.0, end: shown.1, origin: origin, lane: lane, placement: columns["block:\(block.id)"])
          }
          ForEach(slotted, id: \.element.id) { index, row in
            taskBlock(index: index, row: row, origin: origin, compact: (columns["row:\(row.id)"]?.count ?? 1) > 1)
              .timelineSlot(start: shownStart(row), end: shownEnd(row), origin: origin, lane: lane, placement: columns["row:\(row.id)"])
          }
          // A row coming in from below the timeline has no block on it yet;
          // show where it would land.
          if let drag, drag.kind == .move, let row = unslotted.first(where: { $0.element.id == drag.id })?.element {
            DropGhost(text: row.item.text)
              .timelineSlot(start: drag.value, end: drag.value + (row.item.estimatedMinutes ?? 30), origin: origin, lane: lane, placement: nil)
          }
          if !schedule.isClear && range.contains(schedule.now) {
            NowMarker(minute: schedule.now)
              .offset(y: Timeline.y(schedule.now, from: origin) - Timeline.labelHeight / 2)
          }
        }
      }
      .frame(height: Timeline.y(range.upperBound, from: origin))
      if !unslotted.isEmpty {
        // Deferred rows and rows with no estimate have no slot to sit in.
        // Dragging one up onto the timeline pins it there (30 minutes if it had
        // no estimate).
        VStack(alignment: .leading, spacing: Metrics.xxs) {
          Text("没排进时间轴 · 拖到上面的钟点就排进去").font(Typo.caption).foregroundStyle(Palette.ink3)
          ForEach(unslotted, id: \.element.id) { index, row in
            taskBlock(index: index, row: row, origin: origin)
          }
        }
        .padding(.leading, Timeline.gutter)
      }
      if schedule.isClear { ClearState(schedule: schedule) }
    }
    .coordinateSpace(name: Timeline.space)
  }

  private func taskBlock(index: Int, row: DaySchedule.Row, origin: Int, compact: Bool = false) -> some View {
    let isDragging = drag?.id == row.id
    let canResize = row.start != nil && (row.item.state == .open || row.item.state == .partial)
    return CallSheetRow(
      row: row,
      isPlanRow: index < state.plan.count,
      selectedID: $selectedID,
      onUnpin: row.item.pinnedStart == nil ? nil : { unpin(row) },
      compact: compact
    )
    .overlay(alignment: .bottom) {
      if canResize { ResizeHandle(onChanged: { resize(row, by: $0) }, onEnded: { commitResize(row) }) }
    }
    .overlay(alignment: .topTrailing) {
      if isDragging, let drag { DragReadout(drag: drag) }
    }
    .opacity(isDragging && drag?.kind == .move ? 0.85 : 1)
    .transition(.taskRow)
    .gesture(
      DragGesture(minimumDistance: 4, coordinateSpace: .named(Timeline.space))
        .onChanged { value in move(row, value: value, origin: origin) }
        .onEnded { _ in commitMove(row) }
    )
  }

  /// Where a row is drawn: its slot, or where it is being dragged to.
  private func shownStart(_ row: DaySchedule.Row) -> Int {
    if let drag, drag.id == row.id, drag.kind == .move { return drag.value }
    return row.start ?? 0
  }

  private func shownEnd(_ row: DaySchedule.Row) -> Int {
    let start = shownStart(row)
    if let drag, drag.id == row.id, drag.kind == .resize { return start + drag.value }
    return start + ((row.end ?? 0) - (row.start ?? 0))
  }

  private func move(_ row: DaySchedule.Row, value: DragGesture.Value, origin: Int) {
    let raw: Int
    if let start = row.start {
      raw = start + Int((value.translation.height / Timeline.pointsPerMinute).rounded())
    } else {
      // From below the timeline: the pointer is the start.
      raw = origin + Int((value.location.y / Timeline.pointsPerMinute).rounded())
    }
    drag = TimelineDrag(id: row.id, kind: .move, value: TimelineDrag.snap(raw, step: 30))
  }

  private func commitMove(_ row: DaySchedule.Row) {
    guard let drag, drag.id == row.id, drag.kind == .move else { return }
    self.drag = nil
    // Let go where it already was: nothing to pin.
    guard drag.value != row.start else { return }
    Task {
      let outcome = await state.placePlanItem(row.id, rank: row.rank, start: drag.value)
      switch outcome {
      case .ok(let message): state.toast = message ?? "已放到 \(DaySchedule.clock(drag.value))"
      case .failed(let why), .unsupported(let why): state.toast = why
      }
    }
  }

  private func resize(_ row: DaySchedule.Row, by height: CGFloat) {
    let base = (row.end ?? 0) - (row.start ?? 0)
    let raw = base + Int((height / Timeline.pointsPerMinute).rounded())
    drag = TimelineDrag(id: row.id, kind: .resize, value: max(15, TimelineDrag.snap(raw, step: 15)))
  }

  private func commitResize(_ row: DaySchedule.Row) {
    guard let drag, drag.id == row.id, drag.kind == .resize else { return }
    self.drag = nil
    guard drag.value != (row.end ?? 0) - (row.start ?? 0) else { return }
    // A partial row is drawn at half its estimate; what is stored is the whole.
    let estimate = row.item.state == .partial ? drag.value * 2 : drag.value
    Task {
      let outcome = await state.setPlanEstimate(candidateID: row.id, rank: row.rank, minutes: estimate)
      switch outcome {
      case .ok(let message): state.toast = message ?? "已改为 \(DaySchedule.duration(estimate))"
      case .failed(let why), .unsupported(let why): state.toast = why
      }
    }
  }

  // MARK: 作息 blocks, today only

  private func moveFixed(_ block: DaySchedule.FixedBlock, by height: CGFloat) {
    let length = block.end - block.start
    let start = TimelineDrag.snap(block.start + Int((height / Timeline.pointsPerMinute).rounded()), step: 15)
    let clamped = max(0, min(24 * 60 - length, start))
    fixedDrag = (block.id, clamped, clamped + length)
  }

  private func stretchFixed(_ block: DaySchedule.FixedBlock, by height: CGFloat) {
    let end = TimelineDrag.snap(block.end + Int((height / Timeline.pointsPerMinute).rounded()), step: 15)
    fixedDrag = (block.id, block.start, max(block.start + 15, min(24 * 60, end)))
  }

  /// Dropped: the block moves or stretches for today; the 作息 template does not.
  private func commitFixed(_ block: DaySchedule.FixedBlock) {
    guard let drag = fixedDrag, drag.id == block.id, let blockID = block.routineBlockID else { fixedDrag = nil; return }
    fixedDrag = nil
    guard drag.start != block.start || drag.end != block.end else { return }
    Task {
      let outcome = await state.changeTodayRoutineBlock(blockID: blockID, action: "edit", label: block.label, start: drag.start, end: drag.end)
      switch outcome {
      case .ok:
        let store = state
        state.toast("\(block.label) 今天改到 \(DaySchedule.clock(drag.start))–\(DaySchedule.clock(min(drag.end, 24 * 60 - 1)))（只改今天）", undo: {
          Task { @MainActor in _ = await store.changeTodayRoutineBlock(blockID: blockID, action: "reset") }
        })
      case .failed(let why), .unsupported(let why): state.toast = why
      }
    }
  }

  private func unpin(_ row: DaySchedule.Row) {
    Task {
      let outcome = await state.placePlanItem(row.id, rank: row.rank, start: nil)
      switch outcome {
      case .ok(let message): state.toast = message ?? "已取消固定"
      case .failed(let why), .unsupported(let why): state.toast = why
      }
    }
  }

  private var subtitle: String {
    let start = DayStart.resolve(generatedAt: state.planGeneratedAt, workStart: state.planWorkStartMinute)
    return "点空白处加一项 · 点一条编辑或删除 · 拖动改时间，拖下边缘改时长 · 没拖过的从 \(DaySchedule.clock(start)) 起按估时自动排"
  }

  /// Whole hours from the first thing on the day to the last, so the earliest
  /// routine and the projected end both fit.
  private var timelineRange: ClosedRange<Int> {
    let slots = state.todayRoutine?.slots ?? []
    let starts = state.planMealBlocks.map(\.start) + schedule.rows.compactMap(\.start) + slots.map(\.start)
    let ends = state.planMealBlocks.map(\.end) + schedule.rows.compactMap(\.end) + slots.map(\.end)
    let lower = max(0, (starts.min() ?? schedule.now) / 60 * 60)
    let upper = min(24 * 60, ((ends.max() ?? lower) + 59) / 60 * 60)
    return lower...max(upper, lower + 60)
  }

  private var isRunning: Bool { state.planRunStartedAt != nil }

  private func abandon(_ ids: [String]) {
    Task {
      let outcome = await state.abandonCaptures(ids)
      switch outcome {
      case .ok(let message): state.toast = message ?? "已放弃"
      case .failed(let why), .unsupported(let why): state.toast = why
      }
    }
  }

  /// Move every late row to the end of the plan, in the order they were late.
  ///
  /// Only the order changes — a late row stays `open`. The banner's offer is
  /// "give these the time they still need", not "call them done"; rewriting
  /// their state here would make one button do the thing the four-state circle
  /// exists to keep deliberate.
  private func pushLateToNow() {
    let ids = schedule.lateRows.map(\.item.id).filter { id in
      state.plan.contains { $0.id == id }
    }
    guard !ids.isEmpty else { return }
    // A late row the user pinned would stay where it was; release it so it
    // follows the others to the end of the queue.
    for row in schedule.lateRows where row.item.pinnedStart != nil {
      Task { _ = await state.placePlanItem(row.id, rank: row.rank, start: nil) }
    }
    var order = state.plan.map(\.id)
    withAnimation(.snappy(duration: 0.28)) {
      for id in ids { order = state.movePlanItem(id, before: state.plan.count) }
    }
    Task {
      if case .failed(let why) = await state.savePlanOrder(order) { state.toast = why }
      else { state.toast = "顺到队尾了，后面的时段跟着重算" }
    }
  }

  private func switchMode(to mode: String, in routine: TodayRoutine) {
    guard mode != routine.mode.id else { return }
    let label = routine.modes.first { $0.id == mode }?.label ?? mode
    Task {
      switch await state.setDayMode(date: nil, mode: mode) {
      case .ok: state.toast = "今天按「\(label)」过；要让 to-do 落进新的格子，点「重新生成」"
      case .failed(let why), .unsupported(let why): state.toast = why
      }
    }
  }

  private func generate() {
    guard !isStarting, !isRunning else { return }
    isStarting = true
    Task {
      let outcome = await state.generatePlan()
      isStarting = false
      switch outcome {
      case .ok(let message): state.toast = message ?? "已让 daily_plan 跑起来了"
      case .failed(let why), .unsupported(let why): state.toast = why
      }
    }
  }
}

// MARK: - One row

/// 圆圈 | 任务 | MIT·来源 | 时长
///
/// Every control on a row lives in one place (the row editor, opened by
/// clicking the row) except the circle, which stays one click from done. They
/// used to be spread over five spots — circle, hover buttons, the estimate,
/// the title, the pin — and the edit itself was the one with nothing to see.
private struct CallSheetRow: View {

  @Environment(AppState.self) private var state
  let row: DaySchedule.Row
  /// Inbox rows cannot be `partial` — the service's inbox endpoint has no such
  /// status. See `RowActionBar.allowed`.
  let isPlanRow: Bool
  @Binding var selectedID: TodoItem.ID?
  /// Set when the row is pinned to a time; releases it to automatic layout.
  var onUnpin: (() -> Void)?
  /// Sharing the width with an overlapping block. The fixed-width pieces — the
  /// source column, and the hover controls that keep their space while
  /// invisible — would leave the task text no room at all, so the source goes
  /// and the controls only take space while they are showing.
  var compact = false

  @State private var isConfirmingDelete = false
  /// The row editor: click the row; every edit is staged there and sent on 保存.
  @State private var isEditingRow = false
  @State private var editText = ""
  @State private var editColor: String?
  @State private var editNote = ""
  @State private var editState: TodoState = .open
  @State private var editMIT = false
  @State private var editMinutes: Int?

  private var item: TodoItem { row.item }
  private var isEditable: Bool { item.state == .open || item.state == .partial }
  private var isResolved: Bool { item.state == .done || item.state == .deferred }
  /// Meal rows sit after the plan but can still land on a low rank in a short
  /// plan; they are never the day's most important thing.
  private var isMIT: Bool {
    canBeMIT && (item.isMIT ?? (PlanImportance.forRank(row.rank) == .mit))
  }

  /// A meal or routine is never the day's MIT, and a capture off the plan has
  /// nowhere to record it.
  private var canBeMIT: Bool { isPlanRow && !item.id.hasPrefix("rhythm:") }

  /// Fixed locale: the wire format is always `yyyy-MM-dd`, and a user whose
  /// region formats dates differently must still parse it.
  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  /// 昨天没做完 / 已顺延 N 天 — nil for anything captured today.
  ///
  /// Counted in whole days from the capture date, so it does not drift with the
  /// time of day the row is looked at.
  private var carriedLabel: String? {
    guard let from = item.carriedFrom, !isResolved else { return nil }
    let calendar = Calendar.current
    guard let captured = Self.dayFormatter.date(from: from) else { return nil }
    let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: captured), to: calendar.startOfDay(for: .now)).day ?? 0
    if days <= 0 { return nil }
    return days == 1 ? "昨天没做完" : "已顺延 \(days) 天"
  }

  private var tint: BlockTint {
    if isResolved { return .resolved }
    return item.colorTag.flatMap(BlockTint.named) ?? BlockTint.forTask(candidateID: item.id)
  }

  /// Three columns (LEO-335): the content, then what the row *is* (MIT and
  /// its source), then what you can *do* to it. The last two are fixed, so the
  /// content column is the same width on every row and every title wraps at
  /// the same place (LEO-334).
  /// Room for MIT plus the longest source label, a Linear key like CUTTO-1038.
  private static let tagsWidth: CGFloat = 130
  /// The length only. The start time is the hour column's job and a pin is
  /// not something to look at every row for; both live in the row editor.
  private static let actionsWidth: CGFloat = 52

  /// One line for the row's state, kept right under the title.
  private var statusText: (text: String, color: Color)? {
    if row.isLate { return ("已过时段 · 还没更新", Palette.mint600) }
    if item.state == .deferred { return ("顺到明天", Palette.ink3) }
    if item.state == .partial { return ("做了一部分 · 时段按一半算", Palette.ink3) }
    // A capture is written straight onto the sheet and stays until it is done.
    // Saying which day it came from is what separates "still not done" from
    // "new today" — without it a week-old row looks fresh.
    if let carried = carriedLabel { return (carried, Palette.mint600) }
    return nil
  }

  /// Half-hour blocks are 46pt: a title line and the status line only fit
  /// with the padding tightened.
  private var verticalPadding: CGFloat {
    (row.minutes ?? 60) <= 30 && row.start != nil ? Metrics.xxs : Metrics.xs
  }

  /// As many title lines as the block has room for once the status line is
  /// kept, at most two (LEO-334). A long title used to push the status line out
  /// of the block, where it was clipped away.
  private var titleLines: Int {
    guard row.start != nil, let minutes = row.minutes else { return 2 }
    let inside = CGFloat(minutes) * Timeline.pointsPerMinute - 2 - 2 * verticalPadding
    let reserved: CGFloat = statusText == nil ? 0 : 16
    return max(1, min(2, Int((inside - reserved) / 18)))
  }

  var body: some View {
    mainLine
    .padding(.horizontal, Metrics.sm)
    .padding(.vertical, verticalPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(tint.fill)
    // Popovers, not inline editors: on the timeline a block is exactly as tall
    // as its slot, and an editor growing inside it would be clipped away.
    .popover(isPresented: rowEditorBinding, arrowEdge: .trailing) {
      RowEditor(
        text: $editText,
        color: $editColor,
        note: $editNote,
        rowState: $editState,
        isMIT: $editMIT,
        minutes: $editMinutes,
        allowedStates: allowedStates,
        canBeMIT: canBeMIT,
        mitByUser: item.mitByUser,
        showsEstimate: isEditable,
        timeRange: timeRange,
        autoColor: BlockTint.forTask(candidateID: item.id).ink,
        onUnpin: onUnpin.map { unpin in { isEditingRow = false; unpin() } },
        onDelete: { isEditingRow = false; isConfirmingDelete = true },
        onCancel: { isEditingRow = false },
        onSave: saveEdits
      )
    }
    .contentShape(Rectangle())
    .onTapGesture(perform: openEditor)
    .help("点一下编辑：改文字、标完成 / 做了一半 / 顺延、设 MIT、改时长")
    .accessibilityAction(named: "编辑", openEditor)
    .confirmationDialog("删除这一条？", isPresented: $isConfirmingDelete) {
      Button("删除", role: .destructive, action: remove)
      Button("取消", role: .cancel) {}
    } message: {
      Text(deleteMessage)
    }
  }

  /// Clicking away saves, like Calendar; 取消 closes without going through here.
  private var rowEditorBinding: Binding<Bool> {
    Binding(get: { isEditingRow }, set: { if !$0 && isEditingRow { saveEdits() } })
  }

  private var mainLine: some View {
    HStack(alignment: .top, spacing: Metrics.sm) {
      StateCircle(state: item.state) {
        set(item.state == .done ? .open : .done)
      }

      VStack(alignment: .leading, spacing: 2) {
        title
        if let status = statusText {
          Text(status.text).font(Typo.caption).foregroundStyle(status.color).lineLimit(1)
        }
        if let note = item.note, !note.isEmpty {
          // What 记一条更新 wrote. It used to vanish on save — the ledger kept
          // it, nothing read it back — which made the control look like it had
          // thrown the text away.
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "text.quote").font(.system(size: 9))
            Text(note).fixedSize(horizontal: false, vertical: true)
          }
          .font(Typo.caption)
          .foregroundStyle(Palette.ink3)
          .padding(.top, 1)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      tags
        .frame(width: compact ? nil : Self.tagsWidth, alignment: .topLeading)

      actions
        .frame(width: compact ? nil : Self.actionsWidth, alignment: .topTrailing)
    }
  }

  /// The middle column: MIT first, where it is seen, and the source under it,
  /// both on the column's left edge. A row sharing its width with an
  /// overlapping block keeps MIT and drops the source.
  private var tags: some View {
    VStack(alignment: .leading, spacing: 2) {
      if isMIT {
        Text("MIT")
          .font(Typo.caption)
          .bold()
          .kerning(0.96)
          .foregroundStyle(Palette.page)
          .padding(.horizontal, 6)
          .padding(.vertical, 1)
          .background(Palette.q1, in: Capsule())
          .opacity(isResolved ? 0.4 : 1)
          .padding(.top, 1)
      }
      if !compact {
        source
          .padding(.top, isMIT ? 0 : 2)
      }
    }
  }

  /// The right column: the row's length. Here rather than under the title: a
  /// title that wraps fills a short block, and the estimate under it was
  /// clipped away (LEO-332).
  private var actions: some View {
    Text((row.minutes ?? item.estimatedMinutes).map(DaySchedule.duration) ?? "没估时")
      .font(Typo.caption)
      .foregroundStyle(Palette.ink3)
      .lineLimit(1)
      .fixedSize()
      .padding(.top, 2)
  }

  /// The states the editor offers, in its order. An inbox row cannot be
  /// `partial` — the service's inbox endpoint has no such status.
  private var allowedStates: [TodoState] {
    isPlanRow ? [.open, .done, .partial, .deferred] : [.open, .done, .deferred]
  }

  /// "13:00–13:30", for the editor: the row no longer prints its own start.
  private var timeRange: String? {
    guard let start = row.start, let end = row.end else { return nil }
    return "\(DaySchedule.clock(start))–\(DaySchedule.clock(end))"
  }

  /// The row's text, at most as many lines as the block has room for. Click it
  /// to open the row editor (LEO-334).
  private var title: some View {
    Text(item.text)
      .font(Typo.label)
      .foregroundStyle(tint.ink)
      .strikethrough(isResolved, color: Palette.ink3)
      .lineLimit(titleLines)
      .truncationMode(.tail)
      // Without this the stack hands the title less height than its lines need
      // and a two-line title collapses to one.
      .fixedSize(horizontal: false, vertical: true)
  }

  private func openEditor() {
    selectedID = item.id
    editText = item.text
    editColor = item.colorTag
    editNote = ""
    editState = item.state
    editMIT = isMIT
    editMinutes = item.estimatedMinutes
    isEditingRow = true
  }

  /// Sends only what changed, as one `update`. The edit is today's version of
  /// this row; a Linear issue or cycle priority keeps its own (LEO-332).
  private func saveEdits() {
    isEditingRow = false
    let text = editText.trimmingCharacters(in: .whitespacesAndNewlines)
    let note = editNote.trimmingCharacters(in: .whitespacesAndNewlines)
    let newText = !text.isEmpty && text != item.text ? text : nil
    let newColor = editColor != item.colorTag ? (editColor ?? "auto") : nil
    let newNote = note.isEmpty ? nil : note
    let newMIT = canBeMIT && editMIT != isMIT ? editMIT : nil
    let newState = editState != item.state ? editState : nil
    let newMinutes = isEditable && editMinutes != item.estimatedMinutes ? editMinutes : nil
    let clearsMinutes = isEditable && editMinutes == nil && item.estimatedMinutes != nil
    let edits = newText != nil || newColor != nil || newNote != nil || newMIT != nil
    guard edits || newState != nil || newMinutes != nil || clearsMinutes else { return }
    let candidateID = item.id
    let rank = row.rank
    Task {
      var failure: String?
      if edits, isPlanRow {
        let outcome = await state.updatePlanRow(candidateID: candidateID, rank: rank, text: newText, color: newColor, note: newNote, mit: newMIT)
        if case .failed(let why) = outcome { failure = why } else if case .unsupported(let why) = outcome { failure = why }
      }
      if failure == nil, newMinutes != nil || clearsMinutes {
        let outcome = await state.setPlanEstimate(candidateID: candidateID, rank: rank, minutes: newMinutes)
        if case .failed(let why) = outcome { failure = why } else if case .unsupported(let why) = outcome { failure = why }
      }
      // Last, so a rename and a tick in one save land as edited-then-ticked.
      var note: String?
      if failure == nil, let newState { (failure, note) = await send(newState) }
      if let failure { state.toast = failure; return }
      if let note, let newState {
        // The schedule moved with it; offer the way back.
        state.toast("已改好；\(note)", undo: undo(from: newState))
      } else {
        state.toast = "已改好"
      }
    }
  }

  private var isCapture: Bool { !isPlanRow || item.id.hasPrefix("todo_inbox:") }

  /// What deleting does differs by source, so the dialog says which one this is.
  private var deleteMessage: String {
    if isCapture { return "会从今天的通告单和随手记里一起删掉。" }
    let label = PlanSource(candidateID: item.id, sourceRef: item.sourceRef).label
    return "只从今天的通告单上拿掉，\(label) 本身不动，明天还可能再排进来。"
  }

  private func remove() {
    guard isPlanRow else {
      // A capture that is not on the plan: deleting it is the inbox's own delete.
      state.setTodo(item.id, to: .deleted)
      return
    }
    let candidateID = item.id
    let rank = row.rank
    Task {
      switch await state.planFeedback(candidateID: candidateID, rank: rank, event: "remove", note: nil) {
      case .ok(let note):
        let store = state
        let takeBack: @MainActor () -> Void = {
          Task { @MainActor in _ = await store.planFeedback(candidateID: candidateID, rank: rank, event: "reopen", note: nil) }
        }
        state.toast(["已从今天删除", note].compactMap { $0 }.joined(separator: "；"), undo: takeBack)
      case .failed(let why), .unsupported(let why): state.toast = why
      }
    }
  }

  /// Linear key / 要务 / 随手记 — see `PlanSource`. Only an issue key is
  /// styled as a reference; the others are categories, not links.
  private var source: some View {
    let source = PlanSource(candidateID: item.id, sourceRef: item.sourceRef)
    return Text(source.label)
      .font(Typo.caption)
      .foregroundStyle(source.isIssue ? Palette.ink2 : Palette.ink3)
      .underline(source.isIssue, pattern: .dot)
      .lineLimit(1)
      .fixedSize()
  }

  /// The circle: done, or back to open.
  private func set(_ requested: TodoState) {
    let target = requested == item.state && requested != .open ? .open : requested
    guard target != item.state else { return }
    Task {
      let (failure, note) = await send(target)
      if let failure {
        state.toast = failure
      } else if isPlanRow {
        let text = target == .done ? "已完成" : "已恢复"
        if let note { state.toast("\(text)；\(note)", undo: undo(from: target)) } else { state.toast = text }
      }
    }
  }

  /// Takes the row back to open — which also undoes what the schedule did.
  private func undo(from target: TodoState) -> (@MainActor () -> Void)? {
    guard target != .open else { return nil }
    let candidateID = item.id
    let rank = row.rank
    let store = state
    return {
      Task { @MainActor in _ = await store.planFeedback(candidateID: candidateID, rank: rank, event: "reopen", note: nil) }
    }
  }

  /// Puts the row in exactly `target`. Returns why it failed, and what the
  /// cycle schedule did in step, if anything.
  private func send(_ target: TodoState) async -> (failure: String?, note: String?) {
    guard isPlanRow else {
      state.setTodo(item.id, to: target)
      return (nil, nil)
    }
    let event = switch target {
    case .done: "complete"
    case .partial: "partial"
    case .deferred: "defer"
    default: "reopen"
    }
    switch await state.planFeedback(candidateID: item.id, rank: row.rank, event: event, note: nil) {
    case .ok(let note): return (nil, note)
    case .failed(let why), .unsupported(let why): return (why, nil)
    }
  }
}

// MARK: - Row editor

/// Everything you can do to a row, in one popover (after Calendar's event
/// popover): the text, its state, MIT, length, colour, an update, and the two
/// ways off the sheet's normal flow — back to automatic layout, or deleted.
///
/// Staged, not live: nothing is sent until 保存 (or clicking away, like
/// Calendar). Half the controls used to apply on click and half on save, and
/// a popover that does both cannot be cancelled.
private struct RowEditor: View {
  @Binding var text: String
  /// Nil = coloured by source.
  @Binding var color: String?
  @Binding var note: String
  @Binding var rowState: TodoState
  @Binding var isMIT: Bool
  @Binding var minutes: Int?
  let allowedStates: [TodoState]
  let canBeMIT: Bool
  /// The MIT shown is the user's own choice, not the plan's suggestion.
  let mitByUser: Bool
  let showsEstimate: Bool
  /// "13:00–13:30", or nil for a row with no slot.
  let timeRange: String?
  /// The colour the row has when none is chosen, for the 按来源 swatch.
  let autoColor: Color
  /// Set when the row is pinned to a time; releases it to automatic layout.
  let onUnpin: (() -> Void)?
  let onDelete: () -> Void
  let onCancel: () -> Void
  let onSave: () -> Void

  /// Matches the service's cap and the daily_plan prompt's rule.
  static let maxLength = 150
  private static let presets = [15, 30, 45, 60, 90, 120]

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.sm) {
      VStack(alignment: .trailing, spacing: 2) {
        TextField("这一条要做什么", text: $text, axis: .vertical)
          .textFieldStyle(.plain)
          .font(Typo.bodyStrong)
          .lineLimit(1...4)
          .onChange(of: text) { _, new in
            if new.count > Self.maxLength { text = String(new.prefix(Self.maxLength)) }
          }
        Text("\(text.count)/\(Self.maxLength)")
          .font(Typo.caption)
          .monospacedDigit()
          .foregroundStyle(text.count >= Self.maxLength ? Palette.warn : Palette.ink3)
      }
      .padding(Metrics.sm)
      .background(Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

      if timeRange != nil || onUnpin != nil {
        HStack(spacing: Metrics.xs) {
          if let timeRange {
            Text(timeRange).monospacedDigit()
          }
          if let onUnpin {
            Text("· 放在这个钟点")
            Spacer(minLength: 0)
            Button("回到自动排", action: onUnpin)
              .buttonStyle(QuietButtonStyle(tone: .neutral))
              .help("不再固定在这个钟点，跟着前面的条目和估时自动排")
          }
        }
        .font(Typo.caption)
        .foregroundStyle(Palette.ink3)
      }

      field("状态") {
        HStack(spacing: Metrics.xxs) {
          ForEach(allowedStates, id: \.self) { option in
            Button(Self.label(option)) { rowState = option }
              .buttonStyle(EstimateChipStyle(isCurrent: rowState == option))
              .accessibilityAddTraits(rowState == option ? [.isSelected] : [])
          }
        }
      }

      if canBeMIT {
        field("MIT") {
          Toggle(isOn: $isMIT) {
            Text(mitCaption).font(Typo.caption).foregroundStyle(Palette.ink3)
          }
          .toggleStyle(.switch)
          .controlSize(.mini)
        }
      }

      if showsEstimate {
        field("时长") {
          HStack(spacing: Metrics.xxs) {
            ForEach(Self.presets, id: \.self) { preset in
              Button(Fmt.minutes(preset)) { minutes = preset }
                .buttonStyle(EstimateChipStyle(isCurrent: minutes == preset))
            }
            if minutes != nil {
              Button("清除") { minutes = nil }
                .buttonStyle(QuietButtonStyle(tone: .neutral))
                .help("不知道要多久：回到没估时")
            }
          }
        }
      }

      field("颜色 · 只对今天") {
        HStack(spacing: Metrics.xs) {
          swatch(autoColor, selected: color == nil, label: "按来源") { color = nil }
          ForEach(Palette.rowColorNames, id: \.self) { name in
            swatch(Palette.rowColor(name) ?? Palette.ink3, selected: color == name, label: name) { color = name }
          }
        }
      }

      field("添加更新") {
        TextField("做到哪一步了、卡在哪（可留空）", text: $note, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(1...3)
      }

      HStack {
        Button(role: .destructive, action: onDelete) {
          Label("删除", systemImage: "trash")
        }
        .buttonStyle(QuietButtonStyle(tone: .neutral))
        .help("从今天的通告单上拿掉")
        Spacer()
        Button("取消", action: onCancel)
          .buttonStyle(QuietButtonStyle(tone: .neutral))
          .keyboardShortcut(.cancelAction)
        Button("保存", action: onSave)
          .buttonStyle(MossButtonStyle(prominent: true))
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(Metrics.md)
    .frame(width: 380)
  }

  /// Says whose MIT it is: a suggestion the user has not touched reads
  /// differently from one they chose, so taking it off does not feel like
  /// overruling themselves.
  private var mitCaption: String {
    if mitByUser { return isMIT ? "今天最重要的一件 · 你定的" : "不是今天的 MIT · 你定的" }
    return isMIT ? "今天最重要的一件 · 计划建议的" : "设为今天最重要的一件"
  }

  private static func label(_ state: TodoState) -> String {
    switch state {
    case .open, .deleted: "没做"
    case .done: "完成"
    case .partial: "做了一部分"
    case .deferred: "顺到明天"
    }
  }

  private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: Metrics.xxs) {
      Text(title).font(Typo.caption).foregroundStyle(Palette.ink3)
      content()
    }
  }

  private func swatch(_ fill: Color, selected: Bool, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Circle()
        .fill(fill)
        .frame(width: 18, height: 18)
        .overlay {
          Circle().strokeBorder(Palette.ink, lineWidth: selected ? 2 : 0).padding(-3)
        }
        .padding(3)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(label)
    .accessibilityLabel(label)
    .accessibilityAddTraits(selected ? [.isSelected] : [])
  }
}

// MARK: - Quick add

/// What an empty-time click opens: what to do — typed, or one of this
/// cycle's 要务 picked (backfilling the 双周排期) — and for how long. A 要务
/// added here counts as one of the cycle's sessions; the 作息 makes room for
/// today. 撤销 on the toast takes all of it back.
private struct QuickAdd: View {
  @Environment(AppState.self) private var state
  let start: Int
  let onClose: () -> Void

  @State private var title = ""
  @State private var itemKey: String?
  @State private var minutes = 60
  @State private var items: [CycleScheduleState.Item] = []
  @State private var isSaving = false
  @FocusState private var focused: Bool

  private static let lengths = [30, 60, 90, 120, 180]

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.sm) {
      Text("\(DaySchedule.clock(start)) 加一项").font(Typo.caption).foregroundStyle(Palette.ink3)
      TextField("做什么", text: $title)
        .textFieldStyle(.roundedBorder)
        .focused($focused)
        .onSubmit(save)
      if !items.isEmpty {
        VStack(alignment: .leading, spacing: Metrics.xxs) {
          Text("或者从本期要务里选").font(Typo.caption).foregroundStyle(Palette.ink3)
          FlowChips(items: items, selected: itemKey) { item in
            if itemKey == item.key { itemKey = nil } else {
              itemKey = item.key
              title = CycleSchedulePanel.clean(item.text)
            }
          }
        }
      }
      HStack(spacing: Metrics.xxs) {
        ForEach(Self.lengths, id: \.self) { length in
          Button(Fmt.minutes(length)) { minutes = length }
            .buttonStyle(QuietButtonStyle(tone: minutes == length ? .accent : .neutral))
        }
      }
      HStack {
        Spacer()
        Button("取消", action: onClose).buttonStyle(QuietButtonStyle(tone: .neutral)).keyboardShortcut(.cancelAction)
        Button(isSaving ? "加上…" : "加上", action: save)
          .buttonStyle(MossButtonStyle(prominent: true))
          .keyboardShortcut(.defaultAction)
          .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding(Metrics.md)
    .frame(width: 380)
    .onAppear { focused = true }
    .task {
      guard let cycle = state.currentCycle, case .success(let loaded) = await state.loadCycleSchedule(cycleID: cycle.id) else { return }
      items = loaded.items
    }
  }

  private func save() {
    let text = title.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty, !isSaving else { return }
    isSaving = true
    let end = min(24 * 60, start + minutes)
    let request = AdhocRequest(
      title: text, itemKey: itemKey, start: DaySchedule.clock(start), end: end == 24 * 60 ? "24:00" : DaySchedule.clock(end),
      extra: false, displaced: []
    )
    Task {
      let (outcome, undo) = await state.addAdhoc(request)
      isSaving = false
      switch outcome {
      case .ok(let summary):
        onClose()
        var takeBack: (@MainActor () -> Void)?
        if let undo {
          let store = state
          takeBack = { Task { @MainActor in store.toast = (await store.undoAdhoc(undo)).message } }
        }
        state.toast(summary ?? "加上了", undo: takeBack)
      case .failed(let why), .unsupported(let why):
        state.toast = why
      }
    }
  }
}

/// This cycle's 要务 as wrapping chips.
private struct FlowChips: View {
  let items: [CycleScheduleState.Item]
  let selected: String?
  let onPick: (CycleScheduleState.Item) -> Void

  var body: some View {
    ScrollView {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 4)], alignment: .leading, spacing: 4) {
        ForEach(items) { item in
          Button { onPick(item) } label: {
            Text(CycleSchedulePanel.clean(item.text)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(QuietButtonStyle(tone: selected == item.key ? .accent : .neutral))
          .help(item.text)
        }
      }
    }
    .frame(maxHeight: 150)
  }
}

private extension AppState.ActionOutcome {
  var message: String {
    switch self {
    case .ok(let text): text ?? "好了"
    case .failed(let why), .unsupported(let why): why
    }
  }
}

/// A fixed block on Today's timeline. One from the 作息 can be changed for
/// today only — moved, renamed or taken off today — and put back; the
/// template is not touched.
private struct RoutineFixedBlock: View {
  @Environment(AppState.self) private var state
  let block: DaySchedule.FixedBlock
  @State private var isEditing = false
  @State private var label = ""
  @State private var start = 0
  @State private var end = 0

  private static let clocks: [Int] = Array(stride(from: 5 * 60, through: 24 * 60, by: 15))

  var body: some View {
    FixedBlockView(block: block)
      .contentShape(Rectangle())
      .onTapGesture {
        guard block.routineBlockID != nil else { return }
        label = block.label
        start = block.start
        end = block.end
        isEditing = true
      }
      .help(block.routineBlockID == nil ? "" : "作息里的固定块 · 点一下只改今天")
      .popover(isPresented: $isEditing, arrowEdge: .trailing) {
        VStack(alignment: .leading, spacing: Metrics.sm) {
          Text("只改今天").font(Typo.heading)
          Text("作息模板不动，明天还是原样。").font(Typo.caption).foregroundStyle(Palette.ink3)
          TextField("叫什么", text: $label).textFieldStyle(.roundedBorder)
          HStack {
            Picker("从", selection: $start) { ForEach(Self.clocks, id: \.self) { Text(DaySchedule.clock($0)).tag($0) } }
            Picker("到", selection: $end) { ForEach(Self.clocks, id: \.self) { Text($0 == 24 * 60 ? "24:00" : DaySchedule.clock($0)).tag($0) } }
          }
          HStack {
            Button("今天不要这块") { apply("hide") }.buttonStyle(QuietButtonStyle(tone: .neutral))
            Button("恢复作息原样") { apply("reset") }.buttonStyle(QuietButtonStyle(tone: .neutral))
            Spacer()
            Button("保存") { apply("edit") }
              .buttonStyle(MossButtonStyle(prominent: true))
              .keyboardShortcut(.defaultAction)
              .disabled(end <= start || label.trimmingCharacters(in: .whitespaces).isEmpty)
          }
        }
        .padding(Metrics.md)
        .frame(width: 380)
      }
  }

  private func apply(_ action: String) {
    isEditing = false
    guard let id = block.routineBlockID else { return }
    Task {
      let outcome = await state.changeTodayRoutineBlock(blockID: id, action: action, label: label, start: start, end: end)
      switch outcome {
      case .ok(let text):
        var takeBack: (@MainActor () -> Void)?
        if action != "reset" {
          let store = state
          takeBack = {
            Task { @MainActor in _ = await store.changeTodayRoutineBlock(blockID: id, action: "reset") }
          }
        }
        state.toast(text ?? "只改了今天", undo: takeBack)
      case .failed(let why), .unsupported(let why):
        state.toast = why
      }
    }
  }
}

// MARK: - 作息 slots

/// One slot of today's 作息, drawn behind the rows: a faint wash of the
/// category's colour, a bar on the left, and its name in the corner. Dashed
/// when it is a floor.
private struct RoutineSlotBand: View {
  let slot: TodayRoutine.Slot

  var body: some View {
    let color = slot.color.flatMap(Palette.rowColor) ?? Palette.ink3
    ZStack(alignment: .topTrailing) {
      RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.opacity(0.07))
      // What the slot is for, by name — "英语口语", not "习惯" — then its
      // category and whether it is a floor.
      Text([slot.title, slot.category, slot.floor ? "保底" : nil].compactMap { $0 }.joined(separator: " · "))
        .font(Typo.caption)
        .foregroundStyle(color.opacity(0.9))
        .padding(.horizontal, Metrics.xs)
        .padding(.top, 2)
    }
    .overlay(alignment: .leading) { Rectangle().fill(color.opacity(0.6)).frame(width: 3) }
    .overlay {
      if slot.floor {
        RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(color.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
  }
}

// MARK: - Timeline

private enum Timeline {
  /// 96pt an hour, every hour.
  static let pointsPerMinute: CGFloat = 1.6
  /// The hour column.
  static let gutter: CGFloat = 52
  static let labelHeight: CGFloat = 14
  /// The coordinate space drags are measured in: the top of the timeline.
  static let space = "today.timeline"

  static func y(_ minute: Int, from origin: Int) -> CGFloat {
    CGFloat(minute - origin) * pointsPerMinute
  }
}

private extension View {
  /// Place a block on the clock: offset to its start, exactly as tall as its
  /// length (less a hairline gap), content clipped like a calendar's. Blocks
  /// that overlap split the lane into side-by-side columns.
  func timelineSlot(start: Int, end: Int, origin: Int, lane: CGFloat, placement: TimelineColumns.Placement?) -> some View {
    let count = CGFloat(placement?.count ?? 1)
    let column = CGFloat(placement?.column ?? 0)
    return frame(width: max(lane / count - (count > 1 ? 2 : 0), 24), height: max(Timeline.y(end, from: start) - 2, 12), alignment: .top)
      // Opaque under the tint, so the hour rules do not run through blocks.
      .background(Palette.page)
      .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
      .offset(x: Timeline.gutter + column * lane / count, y: Timeline.y(start, from: origin) + 1)
  }
}

/// A move or a resize in progress. `value` is the snapped start for a move and
/// the snapped length for a resize, in minutes.
private struct TimelineDrag: Equatable {
  enum Kind { case move, resize }
  let id: String
  let kind: Kind
  let value: Int

  /// Nearest multiple of `step`, kept inside the day.
  static func snap(_ minute: Int, step: Int) -> Int {
    let snapped = Int((Double(minute) / Double(step)).rounded()) * step
    return min(max(snapped, 0), 24 * 60 - step)
  }
}

/// The strip along a block's bottom edge that drags its length.
private struct ResizeHandle: View {
  let onChanged: (CGFloat) -> Void
  let onEnded: () -> Void
  @State private var isHovering = false

  var body: some View {
    Rectangle()
      .fill(Color.clear)
      .frame(height: 6)
      .frame(maxWidth: .infinity)
      .overlay(alignment: .center) {
        Capsule().fill(Palette.ink3.opacity(isHovering ? 0.5 : 0)).frame(width: 28, height: 3)
      }
      .contentShape(Rectangle())
      .onHover { inside in
        isHovering = inside
        if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
      }
      .gesture(
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Timeline.space))
          .onChanged { onChanged($0.translation.height) }
          .onEnded { _ in onEnded() }
      )
      .help("拖动改时长，15 分钟一档")
  }
}

/// The time a drag would land on, shown on the block while it moves.
private struct DragReadout: View {
  let drag: TimelineDrag

  var body: some View {
    Text(drag.kind == .move ? "放到 \(DaySchedule.clock(drag.value))" : DaySchedule.duration(drag.value))
      .font(Typo.caption.weight(.semibold))
      .monospacedDigit()
      .foregroundStyle(Palette.mint800)
      .padding(.horizontal, Metrics.xs)
      .padding(.vertical, 2)
      .background(Palette.mint200, in: Capsule())
      .padding(Metrics.xxs)
  }
}

/// Where a row dragged up from below the timeline would land.
private struct DropGhost: View {
  let text: String

  var body: some View {
    Text(text)
      .font(Typo.label)
      .foregroundStyle(Palette.mint800)
      .padding(.horizontal, Metrics.sm)
      .padding(.vertical, Metrics.xs)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      .background(Palette.mint100.opacity(0.7))
      .overlay {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(Palette.mint600, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
      }
      .allowsHitTesting(false)
  }
}

/// The hour labels and the dashed rule across the day at each one.
private struct HourGrid: View {
  let range: ClosedRange<Int>

  var body: some View {
    ForEach(Array(stride(from: range.lowerBound, through: range.upperBound, by: 60)), id: \.self) { minute in
      HStack(spacing: Metrics.xxs) {
        Text(DaySchedule.clock(minute))
          .font(Typo.caption)
          .monospacedDigit()
          .foregroundStyle(Palette.ink3)
          .frame(width: Timeline.gutter - Metrics.xxs, alignment: .leading)
        DashedRule().stroke(Palette.rule, style: StrokeStyle(lineWidth: Metrics.hairline, dash: [3, 3]))
          .frame(height: Metrics.hairline)
      }
      .frame(height: Timeline.labelHeight)
      .offset(y: Timeline.y(minute, from: range.lowerBound) - Timeline.labelHeight / 2)
    }
    .accessibilityHidden(true)
  }
}

private struct DashedRule: Shape {
  func path(in rect: CGRect) -> Path {
    Path { path in
      path.move(to: CGPoint(x: rect.minX, y: rect.midY))
      path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
    }
  }
}

/// "现在" on the clock: the time in the hour column, a line across the day.
private struct NowMarker: View {
  let minute: Int

  var body: some View {
    HStack(spacing: Metrics.xxs) {
      Text(DaySchedule.clock(minute))
        .font(Typo.caption.weight(.semibold))
        .monospacedDigit()
        .foregroundStyle(Palette.mint600)
        .frame(width: Timeline.gutter - Metrics.xxs, alignment: .leading)
        .background(Palette.page)
      Rectangle().fill(Palette.mint400).frame(height: 2)
    }
    .frame(height: Timeline.labelHeight)
    .allowsHitTesting(false)
    .accessibilityElement()
    .accessibilityLabel("现在 \(DaySchedule.clock(minute))")
  }
}

/// Block colours by where the block came from. A colour per source rather than
/// per life area: the source is what the data actually knows.
struct BlockTint {
  let fill: Color
  let ink: Color

  static let resolved = BlockTint(fill: Palette.paper.opacity(0.6), ink: Palette.ink3)
  static let routine = BlockTint(fill: Palette.paper, ink: Palette.ink2)
  static let meeting = BlockTint(fill: Palette.series(3).opacity(0.16), ink: Palette.series(3))
  static let priority = BlockTint(fill: Palette.mint100, ink: Palette.mint800)
  static let issue = BlockTint(fill: Palette.series(1).opacity(0.14), ink: Palette.series(1))
  static let capture = BlockTint(fill: Palette.series(2).opacity(0.14), ink: Palette.series(2))

  static func forTask(candidateID: String) -> BlockTint {
    switch candidateID.split(separator: ":", maxSplits: 1).first {
    case "linear": .issue
    case "weekly": .priority
    case "todo_inbox": .capture
    // Meal rows (`rhythm:`) and anything unknown.
    default: .routine
    }
  }

  /// A colour the user picked for the row today (LEO-334).
  static func named(_ name: String) -> BlockTint? {
    Palette.rowColor(name).map { BlockTint(fill: $0.opacity(0.16), ink: $0) }
  }

  static func forBlock(_ kind: DaySchedule.FixedBlock.Kind) -> BlockTint {
    kind == .meeting ? .meeting : .routine
  }
}

/// A meal, routine or fixed meeting: not checkable, not draggable.
private struct FixedBlockView: View {
  let block: DaySchedule.FixedBlock

  var body: some View {
    let tint = BlockTint.forBlock(block.kind)
    HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
      Text(DaySchedule.clock(block.start))
        .font(Typo.caption)
        .monospacedDigit()
        .foregroundStyle(tint.ink.opacity(0.8))
        .frame(width: 40, alignment: .leading)
      VStack(alignment: .leading, spacing: 2) {
        Text(block.label).font(Typo.label).foregroundStyle(tint.ink)
        if let note = block.note {
          Text(note).font(Typo.caption).foregroundStyle(tint.ink.opacity(0.85))
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Metrics.sm)
    .padding(.vertical, Metrics.xs)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(tint.fill)
    .accessibilityElement(children: .combine)
  }
}

// MARK: - Time by source

/// Where today's hours go, by the same sources the timeline colours by.
///
/// Tasks count their slot (done ones too — the hour was spent); deferred rows
/// and rows with no estimate have no slot and count nothing. Fixed blocks count
/// their whole length.
private struct DayTimePanel: View {
  let schedule: DaySchedule
  let blocks: [DaySchedule.FixedBlock]

  private struct Line: Identifiable {
    let id: String
    let minutes: Int
    let tint: BlockTint
  }

  private var lines: [Line] {
    var tasks: [String: Int] = [:]
    for row in schedule.rows {
      guard let minutes = row.minutes, row.start != nil else { continue }
      let key = row.item.id.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
      tasks[key, default: 0] += minutes
    }
    let meetings = blocks.filter { $0.kind == .meeting }.reduce(0) { $0 + $1.end - $1.start }
    let routines = blocks.filter { $0.kind != .meeting }.reduce(0) { $0 + $1.end - $1.start } + (tasks["rhythm"] ?? 0)
    return [
      Line(id: "要务", minutes: tasks["weekly"] ?? 0, tint: .priority),
      Line(id: "Linear", minutes: tasks["linear"] ?? 0, tint: .issue),
      Line(id: "随手记", minutes: tasks["todo_inbox"] ?? 0, tint: .capture),
      Line(id: "会议", minutes: meetings, tint: .meeting),
      Line(id: "作息", minutes: routines, tint: .routine),
    ].filter { $0.minutes > 0 }
  }

  var body: some View {
    let lines = self.lines
    if !lines.isEmpty {
      let longest = lines.map(\.minutes).max() ?? 1
      Panel("今天的时间") {
        VStack(alignment: .leading, spacing: Metrics.xs) {
          ForEach(lines) { line in
            HStack(spacing: Metrics.sm) {
              Text(line.id).font(Typo.label).foregroundStyle(Palette.ink2).frame(width: 52, alignment: .leading)
              GeometryReader { geo in
                Capsule().fill(Palette.rule.opacity(0.5))
                  .overlay(alignment: .leading) {
                    Capsule().fill(line.tint.ink)
                      .frame(width: geo.size.width * CGFloat(line.minutes) / CGFloat(longest))
                  }
              }
              .frame(height: 8)
              Text(DaySchedule.duration(line.minutes))
                .font(Typo.caption)
                .monospacedDigit()
                .foregroundStyle(Palette.ink3)
                .frame(width: 48, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
          }
        }
      }
    }
  }
}

// MARK: - Overdue banner

/// The rows whose slot has passed while they are still open.
///
/// One banner rather than a badge per row: the question it answers — "how far
/// behind am I" — is about the day, not about any single line, and three red
/// marks scattered down a list do not add up to an answer on their own.
/// 顺延太久的捕获，给一个一起放弃的出口。
///
/// Collapsed it is one line, because most days there is nothing to decide. Open
/// it lists each one with its age and a checkbox: dropping the pile wholesale is
/// usually wrong — one of them is the thing that actually matters — so the
/// default is nothing selected and 全选 is one click away.
///
/// 放弃 shelves rather than deletes. Said on the button's help text, because a
/// bulk action whose reach is unclear is one people avoid using.
private struct StaleCaptureBanner: View {
  let captures: [StaleCapture]
  let abandon: ([String]) -> Void

  @State private var isOpen = false
  @State private var picked: Set<String> = []

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xs) {
      HStack(alignment: .top, spacing: Metrics.sm) {
        Image(systemName: "calendar.badge.exclamationmark")
          .font(.system(size: 15))
          .foregroundStyle(Palette.ink3)
        VStack(alignment: .leading, spacing: 2) {
          // The smallest age, not the list's last element: "超过 N 天" has to be
          // true of every row, and reading it off the ordering would quietly
          // break if the service ever sorted them the other way.
          Text("\(captures.count) 项顺延超过 \(captures.map(\.days).min() ?? 0) 天")
            .font(Typo.label)
            .foregroundStyle(Palette.ink)
          Text("每天都在往后推，也在占时段。决定一下还做不做。")
            .font(Typo.caption)
            .foregroundStyle(Palette.ink2)
        }
        Spacer(minLength: Metrics.xs)
        Button(isOpen ? "收起" : "处理一下") {
          withAnimation(.snappy(duration: 0.2)) {
            isOpen.toggle()
            if !isOpen { picked = [] }
          }
        }
        .buttonStyle(QuietButtonStyle())
      }

      if isOpen {
        VStack(alignment: .leading, spacing: Metrics.xxs) {
          ForEach(captures) { capture in
            Toggle(isOn: binding(for: capture.id)) {
              HStack(spacing: Metrics.xs) {
                Text(capture.text).font(Typo.caption).foregroundStyle(Palette.ink)
                Text("\(capture.days) 天").font(Typo.caption).foregroundStyle(Palette.ink3)
              }
            }
            .toggleStyle(.checkbox)
          }
          HStack(spacing: Metrics.xs) {
            Button(picked.count == captures.count ? "全不选" : "全选") {
              picked = picked.count == captures.count ? [] : Set(captures.map(\.id))
            }
            .buttonStyle(QuietButtonStyle(tone: .neutral))
            Spacer(minLength: 0)
            Button("放弃选中的 \(picked.count) 项") {
              abandon(Array(picked))
              withAnimation(.snappy(duration: 0.2)) { isOpen = false }
              picked = []
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(picked.isEmpty)
            .help("不再顺延到明天。会移到「已顺延」，随时能恢复——不是删除。")
          }
          .padding(.top, 2)
        }
        .padding(.leading, 24)
        .transition(.opacity)
      }
    }
    .padding(Metrics.sm)
    .background(Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: Metrics.radiusPaper, style: .continuous))
  }

  private func binding(for id: String) -> Binding<Bool> {
    Binding(
      get: { picked.contains(id) },
      set: { isOn in if isOn { picked.insert(id) } else { picked.remove(id) } }
    )
  }
}

private struct OverdueBanner: View {
  let rows: [DaySchedule.Row]
  let pushAll: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: Metrics.sm) {
      Image(systemName: "clock.badge.exclamationmark")
        .font(.system(size: 15))
        .foregroundStyle(Palette.mint600)
      VStack(alignment: .leading, spacing: 2) {
        Text("\(rows.count) 项过了时段还没更新").font(Typo.label).foregroundStyle(Palette.ink)
        Text(rows.map { "「\(summary($0.item.text))」" }.joined(separator: " "))
          .font(Typo.caption)
          .foregroundStyle(Palette.ink2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: Metrics.xs)
      Button("全部顺到现在", action: pushAll)
        .buttonStyle(QuietButtonStyle())
        .help("把这几项移到队尾，后面的时段跟着重算。状态不变——它们还是未做。")
    }
    .padding(Metrics.sm)
    .background(Palette.mint50, in: RoundedRectangle(cornerRadius: Metrics.radiusPaper, style: .continuous))
  }

  private func summary(_ text: String) -> String {
    text.count <= 14 ? text : String(text.prefix(14)) + "…"
  }
}

// MARK: - Footer

private struct SheetFooter: View {
  let schedule: DaySchedule

  var body: some View {
    HStack(spacing: Metrics.sm) {
      Text(counts).font(Typo.caption).foregroundStyle(Palette.ink2)
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          Capsule().fill(Palette.rule)
          Capsule()
            .fill(Palette.mint400)
            .frame(width: geo.size.width * fraction)
        }
      }
      .frame(height: 2)
      Text(tail).font(Typo.caption).foregroundStyle(Palette.ink2).monospacedDigit()
    }
  }

  private var fraction: Double {
    schedule.total == 0 ? 0 : Double(schedule.doneCount) / Double(schedule.total)
  }

  private var counts: String {
    var parts = ["\(schedule.doneCount)/\(schedule.total) 完成"]
    if schedule.partialCount > 0 { parts.append("\(schedule.partialCount) 部分") }
    if schedule.deferredCount > 0 { parts.append("\(schedule.deferredCount) 延期") }
    return parts.joined(separator: " · ")
  }

  /// The projected finish, and an honest note when it is built on partial data.
  private var tail: String {
    let base = "还需 \(DaySchedule.duration(schedule.remaining)) · 预计 \(DaySchedule.clock(schedule.endOfDay)) 结束"
    guard schedule.missingEstimates > 0 else { return base }
    return base + " · \(schedule.missingEstimates) 项没估时，没算进去"
  }
}

// MARK: - Cleared

private struct ClearState: View {
  let schedule: DaySchedule

  var body: some View {
    HStack(spacing: Metrics.md) {
      Image(systemName: "checkmark.seal")
        .font(.system(size: 34))
        .foregroundStyle(Palette.mint400)
      VStack(alignment: .leading, spacing: Metrics.xxs) {
        Text("今天清完了").font(Typo.hand).foregroundStyle(Palette.mint600)
        Text(detail).font(Typo.caption).foregroundStyle(Palette.ink2)
      }
      Spacer()
    }
    .padding(.vertical, Metrics.md)
  }

  private var detail: String {
    var parts = ["\(schedule.total) 项", "\(schedule.doneCount) 完成"]
    if schedule.deferredCount > 0 { parts.append("\(schedule.deferredCount) 延期") }
    return parts.joined(separator: " · ") + "。写一句复盘，明早的计划会读它。"
  }
}

// MARK: - Execution

/// Three questions, side by side: how today is going, how this cycle is going,
/// and whether cycles usually go this way.
///
/// Collapsed by default. It answers "am I behind", which is a question you ask a
/// few times a day, not one you need answered while reading the sheet — and a
/// permanently open stats block above the work is how the old dashboard ended up
/// competing with the thing it was describing.
private struct ExecutionPanel: View {
  @Environment(AppState.self) private var state
  let schedule: DaySchedule

  var body: some View {
    Panel("执行情况") {
      // Three columns, not two-with-a-stack. The first version put 今天 on the
      // left and the other two stacked on the right, which left the left column
      // half empty — three equal questions should not be laid out as one plus a
      // pile.
      HStack(alignment: .top, spacing: Metrics.lg) {
        today.frame(maxWidth: .infinity, alignment: .leading)
        cycle.frame(maxWidth: .infinity, alignment: .leading)
        history.frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  // MARK: 今天

  private var today: some View {
    VStack(alignment: .leading, spacing: Metrics.xs) {
      header("今天", "\(schedule.total) 项 · \(DaySchedule.duration(plannedMinutes))")
      StackedBar(segments: [
        .init(fraction: share(schedule.doneCount), color: Palette.mint400),
        .init(fraction: share(schedule.partialCount), color: Palette.mint200),
        .init(fraction: share(schedule.deferredCount), color: Palette.rule),
      ])
      Grid(alignment: .leading, horizontalSpacing: Metrics.sm, verticalSpacing: 2) {
        stat("完成", schedule.doneCount)
        stat("部分", schedule.partialCount)
        stat("未做", schedule.openCount)
        stat("延期", schedule.deferredCount)
        stat("过了时段没更新", schedule.lateRows.count)
      }
    }
  }

  private var plannedMinutes: Int {
    schedule.rows.compactMap { $0.item.estimatedMinutes }.reduce(0, +)
  }

  private func share(_ count: Int) -> Double {
    schedule.total == 0 ? 0 : Double(count) / Double(schedule.total)
  }

  // MARK: 本周期

  @ViewBuilder private var cycle: some View {
    if let cycle = state.currentCycle {
      let doc = cycle.section(.priorities)?.priorities
      VStack(alignment: .leading, spacing: Metrics.xs) {
        header("本周期", Fmt.cycleTitle(cycle))
        StackedBar(segments: [
          .init(fraction: rate(doc) ?? 0, color: Palette.mint400)
        ])
        Grid(alignment: .leading, horizontalSpacing: Metrics.sm, verticalSpacing: 2) {
          GridRow {
            Text("要务完成").font(Typo.caption).foregroundStyle(Palette.ink3)
            Text(doc.map { "\($0.doneCount) / \($0.trackedCount)" } ?? "—")
              .font(Typo.tabularCaption).foregroundStyle(Palette.ink)
          }
          GridRow {
            Text("MIT").font(Typo.caption).foregroundStyle(Palette.ink3)
            Text(mitLabel(doc)).font(Typo.caption).foregroundStyle(Palette.ink)
          }
          GridRow {
            Text("更新于").font(Typo.caption).foregroundStyle(Palette.ink3)
            Text(Fmt.stamp(cycle.updatedAt)).font(Typo.caption).foregroundStyle(Palette.ink)
          }
        }
      }
    } else {
      VStack(alignment: .leading, spacing: Metrics.xxs) {
        header("本周期", "—")
        Text("今天不在任何一个周期里。").font(Typo.caption).foregroundStyle(Palette.ink3)
      }
    }
  }

  private func mitLabel(_ doc: PrioritiesDocument?) -> String {
    guard let mits = doc?.allItems.filter(\.isMIT), !mits.isEmpty else { return "没标" }
    let done = mits.filter { $0.status == .done }.count
    return "\(mits.count) 项 · \(done == mits.count ? "已完成" : "未完成")"
  }

  // MARK: 近四期

  /// Derived from the cycle files already loaded, not from an endpoint.
  ///
  /// There is no completion-rate API — but `PrioritiesDocument` already parses
  /// the 要务 section into counted items for the Cycles screen, so the number is
  /// a filter and a division away. Cycles with nothing tracked are skipped
  /// rather than drawn as 0%: an empty cycle is not a failed one.
  @ViewBuilder private var history: some View {
    let recent = recentRates
    VStack(alignment: .leading, spacing: Metrics.xs) {
      header("近四期要务完成率", recent.isEmpty ? "还没有数据" : "")
      if !recent.isEmpty {
        HStack(alignment: .bottom, spacing: Metrics.xs) {
          ForEach(Array(recent.enumerated()), id: \.offset) { index, entry in
            VStack(spacing: Metrics.xxs) {
              Text("\(Int((entry.rate * 100).rounded()))%")
                .font(Typo.caption).foregroundStyle(Palette.ink3).monospacedDigit()
              RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(index == recent.count - 1 ? Palette.mint400 : Palette.mint100)
                .frame(width: 28, height: max(3, 56 * entry.rate))
              Text(entry.label).font(Typo.caption).foregroundStyle(Palette.ink3)
            }
          }
          Spacer()
        }
        .frame(height: 96, alignment: .bottom)
      }
    }
  }

  private struct Rate { let label: String; let rate: Double }

  private var recentRates: [Rate] {
    let tracked = Array(
      state.cycles
        .filter { ($0.section(.priorities)?.priorities.trackedCount ?? 0) > 0 }
        .sorted { $0.start < $1.start }
        .suffix(4)
    )
    // Labels are counted *from the current cycle*, not from the end of the list.
    // Counting back from the end assumed the current cycle is the newest one
    // with tracked 要务 — it often is not, and the first render proved it: the
    // bars came out `−3 −2 本期 −0`, with the marker in the wrong column and a
    // `−0` that means nothing.
    let anchor = tracked.firstIndex { $0.id == state.currentCycle?.id } ?? tracked.count - 1
    return tracked.enumerated().map { index, cycle in
      let offset = index - anchor
      let label = offset == 0 ? "本期" : (offset < 0 ? "−\(-offset)" : "+\(offset)")
      return Rate(label: label, rate: self.rate(cycle.section(.priorities)?.priorities) ?? 0)
    }
  }

  private func rate(_ doc: PrioritiesDocument?) -> Double? {
    guard let doc, doc.trackedCount > 0 else { return nil }
    return Double(doc.doneCount) / Double(doc.trackedCount)
  }

  // MARK: bits

  private func header(_ title: String, _ trailing: String) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(title).font(Typo.heading).foregroundStyle(Palette.ink)
      Spacer()
      Text(trailing).font(Typo.caption).foregroundStyle(Palette.ink3)
    }
  }

  private func stat(_ label: String, _ value: Int) -> some View {
    GridRow {
      Text(label).font(Typo.caption).foregroundStyle(Palette.ink3)
      Text("\(value)").font(Typo.tabularCaption).foregroundStyle(Palette.ink)
    }
  }
}

/// A single bar split into tinted runs.
private struct StackedBar: View {
  struct Segment { let fraction: Double; let color: Color }
  let segments: [Segment]

  var body: some View {
    GeometryReader { geo in
      HStack(spacing: 0) {
        ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
          Rectangle()
            .fill(segment.color)
            .frame(width: max(0, geo.size.width * segment.fraction))
        }
        Spacer(minLength: 0)
      }
    }
    .frame(height: 6)
    .background(Palette.rule)
    .clipShape(Capsule())
  }
}
// MARK: - Team today

/// What the rest of the team is doing today.
///
/// Read-only on purpose, and visibly so: no check circles, no actions, no
/// selection. These rows are someone else's ticks, pulled from the service's
/// sync cache a minute at a time, and a row that looked tickable here would
/// invite an action the service refuses anyway.
///
/// Rendered whenever team sync is configured, even with nobody else in the
/// team — a panel that disappears when there is nothing to show makes "sync is
/// off" and "sync is on and quiet" look identical, which is the confusion the
/// Cycles screen already had to fix once.
private struct TeamTodayPanel: View {
  @Environment(AppState.self) private var state
  @State private var isSyncing = false

  var body: some View {
    // Not configured at all is the one case worth hiding: most installs never
    // set Supabase up, and a permanent "团队同步未启用" on the morning screen is
    // a nag about a feature they did not ask for.
    if let sync = state.teamTodaySync, sync.status != "disabled" {
      Panel("团队今天", subtitle: subtitle(for: sync), badge: "只读", badgeTone: .neutral) {
        VStack(alignment: .leading, spacing: Metrics.sm) {
          if let error = nonEmpty(sync.lastError) {
            Text(error).mutedStyle()
          }
          if sync.status != "ready" {
            Text(sync.reason.isEmpty ? "团队同步还没就绪。" : sync.reason).mutedStyle()
          } else if state.teamToday.isEmpty {
            Text("团队里还没有其他成员。").mutedStyle()
          } else {
            ForEach(state.teamToday) { entry in
              TeamTodayMember(entry: entry)
            }
          }
        }
      } actions: {
        // No longer the only way to see a teammate's plan — the app re-reads
        // when it comes to the front and once a minute after that. What is left
        // is the thing waiting cannot do: this runs a sync *tick*, so it beats
        // the service's own 60 s loop rather than the app's re-read of what
        // that loop already wrote. For the moment you know she just pushed.
        Button(isSyncing ? "更新中…" : "更新", action: syncNow)
          .buttonStyle(QuietButtonStyle())
          .disabled(isSyncing)
          .help("现在拉一次队友的计划和周期，然后刷新这一页。")
      }
    }
  }

  private func syncNow() {
    guard !isSyncing else { return }
    isSyncing = true
    Task {
      let outcome = await state.syncTeamNow()
      isSyncing = false
      switch outcome {
      case .ok(let message): state.toast = message
      case .failed(let why), .unsupported(let why): state.toast = why
      }
    }
  }

  private func subtitle(for sync: TeamSyncState) -> String {
    guard let syncedAt = sync.syncedAt else { return "队友各自机器上的今日计划" }
    return "队友各自机器上的今日计划 · 最近同步 \(Fmt.stamp(syncedAt))"
  }

  private func nonEmpty(_ text: String) -> String? {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
  }
}

private struct TeamTodayMember: View {
  let entry: TeamTodayEntry

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xs) {
      HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
        Text(entry.displayName).inkStyle(Typo.heading)
        if let stale = entry.staleDate {
          // Same distinction the plan panel draws for your own list: a plan
          // from an earlier day looks exactly like today's, and the only way
          // to tell is to be told.
          Pill("还是 \(stale) 的", tone: .warn)
        } else if let updatedAt = entry.updatedAt {
          Text("TA 的机器 \(Fmt.stamp(updatedAt)) 推送").mutedStyle()
        }
      }
      if !entry.hasPlan {
        Text("还没有收到 TA 的今日计划。").mutedStyle()
      } else if entry.items.isEmpty {
        Text("这份计划没有待办条目。").mutedStyle()
      } else {
        VStack(spacing: 2) {
          ForEach(Array(entry.items.enumerated()), id: \.element.id) { index, item in
            TeamTodayRow(item: item, rank: index + 1)
          }
        }
      }
    }
  }
}

/// A call-sheet row with the tick and the actions taken away.
///
/// Not `CallSheetRow` with the circle hidden: that still hovers, still selects,
/// still offers four states, and every one of those is a promise this row cannot
/// keep — the service refuses writes to someone else's plan.
///
/// It follows the sheet's own conventions so the two read as one product: MIT in
/// `q1` where the sheet puts it, strikethrough on a resolved row, the estimate on
/// the right. The importance stripe is gone along with the three-tier ring — only
/// the MIT is coloured now, here as well as in your own sheet.
private struct TeamTodayRow: View {
  let item: TodoItem
  let rank: Int

  private var isMIT: Bool { PlanImportance.forRank(rank) == .mit }
  private var isResolved: Bool { item.state == .done || item.state == .deferred }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
      if isMIT {
        Text("MIT")
          .font(Typo.caption).bold().kerning(0.96)
          .foregroundStyle(Palette.q1)
          .opacity(isResolved ? 0.4 : 1)
          .frame(width: 30, alignment: .leading)
      } else {
        Color.clear.frame(width: 30, height: 1)
      }
      Text(item.text)
        .font(Typo.body)
        .strikethrough(isResolved, color: Palette.ink3)
        .foregroundStyle(isResolved ? Palette.ink3 : Palette.ink)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: Metrics.xs)
      if item.state == .done {
        Pill("已完成", tone: .accent)
      } else if item.state == .partial {
        Pill("部分", tone: .accent)
      } else if item.state == .deferred {
        Pill("已延期", tone: .neutral)
      }
      if let minutes = item.estimatedMinutes {
        Text(DaySchedule.duration(minutes)).font(Typo.caption).foregroundStyle(Palette.ink3)
      }
    }
    .padding(.vertical, Metrics.xxs)
  }
}


// MARK: - Capture

private struct QuickCapturePanel: View {
  @Environment(AppState.self) private var state
  @FocusState private var focused: Bool

  var body: some View {
    @Bindable var state = state
    Panel {
      HStack(spacing: Metrics.xs) {
        Image(systemName: "square.and.pencil").foregroundStyle(Palette.inkMuted)
        TextField("记一条，直接进今天的通告单…", text: $state.quickCaptureText)
          .textFieldStyle(.plain)
          .font(Typo.body)
          .focused($focused)
          .onSubmit { state.capture(state.quickCaptureText) }
        Button("记下") { state.capture(state.quickCaptureText) }
          .buttonStyle(MossButtonStyle())
          .disabled(state.quickCaptureText.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
  }
}


/// What the panel says between pressing 生成计划 and the plan existing.
///
/// Which is a real gap — a couple of minutes — and the only dishonest thing this
/// could do is imply it is shorter, or that the plan is already being written
/// into the rows below. It says where the result will appear and what else the
/// run does on the way.

private struct StartedNote: View {
  let at: Date

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xxs) {
      Label("\(Fmt.time(at)) 已让 daily_plan 跑起来", systemImage: "clock.arrow.circlepath")
        .font(Typo.caption)
        .foregroundStyle(Palette.moss)
      Text("它在后台跑，通常要一两分钟。这里不会有进度，计划写好之后会自己出现；飞书同时也会收到一条。")
        .mutedStyle()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}


/// Change one row's estimate.
///
/// Presets rather than a free number field, because the useful granularity is
/// coarse — the question the bar answers is "does today fit", and 15 versus 20
/// minutes has never changed that answer. The prompt asks the model for the
/// same steps, so a corrected number looks like the numbers around it.
///
/// 清除 is not a courtesy. Without it a mis-click turns an honest "no estimate"
/// into a wrong one that can never be taken back, and the total silently starts
/// lying.
private struct EstimateEditor: View {
  @Environment(AppState.self) private var state
  let item: TodoItem
  let rank: Int
  let onDone: () -> Void

  private static let presets = [15, 30, 45, 60, 90, 120]

  var body: some View {
    HStack(spacing: Metrics.xxs) {
      Text("估时").mutedStyle(Typo.label)
      ForEach(Self.presets, id: \.self) { minutes in
        Button(Fmt.minutes(minutes)) { apply(minutes) }
          .buttonStyle(EstimateChipStyle(isCurrent: item.estimatedMinutes == minutes))
      }
      Spacer(minLength: 0)
      if item.estimatedMinutes != nil {
        Button("清除") { apply(nil) }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
      }
      Button("收起", action: onDone)
        .buttonStyle(QuietButtonStyle(tone: .neutral))
    }
    .padding(.horizontal, Metrics.xs)
  }

  private func apply(_ minutes: Int?) {
    onDone()
    Task {
      let outcome = await state.setPlanEstimate(candidateID: item.id, rank: rank, minutes: minutes)
      switch outcome {
      case .ok(let message): state.toast = message ?? "已更新估时"
      case .failed(let why), .unsupported(let why): state.toast = why
      }
    }
  }
}

/// Pick how long a capture will take, on the way onto the call sheet.
///
/// The estimate is not optional here the way it is on a plan row: the sheet
/// projects every later slot forward through the estimates, so a row arriving
/// without one would push 预计结束 off from that point down. Same presets and
/// same chips as `EstimateEditor`, so the two read as one control.
private struct PlanEstimatePicker: View {
  let onPick: (Int) -> Void
  let onCancel: () -> Void

  private static let presets = [15, 30, 45, 60, 90, 120]

  var body: some View {
    HStack(spacing: Metrics.xxs) {
      Text("要花多久").mutedStyle(Typo.label)
      ForEach(Self.presets, id: \.self) { minutes in
        Button(Fmt.minutes(minutes)) { onPick(minutes) }
          .buttonStyle(EstimateChipStyle(isCurrent: false))
      }
      Spacer(minLength: 0)
      Button("取消", action: onCancel)
        .buttonStyle(QuietButtonStyle(tone: .neutral))
    }
    .padding(.horizontal, Metrics.xs)
  }
}

/// Small enough that six of them fit next to a label in half a window.
/// `MossButtonStyle` is the right look and the wrong size here — its 28pt hit
/// target and 12pt padding turn a row of presets into a toolbar.
private struct EstimateChipStyle: ButtonStyle {
  let isCurrent: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(Typo.tabularCaption.weight(isCurrent ? .semibold : .regular))
      // mint800 on mint200, not white on moss: white on the light accent fill
      // fails contrast — the same fix the prominent button got in the token pass.
      .foregroundStyle(isCurrent ? Palette.mint800 : Palette.ink)
      .padding(.horizontal, Metrics.xs)
      .frame(height: 22)
      .background {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(isCurrent ? Palette.mint200 : Palette.surfaceSunken)
      }
      .opacity(configuration.isPressed ? 0.7 : 1)
      .contentShape(Rectangle())
  }
}

/// A one-line inline form. Escape cancels, Return confirms.
private struct InlineField: View {
  let placeholder: String
  @Binding var text: String
  let confirm: String
  let onConfirm: () -> Void
  let onCancel: () -> Void

  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: Metrics.xs) {
      TextField(placeholder, text: $text)
        .textFieldStyle(.plain)
        .font(Typo.caption)
        .padding(Metrics.xxs)
        .background(Palette.surfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
        .focused($focused)
        .onSubmit(onConfirm)
        .onExitCommand(perform: onCancel)
      Button(confirm, action: onConfirm).buttonStyle(QuietButtonStyle())
      Button("取消", action: onCancel).buttonStyle(QuietButtonStyle(tone: .neutral))
    }
    .padding(.horizontal, Metrics.xs)
    // Opening a field and then having to click it is the kind of small tax that
    // stops people from using the feature at all.
    .onAppear { focused = true }
  }
}


// MARK: - My todos (rail)

/// The inbox, back as its own list.
///
/// Restored from before the call sheet swallowed it: captures are a scratchpad,
/// not scheduled work, and they want their own home with the full set of verbs
/// (改 / 顺延 / 删 / 恢复) rather than a state circle at the tail of the clock.
/// Lives in the Today rail next to 团队今天.
private struct TodoPanel: View {
  @Environment(AppState.self) private var state
  @Binding var selectedID: TodoItem.ID?
  @State private var showsHistory = false

  /// Captures that are open but *not* on today's sheet.
  ///
  /// Normally empty: a capture goes onto the sheet as it is written, and the
  /// morning run puts back any the model left out. It fills for one case —
  /// something captured before today's plan exists, which has nothing to be
  /// appended to yet. Those would otherwise be visible nowhere at all, so they
  /// are surfaced here until the plan catches up.
  private var notOnSheet: [TodoItem] {
    let onSheet = Set(state.plan.map(\.id))
    return state.openTodos.filter { !onSheet.contains("todo_inbox:\($0.id)") }
  }

  private var archived: [TodoItem] { state.doneTodos + state.deferredTodos }

  var body: some View {
    Panel("记过的", subtitle: "已完成和已顺延的都在这儿，随时能恢复") {
      VStack(spacing: 2) {
        if !notOnSheet.isEmpty {
          Text("还没进今天的通告单")
            .font(Typo.caption)
            .foregroundStyle(Palette.mint600)
            .frame(maxWidth: .infinity, alignment: .leading)
          ForEach(notOnSheet) { item in
            TodoRow(item: item, selectedID: $selectedID)
              .transition(.taskRow)
          }
          if !archived.isEmpty { PanelDivider() }
        }

        if archived.isEmpty {
          if notOnSheet.isEmpty {
            Text("还没有记过的事。")
              .mutedStyle(Typo.caption)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        } else {
          // One line until asked for. Capturing and doing both happen on the
          // call sheet now; this is the place you come back to, not the place
          // you work from, so it should not hold a column open all day.
          DisclosureGroup(isExpanded: $showsHistory) {
            VStack(spacing: 2) {
              ForEach(archived) { TodoRow(item: $0, selectedID: $selectedID) }
            }
          } label: {
            Text("已完成 / 已顺延 · \(archived.count)").mutedStyle()
          }
          .tint(Palette.inkMuted)
        }
      }
    }
  }
}

/// One inbox row.
///
/// The web gives an open row Done / Defer / Delete, and a history row Restore /
/// Delete. All four are here; all four are `setTodo(_:to:)`, including delete —
/// the service's `TodoInboxStatus` has a `deleted` tombstone and `/api/state`
/// filters those rows out, so sending the status *is* the deletion.
///
/// 完成 stays on the check circle rather than becoming a fourth icon. It is the
/// affordance people already reach for in a todo list, and duplicating it in the
/// cluster would put the same action on the row twice.
private struct TodoRow: View {
  @Environment(AppState.self) private var state
  let item: TodoItem
  @Binding var selectedID: TodoItem.ID?

  @State private var isRenaming = false
  @State private var draft = ""
  @State private var isPlanning = false

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xxs) {
      TaskRow(
        item: item,
        actions: actions,
        onToggleCheck: item.state == .deferred ? nil : { state.toggleTodo(item.id) },
        selectedID: $selectedID
      ) {
        if item.state == .deferred { Pill("已顺延", tone: .warn) }
      }

      if isRenaming {
        InlineField(
          placeholder: "改成…",
          text: $draft,
          confirm: "保存",
          onConfirm: {
            state.renameTodo(item.id, to: draft)
            withAnimation(.snappy(duration: 0.2)) { isRenaming = false }
          },
          onCancel: { withAnimation(.snappy(duration: 0.2)) { isRenaming = false } }
        )
        .transition(.taskRow)
      }

      if isPlanning {
        PlanEstimatePicker(
          onPick: addToPlan,
          onCancel: { withAnimation(.snappy(duration: 0.2)) { isPlanning = false } }
        )
        .transition(.taskRow)
      }
    }
  }

  private var actions: [TaskAction] {
    var actions: [TaskAction] = []
    switch item.state {
    case .open:
      actions.append(
        TaskAction(id: "plan", label: "今天做", symbol: "calendar.badge.plus", key: "t") {
          withAnimation(.snappy(duration: 0.2)) {
            isPlanning.toggle()
            if isPlanning { isRenaming = false }
          }
        }
      )
      actions.append(
        TaskAction(id: "rename", label: "修改", symbol: "square.and.pencil", key: "e") {
          draft = item.text
          isRenaming.toggle()
        }
      )
      actions.append(
        TaskAction(id: "defer", label: "顺延", symbol: "clock.arrow.circlepath", tone: .warn, key: "d") {
          state.setTodo(item.id, to: .deferred)
        }
      )
    case .deferred:
      actions.append(
        TaskAction(id: "restore", label: "恢复", symbol: "arrow.uturn.backward", key: "r") {
          state.setTodo(item.id, to: .open)
        }
      )
    case .done, .deleted, .partial:
      break
    }
    actions.append(
      TaskAction(id: "delete", label: "删除", symbol: "trash", tone: .danger, key: .delete, role: .destructive) {
        state.setTodo(item.id, to: .deleted)
      }
    )
    return actions
  }

  private func addToPlan(_ minutes: Int) {
    withAnimation(.snappy(duration: 0.2)) { isPlanning = false }
    Task {
      let outcome = await state.addCaptureToPlan(item.id, minutes: minutes)
      switch outcome {
      case .ok(let message): state.toast = message ?? "已加到今天的计划"
      case .failed(let why), .unsupported(let why): state.toast = why
      }
    }
  }
}

// MARK: - Previews

#Preview("今天") {
  TodayScreen()
    .environment(AppState.previewOwner())
    .frame(width: 940, height: 720)
}

#Preview("今天 · 空状态") {
  TodayScreen()
    .environment(AppState.previewEmpty())
    .frame(width: 940, height: 720)
}
