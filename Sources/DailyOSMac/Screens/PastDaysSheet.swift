import SwiftUI
import DailyOSCore

/// 往日 — a previous day's plan, how each row was left, and the evening review.
///
/// A sheet over Today rather than a screen of its own: looking back is a
/// glance you take *from* today ("what did I carry over?"), and a separate
/// sidebar entry would make it a place you go instead.
///
/// Editable the way a calendar's past events are — Google Calendar and 飞书
/// both keep yesterday's events clickable, only paler: the circle ticks a row
/// or takes the tick back, hovering a row offers 部分 / 未做, and clicking it
/// opens its wording and a note. Each edit is sent with the day's date and
/// lands on that day; today's sheet does not move. What reschedules (顺延,
/// 删除, a clock time) is not offered — that day is over. Against a service
/// too old to take a date the sheet stays read-only, because that service
/// would stamp the edit on today.
struct PastDaysSheet: View {
  @Environment(AppState.self) private var state
  @Environment(\.dismiss) private var dismiss

  private enum Phase: Equatable {
    case loading
    case loaded(DayHistory)
    case failed(String)
  }

  /// The line at the bottom after an edit. The sheet covers the window's own
  /// toast, so it carries its own — with 撤销 when there is something to take back.
  private struct Notice {
    let id = UUID()
    let text: String
    let undo: (@MainActor () -> Void)?
  }

  @State private var phase: Phase = .loading
  /// Kept across loads so the list does not vanish while the next day loads.
  @State private var dates: [String] = []
  @State private var today = ""
  @State private var selected: String?
  /// Whether the day on screen takes edits; kept across loads like `dates`.
  /// Nil until the first day has loaded, so the header does not say 只读 first.
  @State private var editable: Bool?
  @State private var notice: Notice?
  /// Open on this day, when the calendar asked for it.
  var initialDate: String?

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
    .overlay(alignment: .bottom) { noticeBar }
    .animation(.easeOut(duration: 0.2), value: notice?.id)
    // nil: the service picks the most recent day before today with a plan.
    .task { await load(initialDate) }
  }

  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        Text("往日").font(Typo.heading).foregroundStyle(Palette.ink)
        Text("每天的最终计划、完成情况和复盘。" + (editable == true ? "点圆圈补记，点一行改文字、记一句。" : editable == false ? "只读。" : ""))
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
        let date = day.date
        let rank = index + 1
        PastPlanRow(item: item, editable: day.editable) { target in
          change(item.id, rank: rank, date: date, from: item.state, to: target)
        } onSave: { target, text, note in
          change(item.id, rank: rank, date: date, from: item.state, to: target)
          update(item, rank: rank, date: date, text: text, note: note)
        }
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
      editable = day.editable
      phase = .loaded(day)
    case .failure(let error):
      phase = .failed(error.message)
    }
  }

  // MARK: Edits

  /// Put a row in `target` on its own day. Drawn first and sent after, like a
  /// tick on Today; a refusal puts it back and says why.
  private func change(_ id: TodoItem.ID, rank: Int, date: String, from previous: TodoState, to target: TodoState, undoable: Bool = true) {
    guard target != previous else { return }
    mutate(date, id) { $0.state = target }
    let said = PastRowEdit.said(target, day: DayLabel.text(for: date, today: today))
    // 顺延 cannot be sent for a past day, so a row that was 顺延 has no way back to it.
    var undo: (@MainActor () -> Void)?
    if undoable && previous != .deferred {
      let sheet = self
      undo = { sheet.change(id, rank: rank, date: date, from: target, to: previous, undoable: false) }
    }
    let event = PastRowEdit.event(for: target)
    Task {
      let outcome = await state.editPastRow(date: date, candidateID: id, rank: rank, event: event)
      switch outcome {
      case .ok:
        notice = Notice(text: said, undo: undo)
      case .failed(let why), .unsupported(let why):
        mutate(date, id) { $0.state = previous }
        notice = Notice(text: why, undo: nil)
      }
    }
  }

  /// New wording and/or a note, as one `update`. Nil leaves that part alone.
  private func update(_ item: TodoItem, rank: Int, date: String, text: String?, note: String?) {
    guard text != nil || note != nil else { return }
    mutate(date, item.id) { row in
      if let text { row.text = text }
      if let note { row.note = note }
    }
    let said = "\(DayLabel.text(for: date, today: today))的这一条改好了"
    Task {
      let outcome = await state.editPastRow(date: date, candidateID: item.id, rank: rank, event: "update", text: text, note: note)
      switch outcome {
      case .ok:
        notice = Notice(text: said, undo: nil)
      case .failed(let why), .unsupported(let why):
        mutate(date, item.id) { row in
          row.text = item.text
          row.note = item.note
        }
        notice = Notice(text: why, undo: nil)
      }
    }
  }

  /// Change a row of the day on screen. A no-op once another day is showing —
  /// the request still goes; the list just has nothing to redraw.
  private func mutate(_ date: String, _ id: TodoItem.ID, _ change: (inout TodoItem) -> Void) {
    guard case .loaded(var day) = phase, day.date == date, let index = day.items.firstIndex(where: { $0.id == id }) else { return }
    change(&day.items[index])
    phase = .loaded(day)
  }

  @ViewBuilder private var noticeBar: some View {
    if let notice {
      HStack(spacing: Metrics.sm) {
        Text(notice.text).font(Typo.caption).foregroundStyle(Palette.paper)
        if let undo = notice.undo {
          Button("撤销") {
            self.notice = nil
            undo()
          }
          .buttonStyle(.plain)
          .font(Typo.caption.bold())
          .foregroundStyle(Palette.mint200)
        }
      }
      .padding(.horizontal, Metrics.sm)
      .padding(.vertical, Metrics.xs)
      .background(Palette.ink.opacity(0.92), in: Capsule())
      .padding(.bottom, Metrics.lg)
      .transition(.move(edge: .bottom).combined(with: .opacity))
      .task(id: notice.id) {
        try? await Task.sleep(for: .seconds(notice.undo == nil ? 2.2 : 6))
        if self.notice?.id == notice.id { self.notice = nil }
      }
    }
  }
}

