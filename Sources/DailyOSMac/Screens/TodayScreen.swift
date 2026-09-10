import SwiftUI
import DailyOSCore

/// The screen you open by reflex.
///
/// Replaces both `/dashboard` and `/today` from the web console. The dashboard's
/// three stats become one strip at the top; below it are the only two questions
/// that matter in the morning — what is planned, and what is still open — plus a
/// capture box, because the most common reason to open this app is to get
/// something out of your head, not to read.
struct TodayScreen: View {
  @Environment(AppState.self) private var state
  /// One selection for the whole screen, not one per panel.
  ///
  /// Two panels each holding their own would let two rows sit highlighted at
  /// once, and then "the selected row" — which is what the keyboard acts on —
  /// stops having a single answer. Plan ids are `daily_plan` candidate ids and
  /// inbox ids are ledger ids, so they cannot collide.
  @State private var selectedTaskID: TodoItem.ID?

  var body: some View {
    ScreenScaffold("今天", subtitle: subtitle) {
      DayProgressPanel()
      QuickCapturePanel()
      TwoColumns {
        PlanPanel(selectedID: $selectedTaskID)
      } trailing: {
        TodoPanel(selectedID: $selectedTaskID)
      }
    }
  }

  private var subtitle: String {
    let date = Fmt.dayHeading()
    guard let cycle = state.currentCycle else { return date }
    return "\(date) · 当前周期 \(Fmt.cycleTitle(cycle))"
  }
}

// MARK: - Day progress

/// What the day looks like, in one panel.
///
/// This replaces the token / cost / in-flight tiles that used to sit here.
/// Those answered "what is the machine doing"; they were three unrelated
/// numbers that happened to be cheap to compute, and none of them changed what
/// you would do next. Cost still exists — on the Runs screen, which is where
/// you go when the machine *is* the question.
///
/// What is here instead answers "how is today going": how much of the plan is
/// done, and how the remaining time is meant to be spent. The time allocation
/// is a suggestion the planner makes, not a commitment — its job is to let you
/// notice that four priorities is six hours of work *before* the day starts.
private struct DayProgressPanel: View {
  @Environment(AppState.self) private var state

  /// The donut is square and the left column is pinned to the same height, so
  /// the panel reads as one block rather than as a chart bolted onto a stat.
  private static let chartSide: CGFloat = 148

  var body: some View {
    let progress = state.dayProgress
    Panel {
      HStack(alignment: .top, spacing: Metrics.lg) {
        VStack(alignment: .leading, spacing: Metrics.sm) {
          HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
            Text("今日进度").mutedStyle(Typo.label)
            Spacer()
            if state.service.state != .running {
              StatusDot(state.service.state.label, tone: state.service.state.tone)
            }
          }

          HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
            Text("\(progress.done)")
              .font(.system(.largeTitle, design: .default).weight(.medium).monospacedDigit())
              .foregroundStyle(progress.isComplete ? Palette.ok : Palette.ink)
            Text("/ \(progress.target)")
              .font(Typo.tabularBody)
              .foregroundStyle(Palette.inkMuted)
            Text(progress.isComplete ? "今天的计划做完了" : "已完成")
              .mutedStyle(Typo.body)
            Spacer(minLength: Metrics.xs)
            if progress.remainingMinutes > 0 {
              Text("还需 \(Fmt.minutes(progress.remainingMinutes))")
                .font(Typo.tabularBody.weight(.medium))
                .foregroundStyle(Palette.moss)
            }
          }

          SegmentedProgress(items: state.plan)

          // Gated on "is there a plan at all", not on "does the plan carry
          // minutes". The old `plannedMinutes > 0` gate is why this block
          // disappeared: with no estimates the sum is always zero and the whole
          // feature silently stopped rendering. A missing input should look
          // like a missing input.
          if !state.plan.isEmpty {
            PanelDivider()
            TimeAllocation(items: state.plan, total: progress.plannedMinutes)
          }

          if let note = state.service.note {
            PanelDivider()
            Label(note, systemImage: "exclamationmark.triangle")
              .font(Typo.caption)
              .foregroundStyle(Palette.warn)
              .frame(maxWidth: .infinity, alignment: .leading)
          }

          Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        if !state.plan.isEmpty {
          TimeDonut(items: state.plan, total: progress.plannedMinutes)
            .frame(width: Self.chartSide, height: Self.chartSide)
        }
      }
      .frame(minHeight: state.plan.isEmpty ? 0 : Self.chartSide)
    }
  }
}

