import SwiftUI
import DailyOSCore

/// OKR, read mostly and edited rarely.
///
/// Deliberately not a form. The objectives live in markdown next to the cycles;
/// this screen exists so that when you are writing a review you can see what you
/// said you were doing without leaving the app. Editing opens the file.
struct OKRScreen: View {
  @Environment(AppState.self) private var state

  var body: some View {
    ScreenScaffold("OKR", subtitle: "来自 10_OKR/ 的快照") {
      ForEach(state.okrFiles) { file in
        Panel(file.label, subtitle: file.fileName) {
          if file.objectives.isEmpty {
            EmptyState(icon: "target", title: "这个文件里还没有目标", message: "在 \(file.fileName) 里写一个 Objective。")
          } else {
            VStack(spacing: Metrics.md) {
              ForEach(Array(file.objectives.enumerated()), id: \.element.id) { index, objective in
                if index > 0 { PanelDivider() }
                ObjectiveBlock(objective: objective)
              }
            }
          }
        } actions: {
          Button("打开文件") {}.buttonStyle(QuietButtonStyle())
        }
      }
    }
  }
}

private struct ObjectiveBlock: View {
  let objective: Objective

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.sm) {
      HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
        Text(objective.id).font(Typo.mono).foregroundStyle(Palette.moss)
        Text(objective.title).inkStyle(Typo.heading)
        Spacer(minLength: Metrics.xs)
        Text("\(Int(objective.progress * 100))%")
          .font(Typo.tabularCaption)
          .foregroundStyle(Palette.inkMuted)
      }
      ForEach(objective.keyResults) { KeyResultRow(kr: $0) }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct KeyResultRow: View {
  let kr: KeyResult

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xxs) {
      HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
        Pill(kr.priority, tone: kr.priority == "P0" ? .accent : .neutral)
        Text(kr.title).inkStyle()
        Spacer(minLength: Metrics.xs)
        Pill(kr.health.label, tone: kr.health.tone)
      }
      HStack(spacing: Metrics.xs) {
        ProgressTrack(fraction: kr.progress, tone: kr.health.tone)
        Text("\(Int(kr.progress * 100))%")
          .font(Typo.tabularCaption)
          .foregroundStyle(Palette.inkMuted)
          .frame(width: 38, alignment: .trailing)
      }
      if let detail = kr.detail {
        Text(detail).mutedStyle()
      }
    }
    .padding(.vertical, Metrics.xxs)
  }
}
