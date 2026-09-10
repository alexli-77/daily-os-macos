import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Dynamic color

extension Color {
  /// A colour that resolves itself against the current appearance.
  ///
  /// Deliberately built on the platform's own dynamic colour rather than on an
  /// `@Environment(\.colorScheme)` read: environment-based theming has to be
  /// threaded through every view that draws, and it silently produces the light
  /// palette anywhere the environment was not propagated — inside `MenuBarExtra`
  /// content, in an `NSHostingView`, in a detached popover. A dynamic colour is
  /// resolved at draw time by the system, so those cases are simply correct.
  init(light: Color, dark: Color) {
    #if canImport(UIKit)
    self = Color(UIColor { traits in
      traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
    })
    #elseif canImport(AppKit)
    self = Color(NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      return NSColor(isDark ? dark : light)
    })
    #else
    self = light
    #endif
  }

  /// `#RRGGBB`, the form the design tokens are written in.
  ///
  /// Public so the icon generator can draw brand artwork in the same notation
  /// the tokens are written in. Not an invitation to spell colours inline in a
  /// screen — everything a view draws should come from `Palette`.
  public init(hex: UInt32) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: 1
    )
  }
}

// MARK: - Palette

/// "Paper & Moss" — the Daily OS palette.
///
/// The light values are lifted verbatim from the existing web console
/// (`src/ui/server.ts`) so that the native apps and the browser render the same
/// product rather than two products that happen to share a name. The dark values
/// are new: they are not the light ramp inverted, because inverting a warm paper
/// white gives a blue-grey that reads as a different brand. They are a warm
/// near-black with the accent lifted to stay legible on it.
public enum Palette {
  /// Page background. Warm off-white — paper, not screen white.
  public static let paper = Color(light: Color(hex: 0xF6F7F4), dark: Color(hex: 0x141815))
  /// Cards, panels, popovers.
  public static let surface = Color(light: Color(hex: 0xFFFFFF), dark: Color(hex: 0x1C211D))
  /// Recessed areas: code blocks, table zebra, inactive tabs.
  public static let surfaceSunken = Color(light: Color(hex: 0xEFF1ED), dark: Color(hex: 0x0F1210))
  /// Primary text.
  public static let ink = Color(light: Color(hex: 0x202421), dark: Color(hex: 0xE8EDE8))
  /// Secondary text, metadata, timestamps.
  public static let inkMuted = Color(light: Color(hex: 0x68726B), dark: Color(hex: 0x96A099))
  /// Hairlines and panel borders.
  public static let line = Color(light: Color(hex: 0xD7DDD8), dark: Color(hex: 0x2C332E))

  /// The accent. One accent only — see DESIGN.md.
  public static let moss = Color(light: Color(hex: 0x1F6F58), dark: Color(hex: 0x5FBF9B))
  /// Accent wash for selected rows and soft badges.
  public static let mossSoft = Color(light: Color(hex: 0xE4EFE9), dark: Color(hex: 0x1B2E27))

  public static let ok = Color(light: Color(hex: 0x1E7A4D), dark: Color(hex: 0x63C08F))
  public static let warn = Color(light: Color(hex: 0xA06413), dark: Color(hex: 0xD9A75A))
  public static let danger = Color(light: Color(hex: 0x9F2D2D), dark: Color(hex: 0xE08585))

  /// Wash behind an `ok` / `warn` / `danger` badge.
  public static func softBackground(for tone: Tone) -> Color {
    switch tone {
    case .neutral: return Color(light: Color(hex: 0xEFF1ED), dark: Color(hex: 0x242925))
    case .accent: return mossSoft
    case .ok: return Color(light: Color(hex: 0xE3F1E9), dark: Color(hex: 0x14301F))
    case .warn: return Color(light: Color(hex: 0xF6EBDA), dark: Color(hex: 0x33260F))
    case .danger: return Color(light: Color(hex: 0xF6E1E1), dark: Color(hex: 0x351717))
    }
  }

  public static func foreground(for tone: Tone) -> Color {
    switch tone {
    case .neutral: return inkMuted
    case .accent: return moss
    case .ok: return ok
    case .warn: return warn
    case .danger: return danger
    }
  }

  /// Categorical chart colours, in order.
  ///
  /// The one sanctioned exception to "one accent only". That rule exists so a
  /// screen of controls does not read as a slot machine — but a pie whose
  /// slices are five tints of the same green cannot be read at all without
  /// tracing each one back to the legend, which defeats the point of drawing it.
  /// Categorical data needs distinguishable hues.
  ///
  /// Constrained anyway: every entry is desaturated to sit on paper, moss leads
  /// so the accent still owns the largest slice on a typical day, and there are
  /// six because a chart needing a seventh is a chart that should be grouping
  /// its tail instead.
  public static let series: [Color] = [
    moss,
    Color(light: Color(hex: 0x3E7CA6), dark: Color(hex: 0x7FB4D9)),
    Color(light: Color(hex: 0xA06413), dark: Color(hex: 0xD9A75A)),
    Color(light: Color(hex: 0x8A5B7A), dark: Color(hex: 0xC69BB8)),
    Color(light: Color(hex: 0x5E7A46), dark: Color(hex: 0x9FBE82)),
    Color(light: Color(hex: 0xA85843), dark: Color(hex: 0xD99A82)),
  ]

  /// Wraps, so a seventh item is drawn rather than dropped.
  public static func series(_ index: Int) -> Color {
    series[((index % series.count) + series.count) % series.count]
  }
}

/// The five semantic colours anything status-bearing is allowed to be.
public enum Tone: Sendable, Hashable {
  case neutral
  case accent
  case ok
  case warn
  case danger
}
