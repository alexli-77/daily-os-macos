import Foundation

/// Display formatting, in one place.
///
/// Timestamps are the most-repeated element in this app and the easiest to get
/// subtly inconsistent — "2 分钟前" in one panel, "14:32" in the next, "2026-09-09
/// 14:32:07" in a third. One helper each, used everywhere.
public enum Fmt {
  /// Dates follow the UI language, not the device.
  ///
  /// Every string in this app is hard-coded Chinese; there is no string catalog
  /// yet. Left to the device locale, a phone set to English renders
  /// "Wednesday, Sep 9 · 当前周期 8.24-9.6" and "更新于 Sep 6 at 1:21 AM" — the
  /// two halves of one sentence in two languages, which reads as a bug rather
  /// than as a setting.
  ///
  /// When the UI is actually localised this constant should be deleted, not
  /// changed: at that point the device locale becomes the right answer and
  /// pinning it would be the bug.
  private static let locale = Locale(identifier: "zh_Hans")

  /// "14:32"
  public static func time(_ date: Date) -> String {
    date.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(locale))
  }

  /// "9月9日 14:32" — for anything older than today.
  public static func stamp(_ date: Date, relativeTo now: Date = .now) -> String {
    if Calendar.current.isDate(date, inSameDayAs: now) {
      return time(date)
    }
    return date.formatted(.dateTime.month().day().hour().minute().locale(locale))
  }

  /// "9月9日 星期三" — the Today screen's subtitle.
  ///
  /// Here rather than in the screen because both platforms show it and a
  /// formatter written twice is a formatter that diverges once.
  public static func dayHeading(_ date: Date = .now) -> String {
    date.formatted(.dateTime.month().day().weekday(.wide).locale(locale))
  }

  /// "1.4s" / "2m 08s" — run durations.
  public static func duration(_ duration: Duration) -> String {
    let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    if seconds < 60 {
      return seconds < 10 ? String(format: "%.1fs", seconds) : String(format: "%.0fs", seconds)
    }
    let minutes = Int(seconds) / 60
    let rest = Int(seconds) % 60
    if minutes < 60 { return String(format: "%dm %02ds", minutes, rest) }
    return String(format: "%dh %02dm", minutes / 60, minutes % 60)
  }

  /// "1h30m" / "45m" — planned effort, which is read in hours-and-minutes, not
  /// in the seconds-precision form `duration(_:)` uses for machine runs.
  public static func minutes(_ total: Int) -> String {
    if total <= 0 { return "0m" }
    let hours = total / 60
    let rest = total % 60
    if hours == 0 { return "\(rest)m" }
    if rest == 0 { return "\(hours)h" }
    return "\(hours)h\(rest)m"
  }

  /// "12.4k" — token counts, which get long and are read at a glance.
  public static func compactCount(_ value: Int) -> String {
    if value < 1_000 { return "\(value)" }
    if value < 1_000_000 { return String(format: "%.1fk", Double(value) / 1_000) }
    return String(format: "%.2fM", Double(value) / 1_000_000)
  }

  /// "$0.0184" — small enough that rounding to cents would show "$0.02" for
  /// everything, which is useless when you are watching per-run cost.
  public static func money(_ value: Double) -> String {
    value < 1 ? String(format: "$%.4f", value) : String(format: "$%.2f", value)
  }

  /// "18 KB"
  public static func bytes(_ value: Int) -> String {
    value.formatted(.byteCount(style: .file))
  }

  /// "8.24-9.6 · 双周"
  public static func cycleTitle(_ cycle: Cycle) -> String {
    "\(cycle.label) · \(cycle.mode.label)"
  }
}
