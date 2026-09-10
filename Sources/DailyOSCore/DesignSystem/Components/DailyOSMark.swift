import SwiftUI

/// The seven-ring mark.
///
/// Drawn rather than borrowed. It began as the `circle.hexagongrid` SF Symbol,
/// which is a fine placeholder and a bad thing to own a brand: you cannot
/// animate its parts, you cannot render it into an app icon without shipping
/// Apple's glyph, and it changes when Apple changes it.
///
/// Six rings around one is also the arrangement the product argues for — a
/// cycle is one thing surrounded by the six that feed it — so the pieces are
/// individually addressable on purpose. `Motion` is what that buys.
public struct DailyOSMark: View {
  public enum Motion: Equatable {
    /// A logo. Nothing moves.
    case still
    /// Waiting on something with no progress to report: the outer rings fill
    /// one after another, forever. Deliberately not a spinner — a spinner says
    /// "the system is busy", and what this screen means is "we are looking for
    /// your service", which has a direction and an order to it.
    case searching
    /// It worked. One settling pulse outward, then still.
    case settled
  }

  /// How each of the seven is drawn.
  public enum Style: Equatable {
    /// Outlined. The mark proper — needs roughly 24pt to hold together.
    case rings
    /// Filled discs. For 16–32pt, where the hole in a ring is smaller than a
    /// pixel and seven of them average out into a smudge. Not a different logo:
    /// same seven positions, same pitch, just without the detail that cannot
    /// survive the size. A mark that is unreadable small is a mark you end up
    /// replacing with a letter.
    case solid
  }

  private let motion: Motion
  private let style: Style
  private let tint: Color
  private let centerTint: Color?

  public init(
    motion: Motion = .still,
    style: Style = .rings,
    tint: Color = Palette.moss,
    centerTint: Color? = nil
  ) {
    self.motion = motion
    self.style = style
    self.tint = tint
    self.centerTint = centerTint
  }

  /// Where the six outer rings sit, in units of the ring pitch, starting at the
  /// top and going clockwise. A flat-top hexagon: `cos30 ≈ 0.866`.
  public static let outerOffsets: [CGPoint] = (0..<6).map { index in
    let angle = Double(index) * .pi / 3 - .pi / 2
    return CGPoint(x: cos(angle), y: sin(angle))
  }

  @State private var phase = 0
  @State private var hasSettled = false

  public var body: some View {
    GeometryReader { geo in
      let side = min(geo.size.width, geo.size.height)
      // Three ring-widths across plus a hair of margin. Solving for the pitch
      // rather than hard-coding it keeps the mark identical at 16pt and 1024pt,
      // which is the whole reason the icon can be generated from this view.
      let pitch = side / 3.05
      // Solid discs are drawn a touch smaller: a filled circle reads visually
      // larger than an outlined one of the same diameter, and at matching sizes
      // the six outer discs close up into a hexagon with no gaps.
      let diameter = pitch * (style == .solid ? 0.84 : 0.94)
      let lineWidth = max(diameter * 0.17, 0.75)
      let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

      ZStack {
        ring(diameter: diameter, lineWidth: lineWidth, color: centerTint ?? tint, lit: true, index: -1)
          .position(center)

        ForEach(Array(Self.outerOffsets.enumerated()), id: \.offset) { index, offset in
          ring(
            diameter: diameter,
            lineWidth: lineWidth,
            color: tint,
            lit: isLit(index),
            index: index
          )
          .position(x: center.x + offset.x * pitch, y: center.y + offset.y * pitch)
        }
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .onAppear(perform: start)
    .onChange(of: motion) { _, _ in start() }
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private func ring(diameter: CGFloat, lineWidth: CGFloat, color: Color, lit: Bool, index: Int) -> some View {
    Group {
      switch style {
      case .rings:
        Circle()
          .strokeBorder(color, lineWidth: lineWidth)
          .background(Circle().fill(color.opacity(lit ? 0.22 : 0)))
      case .solid:
        Circle().fill(color)
      }
    }
      .frame(width: diameter, height: diameter)
      .opacity(lit ? 1 : 0.28)
      .scaleEffect(lit ? 1 : 0.9)
      // Each ring animates on its own clock, so the sweep reads as six things
      // happening in order rather than one thing changing shape.
      .animation(.easeOut(duration: 0.42), value: lit)
  }

  /// Which rings are drawn full strength.
  ///
  /// `searching` lights a moving pair rather than a single ring: one lit dot
  /// chasing round a circle at this size is a very small thing to look at, and
  /// two adjacent ones read as motion instead of as flicker.
  private func isLit(_ index: Int) -> Bool {
    switch motion {
    case .still: true
    case .settled: hasSettled
    case .searching: index == phase % 6 || index == (phase + 1) % 6
    }
  }

  private func start() {
    switch motion {
    case .still:
      break
    case .settled:
      hasSettled = false
      withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { hasSettled = true }
    case .searching:
      phase = 0
      Task { @MainActor in
        // Stops when the view goes away or the mode changes — `motion` is
        // captured per invocation, so a stale loop cannot keep animating a mark
        // that has already connected.
        while !Task.isCancelled, motion == .searching {
          try? await Task.sleep(for: .milliseconds(260))
          phase += 1
        }
      }
    }
  }
}

#Preview("标记") {
  HStack(spacing: 40) {
    DailyOSMark(motion: .still).frame(width: 72, height: 72)
    DailyOSMark(motion: .searching).frame(width: 72, height: 72)
    DailyOSMark(motion: .settled).frame(width: 72, height: 72)
  }
  .padding(40)
  .background(Palette.paper)
}
