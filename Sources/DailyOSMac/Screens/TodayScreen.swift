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

  var body: some View {
    ScreenScaffold("今天", subtitle: subtitle) {
      DayProgressPanel()
      QuickCapturePanel()
      TwoColumns {
        PlanPanel()
      } trailing: {
        TodoPanel()
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

  var body: some View {
    let progress = state.dayProgress
    Panel {
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
        // disappeared: the service supplies no estimates, so the sum is always
        // zero and the whole feature silently stopped rendering. A missing
        // input should look like a missing input.
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
      }
    }
  }
}

/// One segment per planned item, so the bar reads as "three things, one done"
/// rather than as a continuous percentage. A day is countable; pretending it is
/// continuous hides that the last 20% is one whole task.
private struct SegmentedProgress: View {
  let items: [TodoItem]

  var body: some View {
    HStack(spacing: 3) {
      ForEach(items) { item in
        Capsule()
          .fill(item.state == .done ? Palette.ok : Palette.surfaceSunken)
          .frame(height: 6)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("已完成 \(items.filter { $0.state == .done }.count) 项，共 \(items.count) 项"))
  }
}

/// The suggested split of the day, as one proportional bar plus a legend.
///
/// Proportional rather than a list of durations because the useful question is
/// not "how long is this one" but "what is eating the day" — and that is a
/// comparison, which is what widths are for.
///
/// It also has to survive having nothing to compare. Every item the live store
/// produces arrives with `estimatedMinutes == nil`, so the honest states are
/// three, not two: all estimated, some estimated, none estimated. The last one
/// used to render as a blank space, which read as "this feature was removed"
/// rather than as "nobody supplied the numbers".
private struct TimeAllocation: View {
  let items: [TodoItem]
  let total: Int

  private var timed: [TodoItem] { items.filter { ($0.estimatedMinutes ?? 0) > 0 } }
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
        bar
        legend
        if untimedCount > 0 {
          // Partial data is its own trap: a bar drawn from two of five items
          // looks like the whole day unless it says otherwise.
          Text("另有 \(untimedCount) 项没有估时，没算进上面这条。").mutedStyle()
        }
      }
    }
  }

  private var bar: some View {
    GeometryReader { geo in
      HStack(spacing: 2) {
        ForEach(timed) { item in
          RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Palette.foreground(for: item.kind.tone))
            .opacity(item.state == .done ? 0.35 : 1)
            .frame(width: width(for: item, in: geo.size.width))
        }
      }
    }
    .frame(height: 10)
  }

  private var legend: some View {
    VStack(alignment: .leading, spacing: Metrics.xxs) {
      ForEach(timed) { item in
        HStack(spacing: Metrics.xs) {
          Circle()
            .fill(Palette.foreground(for: item.kind.tone))
            .opacity(item.state == .done ? 0.35 : 1)
            .frame(width: 6, height: 6)
          Text(item.text)
            .font(Typo.caption)
            .foregroundStyle(item.state == .done ? Palette.inkMuted : Palette.ink)
            .strikethrough(item.state == .done, color: Palette.inkMuted)
            .lineLimit(1)
          Spacer(minLength: Metrics.xs)
          Text(Fmt.minutes(item.estimatedMinutes ?? 0))
            .font(Typo.tabularCaption)
            .foregroundStyle(Palette.inkMuted)
        }
      }
    }
  }

  /// Floors at 12pt so a 15-minute task stays visible and clickable next to a
  /// two-hour one; exact proportion is not worth an invisible segment.
  private func width(for item: TodoItem, in available: CGFloat) -> CGFloat {
    guard total > 0, available > 0 else { return 0 }
    let gaps = CGFloat(max(timed.count - 1, 0)) * 2
    let usable = max(available - gaps, 0)
    let share = CGFloat(item.estimatedMinutes ?? 0) / CGFloat(total)
    return max(usable * share, 12)
  }
}

