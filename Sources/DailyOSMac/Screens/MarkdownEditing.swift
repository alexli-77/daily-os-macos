import SwiftUI
import DailyOSCore

/// 阅读 / 编辑, and the box you type the markdown in.
///
/// Every file this app lets you edit is markdown somebody also edits by hand —
/// cycles, OKR, the rhythm notes. They all want the same two modes for the same
/// reason: the rendered view is what you use, and the raw view is the escape
/// hatch for everything the renderer does not know about, which in a hand-edited
/// file is always something.
///
/// `CyclesScreen` has its own private copy of this enum from before these were
/// shared. Left alone deliberately — it works, and folding a working screen into
/// a new abstraction is a bigger change than the one being asked for.

enum EditorMode: String, CaseIterable, Identifiable {
  case read
  case edit

  var id: String { rawValue }
  var label: String { self == .read ? "阅读" : "编辑" }
}

/// The segmented control, sized so both labels fit without truncating.
struct EditorModePicker: View {
  @Binding var mode: EditorMode

  var body: some View {
    Picker("", selection: $mode) {
      ForEach(EditorMode.allCases) { Text($0.label).tag($0) }
    }
    .pickerStyle(.segmented)
    .labelsHidden()
    .frame(width: 130)
  }
}

/// A markdown text box that reads as one.
///
/// Deliberately not `OutputBlock`'s styling. The two sat next to each other on
/// the rhythm page — an editable editor above a read-only example — drawn with
/// the same background and the same hairline border, and the honest report from
/// the person using it was that the editor "也不能修改". It was editable the
/// whole time; nothing about it said so.
///
/// So: a paper background rather than the sunken one the read-only blocks use,
/// and a heavier border. Monospaced because every file behind this is markdown
/// with tables in it, and a proportional font makes a misaligned `|` invisible.
struct MarkdownEditor: View {
  @Binding var text: String
  var height: CGFloat = 340

  var body: some View {
    TextEditor(text: $text)
      .font(Typo.monoBody)
      .foregroundStyle(Palette.ink)
      .scrollContentBackground(.hidden)
      .padding(Metrics.xs)
      .frame(height: height)
      .background(Palette.surface)
      .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous)
          .strokeBorder(Palette.line, lineWidth: 1.5)
      )
  }
}