/// A plan row as it was left, and — when the day takes edits — the same
/// controls Today has, minus what reschedules: the circle ticks or takes the
/// tick back, hovering shows 完成 / 部分 / 未做, clicking opens the editor.
private struct PastPlanRow: View {
  let item: TodoItem
  let editable: Bool
  let onSet: (TodoState) -> Void
  let onSave: (_ state: TodoState, _ text: String?, _ note: String?) -> Void

  @State private var isHovering = false
  @State private var isEditing = false
  @State private var draftState: TodoState = .open
  @State private var draftText = ""
  @State private var draftNote = ""

  private var isResolved: Bool { item.state == .done || item.state == .deferred }

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.sm) {
      circle
      VStack(alignment: .leading, spacing: 2) {
        Text(item.text)
          .font(Typo.body)
          .foregroundStyle(isResolved ? Palette.ink3 : Palette.ink)
          .strikethrough(item.state == .done, color: Palette.ink3)
          .fixedSize(horizontal: false, vertical: true)
        Text([stateLabel, item.estimatedMinutes.map(Fmt.minutes)].compactMap { $0 }.joined(separator: " · "))
          .font(Typo.caption).foregroundStyle(Palette.ink3)
        if let note = item.note, !note.isEmpty {
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Image(systemName: "text.quote").font(.system(size: 9))
            Text(note).fixedSize(horizontal: false, vertical: true)
          }
          .font(Typo.caption)
          .foregroundStyle(Palette.ink3)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      trailing
    }
    .padding(.vertical, Metrics.sm)
    .padding(.horizontal, editable ? Metrics.xs : 0)
    .background(
      editable && (isHovering || isEditing) ? Palette.surfaceSunken.opacity(0.6) : Color.clear,
      in: RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous)
    )
    .contentShape(Rectangle())
    .onHover { isHovering = $0 }
    .onTapGesture { if editable { openEditor() } }
    .modifier(PointerWhen(enabled: editable))
    .popover(isPresented: editorBinding, arrowEdge: .trailing) {
      PastRowEditor(state: $draftState, text: $draftText, note: $draftNote, onCancel: { isEditing = false }, onSave: save)
    }
    .accessibilityAction(named: "编辑") { if editable { openEditor() } }
  }

  /// Today's four-state circle when the day takes edits; the drawn record otherwise.
  @ViewBuilder private var circle: some View {
    if editable {
      StateCircle(state: item.state) { onSet(PastRowEdit.toggled(item.state)) }
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
    } else {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .regular))
        .foregroundStyle(item.state == .open ? Palette.ink3 : item.state == .missed ? Palette.q1 : Palette.mint600)
        .frame(width: 18)
        .accessibilityLabel(stateLabel)
    }
  }

  /// The source, or — while the pointer is on the row — the states it can be put in.
  @ViewBuilder private var trailing: some View {
    if editable && isHovering && !isEditing {
      StateMenuBar(state: item.state, choices: PastRowEdit.choices.map { .state($0) }) { choice in
        if case .state(let target) = choice { onSet(PastRowEdit.picked(target, from: item.state)) }
      }
    } else {
      let source = PlanSource(candidateID: item.id, sourceRef: item.sourceRef)
      Text(source.label).font(Typo.caption).foregroundStyle(source.isIssue ? Palette.ink2 : Palette.ink3)
    }
  }

  /// Clicking away saves, like Today's editor; 取消 closes without going through here.
  private var editorBinding: Binding<Bool> {
    Binding(get: { isEditing }, set: { if !$0 && isEditing { save() } })
  }

  private func openEditor() {
    draftState = item.state
    draftText = item.text
    draftNote = ""
    isEditing = true
  }

  /// Sends only what changed.
  private func save() {
    isEditing = false
    let trimmed = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
    let note = draftNote.trimmingCharacters(in: .whitespacesAndNewlines)
    let text = !trimmed.isEmpty && trimmed != item.text ? trimmed : nil
    guard draftState != item.state || text != nil || !note.isEmpty else { return }
    onSave(draftState, text, note.isEmpty ? nil : note)
  }

  private var symbol: String {
    switch item.state {
    case .done: "checkmark.circle.fill"
    case .partial: "circle.lefthalf.filled"
    case .missed: "xmark.circle"
    case .deferred: "arrow.right.circle"
    case .open, .deleted: "circle"
    }
  }

  private var stateLabel: String {
    switch item.state {
    case .done: "完成"
    case .partial: "做了一部分"
    case .missed: "未做"
    case .deferred: "顺到第二天"
    case .open, .deleted: "没勾"
    }
  }
}

