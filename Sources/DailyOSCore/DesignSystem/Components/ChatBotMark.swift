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
  private static let bubbleGradient = Gradient(colors: [Color(hex: 0x2A8B6E), Color(hex: 0x14533F)])

  public init() {}

  public var body: some View {
    GeometryReader { geo in
      let side = min(geo.size.width, geo.size.height)
      ChatBubbleShape(tail: side * 0.18)
        .fill(LinearGradient(gradient: Self.bubbleGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay {
          // The seven dots sit in the bubble body (above the tail), centred.
          DailyOSMark(style: .solid, tint: paper)
            .frame(width: side * 0.52, height: side * 0.52)
            .offset(y: -side * 0.07)
        }
    }
    .aspectRatio(1, contentMode: .fit)
    .accessibilityHidden(true)
  }
}

public extension Palette {
  /// The chat window's soft green canvas (LEO-346): pale mint in light mode,
  /// deep green in dark. The app icon's green family, kept pale enough that
  /// white cards and text stay legible on top.
  static let chatCanvas = LinearGradient(
    gradient: Gradient(colors: [
      Color(light: Color(hex: 0xF4F9F5), dark: Color(hex: 0x16251D)),
      Color(light: Color(hex: 0xE8F2EB), dark: Color(hex: 0x112019)),
      Color(light: Color(hex: 0xD7ECDF), dark: Color(hex: 0x0E1B15)),
    ]),
    startPoint: .top,
    endPoint: .bottom
  )
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
