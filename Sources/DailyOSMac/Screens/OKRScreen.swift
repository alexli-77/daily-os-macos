import SwiftUI
import DailyOSCore

/// OKR, read mostly and edited rarely.
///
/// Deliberately not a form. The objectives live in markdown next to the cycles;
/// this screen exists so that when you are writing a review you can see what you
/// said you were doing without leaving the app. Editing opens the file.
///
/// The files are tabs rather than a stack. Stacked, the annual objectives sat
/// below a scroll of quarterly ones and were effectively never seen — and the
/// two are alternatives you compare, not a sequence you read. Tabs also keep
/// the file path visible for whichever one you are actually looking at.
struct OKRScreen: View {
  @Environment(AppState.self) private var state
  @State private var selectedFileID: OkrFile.ID?

  private var current: OkrFile? {
    state.okrFiles.first { $0.id == selectedFileID } ?? state.okrFiles.first
  }

  var body: some View {
    ScreenScaffold("OKR", subtitle: current?.fileName) {
      if state.okrFiles.count > 1 {
        Picker("", selection: Binding(
          get: { current?.id ?? "" },
          set: { selectedFileID = $0 }
        )) {
          ForEach(state.okrFiles) { file in
            Text(file.label).tag(file.id)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 320, alignment: .leading)
      }

      if let file = current {
        Panel(file.label, subtitle: "\(file.objectives.count) 个目标") {
          if file.objectives.isEmpty {
            EmptyState(
              icon: "target",
              title: "这个文件里还没有目标",
              message: "在 \(file.fileName) 里写一个 Objective。"
            )
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
      } else {
        Panel {
          EmptyState(
            icon: "target",
            title: "还没有 OKR 文件",
            message: "在 10_OKR/ 下建一个 markdown 文件，这里会读它。"
          )
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
        if let priority = kr.priority {
          Pill(priority, tone: priority == "P0" ? .accent : .neutral)
        }
        Text(kr.title).inkStyle()
        Spacer(minLength: Metrics.xs)
        if let health = kr.health {
          Pill(health.label, tone: health.tone)
        }
      }
      HStack(spacing: Metrics.xs) {
        ProgressTrack(fraction: kr.progress, tone: kr.health?.tone ?? .accent)
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

// MARK: - Previews

#Preview("OKR") {
  OKRScreen()
    .environment(AppState.previewOwner())
    .frame(width: 940, height: 760)
}
