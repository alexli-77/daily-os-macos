import SwiftUI

/// The accent button.
///
/// `prominent` is the filled variant and there is at most one per screen region
/// — the thing you came to this screen to do. Everything else is the quiet
/// bordered variant. This is the rule that keeps a settings screen with fourteen
/// controls from looking like a slot machine.
public struct MossButtonStyle: ButtonStyle {
  private let prominent: Bool
  private let tone: Tone

  public init(prominent: Bool = true, tone: Tone = .accent) {
    self.prominent = prominent
    self.tone = tone
  }

  public func makeBody(configuration: Configuration) -> some View {
    // A prominent button is a tinted block with ink on it, not a dark block with
    // white on it. The old version filled with the accent and wrote `Color.white`
    // — a hardcoded colour, in the one palette rule that has no exceptions:
    // nothing in light mode is white-on-dark. `mint200` + `mint800` is what the
    // token table says a primary button is, and it reads as part of the paper
    // rather than as a sticker pressed onto it.
    //
    // Round, not 4pt. `Metrics` states the rule itself — "anything you can
    // press" is `radiusPill` — and this style, the most-pressed thing in the
    // app, was the one place contradicting it. `Panel` and `WeatherStrip` stay
    // on `radiusPaper`: they are surfaces, and the split the radius scale
    // encodes is surface versus control, not big versus small.
    let shape = RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous)
    return configuration.label
      .font(Typo.body.weight(.medium))
      .foregroundStyle(Palette.foreground(for: tone))
      .padding(.horizontal, Metrics.sm)
      .frame(minHeight: Metrics.hitTarget)
      .background {
        shape.fill(prominent ? Palette.softBackground(for: tone) : Palette.page)
      }
      .overlay {
        if !prominent {
          shape.strokeBorder(Palette.rule, lineWidth: Metrics.hairline)
        }
      }
      .opacity(configuration.isPressed ? 0.72 : 1)
      .contentShape(shape)
  }
}

/// A borderless text action for panel headers ("编辑", "重跑", "查看全部").
public struct QuietButtonStyle: ButtonStyle {
  private let tone: Tone
  public init(tone: Tone = .accent) { self.tone = tone }

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(Typo.caption.weight(.medium))
      .foregroundStyle(Palette.foreground(for: tone))
      .padding(.horizontal, Metrics.xs)
      .frame(minHeight: Metrics.hitTarget)
      .opacity(configuration.isPressed ? 0.6 : 1)
      .contentShape(Rectangle())
  }
}

/// A round checkbox for todo rows. Deliberately not `Toggle`: on macOS a Toggle
/// renders as a system checkbox and on iOS as a switch, and a todo list needs
/// the same affordance on both.
public struct CheckCircle: View {
  private let isOn: Bool
  private let action: () -> Void

  public init(isOn: Bool, action: @escaping () -> Void) {
    self.isOn = isOn
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      ZStack {
        Circle()
          .strokeBorder(isOn ? Palette.moss : Palette.line, lineWidth: 1.5)
          .frame(width: 18, height: 18)
        if isOn {
          Image(systemName: "checkmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Palette.moss)
        }
      }
      .frame(width: Metrics.hitTarget, height: Metrics.hitTarget, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
  }
}
