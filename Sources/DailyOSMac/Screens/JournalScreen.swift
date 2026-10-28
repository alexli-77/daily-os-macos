import SwiftUI
import AppKit
import DailyOSCore

/// 日记 — write today on lined notebook paper, read back any past day.
///
/// A diary, not a review: free text, private, one entry per day. The left column
/// is the days you have written; the right is a sheet of ruled paper for the day
/// you picked, which opens on today. The date, the weather and the time sit at the
/// top of the page; the weather + time are frozen into each day when it is
/// written, so an old page shows the weather it *was* that day. Saves a second
/// after you stop typing — no save button to forget; clearing a day deletes it.
struct JournalScreen: View {
  @Environment(AppState.self) private var state
  @AppStorage("journalFont") private var fontRaw = JournalFont.system.rawValue

  @State private var entries: [JournalSummary] = []
  @State private var today = ""
  @State private var selected = ""
  @State private var entry: JournalEntry?
  @State private var content = ""
  @State private var loaded = false
  @State private var saveTask: Task<Void, Never>?
  @State private var replacing = false

  private var fontChoice: JournalFont { JournalFont(rawValue: fontRaw) ?? .system }

  var body: some View {
    ScreenScaffold("日记") {
      HStack(alignment: .top, spacing: Metrics.md) {
        list.frame(width: 220)
        paper.frame(maxWidth: .infinity)
      }
    } toolbar: {
      Menu("字体") {
        ForEach(JournalFont.allCases) { option in
          Button {
            fontRaw = option.rawValue
          } label: {
            if option.rawValue == fontRaw {
              Label(option.label, systemImage: "checkmark")
            } else {
              Text(option.label)
            }
          }
        }
      }
      .menuStyle(.button)
      .buttonStyle(MossButtonStyle(prominent: false))
      .fixedSize()
      .help("日记字体")

      Button("今天") { open(today) }
        .buttonStyle(MossButtonStyle())
        .disabled(!loaded || today.isEmpty || selected == today)
    }
    .task {
      guard !loaded else { return }
      let loadedEntry = await state.loadJournalEntry(date: nil)
      today = loadedEntry?.date ?? ""
      selected = today
      set(loadedEntry)
      entries = await state.loadJournalList()
      loaded = true
      await state.refreshWeather()
    }
  }

  // MARK: - Left: the days

