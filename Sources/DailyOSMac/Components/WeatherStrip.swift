import SwiftUI
import DailyOSCore

/// The weather, in the empty half of the 今天 header.
///
/// It sits in `ScreenScaffold`'s toolbar slot rather than in a panel of its own,
/// and the reason is the whole brief: this is decoration. A panel would give it
/// the same weight as 今日进度 and push the day's actual content down by fifty
/// points to say that it is thirteen degrees. The toolbar slot is space the
/// screen was already wasting.
///
/// Three things it has to be honest about, because all three are normal:
/// location refused, network down, and never fetched. None of them may produce a
/// number — a strip that invents 20° to avoid looking broken is worse than a
/// strip that says it has nothing, since the only reason to glance at it is to
/// find out whether to take a coat.
///
/// Tapping it forces a fetch. That is the whole retry story, and it is enough:
/// the failure modes are all transient and the cost of being wrong is a wasted
/// HTTP request.
struct WeatherStrip: View {
  @Environment(AppState.self) private var state

  private static let glyphSide: CGFloat = 34
  /// Both states are pinned to one height so the header does not jump by a line
  /// when a reading finally lands.
  private static let height: CGFloat = 34

  /// The strip has no frame of its own — it sits on the screen's paper. The only
  /// mark it makes is a mint wash while the pointer is over it, so the tap target
  /// is discoverable without a permanent box competing with 今日进度.
  @State private var hovering = false

  var body: some View {
    Button {
      Task { await state.refreshWeather(force: true) }
    } label: {
      HStack(spacing: Metrics.xs) {
        glyph
        text
      }
      .padding(.horizontal, Metrics.xs)
      .frame(height: Self.height)
      .background {
        RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous)
          .fill(hovering ? Palette.mint50 : .clear)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
    .animation(.easeOut(duration: 0.12), value: hovering)
    .help(helpText)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(accessibilityText))
    .accessibilityHint(Text("点一下重新取一次天气"))
    .task { await keepFresh() }
  }

  @ViewBuilder private var glyph: some View {
    if let weather = state.weather {
      WeatherIcon(look: WeatherLook(code: weather.code), isDay: weather.isDay)
        .frame(width: Self.glyphSide, height: Self.glyphSide)
    } else {
      // The same hairline dashed outline the donut uses for "nothing to draw",
      // so an empty state in one corner of this screen looks like an empty state
      // in the other.
      Circle()
        .strokeBorder(Palette.rule, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .frame(width: 20, height: 20)
        .frame(width: Self.glyphSide, height: Self.glyphSide)
    }
  }

  @ViewBuilder private var text: some View {
    if let weather = state.weather {
      HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
        // One focal number. Everything beside it is demoted a step so the eye
        // lands on the temperature first and reads the rest only if it wants to.
        Text(Self.degrees(weather.temperatureC))
          .font(Typo.tabularTitle)
          .foregroundStyle(Palette.ink)
        VStack(alignment: .leading, spacing: 1) {
          HStack(alignment: .firstTextBaseline, spacing: Metrics.xxs) {
            Text(WeatherLook(code: weather.code).label)
              .font(Typo.label)
              .foregroundStyle(Palette.ink2)
            Text("\(Self.degrees(weather.low)) / \(Self.degrees(weather.high))")
              .font(Typo.tabularCaption)
              .foregroundStyle(Palette.ink2)
          }
          Text(weather.place)
            .font(Typo.caption)
            .foregroundStyle(Palette.ink3)
            .lineLimit(1)
        }
      }
    } else {
      Text("天气还没取到，点一下重试")
        .mutedStyle()
        .lineLimit(1)
    }
  }

  private var helpText: String {
    guard let weather = state.weather else {
      return "没有天气数据。可能是没给定位权限，也可能是取不到 Open-Meteo。"
    }
    return "\(weather.place) · 取于 \(Fmt.stamp(weather.fetchedAt))。每天早中晚各取一次，点一下立刻重取。"
  }

  private var accessibilityText: String {
    guard let weather = state.weather else { return "天气还没取到" }
    let look = WeatherLook(code: weather.code)
    return "天气 \(look.label)，\(Self.degrees(weather.temperatureC))，\(weather.place)"
  }

  /// Ask on appear, then once per slot boundary for as long as this screen is up.
  ///
  /// `refreshWeather` is cheap when the reading is already this slot's, so the
  /// appearance call is free; the sleep is what turns "three times a day" into
  /// something that happens while the window simply stays open, which is how
  /// this app is actually used. A sleeping task costs nothing — the alternative,
  /// a repeating timer, wakes the machine to discover that nothing is due.
  private func keepFresh() async {
    while !Task.isCancelled {
      await state.refreshWeather()
      guard let seconds = Self.secondsUntilNextSlot(), seconds > 0 else { return }
      try? await Task.sleep(for: .seconds(seconds))
    }
  }

