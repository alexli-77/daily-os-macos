import SwiftUI

/// The type ramp.
///
/// ## Exact sizes *and* Dynamic Type
///
/// The spec sheet writes fixed numbers — display is 40/48/700, body is 14/24/400.
/// Taken literally as `Font.system(size: 40)` that would switch off the system's
/// own text-size setting: the reader who turns it up in Accessibility would find
/// this one app ignoring them, silently, with nothing on screen to explain why.
///
/// `Font.custom(_:size:relativeTo:)` gives both. `size` is the exact point size
/// at the default setting, `relativeTo` is the step it scales along. So the
/// numbers below are the spec's numbers, and they still grow when asked to.
///
/// ## The faces
///
/// All three ship with macOS and iOS, so nothing is bundled and there is no font
/// licence to carry:
///
/// | role | face | why |
/// | --- | --- | --- |
/// | serif | Songti SC | Ming/Song skeleton, same family as the Noto Serif SC the design was drawn in |
/// | sans | PingFang SC | the system Chinese sans; what every other Mac app's body text looks like |
/// | hand | Hanzipen SC | a real handwriting face, already on the system |
///
/// The design was drawn in Noto Serif SC / Noto Sans SC. Bundling those would
/// cost 20–40MB and an OFL notice for a difference that is visible at 40pt and
/// close to invisible at 14pt. Handwriting was the one that looked like it would
/// have to be bundled — until it turned out macOS already ships one.
///
/// Weight comes from picking the named face (`STSongti-SC-Bold`,
/// `PingFangSC-Medium`), not from `.weight()`: a synthesised bold on a CJK face
/// smears the strokes.
public enum Typo {
  // MARK: The six styles the design defines

  /// The date. One per screen. 40/48/700 serif.
  public static let display = Font.custom(Face.serifBold, size: 40, relativeTo: .largeTitle)
  /// Section heading. 16/24/700 serif.
  public static let heading = Font.custom(Face.serifBold, size: 16, relativeTo: .headline)
  /// Task text. 14/24/400 sans.
  public static let body = Font.custom(Face.sans, size: 14, relativeTo: .body)
  /// Time slots, buttons. 13/24/500 sans.
  public static let label = Font.custom(Face.sansMedium, size: 13, relativeTo: .subheadline)
  /// Explanations, sources, estimates. 12/16/400 sans.
  public static let caption = Font.custom(Face.sans, size: 12, relativeTo: .caption)
  /// "今天清完了", and nothing else. 34/44/400.
  public static let hand = Font.custom(Face.hand, size: 34, relativeTo: .title)

  /// Line heights, as the spec writes them. SwiftUI sets leading via
  /// `.lineSpacing`, which is the *gap* rather than the box — `lineSpacing(for:)`
  /// does the subtraction so a view never has to.
  public enum Leading {
    public static let display: CGFloat = 48
    public static let heading: CGFloat = 24
    public static let body: CGFloat = 24
    public static let label: CGFloat = 24
    public static let caption: CGFloat = 16
    public static let hand: CGFloat = 44
  }

  // MARK: - System layer
  //
  // Monospace is not in the spec sheet, and it is load-bearing: it is the only
  // visual difference between "the system produced this" and "you wrote this".
  // Run ids, cycle labels, file paths, cron expressions, model names, token
  // counts. Dropping it would not simplify the type ramp, it would delete a
  // distinction the product depends on — the same call made for the status
  // colours in `Palette`.

  public static let mono = Font.system(.caption, design: .monospaced)
  public static let monoBody = Font.system(.body, design: .monospaced)

  /// Emphasised body — a row that is due today, a KR that is off track.
  ///
  /// Also not in the spec sheet, and kept for the same reason as monospace:
  /// eight screens outside the Today page have list rows that need to say "this
  /// one" without a colour, and the alternative was to spend `mint400` on it.
  /// The Today page itself does not use this — there, emphasis is position.
  public static let bodyStrong = Font.custom(Face.sansMedium, size: 14, relativeTo: .body)

  /// Numbers in a column that has to line up (token usage, durations, cost).
  public static let tabularBody = Font.custom(Face.sans, size: 14, relativeTo: .body).monospacedDigit()
  public static let tabularCaption = Font.custom(Face.sans, size: 12, relativeTo: .caption).monospacedDigit()

  /// PostScript names. All present on stock macOS and iOS.
  private enum Face {
    static let serifBold = "STSongti-SC-Bold"
    static let sans = "PingFangSC-Regular"
    static let sansMedium = "PingFangSC-Medium"
    static let hand = "HanziPenSC-W3"
  }
}

// MARK: - Text conveniences

extension View {
  /// Primary text.
  public func inkStyle(_ font: Font = Typo.body) -> some View {
    self.font(font).foregroundStyle(Palette.ink)
  }

  /// Secondary text: metadata, timestamps, empty-state prose.
  public func mutedStyle(_ font: Font = Typo.caption) -> some View {
    self.font(font).foregroundStyle(Palette.ink2)
  }

  /// The spec's line height, applied as the gap SwiftUI actually wants.
  ///
  /// Clamped at zero: a leading smaller than the font size is a negative gap,
  /// which SwiftUI honours by overlapping the lines.
  public func lineSpacing(for style: CGFloat, size: CGFloat) -> some View {
    self.lineSpacing(max(0, style - size))
  }
}
