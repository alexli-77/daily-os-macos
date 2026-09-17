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

/// "Paper & Mint" — the Daily OS palette.
///
/// A warm grey-beige paper with a single mint ramp on it. Replaces the earlier
/// "Paper & Moss" two-step accent (`moss` / `mossSoft`): the Today page needs to
/// say *how much* mint — a hover wash, a chip fill, a selected row, a filled
/// dot, a line of overdue text — and two steps could not carry six jobs without
/// one of them borrowing a colour it had no business using.
///
/// **Dark is not light inverted.** Inverting a warm paper white gives a blue-grey
/// that reads as a different brand. Dark is its own warm near-black with the mint
/// lifted until it stays legible on it.
///
/// ## The rules the ramp encodes
///
/// - `mint400` is the only solid accent fill.
/// - `mint200` is the only tinted background, and text on it is always `mint800`.
/// - Nothing is ever white-on-dark in light mode. Depth comes from hairlines and
///   whitespace, not from inverted blocks.
/// - `q1` appears on the MIT marker and nowhere else. It is the one warm hue in
///   the product, and it is worth exactly one word a day.
///
/// ## Contrast
///
/// Every text token was checked against the surface it actually draws on, at the
/// size it actually draws at, and four values moved to clear WCAG AA (4.5:1):
///
/// | token | was | now | on | ratio |
/// | --- | --- | --- | --- | --- |
/// | `ink3` light | `#9C9DA3` | `#727377` | `page` | 2.59 → 4.53 |
/// | `ink3` dark | `#707578` | `#83898C` | `page` | 3.44 → 4.52 |
/// | `mint600` light | `#2E8A71` | `#287963` | `paper` | 3.66 → 4.56 |
/// | `q1` light | `#D25C5C` | `#B04D4D` | `page` | 3.70 → 4.52 |
///
/// `ink3` was the one that mattered. It is the text colour of *completed and
/// deferred rows* — so at 2.59:1 the reward for finishing a day was half a
/// screen of type some people cannot read. De-emphasis survives the correction:
/// a done row still carries a strikethrough and a filled dot, and those say
/// "done" without asking the eye to fail.
public enum Palette {
  // MARK: Surfaces

  /// Page background. Warm grey-beige — paper, not screen white.
  public static let paper = Color(light: Color(hex: 0xF0EFEB), dark: Color(hex: 0x17191A))
  /// The sheet the day is written on. Sits on `paper`.
  public static let page = Color(light: Color(hex: 0xFAFAF8), dark: Color(hex: 0x1F2223))
  /// Hairline between rows and around the sheet.
  public static let rule = Color(light: Color(hex: 0xE2E1DB), dark: Color(hex: 0x2F3335))

  // MARK: Text

  /// Primary text.
  public static let ink = Color(light: Color(hex: 0x2C2C30), dark: Color(hex: 0xE8EAEA))
  /// Time slots, secondary text.
  public static let ink2 = Color(light: Color(hex: 0x63646A), dark: Color(hex: 0xAEB2B4))
  /// Explanatory text, resolved rows, the stroke of an empty circle.
  ///
  /// AA-corrected from the spec sheet — see the type note above.
  public static let ink3 = Color(light: Color(hex: 0x727377), dark: Color(hex: 0x83898C))

  // MARK: The mint ramp

  /// Circle hover wash. The lightest thing that is still visibly not `page`.
  public static let mint50 = Color(light: Color(hex: 0xEDF7F3), dark: Color(hex: 0x1D2925))
  /// Chip hover, the pale bars in a chart.
  public static let mint100 = Color(light: Color(hex: 0xD6EEE4), dark: Color(hex: 0x22352F))
  /// Primary button fill, selected row. Text on this is always `mint800`.
  public static let mint200 = Color(light: Color(hex: 0xB4E0D0), dark: Color(hex: 0x2B4A40))
  /// The one solid accent: completed dot, progress bar, the now-line.
  public static let mint400 = Color(light: Color(hex: 0x7FCCB3), dark: Color(hex: 0x4CA48A))
  /// Overdue text, link hover. AA-corrected in light — see the type note above.
  public static let mint600 = Color(light: Color(hex: 0x287963), dark: Color(hex: 0x86D2BC))
  /// Text drawn on a mint background. The only thing allowed on `mint200`.
  public static let mint800 = Color(light: Color(hex: 0x1B5245), dark: Color(hex: 0xC9EEE1))

  /// The MIT marker, and nothing else.
  ///
  /// Not a danger colour. The most important task of the day is not a problem,
  /// and this is deliberately warmer and quieter than `danger` so the two never
  /// read as the same kind of statement. AA-corrected in light.
  public static let q1 = Color(light: Color(hex: 0xB04D4D), dark: Color(hex: 0xE98383))

  // MARK: - System status layer
  //
  // Everything below is *outside* the Today page's colour rules, deliberately
  // and by decision rather than by omission.
  //
  // The palette above has one hue because a screen of plans should read as one
  // continuous thing. But this app also has to say "the service is down", "the
  // key is missing", "this run failed" — and a status system rendered entirely
  // in mint cannot say any of them. Asking `q1` to carry it would break the one
  // rule that makes the MIT marker mean something: that it is the only warm mark
  // on the page.
  //
  // So status keeps its own three colours, used *only* where the entire message
  // is a state: service lights, run outcomes, settings validation, sign-in
  // errors. 84 call sites across 14 files. A plan row is never any of these.
  //
  // `series` is the same kind of exception and was already documented as one:
  // categorical data needs distinguishable hues or the legend becomes the only
  // way to read the chart.

