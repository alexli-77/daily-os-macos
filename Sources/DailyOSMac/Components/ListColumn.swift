import SwiftUI
import DailyOSCore

/// The list column of a master–detail screen. Every list–detail screen in the
/// main window uses this one, so moving between them does not move the column.
///
/// Three things are fixed here rather than left to each screen, because each
/// was being chosen per screen and the result read as five different apps:
///
/// - **Width.** One width, shared by every list column and remembered across
///   launches. Drag any of them and they all follow — switching from 运行 to
///   作息 must not make the column jump. Defaults to `listMin`: the detail is
///   what you came for, the list is how you reach it.
/// - **Header.** The section's name, with at most one trailing action (usually
///   "+"). The detail pane's title names the *selected item*, so the two never
///   say the same word twice — the same split as Mail's mailbox / message.
/// - **Rows.** Scrolled, 2pt apart, `xs` inset. Screens pass `SelectableRow`s
///   and `SectionLabel`s, nothing else.
///
/// Not a `NavigationSplitView` column: these lists live *inside* a detail pane
/// that already belongs to the window's split view, and nesting split views
/// gives you two sets of collapse behaviour fighting over the same drag.
///
/// Mac-only chrome, so it lives here rather than in `DailyOSCore` — on a phone
/// the same relationship is expressed by pushing a detail view, not by a second
/// column.
public struct ListColumn<Rows: View, Trailing: View>: View {
  private let title: String
  private let rows: Rows
  private let trailing: Trailing

  @AppStorage("com.dailyos.mac.listColumnWidth") private var storedWidth = Double(Metrics.listMin)
  /// Width at the moment the drag began. Without it every mouse move would
  /// re-apply the whole translation and the column would run away from the
  /// pointer.
  @State private var widthAtDragStart: CGFloat?
  @State private var isHovering = false

  private let range = Metrics.listMin...Metrics.listMax

  public init(
    _ title: String,
    @ViewBuilder rows: () -> Rows,
    @ViewBuilder trailing: () -> Trailing
  ) {
    self.title = title
    self.rows = rows()
    self.trailing = trailing()
  }

  private var width: CGFloat {
    min(max(CGFloat(storedWidth), range.lowerBound), range.upperBound)
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: Metrics.xs) {
        Text(title).inkStyle(Typo.heading)
        Spacer(minLength: 0)
        trailing.buttonStyle(QuietButtonStyle(tone: .neutral))
      }
      .frame(minHeight: Metrics.hitTarget)
      .padding(.horizontal, Metrics.md)
      .padding(.top, Metrics.sm)
      .padding(.bottom, Metrics.xxs)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) { rows }
          .padding(Metrics.xs)
      }
    }
    .frame(width: width)
    .frame(maxHeight: .infinity, alignment: .top)
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
                storedWidth = Double(min(max(start + value.translation.width, range.lowerBound), range.upperBound))
              }
              .onEnded { _ in widthAtDragStart = nil }
          )
      }
      .accessibilityLabel(Text("调整栏宽"))
  }
}

extension ListColumn where Trailing == EmptyView {
  public init(_ title: String, @ViewBuilder rows: () -> Rows) {
    self.init(title, rows: rows, trailing: { EmptyView() })
  }
}
