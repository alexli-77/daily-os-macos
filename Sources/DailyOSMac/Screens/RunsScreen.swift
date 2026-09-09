import SwiftUI
import DailyOSCore

/// What the machine did, and what it cost.
///
/// This is the observability surface. Two things it must answer without a
/// click — is anything running right now, and did the last thing fail — and one
/// it must answer with a click: where exactly did it fail. Hence the step
/// timeline rather than a log blob.
struct RunsScreen: View {
  @Environment(AppState.self) private var state

  var body: some View {
    HStack(spacing: 0) {
      ListColumn { RunList() }
      Group {
        if let run = state.selectedRun {
          RunDetail(run: run)
        } else {
          EmptyState(icon: "waveform.path.ecg", title: "还没有运行记录", message: "跑一次 workflow 之后这里会有记录。")
        }
      }
      .frame(maxWidth: .infinity)
    }
    .background(Palette.paper)
  }
}

private struct RunList: View {
  @Environment(AppState.self) private var state

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: Metrics.xs) {
        if !state.activeRuns.isEmpty {
          SectionLabel("进行中 · \(state.activeRuns.count)")
          ForEach(state.activeRuns) { row(for: $0) }
        }
        SectionLabel("最近")
        ForEach(state.recentRuns) { row(for: $0) }
      }
      .padding(Metrics.xs)
    }
  }

  private func row(for run: WorkflowRun) -> some View {
    SelectableRow(isSelected: run.id == state.selectedRun?.id) {
      state.selectedRunID = run.id
    } content: {
      RunListRow(run: run)
    }
  }
}

private struct RunListRow: View {
  let run: WorkflowRun

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xxs) {
      HStack(spacing: Metrics.xs) {
        StatusDot(tone: run.state.tone, pulsing: run.state == .running)
        Text(run.workflow).inkStyle(Typo.bodyStrong)
        Spacer(minLength: Metrics.xs)
        Text(Fmt.duration(run.duration)).font(Typo.tabularCaption).foregroundStyle(Palette.inkMuted)
      }
      HStack(spacing: Metrics.xs) {
        Text(Fmt.stamp(run.startedAt)).mutedStyle()
        Text(run.id).font(Typo.mono).foregroundStyle(Palette.inkMuted)
      }
      if let progress = run.progress {
        ProgressTrack(fraction: progress)
      }
    }
  }
}

private struct RunDetail: View {
  let run: WorkflowRun

  var body: some View {
    ScreenScaffold(run.workflow, subtitle: "\(Fmt.stamp(run.startedAt)) · \(run.id)") {
      Panel {
        HStack(spacing: Metrics.md) {
          StatTile("状态", value: run.state.label, tone: run.state.tone)
          StatTile("耗时", value: Fmt.duration(run.duration))
          StatTile("token", value: "\(Fmt.compactCount(run.promptTokens)) / \(Fmt.compactCount(run.completionTokens))")
          StatTile("成本", value: Fmt.money(run.costUSD))
        }
      }

      Panel("步骤", subtitle: "规划 → 工具调用 → 确认 → 写入") {
        if run.steps.isEmpty {
          EmptyState(icon: "list.bullet", title: "没有步骤记录", message: "这次运行没有产生可追踪的步骤。")
        } else {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(run.steps.enumerated()), id: \.element.id) { index, step in
              StepRow(step: step, isLast: index == run.steps.count - 1)
            }
          }
        }
      }
    } toolbar: {
      Pill(run.state.label, tone: run.state.tone)
    }
  }
}

/// A timeline row. The connector line is what makes a list of four strings read
/// as a sequence, which is the only thing you care about when a run failed.
private struct StepRow: View {
  let step: RunStep
  let isLast: Bool

  var body: some View {
    HStack(alignment: .top, spacing: Metrics.sm) {
      VStack(spacing: 0) {
        Image(systemName: step.kind.icon)
          .font(.caption)
          .foregroundStyle(Palette.moss)
          .frame(width: 22, height: 22)
          .background(Palette.mossSoft, in: Circle())
        if !isLast {
          Rectangle()
            .fill(Palette.line)
            .frame(width: Metrics.hairline)
            .frame(maxHeight: .infinity)
        }
      }
      .frame(minHeight: 40)

      VStack(alignment: .leading, spacing: Metrics.xxs) {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
          Text(step.title).inkStyle()
          Spacer(minLength: Metrics.xs)
          Text(Fmt.duration(step.duration)).font(Typo.tabularCaption).foregroundStyle(Palette.inkMuted)
        }
        if let detail = step.detail {
          Text(detail).font(Typo.mono).foregroundStyle(Palette.inkMuted)
        }
      }
      .padding(.bottom, isLast ? 0 : Metrics.sm)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
