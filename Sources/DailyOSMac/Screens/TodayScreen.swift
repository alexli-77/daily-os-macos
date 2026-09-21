import SwiftUI
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

  var body: some View {
    ScreenScaffold("今天", subtitle: subtitle) {
      if showsExecution { ExecutionPanel(schedule: schedule) }
      QuickCapturePanel()
      CallSheetPanel(schedule: schedule, selectedID: $selectedTaskID)
      TeamTodayPanel()
    } toolbar: {
      HStack(spacing: Metrics.sm) {
        WeatherStrip()
        Button(showsExecution ? "收起执行情况" : "执行情况") {
          withAnimation(.snappy(duration: 0.2)) { showsExecution.toggle() }
        }
        .buttonStyle(MossButtonStyle(prominent: false))
        .accessibilityAddTraits(showsExecution ? [.isSelected] : [])
      }
    }
  }

  /// The plan, then anything captured that is not in it.
  ///
  /// Plan order is the planner's ranking and the user's drags; inbox captures go
  /// after, because they arrived without a position and inventing one for them
  /// would silently outrank work the planner reasoned about.
  private var items: [TodoItem] { state.plan + state.todos }

  private var schedule: DaySchedule {
    DaySchedule.build(
      items: items,
      startMinute: DayStart.resolve(generatedAt: state.planGeneratedAt),
      nowMinute: DaySchedule.minute(of: .now)
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
  @State private var dropIndex: Int?

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
    .onChange(of: state.plan.map(\.id)) { dropIndex = nil }
  }

  @ViewBuilder private var sheet: some View {
    VStack(spacing: 0) {
      ForEach(Array(schedule.rows.enumerated()), id: \.element.id) { index, row in
        if index == schedule.nowIndex && !schedule.isClear {
          NowLine(minute: schedule.now)
        }
        CallSheetRow(
          row: row,
          isPlanRow: index < state.plan.count,
          selectedID: $selectedID,
          dropEdge: dropEdge(for: index)
        )
        .transition(.taskRow)
        .onDrag { NSItemProvider(object: row.item.id as NSString) }
        .onDrop(
          of: [.text],
          delegate: PlanDropDelegate(index: index, dropIndex: $dropIndex, onDrop: move)
        )
        if index < schedule.rows.count - 1 {
          Rectangle().fill(Palette.rule).frame(height: Metrics.hairline)
        }
      }
      // The line belongs after the last row when the whole day is behind you.
      if schedule.nowIndex >= schedule.rows.count && !schedule.isClear {
        NowLine(minute: schedule.now)
      }
      if schedule.isClear { ClearState(schedule: schedule) }
    }
  }

  private var subtitle: String {
    let start = DayStart.resolve(generatedAt: state.planGeneratedAt)
    return "从 \(DaySchedule.clock(start)) 起按估时顺推 · 拖动换顺序，时段跟着重算"
  }

  private var isRunning: Bool { state.planRunStartedAt != nil }

  private func dropEdge(for index: Int) -> CallSheetRow.DropEdge? {
    guard let dropIndex else { return nil }
    if dropIndex == index { return .top }
    if dropIndex == index + 1 && index == schedule.rows.count - 1 { return .bottom }
    return nil
  }

  /// Reorder inside the plan only.
  ///
  /// Inbox captures live in a different ledger with a different id space and no
  /// concept of rank; letting one be dragged into the middle of the plan would
  /// produce an order the service cannot store and that vanishes on reload.
  private func move(from id: String, to index: Int) {
    guard state.plan.contains(where: { $0.id == id }) else {
      state.toast = "随手记的条目排在计划后面，暂时不能拖进计划里。"
      return
    }
    let order = withAnimation(.snappy(duration: 0.28)) {
      state.movePlanItem(id, before: min(index, state.plan.count))
    }
    Task {
      if case .failed(let why) = await state.savePlanOrder(order) { state.toast = why }
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
  enum DropEdge { case top, bottom }

  @Environment(AppState.self) private var state
  let row: DaySchedule.Row
  /// Inbox rows cannot be `partial` — the service's inbox endpoint has no such
  /// status. See `RowActionBar.allowed`.
  let isPlanRow: Bool
  @Binding var selectedID: TodoItem.ID?
  var dropEdge: DropEdge?

  @State private var isHovering = false

  private var item: TodoItem { row.item }
  private var isResolved: Bool { item.state == .done || item.state == .deferred }
  private var isMIT: Bool { isPlanRow && PlanImportance.forRank(row.rank) == .mit }

  var body: some View {
    HStack(alignment: .top, spacing: Metrics.sm) {
      slot
      StateCircle(state: item.state) {
        set(item.state == .done ? .open : .done)
      }
      .padding(.top, 1)

      VStack(alignment: .leading, spacing: 2) {
        Text(item.text)
          .font(Typo.body)
          .foregroundStyle(isResolved ? Palette.ink3 : Palette.ink)
          .strikethrough(isResolved, color: Palette.ink3)
          .fixedSize(horizontal: false, vertical: true)
        if row.isLate {
          Text("已过时段 · 还没更新").font(Typo.caption).foregroundStyle(Palette.mint600)
        }
        if item.state == .deferred {
          Text("顺到明天").font(Typo.caption).foregroundStyle(Palette.ink3)
        }
        if item.state == .partial {
          Text("做了一部分 · 时段按一半算").font(Typo.caption).foregroundStyle(Palette.ink3)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      RowActionBar(
        state: item.state,
        isVisible: isHovering || selectedID == item.id,
        allowed: isPlanRow ? [.done, .partial, .deferred, .open] : [.done, .deferred, .open],
        set: set
      )

      source
    }
    .padding(.vertical, Metrics.sm)
    .contentShape(Rectangle())
    .onHover { isHovering = $0 }
    .onTapGesture { selectedID = item.id }
    .overlay(alignment: dropEdge == .bottom ? .bottom : .top) {
      if dropEdge != nil {
        Capsule().fill(Palette.mint400).frame(height: 2).transition(.opacity)
      }
    }
  }

  /// 时段 / 估时 / MIT, stacked. Fixed width so every row's text starts on the
  /// same vertical line — a ragged left edge is what makes a list of times
  /// unreadable as a column.
  private var slot: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text(row.start.map { "\(DaySchedule.clock($0))–\(DaySchedule.clock(row.end ?? $0))" } ?? "—")
        .font(Typo.label)
        .foregroundStyle(row.isLate ? Palette.mint600 : (isResolved ? Palette.ink3 : Palette.ink2))
        .monospacedDigit()
      if let minutes = row.minutes ?? item.estimatedMinutes {
        Text(DaySchedule.duration(minutes)).font(Typo.caption).foregroundStyle(Palette.ink3)
      } else {
        Text("没估时").font(Typo.caption).foregroundStyle(Palette.ink3)
      }
      if isMIT {
        Text("MIT")
          .font(Typo.caption)
          .bold()
          .kerning(0.96)
          .foregroundStyle(Palette.q1)
          .opacity(isResolved ? 0.4 : 1)
      }
    }
    .frame(width: 96, alignment: .leading)
  }

  private var source: some View {
    Group {
      if let ref = item.sourceRef {
        Text(ref)
          .font(Typo.caption)
          .foregroundStyle(Palette.ink2)
          .underline(true, pattern: .dot)
      } else {
        Text("日程").font(Typo.caption).foregroundStyle(Palette.ink3)
      }
    }
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

// MARK: - Now line

private struct NowLine: View {
  let minute: Int

  var body: some View {
    HStack(spacing: Metrics.xs) {
      Text("现在 \(DaySchedule.clock(minute))")
        .font(Typo.caption)
        .foregroundStyle(Palette.mint600)
        .monospacedDigit()
      Rectangle().fill(Palette.mint400).frame(height: 2)
    }
    .padding(.vertical, Metrics.xs)
    .accessibilityLabel("现在 \(DaySchedule.clock(minute))，下面的还没开始")
  }
}

// MARK: - Overdue banner

/// The rows whose slot has passed while they are still open.
///
/// One banner rather than a badge per row: the question it answers — "how far
/// behind am I" — is about the day, not about any single line, and three red
/// marks scattered down a list do not add up to an answer on their own.
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
        TextField("随手记一条…", text: $state.quickCaptureText)
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


private struct PlanDropDelegate: DropDelegate {
  let index: Int
  @Binding var dropIndex: Int?
  let onDrop: (String, Int) -> Void

  func dropEntered(info: DropInfo) {
    withAnimation(.snappy(duration: 0.18)) { dropIndex = index }
  }

  func dropExited(info: DropInfo) {
    // Only if this row still owns the line. Enter on the next row fires before
    // exit on this one, so clearing unconditionally would erase a line that
    // belongs to whatever the cursor has already moved onto.
    if dropIndex == index {
      withAnimation(.snappy(duration: 0.18)) { dropIndex = nil }
    }
  }

  func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

  func performDrop(info: DropInfo) -> Bool {
    let destination = index
    guard let provider = info.itemProviders(for: [.text]).first else { return false }
    _ = provider.loadObject(ofClass: NSString.self) { value, _ in
      guard let id = value as? String else { return }
      Task { @MainActor in
        dropIndex = nil
        onDrop(id, destination)
      }
    }
    return true
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

/// Small enough that six of them fit next to a label in half a window.
/// `MossButtonStyle` is the right look and the wrong size here — its 28pt hit
/// target and 12pt padding turn a row of presets into a toolbar.
private struct EstimateChipStyle: ButtonStyle {
  let isCurrent: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(Typo.tabularCaption.weight(isCurrent ? .semibold : .regular))
      .foregroundStyle(isCurrent ? .white : Palette.ink)
      .padding(.horizontal, Metrics.xs)
      .frame(height: 22)
      .background {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(isCurrent ? Palette.moss : Palette.surfaceSunken)
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
