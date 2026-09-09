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

        if progress.plannedMinutes > 0 {
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
private struct TimeAllocation: View {
  let items: [TodoItem]
  let total: Int

  private var timed: [TodoItem] { items.filter { ($0.estimatedMinutes ?? 0) > 0 } }

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xs) {
      HStack {
        Text("建议分配").mutedStyle(Typo.label)
        Spacer()
        Text("共 \(Fmt.minutes(total))").font(Typo.tabularCaption).foregroundStyle(Palette.inkMuted)
      }

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
        EmptyState(
          icon: "tray",
          title: "今天还没有计划",
          message: "跑一次「每日简报」，或者到周期页把这一期的要务排进来。",
          actionTitle: "跑一次简报",
          action: {}
        )
      } else {
        VStack(spacing: 0) {
          ForEach(Array(state.plan.enumerated()), id: \.element.id) { index, item in
            if index > 0 { PanelDivider() }
            PlanRow(item: item)
          }
        }
      }
    } actions: {
      Button("重跑") {}.buttonStyle(QuietButtonStyle())
    }
  }
}

private struct PlanRow: View {
  let item: TodoItem

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
      Pill(item.kind.label, tone: item.kind.tone)
      Text(item.text).inkStyle()
      Spacer(minLength: Metrics.xs)
      if let due = item.due {
        Text(Fmt.time(due)).font(Typo.tabularCaption).foregroundStyle(Palette.inkMuted)
      }
      if let ref = item.sourceRef {
        Text(ref).font(Typo.mono).foregroundStyle(Palette.inkMuted)
      }
    }
    .frame(minHeight: Metrics.hitTarget)
  }
}

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
      }
    }
  }
}

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
      if item.state == .deferred {
        Pill("已顺延", tone: .warn)
      } else if item.state == .open {
        Button("顺延") { state.setTodo(item.id, to: .deferred) }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
      }
    }
    .frame(minHeight: Metrics.hitTarget)
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
