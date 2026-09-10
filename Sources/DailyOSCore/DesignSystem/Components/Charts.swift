import SwiftUI

// Two small charts, hand-drawn.
//
// Not Swift Charts. Both of these are one shape and a handful of labels, and
// they have to sit inside panels whose whole visual argument is hairlines and a
// warm paper ground. Bringing in a charting framework here would mean spending
// more code overriding its gridlines, its type and its legend than the shapes
// themselves cost — and still ending up with something that reads as a chart
// pasted into the app rather than as part of it.

// MARK: - Donut

/// One slice of a `DonutChart`.
public struct DonutSlice: Identifiable, Sendable {
  public let id: String
  public let label: String
  public let value: Double
  public let color: Color
  /// Drawn faded, for a slice that is finished rather than pending.
  public let isSpent: Bool

  public init(id: String, label: String, value: Double, color: Color, isSpent: Bool = false) {
    self.id = id
    self.label = label
    self.value = value
    self.color = color
    self.isSpent = isSpent
  }
}

/// A ring, with whatever you want in the hole.
///
/// A ring rather than a filled pie: the middle of a pie is the part carrying the
/// least information — every slice is widest at the rim — and giving it up buys
/// room for the one number the chart is really about, which here is the day's
/// total. Comparing slices stays an angle comparison either way.
///
/// Starts at twelve o'clock and runs clockwise, matching how a clock face reads,
/// because the quantity being sliced up *is* time.
public struct DonutChart<Center: View>: View {
  private let slices: [DonutSlice]
  private let lineWidth: CGFloat
  private let center: Center

  public init(
    slices: [DonutSlice],
    lineWidth: CGFloat = 22,
    @ViewBuilder center: () -> Center
  ) {
    self.slices = slices
    self.lineWidth = lineWidth
    self.center = center()
  }

  private var total: Double { slices.reduce(0) { $0 + max($1.value, 0) } }

  public var body: some View {
    ZStack {
      GeometryReader { geo in
        let side = min(geo.size.width, geo.size.height)
        let radius = (side - lineWidth) / 2
        let origin = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

        ZStack {
          // The track shows through the gaps, so a chart with one slice still
          // reads as "a whole" rather than as a stray arc.
          Circle()
            .strokeBorder(Palette.surfaceSunken, lineWidth: lineWidth)
            .frame(width: side, height: side)
            .position(origin)

          ForEach(DonutArc.layout(slices)) { arc in
            Path { path in
              path.addArc(
                center: origin,
                radius: radius,
                startAngle: .degrees(arc.startDegrees),
                endAngle: .degrees(arc.endDegrees),
                clockwise: false
              )
            }
            .stroke(
              arc.color.opacity(arc.isSpent ? 0.35 : 1),
              style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
            )
            .accessibilityLabel(Text(arc.label))
            .accessibilityValue(Text(percentText(arc.value)))
          }
        }
      }
      center
    }
    .accessibilityElement(children: .contain)
  }

  private func percentText(_ value: Double) -> String {
    guard total > 0 else { return "0%" }
    return "\(Int((value / total * 100).rounded()))%"
  }
}

extension DonutChart where Center == EmptyView {
  public init(slices: [DonutSlice], lineWidth: CGFloat = 22) {
    self.init(slices: slices, lineWidth: lineWidth) { EmptyView() }
  }
}

/// One drawn arc: a slice plus where it sits on the ring.
public struct DonutArc: Identifiable, Sendable {
  public let id: String
  public let label: String
  public let value: Double
  public let color: Color
  public let isSpent: Bool
  /// Degrees, 0 at three o'clock and increasing clockwise — SwiftUI's own
  /// convention, so these go straight into `Path.addArc` untranslated.
  public let startDegrees: Double
  public let endDegrees: Double

  public var sweep: Double { endDegrees - startDegrees }

  /// Where each slice sits on the ring, starting at twelve o'clock.
  ///
  /// Lives here, on the plain data type, rather than inside `DonutChart` — the
  /// chart is generic over its centre content, and putting the arithmetic there
  /// would mean naming a `Center` type just to compute an angle.
  ///
  /// Separated out at all because it is the only part of this chart that can be
  /// *silently* wrong: a ring always looks like a ring, so slices that quietly
  /// fail to sum to a full turn, or a small slice swallowed whole by its own
  /// separator, would never announce themselves on screen.
  ///
  /// The 2° separator is taken *out of* each slice rather than added between
  /// them, so the arcs span exactly 360° however many there are. It also never
  /// exceeds a quarter of its own slice, which is what stops a 15-minute task
  /// next to a two-hour one from disappearing into the gap.
  public static func layout(_ slices: [DonutSlice]) -> [DonutArc] {
    let total = slices.reduce(0.0) { $0 + max($1.value, 0) }
    guard total > 0 else { return [] }
    var cursor = -90.0
    return slices.compactMap { slice in
      let sweep = max(slice.value, 0) / total * 360
      guard sweep > 0 else { return nil }
      let gap = min(2.0, sweep / 4)
      let arc = DonutArc(
        id: slice.id,
        label: slice.label,
        value: slice.value,
        color: slice.color,
        isSpent: slice.isSpent,
        startDegrees: cursor + gap / 2,
        endDegrees: cursor + sweep - gap / 2
      )
      cursor += sweep
      return arc
    }
  }
}

