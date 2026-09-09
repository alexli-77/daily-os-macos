import SwiftUI
import DailyOSCore

/// The launchd jobs, in plain language.
///
/// Cadence is shown as "每天 08:30" with the cron expression demoted to
/// metadata. The service really is driven by cron, and hiding that entirely
/// would be a lie the first time someone needs to debug a job that did not
/// fire — but a screen that leads with `30 8 * * *` is a screen you have to
/// decode before you can use it.
struct SchedulesScreen: View {
  @Environment(AppState.self) private var state

  var body: some View {
    ScreenScaffold("排程", subtitle: "由本机的 launchd 触发，服务不在运行时不会补跑") {
      if state.schedules.isEmpty {
        Panel {
          EmptyState(icon: "clock.arrow.circlepath", title: "没有排程", message: "所有工作流都要手动触发。")
        }
      } else {
        Panel {
          VStack(spacing: 0) {
            ForEach(Array(state.schedules.enumerated()), id: \.element.id) { index, entry in
              if index > 0 { PanelDivider() }
              ScheduleRow(entry: entry)
            }
          }
        }
      }
    }
  }
}

private struct ScheduleRow: View {
  @Environment(AppState.self) private var state
  let entry: ScheduleEntry

  var body: some View {
    HStack(alignment: .top, spacing: Metrics.sm) {
      VStack(alignment: .leading, spacing: Metrics.xxs) {
        HStack(spacing: Metrics.xs) {
          Text(entry.label).inkStyle(Typo.bodyStrong)
          Pill(entry.workflow, tone: .accent, mono: true)
          if !entry.enabled { Pill("已停用", tone: .neutral) }
        }
        HStack(spacing: Metrics.xs) {
          Text(entry.cadence).mutedStyle()
          Text(entry.cron).font(Typo.mono).foregroundStyle(Palette.inkMuted)
        }
        HStack(spacing: Metrics.md) {
          if let last = entry.lastRun {
            Text("上次 \(Fmt.stamp(last))").mutedStyle()
          }
          if entry.enabled, let next = entry.nextRun {
            Text("下次 \(Fmt.stamp(next))").mutedStyle()
          }
        }
      }
      Spacer(minLength: Metrics.xs)
      VStack(alignment: .trailing, spacing: Metrics.xxs) {
        Toggle("", isOn: Binding(
          get: { entry.enabled },
          set: { _ in state.toggleSchedule(entry.id) }
        ))
        .labelsHidden()
        .toggleStyle(.switch)
        Button("立即跑") {}.buttonStyle(QuietButtonStyle())
      }
    }
    .padding(.vertical, Metrics.xs)
  }
}

// MARK: - Previews

#Preview("排程") {
  SchedulesScreen()
    .environment(AppState.previewOwner())
    .frame(width: 940, height: 640)
}

#Preview("排程 · 空状态") {
  SchedulesScreen()
    .environment(AppState.previewEmpty())
    .frame(width: 940, height: 640)
}
