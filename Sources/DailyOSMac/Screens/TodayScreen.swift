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
          if !schedule.lateRows.isEmpty {
            OverdueBanner(rows: schedule.lateRows, pushAll: pushLateToNow)
          }
          if !state.staleCaptures.isEmpty {
            StaleCaptureBanner(captures: state.staleCaptures, abandon: abandon)
          }
          sheet
          SheetFooter(schedule: schedule)
        }
      }
    } actions: {
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
          ForEach(blocks) { block in
            FixedBlockView(block: block)
              .timelineSlot(start: block.start, end: block.end, origin: origin, lane: lane, placement: columns["block:\(block.id)"])
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
    return "拖到任意钟点（吸附到半点），拖下边缘改时长 · 没拖过的从 \(DaySchedule.clock(start)) 起按估时自动排"
  }

  /// Whole hours from the first thing on the day to the last, so the earliest
  /// routine and the projected end both fit.
  private var timelineRange: ClosedRange<Int> {
    let starts = state.planMealBlocks.map(\.start) + schedule.rows.compactMap(\.start)
    let ends = state.planMealBlocks.map(\.end) + schedule.rows.compactMap(\.end)
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

/// 时段 | 圆圈 | 任务 | 来源
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

  @State private var isHovering = false
  // Restored after the call-sheet rewrite dropped them (74ef388): the old
  // PlanRow let you change a row's estimate and leave it an update note, and
  // the call sheet is *more* dependent on the estimate than the list was —
  // every slot below a row is pushed by it.
  @State private var isEditingEstimate = false
  @State private var isNoting = false
  @State private var note = ""
  @State private var isConfirmingDelete = false

  private var item: TodoItem { row.item }
  private var isEditable: Bool { item.state == .open || item.state == .partial }
  private var isResolved: Bool { item.state == .done || item.state == .deferred }
  private var isMIT: Bool { isPlanRow && PlanImportance.forRank(row.rank) == .mit }

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
    isResolved ? .resolved : BlockTint.forTask(candidateID: item.id)
  }

  var body: some View {
    mainLine
    .padding(.horizontal, Metrics.sm)
    .padding(.vertical, Metrics.xs)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(tint.fill)
    // Popovers, not inline editors: on the timeline a block is exactly as tall
    // as its slot, and an editor growing inside it would be clipped away.
    .popover(isPresented: noteBinding, arrowEdge: .bottom) {
      InlineField(
        placeholder: "记一条更新（可留空）",
        text: $note,
        confirm: "记下",
        onConfirm: sendNote,
        onCancel: closeEditors
      )
      .padding(Metrics.sm)
      .frame(width: 320)
    }
    .popover(isPresented: estimateBinding, arrowEdge: .bottom) {
      EstimateEditor(item: item, rank: row.rank) {
        withAnimation(.snappy(duration: 0.2)) { isEditingEstimate = false }
      }
      .padding(Metrics.sm)
      .frame(width: 420)
      .environment(state)
    }
    .contentShape(Rectangle())
    .onHover { isHovering = $0 }
    .onTapGesture { selectedID = item.id }
    .confirmationDialog("删除这一条？", isPresented: $isConfirmingDelete) {
      Button("删除", role: .destructive, action: remove)
      Button("取消", role: .cancel) {}
    } message: {
      Text(deleteMessage)
    }
  }

  private var noteBinding: Binding<Bool> {
    Binding(get: { isNoting && isEditable }, set: { if !$0 { closeEditors() } })
  }

  private var estimateBinding: Binding<Bool> {
    Binding(get: { isEditingEstimate && isEditable }, set: { if !$0 { closeEditors() } })
  }

  private var mainLine: some View {
    HStack(alignment: .top, spacing: Metrics.sm) {
      slot
      StateCircle(state: item.state) {
        set(item.state == .done ? .open : .done)
      }

      VStack(alignment: .leading, spacing: 2) {
        Text(item.text)
          .font(Typo.body.weight(.medium))
          .foregroundStyle(tint.ink)
          .strikethrough(isResolved, color: Palette.ink3)
          .lineLimit(compact ? 2 : nil)
          .fixedSize(horizontal: false, vertical: !compact)
        HStack(spacing: Metrics.xs) {
          estimateLabel
          if isMIT {
            Text("MIT")
              .font(Typo.caption)
              .bold()
              .kerning(0.96)
              .foregroundStyle(Palette.q1)
              .opacity(isResolved ? 0.4 : 1)
          }
        }
        if row.isLate {
          Text("已过时段 · 还没更新").font(Typo.caption).foregroundStyle(Palette.mint600)
        }
        if item.state == .deferred {
          Text("顺到明天").font(Typo.caption).foregroundStyle(Palette.ink3)
        }
        if item.state == .partial {
          Text("做了一部分 · 时段按一半算").font(Typo.caption).foregroundStyle(Palette.ink3)
        }
        if let carried = carriedLabel {
          // A capture is written straight onto the sheet and stays until it is
          // done. Saying which day it came from is what separates "still not
          // done" from "new today" — without it a week-old row looks fresh.
          Text(carried).font(Typo.caption).foregroundStyle(Palette.mint600)
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

      if !compact || isHovering || selectedID == item.id {
        if isEditable {
          noteButton
        }

        RowActionBar(
          state: item.state,
          isVisible: isHovering || selectedID == item.id,
          allowed: isPlanRow ? [.done, .partial, .deferred, .open] : [.done, .deferred, .open],
          set: set
        )

        deleteButton
      }

      if let onUnpin {
        Button(action: onUnpin) {
          Image(systemName: "pin.fill")
            .font(.system(size: 9, weight: .semibold))
            .frame(width: 20, height: 20)
            .foregroundStyle(tint.ink.opacity(0.8))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("固定在这个钟点 · 点一下取消固定，回到自动排")
        .accessibilityLabel("取消固定")
      }

      if !compact {
        source
      }
    }
  }

  /// 更新 — same look as the state buttons beside it, same fade-in, and like
  /// them it stays in the hierarchy when hidden so the keyboard can reach it.
  private var noteButton: some View {
    let visible = isHovering || selectedID == item.id || isNoting
    return Button {
      withAnimation(.snappy(duration: 0.2)) {
        isNoting.toggle()
        if isNoting { isEditingEstimate = false }
      }
    } label: {
      Image(systemName: "square.and.pencil")
        .font(.system(size: 10, weight: .semibold))
        .frame(width: 20, height: 20)
        .foregroundStyle(isNoting ? Palette.mint800 : Palette.ink3)
        .background(isNoting ? Palette.mint200 : .clear, in: Circle())
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help("记一条更新")
    .accessibilityLabel("记一条更新")
    // No bare-key shortcut: with one per row, and the quick-capture field on
    // the same screen, a plain "e" would fire while you are typing.
    .allowsHitTesting(visible)
    .opacity(visible ? 1 : 0)
    .animation(.easeOut(duration: 0.12), value: visible)
  }

  /// 删除 — fades in with the other row controls. Asks first: for a capture it
  /// deletes the capture itself, which the four-state circle cannot undo.
  private var deleteButton: some View {
    let visible = isHovering || selectedID == item.id
    return Button {
      isConfirmingDelete = true
    } label: {
      Image(systemName: "trash")
        .font(.system(size: 10, weight: .semibold))
        .frame(width: 20, height: 20)
        .foregroundStyle(Palette.ink3)
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help("从今天删除")
    .accessibilityLabel("从今天删除")
    .allowsHitTesting(visible)
    .opacity(visible ? 1 : 0)
    .animation(.easeOut(duration: 0.12), value: visible)
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
    Task {
      let outcome = await state.planFeedback(candidateID: item.id, rank: row.rank, event: "remove", note: nil)
      state.toast = switch outcome {
      case .ok: "已从今天删除"
      case .failed(let why), .unsupported(let why): why
      }
    }
  }

  /// The start time, like a calendar entry. Fixed width so every block's text
  /// starts on the same vertical line; the length is the block's height.
  private var slot: some View {
    Text(row.start.map(DaySchedule.clock) ?? "—")
      .font(Typo.caption)
      .lineLimit(1)
      .fixedSize()
      .foregroundStyle(row.isLate ? Palette.mint600 : tint.ink.opacity(0.8))
      .monospacedDigit()
      .frame(width: 40, alignment: .leading)
      .padding(.top, 2)
  }

  /// The duration under the time, and the way in to changing it. A button only
  /// while the row is still open work: a finished row's estimate no longer
  /// moves anything on the sheet.
  @ViewBuilder private var estimateLabel: some View {
    let text = (row.minutes ?? item.estimatedMinutes).map(DaySchedule.duration) ?? "没估时"
    if isEditable {
      Button {
        withAnimation(.snappy(duration: 0.2)) {
          isEditingEstimate.toggle()
          if isEditingEstimate { isNoting = false }
        }
      } label: {
        HStack(spacing: 2) {
          Text(text)
          Image(systemName: "stopwatch").font(.system(size: 9, weight: .medium))
            .opacity(isHovering || isEditingEstimate ? 1 : 0)
        }
        .font(Typo.caption)
        .foregroundStyle(isEditingEstimate ? Palette.mint600 : Palette.ink3)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(item.estimatedMinutes == nil ? "这条没有估时，点一下自己填" : "点一下改估时")
    } else {
      Text(text).font(Typo.caption).foregroundStyle(Palette.ink3)
    }
  }

  private func closeEditors() {
    withAnimation(.snappy(duration: 0.2)) {
      isNoting = false
      isEditingEstimate = false
    }
    note = ""
  }

  private func sendNote() {
    let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
    closeEditors()
    Task {
      let outcome = await state.planFeedback(
        candidateID: item.id, rank: row.rank, event: "update", note: trimmed.isEmpty ? nil : trimmed
      )
      state.toast = switch outcome {
      case .ok: "已记录"
      case .failed(let why), .unsupported(let why): why
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
      .frame(width: 100, alignment: .trailing)
  }

  private func set(_ target: TodoState) {
    guard target != item.state else { return }
    if isPlanRow {
      let event = switch target {
      case .done: "complete"
      case .partial: "partial"
      case .deferred: "defer"
      default: "reopen"
      }
      Task {
        let outcome = await state.planFeedback(
          candidateID: item.id, rank: row.rank, event: event, note: nil
        )
        state.toast = switch outcome {
        case .ok: ["complete": "已完成", "partial": "标了部分，时段按一半算",
                   "defer": "顺到明天，不占今天"][event] ?? "已恢复"
        case .failed(let why), .unsupported(let why): why
        }
      }
    } else {
      state.setTodo(item.id, to: target)
    }
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
      .font(Typo.body.weight(.medium))
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
    default: .routine
    }
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
        Text(block.label).font(Typo.body.weight(.medium)).foregroundStyle(tint.ink)
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
    let routines = blocks.filter { $0.kind != .meeting }.reduce(0) { $0 + $1.end - $1.start }
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
    .padding(.top, Metrics.xs)
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
