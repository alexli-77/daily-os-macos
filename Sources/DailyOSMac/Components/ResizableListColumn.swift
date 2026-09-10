import SwiftUI
import DailyOSCore

/// A list column the user can drag wider or narrower.
///
/// Replaces the fixed width `ListColumn` shipped with. A cycle label is short
/// and a conversation title is not, so one number could not be right for both —
/// and the person reading the screen already knows which they are looking at.
///
/// The width is remembered per column id rather than globally. Cycles and Chat
/// want different widths for the same reason they show different things, and a
/// shared setting would mean adjusting one silently ruins the other.
public struct ResizableListColumn<Content: View>: View {
  private let id: String
  private let content: Content
  private let range: ClosedRange<CGFloat>

  @State private var width: CGFloat
  /// Width at the moment the drag began. Without it every mouse move would
  /// re-apply the whole translation and the column would run away from the
  /// pointer.
  @State private var widthAtDragStart: CGFloat?
  @State private var isHovering = false

  public init(
    id: String,
    defaultWidth: CGFloat = Metrics.listIdeal,
    range: ClosedRange<CGFloat> = Metrics.listMin...Metrics.listMax,
    @ViewBuilder content: () -> Content
  ) {
    self.id = id
    self.range = range
    self.content = content()
    let stored = UserDefaults.standard.double(forKey: Self.key(id))
    _width = State(initialValue: stored > 0 ? min(max(stored, range.lowerBound), range.upperBound) : defaultWidth)
  }

  public var body: some View {
    content
      .frame(width: width)
      .background(Palette.surface)
      .overlay(alignment: .trailing) { handle }
  }

  private var handle: some View {
    // The hairline stays exactly where it was; the grab area is wider than it
    // and invisible. A divider thick enough to hit comfortably would be a
    // visible ridge down a screen whose depth is carried by hairlines.
    Rectangle()
      .fill(isHovering || widthAtDragStart != nil ? Palette.moss : Palette.line)
      .frame(width: Metrics.hairline)
      .overlay {
        Rectangle()
          .fill(.clear)
          .frame(width: 10)
          .contentShape(Rectangle())
          .onHover { hovering in
            isHovering = hovering
            // The pointer has to say the edge is draggable before anyone tries.
            if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
          }
          .gesture(
            DragGesture(minimumDistance: 1)
              .onChanged { value in
                let start = widthAtDragStart ?? width
                widthAtDragStart = start
                width = min(max(start + value.translation.width, range.lowerBound), range.upperBound)
              }
              .onEnded { _ in
                widthAtDragStart = nil
                UserDefaults.standard.set(Double(width), forKey: Self.key(id))
              }
          )
      }
      .accessibilityLabel(Text("调整栏宽"))
  }

  private static func key(_ id: String) -> String { "com.dailyos.mac.columnWidth.\(id)" }
}
