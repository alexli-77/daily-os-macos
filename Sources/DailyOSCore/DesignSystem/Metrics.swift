import SwiftUI

/// Spacing, radii and hairlines.
///
/// One 4pt grid for both platforms. iOS gets larger *touch targets*, not larger
/// spacing — the rhythm of the layout should read as the same product whether it
/// is on a Mac or a phone.
public enum Metrics {
  // Spacing scale. Everything laid out uses one of these; no ad-hoc numbers.
  public static let xxs: CGFloat = 4
  public static let xs: CGFloat = 8
  public static let sm: CGFloat = 12
  public static let md: CGFloat = 16
  public static let lg: CGFloat = 24
  public static let xl: CGFloat = 32
  public static let xxl: CGFloat = 48

  // Corner radii.
  public static let radiusSmall: CGFloat = 6
  public static let radiusMedium: CGFloat = 10
  public static let radiusLarge: CGFloat = 16
  public static let radiusPill: CGFloat = 999

  /// Panel and divider stroke. Hairline, never heavier.
  public static let hairline: CGFloat = 1

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
}