  /// Seconds until the next of 12:00 / 18:00 / midnight, plus a moment.
  ///
  /// The margin matters: waking exactly on the boundary can land in the second
  /// before it by rounding, and `isFresh` would then say the old reading is
  /// still this slot's and the loop would spin.
  private static func secondsUntilNextSlot(from now: Date = .now) -> TimeInterval? {
    let calendar = Calendar.current
    let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
    let boundaries = [12, 18]
      .compactMap { calendar.date(bySettingHour: $0, minute: 0, second: 0, of: now) }
      + [midnight].compactMap { $0 }
    guard let next = boundaries.filter({ $0 > now }).min() else { return nil }
    return next.timeIntervalSince(now) + 30
  }

  /// "13°" — rounded, because a strip this size has no room to claim a tenth of
  /// a degree and nobody dresses differently for one.
  private static func degrees(_ value: Double) -> String {
    String(format: "%.0f°", value)
  }
}

// MARK: - The drawing

/// What a WMO code looks like.
///
/// The mapping lives here and not in the decoder on purpose: `WeatherSnapshot`
/// carries the raw code precisely so that "code 71 is snow" stays a drawing
/// decision. Collapsing ninety-nine codes into seven pictures is lossy, and the
/// place to be lossy is the place that picks one small icon.
private enum WeatherLook {
  case clear, partly, cloudy, fog, rain, snow, thunder

  init(code: Int) {
    switch code {
    case 0: self = .clear
    case 1, 2: self = .partly
    case 45, 48: self = .fog
    case 71...77, 85, 86: self = .snow
    case 95...99: self = .thunder
    case 51...67, 80...82: self = .rain
    // 3 is overcast, and so is anything Open-Meteo adds later. A code this app
    // has never heard of is still weather; drawing a cloud is a better answer
    // than drawing nothing.
    default: self = .cloudy
    }
  }

  var label: String {
    switch self {
    case .clear: "晴"
    case .partly: "多云"
    case .cloudy: "阴"
    case .fog: "雾"
    case .rain: "雨"
    case .snow: "雪"
    case .thunder: "雷雨"
    }
  }
}

/// The condition as one SF Symbol, in brand ink rather than system multicolour.
///
/// `.palette` and not `.multicolor` on purpose: multicolour pulls the system's
/// own blues and yellows, and a blue raindrop on a page of mint reads as a
/// second brand. So the layers are assigned by hand — the warm mark (sun, bolt)
/// is `warn`, the cloud is a muted `ink3`, and precipitation is `mint400` so the
/// wet conditions stay inside the palette. The layer order is the one Apple
/// ships: cloud first, then the accent it carries.
private struct WeatherIcon: View {
  let look: WeatherLook
  let isDay: Bool

  var body: some View {
    symbol
      .font(.system(size: 30))
      .symbolRenderingMode(.palette)
  }

  @ViewBuilder private var symbol: some View {
    switch look {
    case .clear:
      if isDay {
        Image(systemName: "sun.max.fill").foregroundStyle(Palette.warn)
      } else {
        Image(systemName: "moon.stars.fill").foregroundStyle(Palette.warn, Palette.ink3)
      }
    case .partly:
      Image(systemName: isDay ? "cloud.sun.fill" : "cloud.moon.fill")
        .foregroundStyle(Palette.ink3, Palette.warn)
    case .cloudy:
      Image(systemName: "cloud.fill").foregroundStyle(Palette.ink3)
    case .fog:
      Image(systemName: "cloud.fog.fill").foregroundStyle(Palette.ink3, Palette.ink2)
    case .rain:
      Image(systemName: "cloud.rain.fill").foregroundStyle(Palette.ink3, Palette.mint400)
    case .snow:
      Image(systemName: "cloud.snow.fill").foregroundStyle(Palette.ink3, Palette.mint400)
    case .thunder:
      Image(systemName: "cloud.bolt.rain.fill")
        .foregroundStyle(Palette.ink3, Palette.warn, Palette.mint400)
    }
  }
}

// MARK: - Previews

/// Every condition at once, which is the only way to check that none of them is
/// louder than the others.
#Preview("天气") {
  VStack(alignment: .leading, spacing: Metrics.sm) {
    ForEach([0, 2, 3, 45, 61, 73, 95], id: \.self) { code in
      TodayScreenWeatherPreview(code: code)
    }
    TodayScreenWeatherPreview(code: nil)
  }
  .padding(Metrics.lg)
  .background(Palette.paper)
}

private struct TodayScreenWeatherPreview: View {
  let code: Int?

  var body: some View {
    WeatherStrip()
      .environment(previewState(code: code))
  }

  @MainActor private func previewState(code: Int?) -> AppState {
    let state = AppState.previewOwner()
    state.weather = code.map {
      WeatherSnapshot(
        code: $0,
        temperatureC: 13.4,
        high: 21.6,
        low: 12.6,
        isDay: $0 != 2,
        place: "蒙特利尔",
        fetchedAt: .now
      )
    }
    return state
  }
}
