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
      StatusStrip()
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

// MARK: - Status strip

private struct StatusStrip: View {
  @Environment(AppState.self) private var state

  var body: some View {
    Panel {
      VStack(spacing: Metrics.sm) {
        HStack(spacing: Metrics.md) {
          StatTile(
            "服务",
            value: state.service.state.label,
            tone: state.service.state.tone
          )
          StatTile("今日 token", value: Fmt.compactCount(state.todayTokens))
          StatTile("今日成本", value: Fmt.money(state.todayCost))
          StatTile(
            "进行中",
            value: "\(state.activeRuns.count)",
            tone: state.activeRuns.isEmpty ? .neutral : .accent
          )
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