/// What clicking a past row opens: how it was left, its wording, a note on
/// what actually happened. No time, colour or MIT — those were about planning
/// that day, and the day is over.
private struct PastRowEditor: View {
  @Binding var state: TodoState
  @Binding var text: String
  @Binding var note: String
  let onCancel: () -> Void
  let onSave: () -> Void

  /// Matches the service's cap and Today's editor.
  private static let maxLength = 150

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.sm) {
      TextField("这一条做的是什么", text: $text, axis: .vertical)
        .textFieldStyle(.plain)
        .font(Typo.heading)
        .lineLimit(1...4)
        .onChange(of: text) { _, new in
          if new.count > Self.maxLength { text = String(new.prefix(Self.maxLength)) }
        }

      VStack(alignment: .leading, spacing: Metrics.xxs) {
        Text("那天做得怎样").font(Typo.caption).foregroundStyle(Palette.ink3)
        HStack(spacing: Metrics.xs) {
          StateMenuBar(state: state, choices: PastRowEdit.choices.map { .state($0) }) { choice in
            if case .state(let target) = choice { state = PastRowEdit.picked(target, from: state) }
          }
          if state == .deferred {
            Text("顺到了第二天").font(Typo.caption).foregroundStyle(Palette.ink3)
          }
        }
      }

      VStack(alignment: .leading, spacing: Metrics.xxs) {
        Text("补一句").font(Typo.caption).foregroundStyle(Palette.ink3)
        TextField("其实做到了哪一步、为什么没做（可留空）", text: $note, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(1...3)
      }

      HStack {
        Text("只改这一天，今天的计划不动").font(Typo.caption).foregroundStyle(Palette.ink3)
        Spacer()
        Button("取消", action: onCancel)
          .buttonStyle(QuietButtonStyle(tone: .neutral))
          .keyboardShortcut(.cancelAction)
        Button("保存", action: onSave)
          .buttonStyle(MossButtonStyle(prominent: true))
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(Metrics.md)
    .frame(width: 380)
  }
}

private struct PointerWhen: ViewModifier {
  let enabled: Bool
  func body(content: Content) -> some View {
    if enabled { content.pointerStyleLink() } else { content }
  }
}

#Preview("往日") {
  PastDaysSheet().environment(AppState.previewOwner())
}
