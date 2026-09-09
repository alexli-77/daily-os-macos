import SwiftUI

/// The one container in the system.
///
/// The web console has exactly one card shape (`.panel` / `.panel-head` /
/// `.panel-actions`) and every screen is built out of it. Keeping that here is
/// what makes eight screens feel like one app: a surface, a hairline, a title
/// row with optional trailing actions. There is no "elevated" or "outlined"
/// variant — depth is carried by the hairline, never by a shadow.
public struct Panel<Content: View, Actions: View>: View {
  private let title: String?
  private let subtitle: String?
  private let content: Content
  private let actions: Actions

  public init(
    _ title: String? = nil,
    subtitle: String? = nil,
    @ViewBuilder content: () -> Content,
    @ViewBuilder actions: () -> Actions
  ) {
    self.title = title
    self.subtitle = subtitle
    self.content = content()
    self.actions = actions()
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if title != nil || subtitle != nil {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
          VStack(alignment: .leading, spacing: Metrics.xxs) {
            if let title { Text(title).inkStyle(Typo.title) }
            if let subtitle { Text(subtitle).mutedStyle() }
          }
          Spacer(minLength: Metrics.xs)
          actions
        }
        .padding(.horizontal, Metrics.panelPadding)
        .padding(.top, Metrics.panelPadding)
        .padding(.bottom, Metrics.sm)
      }
      content
        .padding(.horizontal, Metrics.panelPadding)
        .padding(.bottom, Metrics.panelPadding)
        .padding(.top, title == nil && subtitle == nil ? Metrics.panelPadding : 0)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Palette.surface)
    .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusMedium, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Metrics.radiusMedium, style: .continuous)
        .strokeBorder(Palette.line, lineWidth: Metrics.hairline)
    )
  }
}

extension Panel where Actions == EmptyView {
  public init(
    _ title: String? = nil,
    subtitle: String? = nil,
    @ViewBuilder content: () -> Content
  ) {
    self.init(title, subtitle: subtitle, content: content, actions: { EmptyView() })
  }
}

/// A full-bleed hairline for separating rows inside a `Panel`.
public struct PanelDivider: View {
  public init() {}
  public var body: some View {
    Rectangle()
      .fill(Palette.line)
      .frame(height: Metrics.hairline)
      .padding(.horizontal, -Metrics.panelPadding)
  }
}

/// A screen's outer chrome: title, optional subtitle, scrolling body.
///
/// Every screen uses this so the title never drifts by a few points between
/// pages, which is the single most common way a native app starts to feel
/// assembled rather than designed.
public struct ScreenScaffold<Content: View, Toolbar: View>: View {
  private let title: String
  private let subtitle: String?
  private let content: Content
  private let toolbar: Toolbar

  public init(
    _ title: String,
    subtitle: String? = nil,
    @ViewBuilder content: () -> Content,
    @ViewBuilder toolbar: () -> Toolbar
  ) {
    self.title = title
    self.subtitle = subtitle
    self.content = content()
    self.toolbar = toolbar()
  }

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Metrics.md) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: Metrics.xxs) {
            Text(title).inkStyle(Typo.display)
            if let subtitle { Text(subtitle).mutedStyle() }
          }
          Spacer(minLength: Metrics.sm)
          toolbar
        }
        .padding(.bottom, Metrics.xxs)
        content
      }
      .padding(Metrics.screenPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Palette.paper)
  }
}

extension ScreenScaffold where Toolbar == EmptyView {
  public init(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
    self.init(title, subtitle: subtitle, content: content, toolbar: { EmptyView() })
  }
}
