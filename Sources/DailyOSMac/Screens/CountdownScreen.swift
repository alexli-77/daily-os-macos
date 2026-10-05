import SwiftUI
import DailyOSCore

/// Countdown days.
///
/// The reference for this screen is a phone app full of posters, photos and
/// shareable cards. None of that is here: this list exists so that a date you
/// are counting toward can reach the morning card, and the screen is where you
/// put one there. Everything on a row is either the count, the date it counts
/// to, or the two controls that change which — pin and edit.
///
/// Rows rather than tiles. A tile grid makes every entry equally loud, and the
/// honest shape of this data is that two or three matter and the rest are
/// reference.
struct CountdownScreen: View {
  @Environment(AppState.self) private var state
  @State private var editing: CountdownDraft?

  private var groups: [CountdownGroup] { CountdownGroup.group(state.countdowns) }

  var body: some View {
    ScreenScaffold("倒数日", subtitle: subtitle) {
      if state.countdowns.isEmpty {
        Panel {
          EmptyState(
            icon: "hourglass",
            title: "还没有记过日子",
            message: "记一个截稿日、一张机票、一个生日。置顶的，和三十天以内的，会出现在早上那张卡片的第一行。"
          )
        }
      } else {
        ForEach(groups) { group in
          Panel(group.kind.title, subtitle: bandNote(group.kind)) {
            VStack(spacing: Metrics.sm) {
              ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { PanelDivider() }
                CountdownRow(
                  item: item,
                  onEdit: { editing = CountdownDraft(editing: item) },
                  onTogglePin: { run { await state.toggleCountdownPin(item.id) } }
                )
              }
            }
          }
        }

        // Which clock every number above was read off. Outside the panels
        // because it qualifies all of them, and quiet because on most days it
        // says nothing surprising — the day it is worth reading is the day you
        // are somewhere else, and then it says that too.
        if !state.countdownTimezone.isEmpty {
          Text(CountdownZone.note(counting: state.countdownTimezone, card: state.countdownCardTimezone))
            .mutedStyle(Typo.caption)
        }
      }
    } toolbar: {
      Button("记一个") { editing = CountdownDraft(date: CountdownDate.day(from: .now)) }
        .buttonStyle(MossButtonStyle())
    }
    .sheet(item: $editing) { draft in
      CountdownEditor(
        draft: draft,
        onSave: { saved in
          editing = nil
          run { await state.saveCountdown(saved) }
        },
        onDelete: draft.id.map { id in
          {
            editing = nil
            run { await state.deleteCountdown(id) }
          }
        },
        onCancel: { editing = nil }
      )
    }
  }

  private var subtitle: String? {
    guard !state.countdowns.isEmpty else { return nil }
    let onCard = state.countdowns.filter(\.pinned).count
    return onCard == 0
      ? "\(state.countdowns.count) 条，没有置顶的"
      : "\(state.countdowns.count) 条，\(onCard) 条置顶"
  }

  /// Said once per band, where it explains the band, rather than on every row.
  private func bandNote(_ kind: CountdownGroup.Kind) -> String? {
    switch kind {
    case .pinned: "会出现在早上的卡片里"
    case .running: nil
    case .past: "过去的一次性事件，不会再上卡片"
    }
  }

  private func run(_ action: @escaping () async -> AppState.ActionOutcome) {
    Task {
      switch await action() {
      case .ok(let message): if let message { state.toast = message }
      case .failed(let why), .unsupported(let why): state.toast = why
      }
    }
  }
}

// MARK: - Row

private struct CountdownRow: View {
  let item: Countdown
  let onEdit: () -> Void
  let onTogglePin: () -> Void

  @State private var hovering = false

  var body: some View {
    HStack(alignment: .center, spacing: Metrics.md) {
      VStack(alignment: .leading, spacing: Metrics.xxs) {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
          Text(item.title).inkStyle(Typo.bodyStrong)
          if item.recurrence == .yearly { Pill("每年") }
          if let ordinal = item.ordinalLabel { Pill(ordinal, tone: .accent) }
        }
        Text(CountdownDate.heading(item.occurrence)).mutedStyle()
        if let note = item.note {
          Text(note).mutedStyle(Typo.caption)
        }
      }

      Spacer(minLength: Metrics.sm)

      // The controls occupy their slot whether or not the pointer is here, so
      // the count never slides sideways on hover.
      HStack(spacing: Metrics.xxs) {
        Button(action: onTogglePin) {
          Image(systemName: item.pinned ? "pin.fill" : "pin")
        }
        .buttonStyle(QuietButtonStyle())
        .help(item.pinned ? "取消置顶" : "置顶，让它出现在早上的卡片里")
        .opacity(item.pinned || hovering ? 1 : 0)

        Button(action: onEdit) { Image(systemName: "pencil") }
          .buttonStyle(QuietButtonStyle())
          .help("编辑")
          .opacity(hovering ? 1 : 0)
      }

      DayCount(item: item)
    }
    .padding(.vertical, Metrics.xxs)
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .onTapGesture(count: 2, perform: onEdit)
  }
}

/// The number, set large, with what it means above it.
///
/// Right-aligned in a fixed width so that a column of them lines up on the
/// digit rather than on the word — a list of counts is read by scanning down
/// the numbers, and ragged ones defeat that.
private struct DayCount: View {
  let item: Countdown

