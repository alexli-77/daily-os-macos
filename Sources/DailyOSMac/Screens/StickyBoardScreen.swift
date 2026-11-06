import SwiftUI
import DailyOSCore

/// 便签墙 (LEO-355 · 自由画布 LEO-356).
///
/// A free canvas of sticky notes for small things with no deadline. Nothing here
/// nags. Each note carries its own `x,y`: you drag it where you want and it stays
/// there — position is yours, not the schedule's. Spaced repetition still runs,
/// but it only flips a note's badge (💤 asleep → 🔔 awake) and shows the
/// response row in place, never moving the note. The "N surfaced today" nudge
/// lives on the Today page, not here.
///
/// Not a list screen: the whole point of a sticky wall is a note you recognise
/// by colour and *where you left it*, so these are tiles on a board you scroll in
/// two directions, not rows in a ledger.
struct StickyBoardScreen: View {
  @Environment(AppState.self) private var state
  @State private var editing: StickyDraft?

  /// Positions the user just dropped a note at, held locally so the tile lands
  /// smoothly the instant a drag ends rather than after the service round-trip.
  /// The resolved list comes back with the same coordinates, so these stay in
  /// agreement; a stale entry is harmless (it only ever equals the truth).
  @State private var dropped: [Sticky.ID: CGPoint] = [:]

