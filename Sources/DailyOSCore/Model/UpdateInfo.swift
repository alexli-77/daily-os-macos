import Foundation

/// A published build newer than this one.
///
/// Lightweight on purpose (LEO-296): the app has no Apple Developer account yet,
/// so it is not signed, not notarised, and cannot auto-update. What it *can* do
/// is read a small published manifest, notice it is behind, and point at the
/// download. No Sparkle, no appcast — one JSON file and a link.
public struct UpdateInfo: Sendable, Equatable {
  /// The published version string (`CFBundleShortVersionString`).
  public let version: String
  /// The published build's short commit — the real identity, since the version
  /// string is `0.1.0` in every build (see `BuildInfo`).
  public let commit: String
  /// Where to get it. A page a human opens, not a direct binary pull.
  public let url: URL
  /// When the published build was made, for ordering against this build.
  public let builtAt: Date?

  public init(version: String, commit: String, url: URL, builtAt: Date?) {
    self.version = version
    self.commit = commit
    self.url = url
    self.builtAt = builtAt
  }

  /// A short "v0.1.19 · ab12cd" for the settings row.
  public var label: String {
    commit.isEmpty ? version : "\(version) · \(commit)"
  }

  /// Decide, purely, whether a published manifest is a newer build than this
  /// one — and if so, the `UpdateInfo` to surface. Kept here (not in the client
  /// actor) so it is one import away from the checks target and has no network.
  ///
  /// Conservative on purpose:
  /// - An unstamped local build (no commit — built by hand, not by package.sh)
  ///   never nags: it has no honest way to order itself against a release.
  /// - Same commit → not newer.
  /// - Different commit with both dates known → newer only if the manifest is
  ///   strictly later, so a dev machine ahead of the last release is not nagged.
  /// - Different commit, dates missing → treated as newer: the manifest only
  ///   ever advertises a release, so a mismatch is almost always behind.
  /// - A manifest whose url does not parse yields nil.
  public static func resolve(
    localCommit: String,
    localBuiltAt: Date?,
    manifestVersion: String,
    manifestCommit: String,
    manifestURL: String,
    manifestDate: Date?
  ) -> UpdateInfo? {
    guard !localCommit.isEmpty else { return nil }
    guard manifestCommit != localCommit else { return nil }
    guard let url = URL(string: manifestURL) else { return nil }
    if let published = manifestDate, let local = localBuiltAt, published <= local { return nil }
    return UpdateInfo(version: manifestVersion, commit: manifestCommit, url: url, builtAt: manifestDate)
  }
}