  var body: some View {
    VStack(alignment: .trailing, spacing: 0) {
      if item.daysLeft == 0 {
        Text("就是今天")
          .font(Typo.tabularTitle)
          .foregroundStyle(Palette.foreground(for: .danger))
      } else {
        Text(item.dayCaption)
          .font(Typo.caption)
          .foregroundStyle(Palette.inkMuted)
        HStack(alignment: .firstTextBaseline, spacing: Metrics.xxs) {
          Text("\(item.dayNumber)")
            .font(Typo.tabularTitle)
            .foregroundStyle(Palette.foreground(for: item.tone))
          Text("天")
            .font(Typo.caption)
            .foregroundStyle(Palette.inkMuted)
        }
      }
    }
    .frame(width: 96, alignment: .trailing)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(item.title)，\(item.daysLabel)")
  }
}

// MARK: - Editor

/// One sheet for both creating and editing. `onDelete` present means editing.
private struct CountdownEditor: View {
  @State var draft: CountdownDraft
  let onSave: (CountdownDraft) -> Void
  let onDelete: (() -> Void)?
  let onCancel: () -> Void

  @State private var confirmingDelete = false

  init(
    draft: CountdownDraft,
    onSave: @escaping (CountdownDraft) -> Void,
    onDelete: (() -> Void)?,
    onCancel: @escaping () -> Void
  ) {
    _draft = State(initialValue: draft)
    self.onSave = onSave
    self.onDelete = onDelete
    self.onCancel = onCancel
  }

  /// The picker speaks `Date`; everything else speaks `YYYY-MM-DD`. The
  /// conversion is pinned to UTC on both sides — see `CountdownDate`.
  private var pickedDate: Binding<Date> {
    Binding(
      get: { CountdownDate.date(from: draft.date) ?? .now },
      set: { draft.date = CountdownDate.day(from: $0) }
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.md) {
      Text(onDelete == nil ? "记一个日子" : "改一下").inkStyle(Typo.heading)

      VStack(alignment: .leading, spacing: Metrics.sm) {
        TextField("叫什么", text: $draft.title)
          .textFieldStyle(.roundedBorder)

        DatePicker("日子", selection: pickedDate, displayedComponents: .date)
          .datePickerStyle(.field)

        Picker("方向", selection: $draft.direction) {
          Text("倒数到这天").tag(Countdown.Direction.until)
          Text("从这天算起").tag(Countdown.Direction.since)
        }
        .pickerStyle(.radioGroup)

        Toggle("每年重复", isOn: Binding(
          get: { draft.recurrence == .yearly },
          set: { draft.recurrence = $0 ? .yearly : .none }
        ))

        Toggle("置顶（出现在早上的卡片里）", isOn: $draft.pinned)

        TextField("备注，可以不写", text: $draft.note, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(2...4)
      }

      Text(hint).mutedStyle(Typo.caption)

      HStack {
        if onDelete != nil {
          Button("删除", role: .destructive) { confirmingDelete = true }
            .buttonStyle(QuietButtonStyle())
        }
        Spacer()
        Button("取消", action: onCancel).buttonStyle(QuietButtonStyle())
        Button("保存") { onSave(draft) }
          .buttonStyle(MossButtonStyle())
          .disabled(!draft.isValid)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(Metrics.lg)
    .frame(width: 420)
    .background(Palette.page)
    .confirmationDialog("删掉「\(draft.title)」？", isPresented: $confirmingDelete) {
      Button("删除", role: .destructive) { onDelete?() }
      Button("算了", role: .cancel) {}
    } message: {
      Text("这条倒数日会消失，没有回收站。")
    }
  }

  /// Says what the combination in the form will actually do, because "每年" plus
  /// "从这天算起" is the one pair whose result is not obvious from the labels.
  private var hint: String {
    switch (draft.direction, draft.recurrence) {
    case (_, .yearly):
      "每年这天来一次。屏幕上显示离下一次还有多久，以及这是第几年。"
    case (.until, .none):
      "过了这天之后会显示「已过去 N 天」，并且不再出现在卡片上。想留着就置顶。"
    case (.since, .none):
      "一直往上数，适合「读博第 N 天」这种。不置顶就不会上卡片。"
    }
  }
}

// MARK: - The strip on Today

/// The same sentence the morning card opens with, on the screen you actually
/// have open at 14:00.
///
/// One line, no panel, no heading. It is context for the day, not a section of
/// it — the moment this grows a title and a border it starts competing with the
/// call sheet, which is the thing you came to this screen for. Draws nothing
/// at all when there is nothing inside the horizon.
struct CountdownStrip: View {
  @Environment(AppState.self) private var state

  private var items: [Countdown] { Countdown.forCard(state.countdowns) }

  var body: some View {
    if !items.isEmpty {
      Button {
        state.section = .countdown
      } label: {
        HStack(spacing: Metrics.xs) {
          Image(systemName: "hourglass")
            .font(Typo.caption)
            .foregroundStyle(Palette.inkMuted)
          ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index > 0 {
              Text("·").font(Typo.caption).foregroundStyle(Palette.line)
            }
            HStack(spacing: Metrics.xxs) {
              Text(item.title).font(Typo.caption).foregroundStyle(Palette.inkMuted)
              Text(item.daysLabel)
                .font(Typo.tabularCaption)
                .foregroundStyle(Palette.foreground(for: item.tone))
            }
          }
          Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help("去倒数日")
      .accessibilityLabel("倒数日：\(items.map { "\($0.title) \($0.daysLabel)" }.joined(separator: "，"))")
    }
  }
}

// MARK: - Previews

#Preview("倒数日") {
  CountdownScreen()
    .environment(AppState.previewOwner())
    .frame(width: 940, height: 760)
}

#Preview("倒数日 · 空") {
  let state = AppState.previewOwner()
  state.countdowns = []
  return CountdownScreen()
    .environment(state)
    .frame(width: 940, height: 760)
}
