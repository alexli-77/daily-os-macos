import SwiftUI
import DailyOSCore

/// 日记 — write today, read back any past day.
///
/// A diary, not a review: free text, private, one entry per day. The left column
/// is the days you have written; the right is the writing surface for the day you
/// picked, which opens on today. It saves a second after you stop typing, the way
/// a notes app does — there is no save button to forget, and clearing a day's
/// text deletes that day rather than leaving a blank entry.
struct JournalScreen: View {
  @Environment(AppState.self) private var state

  @State private var entries: [JournalSummary] = []
  @State private var today = ""
  @State private var selected = ""
  @State private var content = ""
  @State private var loaded = false
  // Cancels the pending autosave on each keystroke, so only the pause after
  // typing writes.
  @State private var saveTask: Task<Void, Never>?
  // True while `content` is being replaced by a load (first open, or switching
  // day), so the autosave does not fire for text the user did not type.
  @State private var replacing = false

  var body: some View {
    ScreenScaffold("日记", subtitle: subtitle) {
      HStack(alignment: .top, spacing: Metrics.md) {
        list.frame(width: 220)
        editor.frame(maxWidth: .infinity)
      }
    } toolbar: {
      Button("今天") { open(today) }
        .buttonStyle(MossButtonStyle())
        .disabled(!loaded || today.isEmpty || selected == today)
    }
    .task {
      guard !loaded else { return }
      let entry = await state.loadJournalEntry(date: nil)
      today = entry?.date ?? ""
      selected = today
      replacing = true
      content = entry?.content ?? ""
      replacing = false
      entries = await state.loadJournalList()
      loaded = true
    }
  }

  private var subtitle: String {
    guard loaded, !selected.isEmpty else { return "" }
    return selected == today ? "今天 · \(selected)" : selected
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

  /// Today always sits at the top, even before it has an entry; then every past
  /// day that has one, newest first (the service already sorts them).
  private var rows: [Row] {
    var out: [Row] = []
    if !today.isEmpty {
      let preview = entries.first(where: { $0.date == today })?.preview ?? ""
      out.append(Row(date: today, label: "今天", preview: preview))
    }
    for entry in entries where entry.date != today {
      out.append(Row(date: entry.date, label: shortLabel(entry.date), preview: entry.preview))
    }
    return out
  }

  // MARK: - Right: the day

  private var editor: some View {
    Panel {
      ZStack(alignment: .topLeading) {
        TextEditor(text: $content)
          .font(Typo.body)
          .scrollContentBackground(.hidden)
          .padding(Metrics.xs)
          .frame(minHeight: 460)
          .background(Palette.surfaceSunken)
          .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
          .onChange(of: content) { scheduleSave() }
          .disabled(!loaded || selected.isEmpty)
        if content.isEmpty {
          Text("今天怎么样？随便写点。")
            .mutedStyle()
            .padding(Metrics.sm)
            .allowsHitTesting(false)
        }
      }
    }
  }

  // MARK: - Actions

  private func open(_ date: String) {
    guard loaded, !date.isEmpty, date != selected else { return }
    saveTask?.cancel()
    Task {
      selected = date
      let entry = await state.loadJournalEntry(date: date)
      replacing = true
      content = entry?.content ?? ""
      replacing = false
    }
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

  /// `2026-10-25` → `10-25` in the current year, else the full date.
  private func shortLabel(_ date: String) -> String {
    guard date.count == 10, !today.isEmpty, date.prefix(4) == today.prefix(4) else { return date }
    return String(date.dropFirst(5))
  }

  private struct Row: Identifiable {
    let date: String
    let label: String
    let preview: String
    var id: String { date }
  }
}
