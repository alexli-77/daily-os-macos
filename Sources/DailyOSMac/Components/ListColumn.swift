import SwiftUI
import DailyOSCore

/// The fixed-width list column of a master–detail screen.
///
/// Not a `NavigationSplitView` column: these lists live *inside* a detail pane
/// that already belongs to the window's split view, and nesting split views
/// gives you two sets of collapse behaviour fighting over the same drag.
///
/// Mac-only chrome, so it lives here rather than in `DailyOSCore` — on a phone
/// the same relationship is expressed by pushing a detail view, not by a second
/// column.
public struct ListColumn<Content: View>: View {
  private let content: Content
  private let width: CGFloat

  public init(width: CGFloat = Metrics.listIdeal, @ViewBuilder content: () -> Content) {
    self.width = width
    self.content = content()
  }

  public var body: some View {
    content
      .frame(width: width)
      .background(Palette.surface)
      .overlay(alignment: .trailing) {
        Rectangle().fill(Palette.line).frame(width: Metrics.hairline)
      }
  }
}
