import SwiftUI
import AVFoundation
import DailyOSCore

/// 今日 AI 播报 — the daily audio brief from the AI News Radar.
///
/// Read straight off the radar's public GitHub Pages files (one shared `latest`
/// for everyone, refreshed daily): no backend, no hosting, no token. The card
/// plays the mp3 and lists today's items, each linking to its source. General AI
/// news, not anything derived from the user's own Daily OS data.
struct BroadcastCard: View {
  @Environment(\.openURL) private var openURL

  @State private var broadcast: DailyBroadcast?
  @State private var state: LoadState = .loading
  @State private var player: AVPlayer?
  @State private var playing = false

  private enum LoadState { case loading, ready, failed }

  private static let homeURL = URL(string: "https://alexli-77.github.io/daily-news-radar/")!

  var body: some View {
    Panel("今日 AI 播报") {
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
      Button { openURL(Self.homeURL) } label: { Image(systemName: "arrow.up.right") }
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
      // Play row: the one control, with the date beside it (the title no longer
      // carries it).
      HStack(spacing: Metrics.sm) {
        Button { toggle(broadcast) } label: {
          Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
            .font(.system(size: 32))
            .foregroundStyle(Palette.chatAccent)
        }
        .buttonStyle(.plain)
        .help(playing ? "暂停" : "播放今日播报")
        Text(playing ? "播放中" : "听今日播报")
          .inkStyle(Typo.bodyStrong)
        Spacer(minLength: Metrics.xs)
        if let date = broadcast.publishedAt {
          Text(Self.dayFormatter.string(from: date)).mutedStyle(Typo.caption)
        }
      }

      if !broadcast.items.isEmpty {
        Rectangle().fill(Palette.line).frame(height: Metrics.hairline)
        ScrollView {
          VStack(alignment: .leading, spacing: Metrics.sm) {
            ForEach(broadcast.items) { item in
              itemRow(item)
            }
          }
          .padding(.vertical, Metrics.xxs)
        }
        .frame(maxHeight: 230)
      }
    }
  }

  private func itemRow(_ item: BroadcastItem) -> some View {
    Button {
      if let url = item.url { openURL(url) }
    } label: {
      HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
        Text("\(item.index)")
          .font(Typo.body)
          .foregroundStyle(Palette.inkMuted)
          .frame(width: 18, alignment: .trailing)
        Text(item.text)
          .inkStyle(Typo.body)
          .multilineTextAlignment(.leading)
          .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(item.url?.absoluteString ?? "")
    .disabled(item.url == nil)
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

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日"
    return formatter
  }()
}

/// One item of the daily brief: the editorialised one-liner and its source link.
struct BroadcastItem: Sendable, Identifiable {
  let index: Int
  let text: String
  let url: URL?
  var id: Int { index }
}

/// The daily broadcast, read from the radar's public `daily-audio/latest.*`.
struct DailyBroadcast: Sendable {
  let audioURL: URL
  let publishedAt: Date?
  let items: [BroadcastItem]

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

  static func fetch() async -> DailyBroadcast? {
    do {
      let (metaData, metaResponse) = try await URLSession.shared.data(from: metaURL)
      guard (metaResponse as? HTTPURLResponse)?.statusCode == 200 else { return nil }
      let meta = try JSONDecoder().decode(Meta.self, from: metaData)
      guard let raw = meta.publicAudioURL, let audioURL = URL(string: raw) else { return nil }
      let digest = (try? await string(from: digestURL)) ?? ""
      return DailyBroadcast(
        audioURL: audioURL,
        publishedAt: meta.publishedAt.flatMap(iso.date(from:)),
        items: parseItems(digest)
      )
    } catch {
      return nil
    }
  }

  private static func string(from url: URL) async throws -> String {
    let (data, _) = try await URLSession.shared.data(from: url)
    return String(decoding: data, as: UTF8.self)
  }

  /// Merge the two digest sections into one linked list: the `## 播报稿`
  /// one-liner for the text, the matching `## 原始链接` entry for the URL. Falls
  /// back to the link section's own titles when the script is missing, so the
  /// list never comes up empty just because the format shifted.
  static func parseItems(_ markdown: String) -> [BroadcastItem] {
    let script = numberedScript(section(markdown, "播报稿"))
    let links = numberedLinks(section(markdown, "原始链接"))
    let indices = Set(script.keys).union(links.keys).sorted()
    return indices.compactMap { index in
      let text = script[index] ?? links[index]?.title
      guard let text, !text.isEmpty else { return nil }
      return BroadcastItem(index: index, text: text, url: links[index]?.url)
    }
  }

  /// The lines under a `## <name>` heading, up to the next heading.
  private static func section(_ markdown: String, _ name: String) -> [String] {
    var out: [String] = []
    var inside = false
    for line in markdown.components(separatedBy: "\n") {
      if line.hasPrefix("## ") {
        inside = line.dropFirst(3).trimmingCharacters(in: .whitespaces) == name
        continue
      }
      if inside { out.append(line) }
    }
    return out
  }

  /// `1、text` → [1: "text"].
  private static func numberedScript(_ lines: [String]) -> [Int: String] {
    var out: [Int: String] = [:]
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard let marker = trimmed.range(of: "、"),
            let index = Int(trimmed[trimmed.startIndex..<marker.lowerBound]) else { continue }
      out[index] = String(trimmed[marker.upperBound...]).trimmingCharacters(in: .whitespaces)
    }
    return out
  }

  /// `1. title（source） - https://…` → [1: (title, url)].
  private static func numberedLinks(_ lines: [String]) -> [Int: (title: String, url: URL?)] {
    var out: [Int: (String, URL?)] = [:]
    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard let dot = trimmed.firstIndex(of: "."),
            let index = Int(trimmed[trimmed.startIndex..<dot]) else { continue }
      let rest = trimmed[trimmed.index(after: dot)...].trimmingCharacters(in: .whitespaces)
      let urlRange = rest.range(of: "https://") ?? rest.range(of: "http://")
      var title = rest
      var url: URL?
      if let urlRange {
        url = URL(string: String(rest[urlRange.lowerBound...]).trimmingCharacters(in: .whitespaces))
        // Drop the trailing " - URL" and any "（source）" from the title.
        title = String(rest[rest.startIndex..<urlRange.lowerBound])
        if let dash = title.range(of: " - ", options: .backwards) { title = String(title[title.startIndex..<dash.lowerBound]) }
        title = title.trimmingCharacters(in: .whitespaces)
      }
      out[index] = (title, url)
    }
    return out
  }

  nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}
