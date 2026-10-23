import Foundation
import DailyOSCore

// The "am I behind?" check behind the Settings → 服务 → App 版本 row.
//
// Like WeatherStore, this talks to an arbitrary https URL rather than the local
// service: the service has never heard of releases, and gating "there is a new
// build" behind "the service is up" would be backwards — a stuck service is
// exactly when you want to know a fix shipped. One GET of a static manifest, no
// token, short timeout; on any failure it stays quiet rather than guessing.

/// Fetches the published build manifest and decides whether it is newer than
/// this build. An actor only for symmetry with the rest of the client target;
/// it holds no state worth protecting.
public actor UpdateChecker {
  /// The manifest `scripts/release.sh` publishes. Raw main, so there is nothing
  /// to host and nothing to pay for — the release commit updating this file is
  /// the whole release channel.
  private static let manifestURL = URL(string: "https://raw.githubusercontent.com/alexli-77/daily-os-macos/main/release/latest.json")!

  public init() {}

  /// A newer published build, or nil — nil meaning current, unknown, or
  /// unreachable, all of which render the same way: no nag.
  public func check() async -> UpdateInfo? {
    guard let manifest = await fetch() else { return nil }
    return UpdateInfo.resolve(
      localCommit: BuildInfo.commit,
      localBuiltAt: BuildInfo.builtAt,
      manifestVersion: manifest.version,
      manifestCommit: manifest.commit,
      manifestURL: manifest.url,
      manifestDate: manifest.builtAtDate
    )
  }

  private struct Manifest: Decodable {
    let version: String
    let commit: String
    let url: String
    let date: String?

    var builtAtDate: Date? {
      guard let date, !date.isEmpty else { return nil }
      return ISO8601DateFormatter().date(from: date)
    }
  }

  private func fetch() async -> Manifest? {
    var request = URLRequest(url: Self.manifestURL)
    request.timeoutInterval = 10
    request.cachePolicy = .reloadIgnoringLocalCacheData
    do {
      let (data, response) = try await URLSession.shared.data(for: request)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
      return try JSONDecoder().decode(Manifest.self, from: data)
    } catch {
      return nil
    }
  }
}