  public static let ok = Color(light: Color(hex: 0x1E7A4D), dark: Color(hex: 0x63C08F))
  public static let warn = Color(light: Color(hex: 0xA06413), dark: Color(hex: 0xD9A75A))
  public static let danger = Color(light: Color(hex: 0x9F2D2D), dark: Color(hex: 0xE08585))

  /// Wash behind an `ok` / `warn` / `danger` badge.
  public static func softBackground(for tone: Tone) -> Color {
    switch tone {
    case .neutral: return Color(light: Color(hex: 0xEFEEEA), dark: Color(hex: 0x252829))
    case .accent: return mint200
    case .ok: return Color(light: Color(hex: 0xE3F1E9), dark: Color(hex: 0x14301F))
    case .warn: return Color(light: Color(hex: 0xF6EBDA), dark: Color(hex: 0x33260F))
    case .danger: return Color(light: Color(hex: 0xF6E1E1), dark: Color(hex: 0x351717))
    }
  }

  /// The colour text in this tone is *written* in — on `softBackground(for:)`.
  public static func foreground(for tone: Tone) -> Color {
    switch tone {
    case .neutral: return ink2
    case .accent: return mint800
    case .ok: return ok
    case .warn: return warn
    case .danger: return danger
    }
  }

  /// The colour this tone *fills* with — a progress bar, a solid dot, a bar in a
  /// chart.
  ///
  /// Split from `foreground(for:)`, which used to serve both. For the status
  /// tones the two answers happen to coincide, which is why one function could
  /// pretend to be both for so long — but for `accent` they are `mint400` (the
  /// one solid accent) and `mint800` (the ink that goes on a mint background),
  /// and those are at opposite ends of the ramp. A progress bar drawn in
  /// `mint800` is nearly black, and it took a rendered screenshot to notice.
  public static func fill(for tone: Tone) -> Color {
    switch tone {
    case .neutral: return ink3
    case .accent: return mint400
    case .ok: return ok
    case .warn: return warn
    case .danger: return danger
    }
  }

  /// Categorical chart colours, in order.
  ///
  /// The other sanctioned exception to "one hue only". That rule exists so a
  /// screen of controls does not read as a slot machine — but a pie whose slices
  /// are five tints of the same mint cannot be read at all without tracing each
  /// one back to the legend, which defeats the point of drawing it.
  ///
  /// Constrained anyway: every entry is desaturated to sit on paper, mint leads
  /// so the accent still owns the largest slice on a typical day, and there are
  /// six because a chart needing a seventh is a chart that should be grouping its
  /// tail instead.
  public static let series: [Color] = [
    mint400,
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

  /// The colour a plan row and its slice of the day share.
  ///
  /// Only the MIT is coloured now. The old three-tier ring (terracotta / amber /
  /// grey) said "these three are the important ones", which is a different claim
  /// from the one the plan actually makes — the prompt picks *one* thing that
  /// matters most, and colouring rank 2 and 3 as a tier diluted that into a
  /// gradient nobody was asked to read.
  ///
  /// `high` and `normal` now differ by text weight and ink level instead, which
  /// is what the rest of the page already uses to say "less important".
  public static func importance(_ importance: PlanImportance) -> Color {
    switch importance {
    case .mit: q1
    case .high: ink2
    case .normal: ink3
    }
  }

  // MARK: - Migration aliases
  //
  // The old names, pointing at their replacements. 655 call sites across both
  // this repo and daily-os-ios still spell them this way, and renaming those in
  // the same commit that changes every value would make the diff impossible to
  // review — you could not tell a deliberate colour change from a mis-typed
  // rename. Worse, daily-os-ios consumes this package and cannot be built from
  // here, so a hard rename would break a repo this PR has no way to test.
  //
  // Values follow the new palette immediately; only the spelling lags. Removed
  // once both repos have migrated.
  //
  // Deliberately *not* marked `@available(deprecated:)`. Doing so emits one
  // warning per call site — 655 of them — and a build that always prints 655
  // warnings is a build where the 656th, the real one, is invisible. The
  // attribute goes on in the rename PR, where it will be true for a few hours
  // rather than for weeks.

  public static var surface: Color { page }

  /// Recessed areas — code blocks, inputs, folded regions. The new spec has no
  /// name for this, but `paper` under a `page` sheet is exactly what "recessed"
  /// means here, so it maps rather than inventing a fourth surface.
  public static var surfaceSunken: Color { paper }

  public static var inkMuted: Color { ink2 }

  public static var line: Color { rule }

  public static var moss: Color { mint400 }

  public static var mossSoft: Color { mint200 }
}

/// The five semantic colours anything status-bearing is allowed to be.
public enum Tone: Sendable, Hashable {
  case neutral
  case accent
  case ok
  case warn
  case danger
}
