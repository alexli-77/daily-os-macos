import SwiftUI
import DailyOSCore

/// 便签墙 (LEO-355).
///
/// A wall of sticky notes for small things with no deadline. Nothing here nags:
/// notes resurface on a spaced-repetition schedule, and the wall simply shows
/// the ones that woke up today at the top — bright and full-size — with the rest
/// sleeping below, dimmed. You deal with a surfaced note by answering it (完成 /
/// 还惦记 / 知道了), which reschedules when it next comes to find you.
///
/// Tiles rather than rows, unlike every other list screen: the whole point of a
/// sticky wall is that a note is a physical-feeling scrap you recognise by its
/// colour and position, not a line in a ledger.
struct StickyBoardScreen: View {
  @Environment(AppState.self) private var state
  @State private var editing: StickyDraft?

  private var bands: (surfacing: [Sticky], sleeping: [Sticky]) { Sticky.partition(state.stickies) }

  var body: some View {
    ScreenScaffold("便签", subtitle: subtitle) {
      if state.stickies.isEmpty {
        Panel {
          EmptyState(
            icon: "note.text",
            title: "还没有便签",
            message: "记点小事——一个想法、要问的、别忘的。它们不会催你，只会每隔几天自己冒上来一次，提醒你还惦记着。"
          )
        }
      } else {
        if !bands.surfacing.isEmpty {
          Panel("冒头了", subtitle: "想起这些了吗？回应一下，它就安静一阵") {
            grid(bands.surfacing, surfacing: true)
          }
        }
        if !bands.sleeping.isEmpty {
          Panel("沉睡中", subtitle: "过些天会轮到它们") {
            grid(bands.sleeping, surfacing: false)
          }
        }
      }
    } toolbar: {
      Button("写一张") { editing = StickyDraft() }
        .buttonStyle(MossButtonStyle())
    }
    .sheet(item: $editing) { draft in
      StickyEditor(
        draft: draft,
        onSave: { saved in
          editing = nil
          run { await state.saveSticky(saved) }
        },
        onDelete: draft.id.map { id in
          {
            editing = nil
            run { await state.archiveSticky(id) }
          }
        },
        onCancel: { editing = nil }
      )
    }
  }

  private var subtitle: String? {
    guard !state.stickies.isEmpty else { return nil }
    let up = bands.surfacing.count
    let asleep = bands.sleeping.count
    if up == 0 { return "\(asleep) 张都在睡，没有冒头的" }
    return "\(up) 张冒头了 · \(asleep) 张在睡"
  }

  private func grid(_ items: [Sticky], surfacing: Bool) -> some View {
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 200, maximum: 300), spacing: Metrics.sm, alignment: .top)],
      spacing: Metrics.sm
    ) {
      ForEach(items) { item in
        StickyTile(
          item: item,
          surfacing: surfacing,
          onEdit: { editing = StickyDraft(editing: item) },
          onArchive: { run { await state.archiveSticky(item.id) } },
          onRespond: { response in run { await state.surfaceSticky(item.id, response) } }
        )
      }
    }
  }

  private func run(_ action: @escaping () async -> AppState.ActionOutcome) {
    Task {
      switch await action() {
      case .ok(let message): if let message { state.toast = message }
      case .failed(let why), .unsupported(let why): state.toast = why
      }
    }
  }
}

// MARK: - Tile

private struct StickyTile: View {
  let item: Sticky
  let surfacing: Bool
  let onEdit: () -> Void
  let onArchive: () -> Void
  let onRespond: (SurfaceResponse) -> Void

  @State private var hovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.sm) {
      Text(item.text)
        .font(Typo.body)
        .foregroundStyle(Self.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
        .lineLimit(surfacing ? 8 : 4)
        .fixedSize(horizontal: false, vertical: true)

      if surfacing {
        Divider().overlay(Self.ink.opacity(0.18))
        HStack(spacing: Metrics.xs) {
          response("完成", .done)
          response("还惦记", .keep)
          response("知道了", .ok)
        }
      }
    }
    .padding(Metrics.md)
    .frame(maxWidth: .infinity, minHeight: surfacing ? 128 : 92, alignment: .topLeading)
    .background(StickyTileFill.of(item.color))
    .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusMedium, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Metrics.radiusMedium, style: .continuous)
        .strokeBorder(Self.ink.opacity(0.10), lineWidth: Metrics.hairline)
    )
    .overlay(alignment: .topTrailing) {
      // Edit + put-away, revealed on hover so a resting tile is just the note.
      HStack(spacing: Metrics.xxs) {
        tileButton("pencil", help: "改一下", action: onEdit)
        tileButton("xmark", help: surfacing ? "收起来" : "不用了，收起来", action: onArchive)
      }
      .padding(Metrics.xs)
      .opacity(hovering ? 1 : 0)
    }
    .opacity(surfacing ? 1 : 0.68)
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .onTapGesture(count: 2, perform: onEdit)
    .animation(.easeInOut(duration: 0.12), value: hovering)
  }

  private func response(_ label: String, _ value: SurfaceResponse) -> some View {
    Button(label) { onRespond(value) }
      .buttonStyle(.plain)
      .font(Typo.caption)
      .foregroundStyle(Self.ink.opacity(0.85))
      .padding(.vertical, 3)
      .padding(.horizontal, Metrics.xs)
      .background(Self.ink.opacity(hovering ? 0.08 : 0.0))
      .clipShape(Capsule())
  }

  private func tileButton(_ icon: String, help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Self.ink.opacity(0.7))
        .padding(5)
        .background(Self.ink.opacity(0.08))
        .clipShape(Circle())
    }
    .buttonStyle(.plain)
    .help(help)
  }

  /// A sticky is always a scrap of coloured paper, so its fill and ink are fixed
  /// light tones — independent of the app's light/dark theme, which would
  /// otherwise flip the ink to white on these pastels and make it unreadable.
  static let ink = Color(red: 0.20, green: 0.18, blue: 0.14)
}