  private var list: some View {
    Panel {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
          if index > 0 { PanelDivider() }
          Button { open(row.date) } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(row.label)
                .font(Typo.bodyStrong)
                .foregroundStyle(row.date == selected ? Palette.ink : Palette.ink2)
              Text(row.preview.isEmpty ? "还没写" : row.preview)
                .mutedStyle(Typo.caption)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Metrics.xs)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
      }
    }
  }

  private var rows: [Row] {
    var out: [Row] = []
    if !today.isEmpty {
      let preview = entries.first(where: { $0.date == today })?.preview ?? ""
      out.append(Row(date: today, label: "今天", preview: preview))
    }
    for summary in entries where summary.date != today {
      out.append(Row(date: summary.date, label: Self.shortLabel(summary.date, today: today), preview: summary.preview))
    }
    return out
  }

  // MARK: - Right: the page

  private var paper: some View {
    VStack(spacing: 0) {
      header
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Metrics.md)
        .padding(.bottom, Metrics.sm)
        .padding(.leading, 54)
        .padding(.trailing, Metrics.md)
      Rectangle().fill(Palette.line).frame(height: Metrics.hairline)
      PaperTextView(
        text: $content,
        font: fontChoice.nsFont(size: 16),
        lineHeight: 28,
        paper: NSColor(Palette.paper),
        margin: Self.marginColor,
        ink: NSColor(Palette.ink),
        leftInset: 54,
        topInset: 10,
        onChange: scheduleSave
      )
      .frame(minHeight: 460)
      .disabled(!loaded || selected.isEmpty)
    }
    .background(Palette.paper)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line))
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(selected.isEmpty ? "日记" : Self.title(for: selected))
        .font(titleFont)
        .foregroundStyle(Palette.ink)
      if displayWeather != nil || displayTime != nil {
        HStack(spacing: 14) {
          if let w = displayWeather {
            HStack(spacing: 5) {
              Image(systemName: Self.weatherSymbol(w.code, isDay: w.isDay))
                .foregroundStyle(Palette.ink2)
              Text("\(Int(w.temp.rounded()))° \(Self.weatherLabel(w.code)) · \(w.place)")
            }
          }
          if let t = displayTime {
            HStack(spacing: 5) {
              Image(systemName: "clock")
              Text(t)
            }
          }
        }
        .font(Typo.caption)
        .foregroundStyle(Palette.ink2)
      }
    }
  }

  private var titleFont: Font {
    if let name = fontChoice.fontName { return .custom(name, size: 21) }
    return .system(size: 21, weight: .regular, design: .serif)
  }

  /// The weather to show: a past day's frozen snapshot, else today's live one.
  private var displayWeather: (code: Int, temp: Double, place: String, isDay: Bool)? {
    if let w = entry?.weather { return (w.code, w.temp, w.place, w.isDay ?? true) }
    if selected == today, let w = state.weather { return (w.code, w.temperatureC, w.place, w.isDay) }
    return nil
  }

  private var displayTime: String? {
    if let written = entry?.writtenAt { return Self.timeFormatter.string(from: written) }
    if selected == today { return Self.timeFormatter.string(from: .now) }
    return nil
  }

  // MARK: - Actions

  private func open(_ date: String) {
    guard loaded, !date.isEmpty, date != selected else { return }
    saveTask?.cancel()
    Task {
      selected = date
      set(await state.loadJournalEntry(date: date))
    }
  }

  private func set(_ loadedEntry: JournalEntry?) {
    entry = loadedEntry
    replacing = true
    content = loadedEntry?.content ?? ""
    replacing = false
  }

  private func scheduleSave() {
    guard loaded, !replacing else { return }
    saveTask?.cancel()
    let date = selected
    let text = content
    saveTask = Task {
      try? await Task.sleep(for: .seconds(1))
      if Task.isCancelled { return }
      _ = await state.saveJournalEntry(date: date, content: text)
      let refreshed = await state.loadJournalList()
      if Task.isCancelled { return }
      entries = refreshed
    }
  }

  // MARK: - Formatting

  private static let marginColor = NSColor(srgbRed: 0xCE / 255, green: 0x9A / 255, blue: 0x93 / 255, alpha: 1)

  private static let isoDay: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  private static let titleFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.dateFormat = "M月d日 EEEE"
    return formatter
  }()

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm"
    return formatter
  }()

  private static func title(for date: String) -> String {
    guard let parsed = isoDay.date(from: date) else { return date }
    return titleFormatter.string(from: parsed)
  }

  /// `2026-10-25` → `10-25` in the current year, else the full date.
  private static func shortLabel(_ date: String, today: String) -> String {
    guard date.count == 10, !today.isEmpty, date.prefix(4) == today.prefix(4) else { return date }
    return String(date.dropFirst(5))
  }

  private static func weatherSymbol(_ code: Int, isDay: Bool) -> String {
    switch code {
    case 0: return isDay ? "sun.max" : "moon.stars"
    case 1, 2: return isDay ? "cloud.sun" : "cloud.moon"
    case 45, 48: return "cloud.fog"
    case 71...77, 85, 86: return "cloud.snow"
    case 95...99: return "cloud.bolt.rain"
    case 51...67, 80...82: return "cloud.rain"
    default: return "cloud"
    }
  }

  private static func weatherLabel(_ code: Int) -> String {
    switch code {
    case 0: return "晴"
    case 1, 2: return "多云"
    case 45, 48: return "雾"
    case 71...77, 85, 86: return "雪"
    case 95...99: return "雷"
    case 51...67, 80...82: return "雨"
    default: return "阴"
    }
  }

  private struct Row: Identifiable {
    let date: String
    let label: String
    let preview: String
    var id: String { date }
  }
}

/// The journal's writing fonts. Handwriting options use the Chinese handwriting
/// faces that ship with macOS, so no download is needed.
private enum JournalFont: String, CaseIterable, Identifiable {
  case system, songti, kai, hanzipen, hannotate

  var id: String { rawValue }

  var label: String {
    switch self {
    case .system: return "默认"
    case .songti: return "宋体"
    case .kai: return "楷体"
    case .hanzipen: return "手写 · 翩翩"
    case .hannotate: return "手写 · 手札"
    }
  }

  /// The PostScript/family name, or nil for the system font.
  var fontName: String? {
    switch self {
    case .system: return nil
    case .songti: return "Songti SC"
    case .kai: return "Kaiti SC"
    case .hanzipen: return "HanziPen SC"
    case .hannotate: return "Hannotate SC"
    }
  }

  func nsFont(size: CGFloat) -> NSFont {
    if let name = fontName, let font = NSFont(name: name, size: size) { return font }
    return NSFont.systemFont(ofSize: size)
  }
}
