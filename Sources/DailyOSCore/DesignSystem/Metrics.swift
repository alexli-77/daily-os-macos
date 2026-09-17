import SwiftUI

/// Spacing, radii and hairlines.
///
/// One 4pt grid for both platforms. iOS gets larger *touch targets*, not larger
/// spacing — the rhythm of the layout should read as the same product whether it
/// is on a Mac or a phone.
public enum Metrics {
  // MARK: Spacing — 4 / 8 / 12 / 16 / 24 / 32 / 40

  public static let xxs: CGFloat = 4
  public static let xs: CGFloat = 8
  public static let sm: CGFloat = 12
  public static let md: CGFloat = 16
  public static let lg: CGFloat = 24
  public static let xl: CGFloat = 32
  /// 40, not 48. The old top step had no call sites, so the scale was carrying a
  /// value nothing used.
  public static let xxl: CGFloat = 40

  // MARK: Radius — two, not a ramp

  /// Paper. Sheets, panels, anything that is a surface rather than a control.
  public static let radiusPaper: CGFloat = 4
  /// Anything you can press. Fully round, never a squared-off button.
  public static let radiusPill: CGFloat = 999

  /// Panel and divider stroke. Hairline, never heavier.
  public static let hairline: CGFloat = 1

  /// The stroke of an unchecked circle. Heavier than a hairline on purpose: it
  /// is an affordance, not a divider, and at 1pt in `ink3` it reads as a smudge.
  public static let circleStroke: CGFloat = 1.5

  /// The state circle on a plan row.
  public static let circleSize: CGFloat = 22

  /// Minimum hit target. 28 on macOS (pointer), 44 on iOS (finger).
  public static var hitTarget: CGFloat {
    #if os(iOS)
    44
    #else
    28
    #endif
  }

  /// Padding inside a `Panel`.
  public static let panelPadding: CGFloat = md

  /// Outer padding of a screen's scroll content.
  public static var screenPadding: CGFloat {
    #if os(iOS)
    md
    #else
    lg
    #endif
  }

  /// Widest a column of prose is allowed to get before it stops being readable.
  public static let readableWidth: CGFloat = 720

  /// macOS sidebar bounds.
  public static let sidebarMin: CGFloat = 190
  public static let sidebarIdeal: CGFloat = 214
  public static let sidebarMax: CGFloat = 280

  /// macOS middle (list) column bounds.
  public static let listMin: CGFloat = 260
  public static let listIdeal: CGFloat = 320
  public static let listMax: CGFloat = 420

  // MARK: - Migration aliases
  //
  // The radius ramp collapsed from four steps to two: a surface is 4 and a
  // control is round, and every value in between was a decision nobody could
  // state a rule for. 33 call sites still name the old steps; they all resolve
  // to `radiusPaper` so the rendering follows the new spec immediately while the
  // spelling catches up in a later pass. Same reasoning as the palette aliases —
  // and the same constraint, since daily-os-ios spells them this way too, plus
  // the same reason for not marking them deprecated yet.

  public static var radiusSmall: CGFloat { radiusPaper }

  public static var radiusMedium: CGFloat { radiusPaper }

  public static var radiusLarge: CGFloat { radiusPaper }
}
