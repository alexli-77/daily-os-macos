import Foundation

/// Which build this is.
///
/// Exists because "am I running the latest?" had no answer from inside the app.
/// `CFBundleShortVersionString` is `0.1.0` and `CFBundleVersion` is `1` in every
/// build ever made from this repo, so two apps a week apart are indistinguishable
/// — and the only way to check was to read a binary's mtime in a terminal, which
/// is not a thing to ask of someone who just wants to know whether their fix
/// landed.
///
/// `scripts/package.sh` stamps the commit and the build time into `Info.plist`
/// after the build. A build made any other way has no stamp, and says so rather
/// than showing a blank or, worse, a stale one.
public enum BuildInfo {
  /// Short commit hash, or empty when this build was not packaged by the script.
  public static var commit: String {
    string("DailyOSBuildCommit")
  }

  /// Set when the working tree had uncommitted changes at package time. Worth
  /// surfacing: a stamped commit that does not describe the code in the bundle
  /// is more misleading than no stamp at all.
  public static var isDirty: Bool {
    string("DailyOSBuildDirty") == "YES"
  }

  public static var builtAt: Date? {
    let raw = string("DailyOSBuildDate")
    guard !raw.isEmpty else { return nil }
    return ISO8601DateFormatter().date(from: raw)
  }

  public static var version: String {
    string("CFBundleShortVersionString")
  }

  /// One line for a settings row.
  public static var summary: String {
    guard !commit.isEmpty else {
      return "\(version) · 这个包不是用 scripts/package.sh 打的，没有版本戳"
    }
    var parts = ["\(version) · \(commit)"]
    if isDirty { parts.append("有未提交改动") }
    if let builtAt { parts.append(Fmt.stamp(builtAt)) }
    return parts.joined(separator: " · ")
  }

  private static func string(_ key: String) -> String {
    Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
  }
}