// MARK: - Editor

/// One sheet for both creating and editing; `onDelete` present means editing.
private struct StickyEditor: View {
  @State var draft: StickyDraft
  let onSave: (StickyDraft) -> Void
  let onDelete: (() -> Void)?
  let onCancel: () -> Void

  @State private var confirmingDelete = false

  init(
    draft: StickyDraft,
    onSave: @escaping (StickyDraft) -> Void,
    onDelete: (() -> Void)?,
    onCancel: @escaping () -> Void
  ) {
    _draft = State(initialValue: draft)
    self.onSave = onSave
    self.onDelete = onDelete
    self.onCancel = onCancel
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.md) {
      Text(onDelete == nil ? "写一张便签" : "改一下").inkStyle(Typo.heading)

      TextField("记点什么", text: $draft.text, axis: .vertical)
        .textFieldStyle(.roundedBorder)
        .lineLimit(3...8)

      HStack(spacing: Metrics.sm) {
        ForEach(Sticky.Color.allCases) { color in
          Swatch(color: color, selected: draft.color == color) { draft.color = color }
        }
      }

      Text("便签没有截止日。写下后，它会每隔几天自己冒到墙顶来找你一次；你回应得越从容，它就睡得越久。")
        .mutedStyle(Typo.caption)
        .fixedSize(horizontal: false, vertical: true)

      HStack {
        if onDelete != nil {
          Button("删除", role: .destructive) { confirmingDelete = true }
            .buttonStyle(QuietButtonStyle())
        }
        Spacer()
        Button("取消", action: onCancel).buttonStyle(QuietButtonStyle())
        Button("保存") { onSave(draft) }
          .buttonStyle(MossButtonStyle())
          .disabled(!draft.isValid)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(Metrics.lg)
    .frame(width: 380)
    .background(Palette.page)
    .confirmationDialog("收起这张便签？", isPresented: $confirmingDelete) {
      Button("收起来", role: .destructive) { onDelete?() }
      Button("算了", role: .cancel) {}
    } message: {
      Text("它会从墙上拿掉，不再冒头。")
    }
  }

  private struct Swatch: View {
    let color: Sticky.Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
      Button(action: action) {
        Circle()
          .fill(StickyTileFill.of(color))
          .frame(width: 26, height: 26)
          .overlay(
            Circle().strokeBorder(
              selected ? Palette.ink : Color(red: 0.20, green: 0.18, blue: 0.14).opacity(0.18),
              lineWidth: selected ? 2 : 1
            )
          )
      }
      .buttonStyle(.plain)
      .help(color.label)
    }
  }
}

/// The tile fill, shared so the editor's swatches match the wall exactly.
private enum StickyTileFill {
  static func of(_ color: Sticky.Color) -> Color {
    switch color {
    case .yellow: Color(red: 0.98, green: 0.93, blue: 0.72)
    case .pink: Color(red: 0.97, green: 0.84, blue: 0.86)
    case .blue: Color(red: 0.81, green: 0.89, blue: 0.96)
    case .green: Color(red: 0.84, green: 0.92, blue: 0.80)
    case .gray: Color(red: 0.91, green: 0.90, blue: 0.86)
    }
  }
}

// MARK: - Previews

#Preview("便签") {
  StickyBoardScreen()
    .environment(AppState.previewOwner())
    .frame(width: 940, height: 760)
}

#Preview("便签 · 空") {
  let state = AppState.previewOwner()
  state.stickies = []
  return StickyBoardScreen()
    .environment(state)
    .frame(width: 940, height: 760)
}