  private let tileWidth: CGFloat = 200
  private let margin: CGFloat = 40

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.md) {
      header
      if state.stickies.isEmpty {
        Panel {
          EmptyState(
            icon: "note.text",
            title: "还没有便签",
            message: "记点小事——一个想法、要问的、别忘的。写下后它就钉在这块板上，你拖到哪它就待在哪；每隔几天自己醒一次（🔔）提醒你还惦记着。"
          )
        }
      } else {
        canvas
      }
    }
    .padding(Metrics.screenPadding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(Palette.chatCanvas)
    .sheet(item: $editing) { draft in
      StickyEditor(
        draft: draft,
        onSave: { saved in
          editing = nil
          let spot: StickyPoint? = draft.id == nil ? { let p = newSpot(); return StickyPoint(x: Double(p.x), y: Double(p.y)) }() : nil
          run { await state.saveSticky(saved, at: spot) }
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

  // MARK: Header

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      (Text("便签").font(Typo.display).foregroundColor(Palette.ink)
        + Text(subtitle.map { "    \($0)" } ?? "").font(Typo.caption).foregroundColor(Palette.ink2))
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: Metrics.sm)
      Button("写一张") { editing = StickyDraft() }
        .buttonStyle(MossButtonStyle())
    }
  }

  private var subtitle: String? {
    guard !state.stickies.isEmpty else { return nil }
    let up = state.stickies.filter(\.surfacing).count
    if up == 0 { return "都在睡 · 拖着随便摆" }
    return "\(up) 张冒头了（🔔）· 拖着随便摆"
  }

  // MARK: Canvas

  private var canvas: some View {
    let placed = layout()
    let bounds = canvasBounds(placed)
    return ScrollView([.horizontal, .vertical]) {
      ZStack(alignment: .topLeading) {
        // A faint board so the scrollable area reads as a surface, not a void.
        RoundedRectangle(cornerRadius: Metrics.radiusMedium, style: .continuous)
          .fill(Palette.surface.opacity(0.4))
          .frame(width: bounds.width, height: bounds.height)

        ForEach(placed, id: \.item.id) { entry in
          StickyTile(
            item: entry.item,
            position: entry.point,
            width: tileWidth,
            onMove: { commitMove(entry.item.id, to: $0) },
            onEdit: { editing = StickyDraft(editing: entry.item) },
            onArchive: { run { await state.archiveSticky(entry.item.id) } },
            onRespond: { response in run { await state.surfaceSticky(entry.item.id, response) } }
          )
        }
      }
      .frame(width: bounds.width, height: bounds.height, alignment: .topLeading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusMedium, style: .continuous))
  }

  // MARK: Placement

  private struct Placed { let item: Sticky; let point: CGPoint }

  /// Resolve every note to a point: the spot just dropped, else the note's own
  /// saved `x,y`, else a tidy grid slot for notes not placed yet (written before
  /// the canvas, or just created) — those persist a real position on first drag.
  private func layout() -> [Placed] {
    var unplaced = 0
    return state.stickies.map { item in
      let point: CGPoint
      if let drop = dropped[item.id] {
        point = drop
      } else if let x = item.x, let y = item.y {
        point = CGPoint(x: x, y: y)
      } else {
        point = gridSlot(unplaced)
        unplaced += 1
      }
      return Placed(item: item, point: point)
    }
  }

  private func gridSlot(_ index: Int) -> CGPoint {
    let columns = 3
    let col = index % columns
    let row = index / columns
    return CGPoint(x: margin + CGFloat(col) * (tileWidth + 30), y: margin + CGFloat(row) * 170)
  }

  /// A cascading spot for a brand-new note, nudged by how many already exist so
  /// it does not land exactly on top of the last one.
  private func newSpot() -> CGPoint {
    let n = state.stickies.count
    return CGPoint(x: margin + CGFloat(n % 6) * 26, y: margin + CGFloat(n % 6) * 26)
  }

  private func canvasBounds(_ placed: [Placed]) -> CGSize {
    let right = placed.map { $0.point.x }.max() ?? 0
    let bottom = placed.map { $0.point.y }.max() ?? 0
    // Generous tile-height allowance so a long note near the edge still has room.
    return CGSize(width: max(1000, right + tileWidth + margin), height: max(680, bottom + 220 + margin))
  }

  private func commitMove(_ id: Sticky.ID, to point: CGPoint) {
    // Never off the top-left edge, so a note can't be lost behind the origin.
    let clamped = CGPoint(x: max(margin / 2, point.x), y: max(margin / 2, point.y))
    dropped[id] = clamped
    run { await state.moveSticky(id, to: StickyPoint(x: Double(clamped.x), y: Double(clamped.y))) }
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
  let position: CGPoint
  let width: CGFloat
  let onMove: (CGPoint) -> Void
  let onEdit: () -> Void
  let onArchive: () -> Void
  let onRespond: (SurfaceResponse) -> Void

  @GestureState private var translation: CGSize = .zero
  @State private var dragging = false
  @State private var hovering = false

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xs) {
      HStack(alignment: .top, spacing: Metrics.xs) {
        badge
        Text(item.text)
          .font(Typo.body)
          .foregroundStyle(Self.ink)
          .frame(maxWidth: .infinity, alignment: .leading)
          .multilineTextAlignment(.leading)
          .lineLimit(item.surfacing ? 7 : 4)
          .fixedSize(horizontal: false, vertical: true)
      }

      if item.surfacing {
        Divider().overlay(Self.ink.opacity(0.18))
        HStack(spacing: Metrics.xs) {
          response("完成", .done)
          response("还惦记", .keep)
          response("知道了", .ok)
        }
      }
    }
    .padding(Metrics.sm)
    .frame(width: width, alignment: .topLeading)
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
        tileButton("xmark", help: item.surfacing ? "收起来" : "不用了，收起来", action: onArchive)
      }
      .padding(Metrics.xs)
      .opacity(hovering && !dragging ? 1 : 0)
    }
    .shadow(color: .black.opacity(dragging ? 0.18 : 0.06), radius: dragging ? 10 : 3, y: dragging ? 6 : 1)
    .opacity(item.surfacing ? 1 : 0.82)
    .offset(x: position.x + translation.width, y: position.y + translation.height)
    .zIndex(dragging ? 1 : 0)
    .onHover { hovering = $0 }
    .onTapGesture(count: 2, perform: onEdit)
    .gesture(
      // minimumDistance keeps a click on a button a click, not a micro-drag.
      DragGesture(minimumDistance: 6, coordinateSpace: .local)
        .updating($translation) { value, state, _ in state = value.translation }
        .onChanged { _ in if !dragging { dragging = true } }
        .onEnded { value in
          dragging = false
          onMove(CGPoint(x: position.x + value.translation.width, y: position.y + value.translation.height))
        }
    )
    .animation(.easeInOut(duration: 0.12), value: dragging)
    .animation(.easeInOut(duration: 0.12), value: hovering)
  }

  /// The state corner mark the user asked for: 💤 asleep, 🔔 awake. Small and
  /// quiet — a mark, not a button.
  private var badge: some View {
    Text(item.surfacing ? "🔔" : "💤")
      .font(.system(size: 12))
      .frame(width: 20, height: 20)
      .background(Self.ink.opacity(0.06))
      .clipShape(Circle())
      .help(item.surfacing ? "今天冒头了" : "沉睡中")
      .accessibilityLabel(item.surfacing ? "冒头" : "沉睡")
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

  /// A sticky is always a scrap of coloured paper, so its ink is a fixed light
  /// tone — independent of the app's light/dark theme, which would otherwise
  /// flip it to white on these pastels and make it unreadable.
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

      Text("便签没有截止日。写下后它钉在板上，你拖到哪就待在哪；每隔几天自己醒一次来找你，你回应得越从容，它就睡得越久。")
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
      Text("它会从板上拿掉，不再冒头。")
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
