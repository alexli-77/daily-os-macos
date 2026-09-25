import SwiftUI
import DailyOSCore

/// 往日 — a previous day's plan, how each row was left, and the evening review.
///
/// A sheet over Today rather than a screen of its own: looking back is a
/// glance you take *from* today ("what did I carry over?"), and a separate
/// sidebar entry would make it a place you go instead.
///
/// Read-only on purpose. The service stamps feedback with the day it receives
/// it, so ticking yesterday's row would record a completion against today —
/// there are no controls here that write.
struct PastDaysSheet: View {
  @Environment(AppState.self) private var state
  @Environment(\.dismiss) private var dismiss

  private enum Phase: Equatable {
    case loading
    case loaded(DayHistory)
    case failed(String)
  }

  @State private var phase: Phase = .loading
  /// Kept across loads so the list does not vanish while the next day loads.
  @State private var dates: [String] = []
  @State private var today = ""
  @State private var selected: String?

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      HStack(spacing: 0) {
        dayList.frame(width: 190)
        Divider()
        detail.frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .frame(minWidth: 780, idealWidth: 860, minHeight: 540, idealHeight: 640)
    .background(Palette.paper)
    // nil: the service picks the most recent day before today with a plan.
    .task { await load(nil) }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text("往日").font(Typo.heading).foregroundStyle(Palette.ink)
        Text("每天最后一版计划、当天勾到哪一步、晚上的复盘。只能看，不能改。")
          .font(Typo.caption).foregroundStyle(Palette.ink3)
      }
      Spacer()
      Button("关闭") { dismiss() }
        .buttonStyle(QuietButtonStyle(tone: .neutral))
        .keyboardShortcut(.cancelAction)
    }
    .padding(.horizontal, Metrics.lg)
    .padding(.vertical, Metrics.md)
  }

  // MARK: Day list

  private var dayList: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 2) {
        ForEach(dates.filter { $0 != today }, id: \.self) { date in
          SelectableRow(isSelected: date == selected) {
            Task { await load(date) }
          } content: {
            VStack(alignment: .leading, spacing: 1) {
              Text(DayLabel.text(for: date, today: today)).font(Typo.body).foregroundStyle(Palette.ink)
              Text(date).font(Typo.caption).foregroundStyle(Palette.ink3).monospacedDigit()
            }
          }
        }
      }
      .padding(Metrics.xs)
    }
    .background(Palette.paper)
  }

  // MARK: Detail

  @ViewBuilder private var detail: some View {
    switch phase {
    case .loading:
      ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let message):
      EmptyState(icon: "exclamationmark.triangle", title: "读不到这一天", message: message, actionTitle: "重试") {
        Task { await load(selected) }
      }
    case .loaded(let day):
      ScrollView {
        VStack(alignment: .leading, spacing: Metrics.lg) {
          dayHeader(day)
          if !day.items.isEmpty {
            planSection(day)
          } else if let raw = day.rawPlan {
            rawSection(raw)
          } else {
            Text(day.hasPlan ? "这天的计划没有可以列出来的条目。" : "这天没有生成计划。")
              .font(Typo.body).foregroundStyle(Palette.ink3)
          }
          if let review = day.review { reviewSection(review) }
        }
        .padding(Metrics.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }

  private func dayHeader(_ day: DayHistory) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(DayLabel.text(for: day.date, today: day.today) + (DayLabel.text(for: day.date, today: day.today) == day.date ? "" : " · \(day.date)"))
        .font(Typo.heading).foregroundStyle(Palette.ink)
      HStack(spacing: Metrics.xs) {
        Text(day.summary)
        if let generated = day.generatedAt {
          Text("·")
          Text("计划生成于 \(Fmt.time(generated))")
        }
      }
      .font(Typo.caption).foregroundStyle(Palette.ink3)
    }
  }

  private func planSection(_ day: DayHistory) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      SectionLabel("计划")
      ForEach(Array(day.items.enumerated()), id: \.element.id) { index, item in
        if index > 0 { Divider() }
        PastPlanRow(item: item)
      }
    }
  }

  private func reviewSection(_ review: DayReview) -> some View {
    VStack(alignment: .leading, spacing: Metrics.xs) {
      SectionLabel("晚上的复盘")
      ForEach(review.items) { item in
        HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
          Pill(item.status.label, tone: tone(for: item.status))
            .frame(width: 56, alignment: .leading)
          VStack(alignment: .leading, spacing: 2) {
            Text(item.text).font(Typo.body).foregroundStyle(Palette.ink)
              .fixedSize(horizontal: false, vertical: true)
            if let evidence = item.evidence {
              Text(evidence).font(Typo.caption).foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        .padding(.vertical, 2)
      }
      if let note = review.note {
        Text(note)
          .font(Typo.body).foregroundStyle(Palette.ink2)
          .fixedSize(horizontal: false, vertical: true)
          .padding(Metrics.sm)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
          .padding(.top, Metrics.xs)
      }
    }
  }

  private func rawSection(_ raw: String) -> some View {
    VStack(alignment: .leading, spacing: Metrics.xs) {
      SectionLabel("计划（旧格式，原文）")
      Text(raw)
        .font(Typo.monoBody).foregroundStyle(Palette.ink2)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func tone(for status: DayReview.Item.Status) -> Tone {
    switch status {
    case .done: .ok
    case .progressed: .accent
    case .open: .neutral
    }
  }

  private func load(_ date: String?) async {
    selected = date ?? selected
    phase = .loading
    switch await state.loadDayHistory(date: date) {
    case .success(let day):
      dates = day.dates
      today = day.today
      selected = day.date
      phase = .loaded(day)
    case .failure(let error):
      phase = .failed(error.message)
    }
  }
}

/// A plan row as it was left. Same visual vocabulary as Today's four-state
/// circle, drawn rather than clickable — this is a record, not a control.
private struct PastPlanRow: View {
  let item: TodoItem

  private var isResolved: Bool { item.state == .done || item.state == .deferred }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .regular))
        .foregroundStyle(item.state == .open ? Palette.ink3 : Palette.mint600)
        .frame(width: 18)
        .accessibilityLabel(stateLabel)
      VStack(alignment: .leading, spacing: 2) {
        Text(item.text)
          .font(Typo.body)
          .foregroundStyle(isResolved ? Palette.ink3 : Palette.ink)
          .strikethrough(item.state == .done, color: Palette.ink3)
          .fixedSize(horizontal: false, vertical: true)
        Text([stateLabel, item.estimatedMinutes.map(Fmt.minutes)].compactMap { $0 }.joined(separator: " · "))
          .font(Typo.caption).foregroundStyle(Palette.ink3)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if let ref = item.sourceRef {
        Text(ref).font(Typo.caption).foregroundStyle(Palette.ink2)
      }
    }
    .padding(.vertical, Metrics.sm)
  }

  private var symbol: String {
    switch item.state {
    case .done: "checkmark.circle.fill"
    case .partial: "circle.lefthalf.filled"
    case .deferred: "arrow.right.circle"
    case .open, .deleted: "circle"
    }
  }

  private var stateLabel: String {
    switch item.state {
    case .done: "完成"
    case .partial: "做了一部分"
    case .deferred: "顺到第二天"
    case .open, .deleted: "没勾"
    }
  }
}

#Preview("往日") {
  PastDaysSheet().environment(AppState.previewOwner())
}