/// The day's time split, as a ring.
///
/// Answers "what is eating the day", which is a comparison — and comparisons
/// are what angles and widths are for. It sits beside 今日进度 rather than under
/// it because the two are the same question asked twice: how much of today is
/// done, and how much of today there is.
///
/// It has to survive having nothing to compare, and that is not a rare state:
/// the planner omits `minutes` whenever it cannot judge, and any plan generated
/// before the prompt asked for the field has none at all.
private struct TimeDonut: View {
  let items: [TodoItem]
  let total: Int

  private var timed: [TodoItem] { items.filter { ($0.estimatedMinutes ?? 0) > 0 } }

  var body: some View {
    if timed.isEmpty {
      empty
    } else {
      DonutChart(slices: slices, lineWidth: 20) {
        VStack(spacing: 0) {
          Text(Fmt.minutes(total))
            .font(Typo.tabularBody.weight(.medium))
            .foregroundStyle(Palette.ink)
          Text("共 \(timed.count) 项")
            .font(Typo.caption)
            .foregroundStyle(Palette.inkMuted)
        }
      }
      .help("按估时分配今天的时间")
    }
  }

  /// One slice per estimated item, in plan order, so a slice's colour matches
  /// its legend row without either needing to be sorted.
  ///
  /// Finished items keep their slice and get faded rather than being dropped.
  /// Removing them would shrink the ring as the day went on, which would make
  /// the total silently mean "what is left" in a chart labelled with the day's
  /// whole planned time.
  private var slices: [DonutSlice] {
    items.enumerated().compactMap { index, item in
      guard let minutes = item.estimatedMinutes, minutes > 0 else { return nil }
      return DonutSlice(
        id: item.id,
        label: "\(item.text) · \(Fmt.minutes(minutes))",
        value: Double(minutes),
        color: Palette.series(index),
        isSpent: item.state != .open
      )
    }
  }

  private var empty: some View {
    ZStack {
      // A hairline outline, not a 20pt dashed stroke. Dashing a ring that thick
      // turns it into a sunburst — the loudest thing in the panel, drawn to say
      // that there is nothing here.
      Circle()
        .strokeBorder(Palette.line, style: StrokeStyle(lineWidth: 1.5, dash: [4, 5]))
        .padding(10)
      VStack(spacing: 2) {
        Image(systemName: "stopwatch")
          .font(.system(size: 15))
          .foregroundStyle(Palette.inkMuted)
        Text("没有估时")
          .font(Typo.caption)
          .foregroundStyle(Palette.inkMuted)
      }
    }
    .help("这份计划没有耗时估计，点每行的估时按钮可以自己填")
  }
}

/// One segment per planned item, so the bar reads as "three things, one done"
/// rather than as a continuous percentage. A day is countable; pretending it is
/// continuous hides that the last 20% is one whole task.
///
/// Three rules on top of that, all of which exist so the bar is a *progress*
/// bar rather than a row of tiles:
///
/// 1. **Finished work goes left.** Progress in a plan you keep reordering is
///    unreadable if the done segments are scattered through it — the eye reads
///    a bar left to right and wants the boundary between "behind me" and "ahead
///    of me" to be one edge, not five.
/// 2. **Width follows the estimate.** Equal cells say four things are left when
///    three of them are ten minutes and the fourth is the afternoon.
/// 3. **An item with no estimate is drawn as one**, not hidden and not given a
///    fabricated duration — see `Segment.isEstimated`.
private struct SegmentedProgress: View {
  let items: [TodoItem]

