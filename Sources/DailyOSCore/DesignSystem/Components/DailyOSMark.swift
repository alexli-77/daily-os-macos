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
  private let gradient: Gradient?

  public init(
    motion: Motion = .still,
    style: Style = .rings,
    tint: Color = Palette.moss,
    centerTint: Color? = nil,
    gradient: Gradient? = nil
  ) {
    self.motion = motion
    self.style = style
    self.tint = tint
    self.centerTint = centerTint
    self.gradient = gradient
  }

  /// The house gradient: deep moss through to a cooler teal, lifted at the top.
  ///
  /// Spans the *whole mark* rather than each ring, which is the difference
  /// between a logo and seven independently-shaded circles. Two stops are worth
  /// it and a rainbow is not — this sits next to a UI whose entire visual
  /// argument is restraint, and a mark that out-colours everything around it
  /// stops reading as the product's own.
  public static let houseGradient = Gradient(colors: [
    Color(light: Color(hex: 0x3FB392), dark: Color(hex: 0x6FE0BC)),
    Color(light: Color(hex: 0x1F6F58), dark: Color(hex: 0x3E9E82)),
    Color(light: Color(hex: 0x1B5E7A), dark: Color(hex: 0x3D8FB0)),
  ])

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

      // Drawn as a mask and filled once, rather than seven separately-coloured
      // shapes. A mask carries alpha, so the per-ring opacity that drives the
      // searching animation still works — and the gradient stays continuous
      // across the whole mark instead of restarting inside every circle.
      fill
        .mask {
          ZStack {
            ring(diameter: diameter, lineWidth: lineWidth, lit: true, isCenter: true)
              .position(center)

            ForEach(Array(Self.outerOffsets.enumerated()), id: \.offset) { index, offset in
              ring(diameter: diameter, lineWidth: lineWidth, lit: isLit(index), isCenter: false)
                .position(x: center.x + offset.x * pitch, y: center.y + offset.y * pitch)
            }
          }
        }
        // The centre is the one thing a single fill cannot say on its own, and
        // it is load-bearing: six around one *is* the mark. Overlaid rather
        // than folded into the mask so it keeps its own colour.
        .overlay {
          if let centerTint {
            ring(diameter: diameter, lineWidth: lineWidth, lit: true, isCenter: true)
              .foregroundStyle(centerTint)
              .position(center)
          }
        }
    }
    .aspectRatio(1, contentMode: .fit)
    .onAppear(perform: start)
    .onChange(of: motion) { _, _ in start() }
    .accessibilityHidden(true)
  }

  /// Colourless on purpose — `fill` supplies the colour through the mask.
  @ViewBuilder
  private func ring(diameter: CGFloat, lineWidth: CGFloat, lit: Bool, isCenter: Bool) -> some View {
    Group {
      switch style {
      case .rings:
        Circle()
          .strokeBorder(.white, lineWidth: lineWidth)
          // The wash inside a lit ring. In a mask this is alpha, so it comes
          // out as the fill at 22% rather than as a grey disc.
          .background(Circle().fill(.white.opacity(lit ? 0.22 : 0)))
      case .solid:
        Circle().fill(.white)
      }
    }
      .frame(width: diameter, height: diameter)
      .opacity(lit ? 1 : 0.28)
      .scaleEffect(lit ? 1 : 0.9)
      // Each ring animates on its own clock, so the sweep reads as six things
      // happening in order rather than one thing changing shape.
      .animation(.easeOut(duration: 0.42), value: lit)
  }

  /// One gradient across the whole mark, or one flat colour. The icon generator
  /// passes a flat colour — an app icon already carries a gradient in its tile,
  /// and a second one inside the glyph muddies both.
  @ViewBuilder private var fill: some View {
    if let gradient {
      LinearGradient(gradient: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
    } else {
      tint
    }
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
