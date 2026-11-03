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
///
/// ## macOS: the system font, everywhere
///
/// On the Mac every style resolves to the system font instead — SF for Latin
/// and digits, PingFang SC for Chinese, chosen by the system per glyph. Three
/// faces side by side read as three apps: Songti's Latin is a book face, so a
/// title like `cycle-plan` or `OKR` sat next to `今天` looking pasted in, and
/// PingFang's Latin differs from SF's in every hyphen and digit while the
/// hundred-odd system controls (pickers, toggles, fields) all render in SF.
/// SF and PingFang were drawn to pair; weights match across the two scripts.
///
/// iOS keeps the named faces for now: `Font.custom(_:size:relativeTo:)` is how
/// those sizes follow Dynamic Type there, and SwiftUI has no system-font
/// equivalent that takes an exact size *and* a text style to scale along.
public enum Typo {
  // MARK: The six styles the design defines

  /// The date. One per screen. 40/48/700 serif.
  public static let display = face(Face.serifBold, 40, .bold, .largeTitle)
  /// Section heading. 16/24/700 serif.
  public static let heading = face(Face.serifBold, 16, .semibold, .headline)
  /// Task text. 14/24/400 sans.
  public static let body = face(Face.sans, 14, .regular, .body)
  /// Time slots, buttons. 13/24/500 sans.
  public static let label = face(Face.sansMedium, 13, .medium, .subheadline)
  /// Explanations, sources, estimates. 12/16/400 sans.
  public static let caption = face(Face.sans, 12, .regular, .caption)
  /// "今天清完了", and nothing else. 34/44/400.
  public static let hand = face(Face.hand, 34, .regular, .title)

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
  public static let bodyStrong = face(Face.sansMedium, 14, .medium, .body)

  /// Numbers in a column that has to line up (token usage, durations, cost).
  public static let tabularBody = face(Face.sans, 14, .regular, .body).monospacedDigit()
  public static let tabularCaption = face(Face.sans, 12, .regular, .caption).monospacedDigit()

  /// A single focal number — the temperature on the weather strip. The one place
  /// a reading is the thing being looked at rather than a cell in a column.
  public static let tabularTitle = face(Face.sansMedium, 20, .medium, .title3).monospacedDigit()

  /// The system font on macOS, the named face elsewhere. See "macOS: the
  /// system font, everywhere" above.
  private static func face(_ name: String, _ size: CGFloat, _ weight: Font.Weight, _ style: Font.TextStyle) -> Font {
    #if os(macOS)
    Font.system(size: size, weight: weight)
    #else
    Font.custom(name, size: size, relativeTo: style)
    #endif
  }

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