// MARK: - Trend line

/// One point on a `TrendLine`.
public struct TrendPoint: Identifiable, Sendable {
  public let id: String
  public let label: String
  /// 0…1.
  public let value: Double
  /// Drawn as a filled ring rather than a hollow one.
  public let isCurrent: Bool
  /// The reading, spelled out for the tooltip and for VoiceOver.
  public let detail: String

  public init(id: String, label: String, value: Double, isCurrent: Bool = false, detail: String = "") {
    self.id = id
    self.label = label
    self.value = value
    self.isCurrent = isCurrent
    self.detail = detail
  }
}

/// A small line chart over an ordered series, 0…1 on the y axis.
///
/// Deliberately without axes or gridlines. At this size they would take more
/// room than the line and answer a question nobody has here — the point is the
/// *shape*, whether the last few periods went up or down, and a 50% guide is
/// enough to say which half you are in.
public struct TrendLine: View {
  private let points: [TrendPoint]
  private let onSelect: ((TrendPoint) -> Void)?

  public init(points: [TrendPoint], onSelect: ((TrendPoint) -> Void)? = nil) {
    self.points = points
    self.onSelect = onSelect
  }

  public var body: some View {
    GeometryReader { geo in
      let positions = positions(in: geo.size)
      ZStack {
        // Half. Every other horizontal rule was noise at this height.
        Path { path in
          path.move(to: CGPoint(x: 0, y: geo.size.height / 2))
          path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height / 2))
        }
        .stroke(Palette.line, style: StrokeStyle(lineWidth: Metrics.hairline, dash: [3, 3]))

        // Fill under the line, so a short series still reads as a quantity
        // rather than as three dots and a stick.
        if positions.count > 1 {
          Path { path in
            path.move(to: CGPoint(x: positions[0].x, y: geo.size.height))
            for point in positions { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: positions[positions.count - 1].x, y: geo.size.height))
            path.closeSubpath()
          }
          .fill(
            LinearGradient(
              colors: [Palette.moss.opacity(0.18), Palette.moss.opacity(0.02)],
              startPoint: .top,
              endPoint: .bottom
            )
          )

          Path { path in
            path.move(to: positions[0])
            for point in positions.dropFirst() { path.addLine(to: point) }
          }
          .stroke(Palette.moss, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }

        ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
          let position = positions[index]
          Circle()
            .fill(point.isCurrent ? Palette.moss : Palette.surface)
            .overlay(Circle().strokeBorder(Palette.moss, lineWidth: 1.5))
            .frame(width: point.isCurrent ? 9 : 6, height: point.isCurrent ? 9 : 6)
            .position(position)
            .help("\(point.label) · \(point.detail)")
            .accessibilityLabel(Text(point.label))
            .accessibilityValue(Text(point.detail))
        }

        // Hit targets, separate from the dots: a 6pt circle is not clickable,
        // and widening the dot to be clickable would make the chart a row of
        // blobs.
        if let onSelect {
          HStack(spacing: 0) {
            ForEach(points) { point in
              Rectangle()
                .fill(.clear)
                .contentShape(Rectangle())
                .onTapGesture { onSelect(point) }
            }
          }
        }
      }
    }
  }

  private func positions(in size: CGSize) -> [CGPoint] {
    guard !points.isEmpty else { return [] }
    // Insets so a dot sitting at 0 or 1 is not half-clipped by the frame.
    let top: CGFloat = 6
    let bottom: CGFloat = 6
    let usable = max(size.height - top - bottom, 1)
    guard points.count > 1 else {
      return [CGPoint(x: size.width / 2, y: top + usable * (1 - clamp(points[0].value)))]
    }
    let step = size.width / CGFloat(points.count - 1)
    return points.enumerated().map { index, point in
      CGPoint(x: CGFloat(index) * step, y: top + usable * (1 - clamp(point.value)))
    }
  }

  private func clamp(_ value: Double) -> CGFloat { CGFloat(min(max(value, 0), 1)) }
}
