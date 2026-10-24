import SwiftUI

/// The chat entry/assistant mark (LEO-346): the seven-ring mark inside a speech
/// bubble, in the app icon's own deep-green gradient. Reuses `DailyOSMark` so the
/// seven life areas stay byte-identical to the app icon; the bubble just says
/// "this is where you talk to it".
///
/// Fixed brand greens, not theme colours — like the app icon, the mark reads the
/// same in light and dark.
public struct ChatBotMark: View {
  private let paper = Color(hex: 0xF6F7F4)

  public init() {}

  public var body: some View {
    GeometryReader { geo in
      let side = min(geo.size.width, geo.size.height)
      ChatBubbleShape(tail: side * 0.18)
        .fill(Palette.chatAccent)
        .overlay {
          // One white ring in the bubble body (above the tail) — concept C, a
          // nod to the app icon's rings without the seven-dot crowding.
          Circle()
            .strokeBorder(paper, lineWidth: side * 0.082)
            .frame(width: side * 0.34, height: side * 0.34)
            .offset(y: -side * 0.08)
        }
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityHidden(true)
  }
}

public extension Palette {
  /// The app-wide canvas (LEO-346): a faint green-tinted near-white, the gradient
  /// canvas's top tone. Replaces the old warm grey behind every screen.
  static let appCanvas = Color(light: Color(hex: 0xFBFCFB), dark: Color(hex: 0x181D1A))

  /// The chat's moss-green accent — the bot mark bubble and the send button.
  /// A mid moss gradient, matching the "执行情况" bar-chart icon's green family.
  static let chatAccent = LinearGradient(
    gradient: Gradient(colors: [Color(hex: 0x3C9D80), Color(hex: 0x256E58)]),
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  /// The chat window's soft green canvas (LEO-346): pale mint in light mode,
  /// deep green in dark. The app icon's green family, kept pale enough that
  /// white cards and text stay legible on top.
  static let chatCanvas = LinearGradient(
    gradient: Gradient(colors: [
      Color(light: Color(hex: 0xFBFCFB), dark: Color(hex: 0x202522)),
      Color(light: Color(hex: 0xEAEFEB), dark: Color(hex: 0x191E1A)),
      Color(light: Color(hex: 0xD2DCD4), dark: Color(hex: 0x121613)),
    ]),
    startPoint: .top,
    endPoint: .bottom
  )
}

/// The chat panel toggle, handed down from the Mac shell so each screen's
/// header can draw the assistant entry itself (see `ScreenScaffold`). Nil off
/// the Mac shell, so other hosts simply show no entry.
public struct ChatEntryActionKey: EnvironmentKey {
  // `nonisolated(unsafe)`: the value is a constant nil and is only ever read on
  // the main actor during view updates, so there is no shared mutable state to
  // race. Keeping the plain (non-`@Sendable`) closure type lets the Mac shell
  // inject a closure that captures its main-actor `AppState`.
  public nonisolated(unsafe) static let defaultValue: (() -> Void)? = nil
}

public extension EnvironmentValues {
  var chatEntryAction: (() -> Void)? {
    get { self[ChatEntryActionKey.self] }
    set { self[ChatEntryActionKey.self] = newValue }
  }
}

/// A rounded speech bubble with a short tail at the bottom-left.
public struct ChatBubbleShape: Shape {
  public var tail: CGFloat

  public init(tail: CGFloat = 8) {
    self.tail = tail
  }

  public func path(in rect: CGRect) -> Path {
    // The bubble body occupies the top ~82%; the tail drops from the lower-left.
    let bodyHeight = rect.height - tail
    let body = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: bodyHeight)
    let radius = min(body.width, body.height) * 0.26
    var path = Path(roundedRect: body, cornerRadius: radius)

    let tailX = rect.minX + rect.width * 0.26
    var tailPath = Path()
    tailPath.move(to: CGPoint(x: tailX, y: body.maxY - radius * 0.3))
    tailPath.addLine(to: CGPoint(x: tailX - tail * 0.5, y: rect.maxY))
    tailPath.addLine(to: CGPoint(x: tailX + tail * 1.4, y: body.maxY - radius * 0.3))
    tailPath.closeSubpath()
    path.addPath(tailPath)
    return path
  }
}
