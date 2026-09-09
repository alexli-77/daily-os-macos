import SwiftUI

/// The type ramp.
///
/// Built on `Font.system(_:design:)` rather than fixed point sizes so every
/// style tracks Dynamic Type on iOS and the accessibility text size on macOS.
/// The web console shipped a three-step font control (small / medium / large,
/// LEO-290); on Apple platforms that control belongs to the OS, so the app reads
/// the system setting instead of inventing a second one. See DESIGN.md §Type.
public enum Typo {
  /// Screen title. One per screen, top-left.
  public static let display = Font.system(.title, design: .default).weight(.semibold)
  /// Panel title.
  public static let title = Font.system(.title3, design: .default).weight(.semibold)
  /// Sub-heading inside a panel.
  public static let heading = Font.system(.headline, design: .default)
  /// Body copy and list rows.
  public static let body = Font.system(.body, design: .default)
  /// Emphasised body — a todo that is due today, a KR that is off track.
  public static let bodyStrong = Font.system(.body, design: .default).weight(.medium)
  /// Metadata: timestamps, counts, "synced at", file paths in prose.
  public static let caption = Font.system(.caption, design: .default)
  /// Pill and badge text.
  public static let label = Font.system(.caption2, design: .default).weight(.semibold)

  /// Anything machine-shaped: run ids, cycle labels, file paths, token counts,
  /// cron expressions, model names. Monospace is load-bearing here — it is how
  /// you tell "something the system produced" from "something you wrote".
  public static let mono = Font.system(.caption, design: .monospaced)
  public static let monoBody = Font.system(.body, design: .monospaced)

  /// Numbers in a column that has to line up (token usage, durations, cost).
  public static let tabularBody = Font.system(.body, design: .default).monospacedDigit()
  public static let tabularCaption = Font.system(.caption, design: .default).monospacedDigit()
}

// MARK: - Text conveniences

extension View {
  /// Primary text.
  public func inkStyle(_ font: Font = Typo.body) -> some View {
    self.font(font).foregroundStyle(Palette.ink)
  }

  /// Secondary text: metadata, timestamps, empty-state prose.
  public func mutedStyle(_ font: Font = Typo.caption) -> some View {
    self.font(font).foregroundStyle(Palette.inkMuted)
  }
}