  var body: some View {
    let segments = PlanSegment.layout(items)
    // Only meaningful when the bar is *mixed*. A dash marks a width that is a
    // stand-in sitting next to widths that are measurements — without it the
    // bar presents a guess with the same authority as the real numbers beside
    // it. When nothing is estimated, equal cells are not a guess, they are the
    // honest rendering of knowing nothing, and dashing every one of them is
    // just five dashed boxes saying what the caption below already says.
    let isMixed = segments.contains(where: \.isEstimated) && segments.contains { !$0.isEstimated }
    GeometryReader { geo in
      HStack(spacing: 3) {
        ForEach(segments) { segment in
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(fill(for: segment.state))
            .overlay {
              RoundedRectangle(cornerRadius: 3, style: .continuous)
                .strokeBorder(
                  border(for: segment),
                  style: StrokeStyle(
                    lineWidth: Metrics.hairline,
                    dash: isMixed && !segment.isEstimated ? [3, 2] : []
                  )
                )
            }
            .frame(width: width(for: segment, in: segments, available: geo.size.width))
            .help(tooltip(for: segment))
        }
      }
    }
    .frame(height: 8)
    // Finishing something makes its segment change colour and slide to the
    // left edge. That movement *is* the progress, so it gets to be seen.
    .animation(.snappy(duration: 0.4), value: segments.map(\.id))
    .animation(.snappy(duration: 0.4), value: segments.map(\.weight))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("已完成 \(items.filter { $0.state == .done }.count) 项，共 \(items.count) 项"))
  }

  private func fill(for state: TodoState) -> Color {
    switch state {
    case .done: Palette.ok
    case .deferred: Palette.softBackground(for: .warn)
    case .open, .deleted: Palette.surfaceSunken
    }
  }

  /// The outline carries the shape when the fill is nearly the panel colour —
  /// a pale grey block on a white panel has no edges without it.
  private func border(for segment: PlanSegment) -> Color {
    switch segment.state {
    case .done: .clear
    case .deferred: Palette.warn.opacity(0.4)
    case .open, .deleted: Palette.line
    }
  }

  /// Floors at 10pt so a fifteen-minute task next to a three-hour one is still
  /// a visible, hoverable segment. Exact proportion is not worth a segment you
  /// cannot see or point at.
  private func width(for segment: PlanSegment, in segments: [PlanSegment], available: CGFloat) -> CGFloat {
    let total = segments.reduce(0) { $0 + $1.weight }
    guard total > 0, available > 0 else { return 0 }
    let gaps = CGFloat(max(segments.count - 1, 0)) * 3
    let usable = max(available - gaps, 0)
    return max(usable * CGFloat(segment.weight / total), 10)
  }

  private func tooltip(for segment: PlanSegment) -> String {
    let status = switch segment.state {
    case .done: "已完成"
    case .deferred: "已顺延"
    case .open, .deleted: "未完成"
    }
    let time = segment.minutes.map(Fmt.minutes) ?? "没有估时"
    return "\(segment.text)\n\(status) · \(time)"
  }
}

/// The legend for the ring beside it.
///
/// The proportional bar this used to draw is gone: it and the donut answered the
/// same question, and two pictures of one number is how a panel stops being
/// readable. What is left is the part a ring genuinely cannot do — naming the
/// slices and giving each one its figure.
///
/// It still has to survive having nothing to compare, and the honest states are
/// three rather than two: all estimated, some estimated, none estimated. The
/// middle one is the trap — a chart drawn from two of five items looks like the
/// whole day unless it says otherwise.
private struct TimeAllocation: View {
  let items: [TodoItem]
  let total: Int

  /// Carries each item's index in the *plan*, not in the filtered list, because
  /// that index picks the colour and the ring is coloured the same way. Filter
  /// first and the third slice ends up the second legend colour.
  private var timed: [(index: Int, item: TodoItem)] {
    items.enumerated()
      .filter { ($0.element.estimatedMinutes ?? 0) > 0 }
      .map { (index: $0.offset, item: $0.element) }
  }

