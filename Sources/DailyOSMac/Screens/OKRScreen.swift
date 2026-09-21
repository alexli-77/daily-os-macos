import SwiftUI
import DailyOSCore

/// OKR, read mostly and edited rarely.
///
/// Deliberately not a form. The objectives live in markdown next to the cycles;
/// this screen exists so that when you are writing a review you can see what you
/// said you were doing without leaving the app. Editing is the raw file, behind
/// a 编辑 toggle — see `OKRFilePanel`.
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
        OKRFilePanel(file: file)
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

/// One OKR file, read or edited in place.
///
/// The screen used to carry a 打开文件 button whose action was an empty closure:
/// it looked live, answered nothing, and the only way to change an objective was
/// to find the markdown yourself. The comment above this screen said editing
/// "opens the file", and nothing opened anything.
///
/// 阅读 stays the default, which is what that older decision was protecting —
/// objectives are written a few times a year and consulted whenever a review
/// gets drafted, so the glance must not have a text box in front of it. A
/// toggle costs that glance nothing and gives the other case somewhere to
/// happen. Same control, same wording and same save rule as a 周期 section, so
/// the two screens teach each other.
///
/// The draft survives switching to 阅读 — the toggle can never eat typing, so
/// it needs no confirmation.
private struct OKRFilePanel: View {
  @Environment(AppState.self) private var state
  let file: OkrFile

  @State private var mode: EditorMode = .read
  @State private var draft: String?

  private var isDirty: Bool {
    guard let draft else { return false }
    return draft != file.markdown
  }

  var body: some View {
    Panel(file.label, subtitle: subtitle) {
      if mode == .edit {
        VStack(alignment: .leading, spacing: Metrics.xs) {
          MarkdownEditor(text: Binding(
            get: { draft ?? file.markdown },
            set: { draft = $0 }
          ))
          HintText("整份文件，原样写回。表格格式不确定时，「设置 → OKR」那边有「整理格式」。")
        }
      } else if file.objectives.isEmpty {
        EmptyState(
          icon: "target",
          title: "这个文件里还没有目标",
          message: "切到「编辑」写一个 Objective，或者在 \(file.fileName) 里写。"
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
      if isDirty { Pill("未保存", tone: .warn) }
      EditorModePicker(mode: $mode)
      if mode == .edit {
        Button("保存") {
          state.updateOkrFile(id: file.id, markdown: draft ?? file.markdown)
          draft = nil
          mode = .read
        }
        .buttonStyle(QuietButtonStyle())
        .disabled(!isDirty)
      }
    }
  }

  private var subtitle: String {
    mode == .edit ? file.fileName : "\(file.objectives.count) 个目标"
  }
}

/// Shared with the 周期 screen's OKR panel, so an objective looks the same
/// wherever it is read.
struct ObjectiveBlock: View {
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
