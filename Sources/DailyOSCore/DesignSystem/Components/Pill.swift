import SwiftUI

/// A small status label.
///
/// Pills carry *state*, never navigation. If it can be tapped it is a button,
/// not a pill — the web console blurred this and ended up with badges people
/// tried to click.
public struct Pill: View {
  private let text: String
  private let tone: Tone
  private let mono: Bool

  public init(_ text: String, tone: Tone = .neutral, mono: Bool = false) {
    self.text = text
    self.tone = tone
    self.mono = mono
  }

  public var body: some View {
    Text(text)
      .font(mono ? Typo.mono : Typo.label)
      .foregroundStyle(Palette.foreground(for: tone))
      .padding(.horizontal, Metrics.xs)
      .padding(.vertical, Metrics.xxs)
      .background(Palette.softBackground(for: tone))
      .clipShape(Capsule())
  }
}

/// A coloured dot plus a label — for service health and run state, where the
/// colour is the message and the word is the confirmation.
public struct StatusDot: View {
  private let label: String?
  private let tone: Tone
  private let pulsing: Bool

  public init(_ label: String? = nil, tone: Tone, pulsing: Bool = false) {
    self.label = label
    self.tone = tone
    self.pulsing = pulsing
  }

  public var body: some View {
    HStack(spacing: Metrics.xs) {
      Circle()
        .fill(Palette.foreground(for: tone))
        .frame(width: 8, height: 8)
        .opacity(pulsing ? 0.55 : 1)
        .overlay {
          if pulsing {
            Circle()
              .stroke(Palette.foreground(for: tone), lineWidth: 1)
              .scaleEffect(1.9)
              .opacity(0.35)
          }
        }
      if let label {
        Text(label).mutedStyle()
      }
    }
  }
}

/// A label / value row. The workhorse of the settings and detail panes.
public struct KeyValueRow<Value: View>: View {
  private let key: String
  private let value: Value

  public init(_ key: String, @ViewBuilder value: () -> Value) {
    self.key = key
    self.value = value()
  }

  public var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
      Text(key)
        .mutedStyle(Typo.body)
        .frame(minWidth: 108, alignment: .leading)
      value
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minHeight: Metrics.hitTarget)
  }
}

extension KeyValueRow where Value == Text {
  public init(_ key: String, _ value: String, mono: Bool = false) {
    self.init(key) { Text(value).font(mono ? Typo.monoBody : Typo.body).foregroundStyle(Palette.ink) }
  }
}

/// A thin progress track. Used for key-result progress and in-flight runs.
public struct ProgressTrack: View {
  private let fraction: Double
  private let tone: Tone

  public init(fraction: Double, tone: Tone = .accent) {
    self.fraction = min(max(fraction, 0), 1)
    self.tone = tone
  }

  public var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        Capsule().fill(Palette.surfaceSunken)
        Capsule()
          .fill(Palette.foreground(for: tone))
          .frame(width: max(geo.size.width * fraction, fraction > 0 ? 4 : 0))
      }
    }
    .frame(height: 6)
    .accessibilityValue(Text("\(Int(fraction * 100))%"))
  }
}

/// What a screen shows when it has nothing to show.
///
/// Never an empty page: the daily-os issues call this out repeatedly (LEO-277,
/// LEO-285). An empty state names the reason and offers the one action that
/// resolves it.
public struct EmptyState: View {
  private let icon: String
  private let title: String
  private let message: String
  private let actionTitle: String?
  private let action: (() -> Void)?

  public init(
    icon: String,
    title: String,
    message: String,
    actionTitle: String? = nil,
    action: (() -> Void)? = nil
  ) {
    self.icon = icon
    self.title = title
    self.message = message
    self.actionTitle = actionTitle
    self.action = action
  }

  public var body: some View {
    VStack(spacing: Metrics.sm) {
      Image(systemName: icon)
        .font(.system(size: 26, weight: .light))
        .foregroundStyle(Palette.inkMuted)
      Text(title).inkStyle(Typo.heading)
      Text(message)
        .mutedStyle(Typo.body)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 340)
      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .buttonStyle(MossButtonStyle(prominent: false))
          .padding(.top, Metrics.xxs)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Metrics.xl)
  }
}
