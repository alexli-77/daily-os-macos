import CoreLocation
import Foundation
import DailyOSCore

// The weather behind the strip at the top of Today.
//
// The one thing in this target that does not talk to daily-os. The service has
// never heard of weather and teaching it would put a decoration behind a process
// that has to be running — the top of Today would then go blank for the same
// reason a cycle does, which is a much bigger claim than "it is 13 degrees".
// Open-Meteo answers without a key and CoreLocation says where to ask about;
// both are this client's own business.

/// Fetches today's weather, caches it on disk, and refuses to go to the network
/// when it does not need to.
///
/// An actor because the cache is the whole point. Two screens appearing at once
/// — the window and the menu bar item both read `AppState` — would otherwise
/// race into two fetches and two writes of the same file.
public actor WeatherStore {
  /// Read from disk exactly once per launch. Separate from `cached == nil`
  /// because "never fetched" is a real, persistent state: without this flag a
  /// machine that has never had a successful fetch would re-read a file that is
  /// not there on every appearance.
  private var didReadCache = false
  private var cached: WeatherSnapshot?

  public init() {}

  /// Today's weather, or whatever is left over when it cannot be fetched.
  ///
  /// Returns the stale cache rather than nil when the network fails: the strip
  /// prints the time the reading was taken, so yesterday evening's 13° labelled
  /// "昨天 18:03" is honest, while blanking the strip throws away the last thing
  /// that was true for no gain.
  public func snapshot(force: Bool = false) async -> WeatherSnapshot? {
    if !didReadCache {
      didReadCache = true
      cached = Self.readCache()
    }
    if !force, let cached, cached.isFresh() { return cached }

    let place = await resolvePlace()
    do {
      let fetched = try await fetch(place)
      cached = fetched
      Self.writeCache(fetched)
      return fetched
    } catch {
      return cached
    }
  }

  // MARK: - Where to ask about

  /// A coordinate and what to call it on screen.
  private struct Place {
    let latitude: Double
    let longitude: Double
    let name: String
  }

  /// The device's location, or the configured stand-in.
  ///
  /// Refusing the permission prompt is a supported answer, not an error: the
  /// fallback place is fetched exactly the same way, and its name carries
  /// "（默认）" because `place` is the only channel the strip has to say "this is
  /// not where you are". A city you did not ask about, printed as if it were
  /// yours, is the one dishonest state this feature could have.
  private func resolvePlace() async -> Place {
    guard let coordinate = await Self.deviceCoordinate() else { return Self.fallbackPlace() }
    let name = await Self.placeName(for: coordinate)
    return Place(latitude: coordinate.latitude, longitude: coordinate.longitude, name: name ?? "当前位置")
  }

  /// Where to ask about when there is no location to use.
  ///
  /// Overridable without a settings screen, because the strip must not become
  /// the reason this app grows one:
  ///
  ///     defaults write com.example.dailyos.mac weather.place.name 北京
  ///     defaults write com.example.dailyos.mac weather.place.latitude 39.9042
  ///     defaults write com.example.dailyos.mac weather.place.longitude 116.4074
  private static func fallbackPlace() -> Place {
    let defaults = UserDefaults.standard
    let name = defaults.string(forKey: "weather.place.name") ?? "蒙特利尔"
    let latitude = defaults.object(forKey: "weather.place.latitude") as? Double
    let longitude = defaults.object(forKey: "weather.place.longitude") as? Double
    return Place(
      latitude: latitude ?? 45.5019,
      longitude: longitude ?? -73.5674,
      name: "\(name)（默认）"
    )
  }

  /// One location fix, or nil.
  ///
  /// Timed out rather than awaited, because every way this can fail is a way it
  /// can fail *silently*: a denied prompt answers, but a bundle with no
  /// `NSLocationWhenInUseUsageDescription` never gets a prompt at all and the
  /// stream simply never yields. Six seconds and then the fallback — the strip
  /// is decoration and must never be the reason Today takes a minute to draw.
  private static func deviceCoordinate() async -> CLLocationCoordinate2D? {
    if await isRefused() { return nil }
    return await withTaskGroup(of: CLLocationCoordinate2D?.self) { group in
      group.addTask { await liveCoordinate() }
      group.addTask {
        try? await Task.sleep(for: .seconds(6))
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }
  }

  /// Already said no, on this machine, at some point.
  ///
  /// Asked before starting the stream rather than read off it: the update's own
  /// `authorizationDenied` arrived in macOS 15 and this app ships back to 14, so
  /// on 14 a refusal would be indistinguishable from a slow fix and cost the
  /// full timeout on every attempt.
  @MainActor private static func isRefused() -> Bool {
    switch CLLocationManager().authorizationStatus {
    case .denied, .restricted: true
    default: false
    }
  }

  /// `CLLocationUpdate` rather than a `CLLocationManager` delegate: it raises
  /// the permission prompt on first use by itself and is an `AsyncSequence`, so
  /// there is no delegate object to keep alive across a suspension.
  private static func liveCoordinate() async -> CLLocationCoordinate2D? {
    do {
      for try await update in CLLocationUpdate.liveUpdates(.default) {
        if let location = update.location { return location.coordinate }
      }
    } catch {
      return nil
    }
    return nil
  }

  /// Pinned to Chinese for the same reason `Fmt` pins its dates: every string in
  /// this app is hard-coded Chinese, and "Montreal · 多云" is one sentence in two
  /// languages, which reads as a bug rather than as a setting.
  @MainActor private static func placeName(for coordinate: CLLocationCoordinate2D) async -> String? {
    let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    let placemarks = try? await CLGeocoder().reverseGeocodeLocation(
      location,
      preferredLocale: Locale(identifier: "zh_Hans")
    )
    guard let mark = placemarks?.first else { return nil }
    return mark.locality ?? mark.subAdministrativeArea ?? mark.administrativeArea
  }

  // MARK: - Open-Meteo

  /// The shape of `/v1/forecast`, and only the parts the strip draws.
  ///
  /// Spelled out rather than decoded with `.convertFromSnakeCase`, because that
  /// strategy turns `temperature_2m` into `temperature2m` — a name nobody would
  /// write, sitting in the one place where a rename is a silent decode failure.
  private struct Forecast: Decodable {
    struct Current: Decodable {
      let temperature: Double
      let code: Int
      let isDay: Int

      enum CodingKeys: String, CodingKey {
        case temperature = "temperature_2m"
        case code = "weather_code"
        case isDay = "is_day"
      }
    }

    struct Daily: Decodable {
      let high: [Double]
      let low: [Double]

      enum CodingKeys: String, CodingKey {
        case high = "temperature_2m_max"
        case low = "temperature_2m_min"
      }
    }

    let current: Current
    let daily: Daily
  }

  private func fetch(_ place: Place) async throws -> WeatherSnapshot {
    var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
    components?.queryItems = [
      URLQueryItem(name: "latitude", value: String(place.latitude)),
      URLQueryItem(name: "longitude", value: String(place.longitude)),
      URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
      URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
      // The day's high and low have to be *the local day's*, or an evening
      // reading in Montréal reports a low that belongs to tomorrow in UTC.
      URLQueryItem(name: "timezone", value: "auto"),
      URLQueryItem(name: "forecast_days", value: "1"),
    ]
    guard let url = components?.url else { throw URLError(.badURL) }

    var request = URLRequest(url: url)
    // Shorter than the service client's 30s on purpose: nothing on this screen
    // waits for the answer, and a request still outstanding when the slot rolls
    // over is a request whose answer is already stale.
    request.timeoutInterval = 10
    let (data, _) = try await URLSession.shared.data(for: request)
    let forecast = try JSONDecoder().decode(Forecast.self, from: data)

    return WeatherSnapshot(
      code: forecast.current.code,
      temperatureC: forecast.current.temperature,
      // Falls back to the current reading rather than to zero: an empty `daily`
      // array would otherwise print "0° / 0°", which reads as a cold snap.
      high: forecast.daily.high.first ?? forecast.current.temperature,
      low: forecast.daily.low.first ?? forecast.current.temperature,
      isDay: forecast.current.isDay == 1,
      place: place.name,
      fetchedAt: .now
    )
  }

  // MARK: - Disk

  /// The on-disk form.
  ///
  /// A mirror rather than `Codable` on `WeatherSnapshot` itself, so that the
  /// display type stays a display type: the moment the model is also the file
  /// format, renaming a field becomes a migration.
  private struct Stored: Codable {
    let code: Int
    let temperatureC: Double
    let high: Double
    let low: Double
    let isDay: Bool
    let place: String
    let fetchedAt: Date
  }

  /// `Application Support/DailyOS/weather.json`. Not `Caches`: the whole point
  /// of writing it down is that a relaunch does not refetch, and the system is
  /// free to empty Caches between one launch and the next.
  private static func cacheURL() -> URL? {
    guard let support = try? FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ) else { return nil }
    let directory = support.appending(path: "DailyOS", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "weather.json")
  }

  private static func readCache() -> WeatherSnapshot? {
    guard let url = cacheURL(),
          let data = try? Data(contentsOf: url),
          let stored = try? JSONDecoder().decode(Stored.self, from: data)
    else { return nil }
    return WeatherSnapshot(
      code: stored.code,
      temperatureC: stored.temperatureC,
      high: stored.high,
      low: stored.low,
      isDay: stored.isDay,
      place: stored.place,
      fetchedAt: stored.fetchedAt
    )
  }

  /// Best effort. A weather reading that cannot be written down costs one extra
  /// fetch after the next launch, which is not worth surfacing to anyone.
  private static func writeCache(_ snapshot: WeatherSnapshot) {
    let stored = Stored(
      code: snapshot.code,
      temperatureC: snapshot.temperatureC,
      high: snapshot.high,
      low: snapshot.low,
      isDay: snapshot.isDay,
      place: snapshot.place,
      fetchedAt: snapshot.fetchedAt
    )
    guard let url = cacheURL(), let data = try? JSONEncoder().encode(stored) else { return }
    try? data.write(to: url, options: .atomic)
  }
}
