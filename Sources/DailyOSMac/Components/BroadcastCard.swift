import SwiftUI
import AVFoundation
import DailyOSCore

/// 今日 AI 播报 — the daily audio brief from the AI News Radar.
///
/// Read straight off the radar's public GitHub Pages files (one shared `latest`
/// for everyone, refreshed daily): no backend, no hosting, no token. The card
/// plays the mp3 and shows the text digest; it is general AI news, not anything
/// derived from the user's own Daily OS data.
struct BroadcastCard: View {
  @Environment(\.openURL) private var openURL

  @State private var broadcast: DailyBroadcast?
  @State private var state: LoadState = .loading
  @State private var player: AVPlayer?
  @State private var playing = false

  private enum LoadState { case loading, ready, failed }

  private static let homeURL = URL(string: "https://alexli-77.github.io/daily-news-radar/")!

  var body: some View {
    Panel("今日 AI 播报", subtitle: subtitle) {
      switch state {
      case .loading:
        HStack(spacing: Metrics.xs) {
          ProgressView().controlSize(.small)
          Text("正在拉取…").mutedStyle(Typo.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      case .failed:
        Text("没拉到今天的播报").mutedStyle(Typo.caption)
      case .ready:
        if let broadcast { content(broadcast) }
      }
    } actions: {
      Button { openURL(Self.homeURL) } label: { Image(systemName: "arrow.up.right.square") }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.inkMuted)
        .help("打开 AI News Radar")
    }
    .task { await load() }
    .onDisappear { player?.pause() }
    .onReceive(NotificationCenter.default.publisher(for: AVPlayerItem.didPlayToEndTimeNotification)) { _ in
      playing = false
      player?.seek(to: .zero)
    }
  }

  private func content(_ broadcast: DailyBroadcast) -> some View {
    VStack(alignment: .leading, spacing: Metrics.sm) {
      HStack(spacing: Metrics.xs) {
        Button { toggle(broadcast) } label: {
          Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
            .font(.system(size: 30))
            .foregroundStyle(Palette.chatAccent)
        }
        .buttonStyle(.plain)
        .help(playing ? "暂停" : "播放今日播报")
        Text(playing ? "播放中" : "点开听今天的 AI 要闻")
          .mutedStyle(Typo.caption)
      }

      if !broadcast.digest.isEmpty {
        ScrollView {
          Text(digestText(broadcast.digest))
            .font(Typo.caption)
            .foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
        }
        .frame(maxHeight: 150)
      }
    }
  }

  private var subtitle: String? {
    guard let date = broadcast?.publishedAt else { return nil }
    return "AI News Radar · \(Self.dayFormatter.string(from: date))"
  }

  private func toggle(_ broadcast: DailyBroadcast) {
    if player == nil { player = AVPlayer(url: broadcast.audioURL) }
    if playing { player?.pause() } else { player?.play() }
    playing.toggle()
  }

  private func load() async {
    guard broadcast == nil else { return }
    if let fetched = await DailyBroadcast.fetch() {
      broadcast = fetched
      state = .ready
    } else {
      state = .failed
    }
  }

  /// Render the digest markdown inline (bold/links), keeping its line breaks;
  /// falls back to the raw text if it will not parse.
  private func digestText(_ markdown: String) -> AttributedString {
    // Drop leading heading marks (`#`, `##`) on every line — the inline parser
    // keeps them as literal text otherwise, which reads as clutter in the card.
    let cleaned = markdown.replacingOccurrences(of: "(?m)^#{1,6}[ \\t]*", with: "", options: .regularExpression)
    return (try? AttributedString(markdown: cleaned, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(cleaned)
  }

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日"
    return formatter
  }()
}

/// The daily broadcast, read from the radar's public `daily-audio/latest.*`.
struct DailyBroadcast: Sendable {
  let audioURL: URL
  let publishedAt: Date?
  let digest: String

  private static let metaURL = URL(string: "https://alexli-77.github.io/daily-news-radar/data/daily-audio/latest.json")!
  private static let digestURL = URL(string: "https://alexli-77.github.io/daily-news-radar/data/daily-audio/latest.md")!

  private struct Meta: Decodable {
    let publicAudioURL: String?
    let publishedAt: String?
    enum CodingKeys: String, CodingKey {
      case publicAudioURL = "public_audio_url"
      case publishedAt = "published_at"
    }
  }

  /// Fetch the shared latest broadcast; nil when offline or not yet published.
  static func fetch() async -> DailyBroadcast? {
    do {
      let (metaData, metaResponse) = try await URLSession.shared.data(from: metaURL)
      guard (metaResponse as? HTTPURLResponse)?.statusCode == 200 else { return nil }
      let meta = try JSONDecoder().decode(Meta.self, from: metaData)
      guard let raw = meta.publicAudioURL, let audioURL = URL(string: raw) else { return nil }
      let digest = (try? await string(from: digestURL)) ?? ""
      return DailyBroadcast(audioURL: audioURL, publishedAt: meta.publishedAt.flatMap(iso.date(from:)), digest: digest)
    } catch {
      return nil
    }
  }

  private static func string(from url: URL) async throws -> String {
    let (data, _) = try await URLSession.shared.data(from: url)
    return String(decoding: data, as: UTF8.self)
  }

  nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}