  private var untimedCount: Int { items.count - timed.count }

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xs) {
      HStack {
        Text("建议分配").mutedStyle(Typo.label)
        Spacer()
        if total > 0 {
          Text("共 \(Fmt.minutes(total))").font(Typo.tabularCaption).foregroundStyle(Palette.inkMuted)
        }
      }

      if timed.isEmpty {
        MissingEstimates(count: items.count)
      } else {
        legend
        if untimedCount > 0 {
          Text("另有 \(untimedCount) 项没有估时，点行尾的估时按钮就能填。").mutedStyle()
        }
      }
    }
    // Correcting one row's estimate is worth watching: these figures and the
    // ring beside them are the answer to "does today fit", and seeing them move
    // is the point of editing one.
    .animation(.snappy(duration: 0.32), value: total)
    .animation(.snappy(duration: 0.32), value: timed.count)
  }

  private var legend: some View {
    VStack(alignment: .leading, spacing: Metrics.xxs) {
      ForEach(timed, id: \.item.id) { entry in
        HStack(spacing: Metrics.xs) {
          RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(Palette.series(entry.index))
            .opacity(entry.item.state == .open ? 1 : 0.35)
            .frame(width: 8, height: 8)
          Text(entry.item.text)
            .font(Typo.caption)
            .foregroundStyle(entry.item.state == .open ? Palette.ink : Palette.inkMuted)
            .strikethrough(entry.item.state == .done, color: Palette.inkMuted)
            .lineLimit(1)
          Spacer(minLength: Metrics.xs)
          Text(Fmt.minutes(entry.item.estimatedMinutes ?? 0))
            .font(Typo.tabularCaption)
            .foregroundStyle(Palette.inkMuted)
        }
      }
    }
  }
}

