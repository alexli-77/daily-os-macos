import SwiftUI

/// Side by side on the Mac, stacked on the phone.
///
/// The alternative — one adaptive grid everywhere — produces a two-column phone
/// layout in landscape that nobody asked for and that breaks the reading order
/// of a todo list.
public struct TwoColumns<Leading: View, Trailing: View>: View {
  private let leading: Leading
  private let trailing: Trailing

  public init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
    self.leading = leading()
    self.trailing = trailing()
  }

  public var body: some View {
    #if os(macOS)
    HStack(alignment: .top, spacing: Metrics.md) {
      leading.frame(maxWidth: .infinity, alignment: .top)
      trailing.frame(maxWidth: .infinity, alignment: .top)
    }
    #else
    VStack(spacing: Metrics.md) {
      leading
      trailing
    }
    #endif
  }
}

/// A row in a list column: selectable, with the selected state carried by a
/// wash rather than by the system's blue highlight, so it matches the rest of
/// the palette.
public struct SelectableRow<Content: View>: View {
  private let isSelected: Bool
  private let action: () -> Void
  private let content: Content

  public init(isSelected: Bool, action: @escaping () -> Void, @ViewBuilder content: () -> Content) {
    self.isSelected = isSelected
    self.action = action
    self.content = content()
  }

  public var body: some View {
    Button(action: action) {
      content
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.sm)
        .padding(.vertical, Metrics.xs)
        .frame(minHeight: Metrics.hitTarget)
        .background(isSelected ? Palette.mossSoft : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }
}

/// A labelled statistic. Three or four of these across the top of a screen is
/// the whole of what the old Dashboard was for.
public struct StatTile: View {
  private let label: String
  private let value: String
  private let tone: Tone

  public init(_ label: String, value: String, tone: Tone = .neutral) {
    self.label = label
    self.value = value
    self.tone = tone
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xxs) {
      Text(label).mutedStyle(Typo.label)
      Text(value)
        .font(Typo.tabularBody.weight(.medium))
        .foregroundStyle(tone == .neutral ? Palette.ink : Palette.foreground(for: tone))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
