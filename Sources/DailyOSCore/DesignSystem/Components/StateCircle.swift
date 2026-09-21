import SwiftUI

/// The circle at the head of a call-sheet row, in its four states.
///
/// Replaces `CheckCircle` on the Today screen. A checkbox has two states and the
/// day has four: not done, done, did half of it, pushed to tomorrow. The two the
/// old control could not express are the two that describe most afternoons.
///
/// Clicking toggles only between **not done** and **done** — the one action
/// worth a 22pt target and the one people do twenty times a day. Partial and
/// deferred are deliberately not in the click cycle: cycling four states through
/// one target means every mis-click lands somewhere you have to click three more
/// times to leave. They live in `RowActionBar`, which appears on hover.
public struct StateCircle: View {
  public let state: TodoState
  public let toggle: () -> Void

  @State private var isHovering = false

  public init(state: TodoState, toggle: @escaping () -> Void) {
    self.state = state
    self.toggle = toggle
  }

  public var body: some View {
    Button(action: toggle) {
      ZStack {
        shape
      }
      .frame(width: Metrics.circleSize, height: Metrics.circleSize)
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .accessibilityLabel(label)
    .accessibilityAddTraits(state == .done ? [.isSelected] : [])
    .help(label)
  }

  @ViewBuilder private var shape: some View {
    switch state {
    case .done:
      Circle().fill(Palette.mint400)
      check.stroke(Palette.mint800, style: .init(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        .frame(width: 12, height: 12)

    case .partial:
      // Left half filled, right half empty — the shape says "halfway" without a
      // label, and reads the same at a glance as a half-filled glass.
      Circle().fill(Palette.page)
      Circle().fill(Palette.mint200).mask(alignment: .leading) {
        Rectangle().frame(width: Metrics.circleSize / 2)
      }
      Circle().strokeBorder(Palette.mint400, lineWidth: Metrics.circleStroke)

    case .deferred:
      Circle().strokeBorder(
        Palette.ink3,
        style: .init(lineWidth: Metrics.circleStroke, dash: [2.5, 2.5])
      )
      arrow.stroke(Palette.ink3, style: .init(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
        .frame(width: 11, height: 11)

    case .open, .deleted:
      Circle().fill(isHovering ? Palette.mint50 : Palette.page)
      Circle().strokeBorder(
        isHovering ? Palette.mint400 : Palette.ink3,
        lineWidth: Metrics.circleStroke
      )
    }
  }

  private var check: Path {
    Path { p in
      p.move(to: CGPoint(x: 2.5, y: 6.5))
      p.addLine(to: CGPoint(x: 5, y: 9))
      p.addLine(to: CGPoint(x: 9.5, y: 4))
    }
  }

  private var arrow: Path {
    Path { p in
      p.move(to: CGPoint(x: 2.5, y: 5.5))
      p.addLine(to: CGPoint(x: 8.5, y: 5.5))
      p.move(to: CGPoint(x: 6, y: 3))
      p.addLine(to: CGPoint(x: 8.5, y: 5.5))
      p.addLine(to: CGPoint(x: 6, y: 8))
    }
  }

  private var label: String {
    switch state {
    case .done: "已完成，点一下恢复未做"
    case .partial: "做了一部分"
    case .deferred: "顺到明天"
    case .open, .deleted: "标记完成"
    }
  }
}

// MARK: - Hover action bar

/// The four state actions, floated at the end of a row on hover.
///
/// Not permanent. Four icons on every row of a six-row sheet is twenty-four
/// controls competing with the six sentences you actually came to read — and
/// three of the four are rare. The frequent one (complete) already has the
/// circle; this is where the other three live.
///
/// Every button keeps its label as tooltip and VoiceOver name. That is the whole
/// justification for an icon-only control, and it is also why the bar is
/// reachable without a pointer: it stays in the view hierarchy and simply fades,
/// so VoiceOver and keyboard focus still find it.
public struct RowActionBar: View {
  public let state: TodoState
  public let isVisible: Bool
  /// Which states this row can actually be put into.
  ///
  /// Not every row supports all four. An inbox capture is written through the
  /// service's todo-inbox endpoint, which knows `done` / `deferred` / `open` and
  /// has no `partial` — offering the button anyway would produce a control that
  /// looks available and fails, which is worse than one that is not there.
  public let allowed: Set<TodoState>
  public let set: (TodoState) -> Void

  public init(
    state: TodoState,
    isVisible: Bool,
    allowed: Set<TodoState> = [.done, .partial, .deferred, .open],
    set: @escaping (TodoState) -> Void
  ) {
    self.state = state
    self.isVisible = isVisible
    self.allowed = allowed
    self.set = set
  }

  public var body: some View {
    HStack(spacing: 2) {
      if allowed.contains(.done) { button("完成", "checkmark", .done) }
      if allowed.contains(.partial) { button("做了一部分", "circle.lefthalf.filled", .partial) }
      if allowed.contains(.deferred) { button("顺到明天", "arrow.right", .deferred) }
      if allowed.contains(.open) { button("恢复未做", "circle", .open) }
    }
    .opacity(isVisible ? 1 : 0)
    // Not `if isVisible` — a row whose actions leave the hierarchy is a row
    // VoiceOver and the tab key cannot reach without a mouse.
    .allowsHitTesting(isVisible)
    .animation(.easeOut(duration: 0.12), value: isVisible)
  }

  private func button(_ label: String, _ symbol: String, _ target: TodoState) -> some View {
    Button { set(target) } label: {
      Image(systemName: symbol)
        .font(.system(size: 10, weight: .semibold))
        .frame(width: 20, height: 20)
        .foregroundStyle(state == target ? Palette.mint800 : Palette.ink3)
        .background(state == target ? Palette.mint200 : .clear, in: Circle())
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .help(label)
    .accessibilityLabel(label)
    .accessibilityAddTraits(state == target ? [.isSelected] : [])
  }
}