/// What the allocation block shows when nothing carries an estimate.
///
/// Names what to do about it. `daily_plan` now asks for `minutes`, but the
/// prompt tells the model to omit the field rather than guess, and every plan
/// generated before that change has none — so an empty bar is still a state
/// this has to explain rather than a bug.
///
/// Inventing a plausible duration would be worse than silence: the point of the
/// bar is to catch "four priorities is six hours" *before* the day starts, and a
/// made-up six hours makes that check meaningless.
private struct MissingEstimates: View {
  let count: Int

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xxs) {
      Label("这 \(count) 项都没有耗时估计", systemImage: "questionmark.circle")
        .font(Typo.caption)
        .foregroundStyle(Palette.inkMuted)
      Text("估时由 daily_plan 给出，模型判断不出来时会省略，今天之前跑的计划则一条都没有。点每行的「估时」可以自己填。")
        .mutedStyle()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Plan

private struct PlanPanel: View {
  @Environment(AppState.self) private var state
  @Binding var selectedID: TodoItem.ID?

  var body: some View {
    Panel("今天的计划", subtitle: "来自当前周期的要务与日程") {
      if state.plan.isEmpty {
        // No action button: nothing in this client can start a workflow, and a
        // "跑一次简报" that does nothing is the complaint this screen exists to
        // fix. The message carries the two places the plan can actually come
        // from instead. The panel header lost its 重跑 button for the same
        // reason — it was wired to an empty closure.
        EmptyState(
          icon: "tray",
          title: "今天还没有计划",
          message: "计划由 daily_plan 工作流生成——早上的定时任务会跑，也可以在飞书里发一句「daily-os plan」。Mac 端还不能触发工作流，跑完之后这里会自己出现。"
        )
      } else {
        VStack(spacing: 2) {
          ForEach(Array(state.plan.enumerated()), id: \.element.id) { index, item in
            PlanRow(item: item, rank: index + 1, selectedID: $selectedID)
              .transition(.taskRow)
          }
        }
      }
    }
  }

}

/// One planned item, with all three of the web's actions.
///
/// The web console gives a plan row 更新 / 延期 / 完成, all three POSTing
/// `/api/today/todo-feedback` keyed by the `daily_plan` `candidateId`. All
/// three work here, because `TodoItem.id` on a plan row *is* the candidate id —
/// mapped that way deliberately, since the ledger is keyed on it and matching
/// on rank or text would move this morning's tick onto a different row the
/// moment the planner reorders or rewords a line.
///
/// The three used to be worded buttons on every row. They are now the check
/// circle plus two icons that arrive on select or hover — see `TaskRow` for why
/// that is not the undiscoverable hover-only pattern it resembles.
private struct PlanRow: View {
  @Environment(AppState.self) private var state
  let item: TodoItem
  /// Position in the list, 1-based. Part of the ledger key, not decoration.
  let rank: Int
  @Binding var selectedID: TodoItem.ID?

  @State private var isNoting = false
  @State private var note = ""
  @State private var isEditingEstimate = false

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xxs) {
      TaskRow(
        item: item,
        actions: actions,
        // Both directions. A tick that cannot be untucked is the one action on
        // this screen with no way back, and it is also the easiest to do by
        // accident — the circle is the biggest target on the row.
        onToggleCheck: item.state == .deferred ? nil : {
          send(item.state == .done ? "reopen" : "complete", note: nil)
        },
        selectedID: $selectedID
      ) {
        accessory
      }

      if isNoting {
        // The web prompts for the note in a dialog. Inline here because a modal
        // for one optional sentence is heavier than the sentence.
        InlineField(
          placeholder: "记一条更新（可留空）",
          text: $note,
          confirm: "记下",
          onConfirm: { send("update", note: note) },
          onCancel: { isNoting = false; note = "" }
        )
        .transition(.taskRow)
      }

      if isEditingEstimate {
        EstimateEditor(item: item, rank: rank) {
          withAnimation(.snappy(duration: 0.2)) { isEditingEstimate = false }
        }
        .transition(.taskRow)
      }
    }
  }

  /// The estimate, and the way in to changing it.
  ///
  /// A row with no estimate still shows the chip. The point of the number is to
  /// make the day's total addable, and a blank that looks like nothing gives you
  /// no reason to suspect the total is short.
  @ViewBuilder private var accessory: some View {
    if let due = item.due {
      Text(Fmt.time(due)).font(Typo.tabularCaption).foregroundStyle(Palette.inkMuted)
    }
    switch item.state {
    case .done: Pill("已完成", tone: .ok)
    case .deferred: Pill("已顺延", tone: .warn)
    case .deleted, .open: EmptyView()
    }
    if item.state == .open {
      Button {
        withAnimation(.snappy(duration: 0.2)) {
          isEditingEstimate.toggle()
          if isEditingEstimate { isNoting = false }
        }
      } label: {
        // A bare "—" is not readable as "duration, unset" — it reads as a
        // separator, or as nothing. The stopwatch says what the control is
        // about before you have hovered it, and the word says what is missing.
        HStack(spacing: 3) {
          Image(systemName: "stopwatch")
            .font(.system(size: 11, weight: .medium))
          Text(item.estimatedMinutes.map(Fmt.minutes) ?? "估时")
            .font(Typo.tabularCaption)
        }
        .foregroundStyle(item.estimatedMinutes == nil ? Palette.inkMuted : Palette.moss)
        .padding(.horizontal, 5)
        .frame(height: 20)
        .background {
          RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Palette.surfaceSunken)
            .opacity(item.estimatedMinutes == nil ? 0 : 1)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(item.estimatedMinutes == nil ? "这条没有估时，点一下自己填" : "点一下改估时")
    }
  }

  private var actions: [TaskAction] {
    // A deferred row's circle is empty, so ticking it would mark it done rather
    // than put it back — it gets a worded restore instead, exactly like the
    // inbox rows do.
    if item.state == .deferred {
      return [
        TaskAction(id: "reopen", label: "恢复", symbol: "arrow.uturn.backward", key: "r") {
          send("reopen", note: nil)
        }
      ]
    }
    // A completed row needs no cluster: unticking the circle is its undo.
    guard item.state == .open else { return [] }
    return [
      TaskAction(
        id: "update",
        label: "更新",
        symbol: "square.and.pencil",
        key: "e"
      ) {
        isNoting.toggle()
        if isNoting { isEditingEstimate = false }
      },
      TaskAction(
        id: "defer",
        label: "顺延",
        symbol: "clock.arrow.circlepath",
        tone: .warn,
        key: "d"
      ) {
        send("defer", note: nil)
      },
    ]
  }

  private func send(_ event: String, note: String?) {
    isNoting = false
    isEditingEstimate = false
    let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.note = ""
    Task {
      let outcome = await state.planFeedback(
        candidateID: item.id,
        rank: rank,
        event: event,
        note: (trimmed?.isEmpty ?? true) ? nil : trimmed
      )
      switch outcome {
      case .ok:
        state.toast = switch event {
        case "complete": "已完成"
        case "defer": "已顺延"
        case "reopen": "已恢复"
        default: "已记录"
        }
      case .failed(let why), .unsupported(let why): state.toast = why
      }
    }
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

// MARK: - Todos

private struct TodoPanel: View {
  @Environment(AppState.self) private var state
  @Binding var selectedID: TodoItem.ID?
  @State private var showsHistory = false

  var body: some View {
    Panel("我的待办", subtitle: "\(state.openTodos.count) 项未完成") {
      VStack(spacing: 2) {
        if state.openTodos.isEmpty {
          EmptyState(icon: "checkmark.circle", title: "都清完了", message: "收件箱是空的。")
        } else {
          ForEach(state.openTodos) { item in
            TodoRow(item: item, selectedID: $selectedID)
              .transition(.taskRow)
          }
        }

        if !state.doneTodos.isEmpty || !state.deferredTodos.isEmpty {
          PanelDivider()
          DisclosureGroup(isExpanded: $showsHistory) {
            VStack(spacing: 2) {
              ForEach(state.doneTodos) { TodoRow(item: $0, selectedID: $selectedID) }
              ForEach(state.deferredTodos) { TodoRow(item: $0, selectedID: $selectedID) }
            }
          } label: {
            Text("已完成 / 已顺延 · \(state.doneTodos.count + state.deferredTodos.count)")
              .mutedStyle()
          }
          .tint(Palette.inkMuted)
          .padding(.top, Metrics.xs)
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
    }
  }

  private var actions: [TaskAction] {
    var actions: [TaskAction] = []
    switch item.state {
    case .open:
      // A capture is one sentence typed in a hurry. Before this, fixing a typo
      // meant deleting the row and retyping it — which throws away its id, and
      // with it everything the scorer had learned about the thing.
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
      // The web's Restore. The check circle cannot stand in for it: on a
      // deferred row the circle is empty, so ticking it would mark the item
      // done rather than put it back in the open list — which is why this row
      // gets no circle at all.
      actions.append(
        TaskAction(id: "restore", label: "恢复", symbol: "arrow.uturn.backward", key: "r") {
          state.setTodo(item.id, to: .open)
        }
      )
    case .done, .deleted:
      // Unticking the circle is already Restore for a done row.
      break
    }
    actions.append(
      TaskAction(id: "delete", label: "删除", symbol: "trash", tone: .danger, key: .delete, role: .destructive) {
        state.setTodo(item.id, to: .deleted)
      }
    )
    return actions
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

#Preview("今天 · 服务降级") {
  TodayScreen()
    .environment(AppState.previewDegraded())
    .frame(width: 940, height: 720)
}

/// The shape a real daily-os hands this screen.
///
/// One preview for two of the fixture's lies at once, because in the live store
/// they are the same state: `LiveAppState` fills `plan` from the open todo
/// inbox — which is why these plan rows have working 完成 / 顺延 while the
/// fixture's own `p1…p4` do not — and the service supplies no per-item minutes,
/// so 建议分配 has nothing to draw and has to say so instead of vanishing.
#Preview("今天 · 没有估时") {
  TodayScreen()
    .environment(previewWithoutEstimates())
    .frame(width: 940, height: 720)
}

@MainActor private func previewWithoutEstimates() -> AppState {
  let state = AppState.previewOwner()
  state.plan = state.openTodos.map { item in
    var item = item
    item.estimatedMinutes = nil
    return item
  }
  return state
}
