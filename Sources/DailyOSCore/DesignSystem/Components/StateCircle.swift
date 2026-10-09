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
/// times to leave. They live in `StateMenuBar`, which appears on hover.
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

    case .missed:
      // Red ring: settled as not done. Empty inside, so it never reads as done.
      Circle().fill(Palette.q1.opacity(0.08))
      Circle().strokeBorder(Palette.q1, lineWidth: Metrics.circleStroke + 0.5)

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
    case .done: "已完成，点一下撤回"
    case .partial: "做了一部分"
    case .missed: "未做"
    case .deferred: "顺到明天"
    case .open, .deleted: "标记完成"
    }
  }
}

// MARK: - Hover menu

/// What hovering the circle shows: every state a row can be put in, plus
/// delete, in one horizontal strip with words on it.
///
/// The circle stays a one-click tick; this is for the other answers. Clicking
/// the state a row is already in takes it back to not started.
public struct StateMenuBar: View {
  public enum Choice: Hashable, Sendable {
    case state(TodoState)
    case delete
  }

  public let state: TodoState
  public let choices: [Choice]
  public let pick: (Choice) -> Void

  public init(state: TodoState, choices: [Choice], pick: @escaping (Choice) -> Void) {
    self.state = state
    self.choices = choices
    self.pick = pick
  }

  public var body: some View {
    HStack(spacing: 2) {
      ForEach(choices, id: \.self) { choice in
        let isCurrent = choice == .state(state)
        Button { pick(choice) } label: {
          Label(Self.label(choice), systemImage: Self.symbol(choice))
            .labelStyle(.titleAndIcon)
            .font(Typo.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(Self.ink(choice, isCurrent: isCurrent))
            .background(isCurrent ? Self.ink(choice, isCurrent: true).opacity(0.14) : .clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointerStyleLink()
        .help(isCurrent ? "再点一下撤回" : Self.label(choice))
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
      }
    }
    .padding(3)
    .background(Palette.surface, in: Capsule())
    .overlay(Capsule().strokeBorder(Palette.line, lineWidth: Metrics.hairline))
    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
    .fixedSize()
  }

  public static func label(_ choice: Choice) -> String {
    switch choice {
    case .state(.done): "完成"
    case .state(.partial): "部分"
    case .state(.missed): "未做"
    case .state(.deferred): "顺延"
    case .state: "没开始"
    case .delete: "删除"
    }
  }

  static func symbol(_ choice: Choice) -> String {
    switch choice {
    case .state(.done): "checkmark.circle"
    case .state(.partial): "circle.lefthalf.filled"
    case .state(.missed): "xmark.circle"
    case .state(.deferred): "arrow.right.circle"
    case .state: "circle"
    case .delete: "trash"
    }
  }

  static func ink(_ choice: Choice, isCurrent: Bool) -> Color {
    switch choice {
    case .state(.missed), .delete: Palette.q1
    case .state(.done), .state(.partial): isCurrent ? Palette.mint800 : Palette.ink2
    default: Palette.ink2
    }
  }
}

extension View {
  /// The pointing hand over something clickable.
  /// `pointerStyle` where it exists: it cannot get stuck when the view goes
  /// away under the pointer, which a push/pop pair can.
  @ViewBuilder public func pointerStyleLink() -> some View {
    #if os(macOS)
    if #available(macOS 15, *) {
      pointerStyle(.link)
    } else {
      onHover { inside in
        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
      }
    }
    #else
    self
    #endif
  }
}
