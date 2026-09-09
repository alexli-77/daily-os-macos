import Foundation

/// Display formatting, in one place.
///
/// Timestamps are the most-repeated element in this app and the easiest to get
/// subtly inconsistent — "2 分钟前" in one panel, "14:32" in the next, "2026-09-09
/// 14:32:07" in a third. One helper each, used everywhere.
public enum Fmt {
  /// "14:32"
  public static func time(_ date: Date) -> String {
    date.formatted(date: .omitted, time: .shortened)
  }

  /// "9月9日 14:32" — for anything older than today.
  public static func stamp(_ date: Date, relativeTo now: Date = .now) -> String {
    if Calendar.current.isDate(date, inSameDayAs: now) {
      return time(date)
    }
    return date.formatted(.dateTime.month().day().hour().minute())
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
