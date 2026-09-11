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

  private static let glyphSide: CGFloat = 26
  /// Both states are pinned to one height so the header does not jump by a line
  /// when a reading finally lands.
  private static let height: CGFloat = 34

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
          .fill(Palette.surface)
      }
      .overlay {
        RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous)
          .strokeBorder(Palette.line, lineWidth: Metrics.hairline)
      }
      .contentShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
    }
    .buttonStyle(.plain)
    .help(helpText)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(accessibilityText))
    .accessibilityHint(Text("点一下重新取一次天气"))
    .task { await keepFresh() }
  }

  @ViewBuilder private var glyph: some View {
    if let weather = state.weather {
      WeatherGlyph(look: WeatherLook(code: weather.code), isDay: weather.isDay)
        // Replaying the entrance is what makes a new reading noticeable without
        // anything having to flash: a changed id is a new view, and a new view
        // draws itself in from zero again. Three times a day, not once a frame.
        .id(weather.fetchedAt)
        .frame(width: Self.glyphSide, height: Self.glyphSide)
    } else {
      // The same hairline dashed outline the donut uses for "nothing to draw",
      // so an empty state in one corner of this screen looks like an empty state
      // in the other.
      Circle()
        .strokeBorder(Palette.line, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        .frame(width: 20, height: 20)
        .frame(width: Self.glyphSide, height: Self.glyphSide)
    }
  }

  @ViewBuilder private var text: some View {
    if let weather = state.weather {
      VStack(alignment: .leading, spacing: 1) {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.xxs) {
          Text(Self.degrees(weather.temperatureC))
            .font(Typo.tabularBody.weight(.medium))
            .foregroundStyle(Palette.ink)
          Text("\(Self.degrees(weather.low)) / \(Self.degrees(weather.high))")
            .font(Typo.tabularCaption)
            .foregroundStyle(Palette.inkMuted)
        }
        Text("\(WeatherLook(code: weather.code).label) · \(weather.place)")
          .mutedStyle()
          .lineLimit(1)
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
/// place to be lossy is the place that draws 26 points of cloud.
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

  var hasSun: Bool { self == .clear || self == .partly }
  var hasCloud: Bool { self != .clear }
}

/// A sun, a cloud and some weather under it, at 26 points.
///
/// Everything here animates exactly once, on appear. No `repeatForever`: a
/// looping animation holds a display link open for as long as the window is
/// visible, and this app is left open all day next to other work — a decoration
/// that spins the fans is a decoration that gets deleted. The motion is an
/// entrance, which means it plays when there is something new to see (a fresh
/// reading replaces the view, see `.id`) and is perfectly still the rest of the
/// time.
private struct WeatherGlyph: View {
  let look: WeatherLook
  let isDay: Bool

  /// 0 before the entrance, 1 after. Every element reads it and declares its own
  /// timing, which is how the drops can be staggered without a keyframe track.
  @State private var entrance: Double = 0

  private var cloudOpacity: Double {
    look == .cloudy || look == .fog ? 0.5 : 0.34
  }

  var body: some View {
    ZStack {
      if look.hasSun {
        if isDay { sun } else { moon }
      }
      if look.hasCloud { cloud }
      precipitation
    }
    .frame(width: 26, height: 26)
    .onAppear { entrance = 1 }
  }

  /// Rays only when there is no cloud in front. Eight little capsules behind a
  /// cloud at this size read as fuzz, not as sunshine.
  private var sun: some View {
    ZStack {
      if look == .clear {
        ForEach(0..<8, id: \.self) { index in
          Capsule()
            .fill(Palette.warn)
            .frame(width: 1.5, height: 3.5)
            .offset(y: -9)
            .rotationEffect(.degrees(Double(index) * 45))
        }
        .scaleEffect(0.6 + 0.4 * entrance)
        .rotationEffect(.degrees((1 - entrance) * 20))
        .opacity(entrance)
        .animation(.easeOut(duration: 0.8).delay(0.1), value: entrance)
      }
      Circle()
        .fill(Palette.warn)
        .frame(width: 11, height: 11)
        .scaleEffect(0.7 + 0.3 * entrance)
        .opacity(entrance)
        .animation(.spring(duration: 0.5), value: entrance)
    }
    .offset(x: look.hasCloud ? -6.5 : 0, y: look.hasCloud ? -6 : 0)
  }

  /// A symbol rather than a hand-drawn crescent, for the same reason as the
  /// bolt: a crescent is a disc with another disc punched out of it, and that
  /// cut edge is the first thing to go ragged when a 26-point drawing lands on a
  /// non-integral position. Two dots beside it, because a lone grey disc reads
  /// as a hole in the strip rather than as night.
  private var moon: some View {
    ZStack {
      Image(systemName: "moon.fill")
        .font(.system(size: 12))
        .foregroundStyle(Palette.inkMuted.opacity(0.75))
        .scaleEffect(0.7 + 0.3 * entrance)
        .opacity(entrance)
        .animation(.spring(duration: 0.5), value: entrance)
      ForEach(Array([CGSize(width: 8, height: -7), CGSize(width: -8, height: 6)].enumerated()), id: \.offset) { index, position in
        Circle()
          .fill(Palette.inkMuted.opacity(0.55))
          .frame(width: 2, height: 2)
          .offset(position)
          .opacity(entrance)
          .animation(.easeOut(duration: 0.6).delay(0.2 + Double(index) * 0.15), value: entrance)
      }
    }
    .offset(x: look.hasCloud ? -6.5 : 0, y: look.hasCloud ? -6 : 0)
  }

  /// Drifts in from the left and stops. Clouds move; this one moves once.
  ///
  /// The opacity is on the flattened group rather than in each shape's fill.
  /// Three translucent shapes stacked show their own overlaps, and the
  /// lens-shaped creases where they cross were the first thing the eye found in
  /// a drawing this small — a cloud has one silhouette, not three.
  private var cloud: some View {
    ZStack {
      Circle().frame(width: 9, height: 9).offset(x: -3.5, y: -2)
      Circle().frame(width: 11, height: 11).offset(x: 3, y: -3)
      Capsule().frame(width: 18, height: 8).offset(y: 1)
    }
    .foregroundStyle(Palette.inkMuted)
    .compositingGroup()
    .opacity(cloudOpacity * entrance)
    .offset(x: -6 * (1 - entrance) + 2, y: 1)
    .animation(.easeOut(duration: 0.7), value: entrance)
  }

  @ViewBuilder private var precipitation: some View {
    switch look {
    case .rain:
      falling { Capsule().fill(Palette.inkMuted.opacity(0.55)).frame(width: 1.5, height: 4) }
    case .snow:
      falling { Circle().fill(Palette.inkMuted.opacity(0.55)).frame(width: 3, height: 3) }
    case .fog:
      fog
    case .thunder:
      bolt
    case .clear, .partly, .cloudy:
      EmptyView()
    }
  }

  /// Three drops, staggered, each falling once and staying where it landed —
  /// which reads as drawn rain rather than as a paused animation.
  private func falling<Drop: View>(@ViewBuilder drop: @escaping () -> Drop) -> some View {
    HStack(spacing: 4) {
      ForEach(0..<3, id: \.self) { index in
        drop()
          .offset(y: 6 * entrance)
          .opacity(entrance)
          .animation(.easeIn(duration: 0.45).delay(0.25 + Double(index) * 0.12), value: entrance)
      }
    }
    .offset(y: 5)
  }

  /// Two hairlines under the cloud, widening in. Fog is the one condition with
  /// no shape of its own, so it borrows the system's: a line.
  private var fog: some View {
    VStack(alignment: .leading, spacing: 3) {
      ForEach(0..<2, id: \.self) { index in
        Capsule()
          .fill(Palette.inkMuted.opacity(0.45))
          .frame(width: index == 0 ? 16 : 11, height: 1.5)
          .scaleEffect(x: entrance, anchor: .leading)
          .opacity(entrance)
          .animation(.easeOut(duration: 0.5).delay(0.3 + Double(index) * 0.12), value: entrance)
      }
    }
    .offset(x: -3, y: 8)
  }

  private var bolt: some View {
    Image(systemName: "bolt.fill")
      .font(.system(size: 9, weight: .semibold))
      .foregroundStyle(Palette.warn)
      .offset(y: 8)
      .scaleEffect(0.5 + 0.5 * entrance, anchor: .top)
      .opacity(entrance)
      .animation(.spring(duration: 0.45).delay(0.3), value: entrance)
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