/// What the allocation block shows when nothing carries an estimate.
///
/// Names the supplier rather than the symptom. `daily_plan` emits
/// `{ rank, text, candidateId }` and the todo inbox ledger has no duration field
/// either, so there is no number anywhere upstream — whoever reads this should
/// end up asking the workflow for minutes, not wondering whether the Mac app
/// dropped a panel. Inventing a plausible duration would be worse than silence:
/// the point of the bar is to catch "four priorities is six hours" *before* the
/// day starts, and a made-up six hours makes that check meaningless.
private struct MissingEstimates: View {
  let count: Int

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xxs) {
      Label("这 \(count) 项都没有耗时估计", systemImage: "questionmark.circle")
        .font(Typo.caption)
        .foregroundStyle(Palette.inkMuted)
      Text("估时要由 daily_plan 工作流给出，它现在只产出排序、正文和来源 id；待办账本里也没有这个字段。所以这里空着，不编一个数。")
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
        VStack(spacing: 0) {
          ForEach(Array(state.plan.enumerated()), id: \.element.id) { index, item in
            if index > 0 { PanelDivider() }
            PlanRow(item: item, rank: index + 1)
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
private struct PlanRow: View {
  @Environment(AppState.self) private var state
  let item: TodoItem
  /// Position in the list, 1-based. Part of the ledger key, not decoration.
  let rank: Int

  @State private var isNoting = false
  @State private var note = ""

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xxs) {
      HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
        Pill(item.kind.label, tone: item.kind.tone)
        Text(item.text)
          .inkStyle()
          .strikethrough(item.state == .done, color: Palette.inkMuted)
          .foregroundStyle(item.state == .open ? Palette.ink : Palette.inkMuted)
        Spacer(minLength: Metrics.xs)
        if let due = item.due {
          Text(Fmt.time(due)).font(Typo.tabularCaption).foregroundStyle(Palette.inkMuted)
        }
        actions
      }
      .frame(minHeight: Metrics.hitTarget)

      if isNoting {
        // The web prompts for the note in a dialog. Inline here because a modal
        // for one optional sentence is heavier than the sentence.
        HStack(spacing: Metrics.xs) {
          TextField("记一条更新（可留空）", text: $note)
            .textFieldStyle(.plain)
            .font(Typo.caption)
            .padding(Metrics.xxs)
            .background(Palette.surfaceSunken)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
            .onSubmit { send("update", note: note) }
          Button("记下") { send("update", note: note) }
            .buttonStyle(QuietButtonStyle())
          Button("取消") { isNoting = false; note = "" }
            .buttonStyle(QuietButtonStyle(tone: .neutral))
        }
      }
    }
  }

  /// Always rendered, never on hover: these are the day's decisions, and a
  /// control you have to go looking for is a control that does not get used.
  @ViewBuilder private var actions: some View {
    switch item.state {
    case .done:
      Pill("已完成", tone: .ok)
    case .deferred:
      Pill("已顺延", tone: .warn)
    case .open:
      // Web order: secondary actions first, the one that closes the row last,
      // so the same click lands in the same place in both consoles.
      Button("更新") { isNoting.toggle() }
        .buttonStyle(QuietButtonStyle(tone: .neutral))
      Button("顺延") { send("defer", note: nil) }
        .buttonStyle(QuietButtonStyle(tone: .neutral))
      Button("完成") { send("complete", note: nil) }
        .buttonStyle(QuietButtonStyle())
    }
  }

  private func send(_ event: String, note: String?) {
    isNoting = false
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
      case .ok: state.toast = event == "update" ? "已记录" : (event == "complete" ? "已完成" : "已顺延")
      case .failed(let why), .unsupported(let why): state.toast = why
      }
    }
  }
}

/// Why a row here can be short of the web's three buttons.
///
// MARK: - Todos

private struct TodoPanel: View {
  @Environment(AppState.self) private var state
  @State private var showsHistory = false

  var body: some View {
    Panel("我的待办", subtitle: "\(state.openTodos.count) 项未完成") {
      VStack(spacing: 0) {
        if state.openTodos.isEmpty {
          EmptyState(icon: "checkmark.circle", title: "都清完了", message: "收件箱是空的。")
        } else {
          ForEach(Array(state.openTodos.enumerated()), id: \.element.id) { index, item in
            if index > 0 { PanelDivider() }
            TodoRow(item: item)
          }
        }

        if !state.doneTodos.isEmpty || !state.deferredTodos.isEmpty {
          PanelDivider()
          DisclosureGroup(isExpanded: $showsHistory) {
            VStack(spacing: 0) {
              ForEach(state.doneTodos) { TodoRow(item: $0) }
              ForEach(state.deferredTodos) { TodoRow(item: $0) }
            }
          } label: {
            Text("已完成 / 已顺延 · \(state.doneTodos.count + state.deferredTodos.count)")
              .mutedStyle()
          }
          .tint(Palette.inkMuted)
          .padding(.top, Metrics.xs)
        }

        TodoDeleteNote()
      }
    }
  }
}

/// One inbox row.
///
/// The web gives an open row Done / Defer / Delete, and a history row Restore /
/// Delete. Three of those four are `setTodo(_:to:)` in disguise and are here;
/// Delete is not, and `TodoDeleteNote` explains that rather than pretending.
///
/// 完成 stays on the check circle instead of becoming a worded button. It is the
/// same action as the web's Done, it is already the affordance people reach for
/// in a todo list, and a list where every row carries three worded buttons is
/// harder to read than the problem being fixed.
private struct TodoRow: View {
  @Environment(AppState.self) private var state
  let item: TodoItem

  var body: some View {
    HStack(spacing: Metrics.xxs) {
      CheckCircle(isOn: item.state == .done) { state.toggleTodo(item.id) }
      Text(item.text)
        .inkStyle()
        .strikethrough(item.state == .done, color: Palette.inkMuted)
        .foregroundStyle(item.state == .open ? Palette.ink : Palette.inkMuted)
      Spacer(minLength: Metrics.xs)
      switch item.state {
      case .open:
        Button("顺延") { state.setTodo(item.id, to: .deferred) }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
      case .deferred:
        Pill("已顺延", tone: .warn)
        // The web's Restore. The check circle cannot stand in for it: on a
        // deferred row the circle is empty, so tapping it marks the item done
        // instead of putting it back in the open list.
        Button("恢复") { state.setTodo(item.id, to: .open) }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
      case .done:
        // Unticking the circle is already Restore for a done row.
        EmptyView()
      }
    }
    .frame(minHeight: Metrics.hitTarget)
  }
}

/// Delete is real on the service and unreachable from here; say which.
///
/// `TodoInboxStatus` is `open | done | deferred | deleted` — a delete is a
/// tombstone status on the ledger row, not a removal, and `/api/state` filters
/// those out before this client ever sees them. But `TodoState` has three cases
/// and the client's `setTodo` can only spell those three, so `deleted` cannot be
/// sent from this app at all. Wiring 删除 to `.deferred` would be the worst of
/// both worlds: the item survives, reappears under 已顺延, and the ledger records
/// a decision the user never made.
private struct TodoDeleteNote: View {
  var body: some View {
    Text("删除不在这里：服务端把「已删除」记成待办的第四种状态，Mac 端还没接这个写入。要删就去网页控制台，或者在飞书里发一句「删除 todo …」。")
      .mutedStyle()
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.top, Metrics.sm)
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
