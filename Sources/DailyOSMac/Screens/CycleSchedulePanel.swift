import SwiftUI
import DailyOSCore

/// 双周排期 — the cycle's 要务 over its days, one row per 要务, grouped by role.
///
/// This is where the cycle is confirmed, before any day is planned: the daily
/// plan takes today's column from here. A row that keeps going wrong on the
/// Today page is fixed here, once, instead of every morning there.
///
/// A filled block with a time is a big rock — a slot reserved before anything
/// else is planned around it. A light block is a day's session with no fixed
/// time. ◆ is the 要务's deadline. Days before today are history and read-only.
struct CycleSchedulePanel: View {
  @Environment(AppState.self) private var state
  let cycle: Cycle
  let editable: Bool

  private enum Phase: Equatable {
    case loading
    case loaded
    case failed(String)
  }

  @State private var phase: Phase = .loading
  @State private var data: CycleScheduleState?
  @State private var isStarting = false
  @State private var confirmsRegenerate = false
  @State private var editing: ScheduleSession?

  private static let labelWidth: CGFloat = 200
  private static let dayWidth: CGFloat = 46
  private static let rowHeight: CGFloat = 34

  var body: some View {
    Panel("排期", subtitle: subtitle) {
      content
    } actions: {
      if editable, let data, !data.items.isEmpty {
        Button(generateTitle(data)) {
          if data.schedule == nil { generate() } else { confirmsRegenerate = true }
        }
        .buttonStyle(QuietButtonStyle())
        .disabled(isStarting || data.running)
        .help("让模型从今天起把这一期的要务排到每一天：大石头占具体时段，其余只定哪天。今天以前的格子不动。会花模型额度。")
      }
    }
    .task(id: cycle.id) { await load() }
    .confirmationDialog("重新排今天以后的日子？", isPresented: $confirmsRegenerate) {
      Button("重新排") { generate() }
      Button("取消", role: .cancel) {}
    } message: {
      Text(data?.schedule?.editedAt != nil
        ? "今天及以后的格子会被新的排期替换，包括你手动改过的。今天以前的不动。"
        : "今天及以后的格子会被新的排期替换。今天以前的不动。")
    }
  }

  @ViewBuilder private var content: some View {
    switch phase {
    case .loading:
      ProgressView().controlSize(.small).frame(maxWidth: .infinity, minHeight: 80)
    case .failed(let message):
      EmptyState(icon: "exclamationmark.triangle", title: "读不到排期", message: message, actionTitle: "重试") {
        Task { await load() }
      }
    case .loaded:
      if let data {
        if data.items.isEmpty {
          Text("这一期还没有要务。要务写好以后，再在这里排到每一天。")
            .font(Typo.body).foregroundStyle(Palette.ink3)
        } else if data.schedule == nil && !data.running {
          VStack(alignment: .leading, spacing: Metrics.xs) {
            Text("还没有排期。排期会把每个角色最重要的事先放进具体时段，其余的分到每一天；之后每天的计划就从这里取当天那一列。")
              .font(Typo.body).foregroundStyle(Palette.ink2)
              .fixedSize(horizontal: false, vertical: true)
            if let error = data.error { Text("上次没排成：\(error)").font(Typo.caption).foregroundStyle(Palette.warn) }
          }
        } else {
          VStack(alignment: .leading, spacing: Metrics.sm) {
            if data.running {
              HStack(spacing: Metrics.xs) {
                ProgressView().controlSize(.small)
                Text("正在排期，一两分钟。排好会自己出现。").font(Typo.caption).foregroundStyle(Palette.ink3)
              }
            }
            if let error = data.error { Text("上次没排成：\(error)").font(Typo.caption).foregroundStyle(Palette.warn) }
            if let note = data.schedule?.note { Text(note).font(Typo.body).foregroundStyle(Palette.ink2) }
            ScrollView(.horizontal) { grid(data) }
            legend
          }
        }
      }
    }
  }

  // MARK: Grid

  private func grid(_ data: CycleScheduleState) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 0) {
        Color.clear.frame(width: Self.labelWidth, height: 36)
        ForEach(data.days) { day in
          VStack(spacing: 1) {
            Text(day.weekday.replacingOccurrences(of: "星期", with: "周")).font(Typo.caption)
            Text(Self.short(day.date)).font(Typo.tabularCaption)
          }
          .foregroundStyle(day.date == data.today ? Palette.q1 : Palette.ink3)
          .frame(width: Self.dayWidth, height: 36)
          .background(column(day, data))
        }
      }
      ForEach(data.roles, id: \.role) { group in
        Text(group.role)
          .font(Typo.caption).bold().foregroundStyle(Palette.ink3)
          .frame(height: 22, alignment: .bottom)
          .padding(.top, Metrics.xs)
        ForEach(group.items) { item in
          HStack(spacing: 0) {
            HStack(spacing: Metrics.xxs) {
              Text(Self.clean(item.text))
                .font(Typo.caption).foregroundStyle(Palette.ink)
                .lineLimit(2)
              if item.mit {
                Text("MIT").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.page)
                  .padding(.horizontal, 4).background(Palette.q1, in: Capsule())
              }
            }
            .frame(width: Self.labelWidth - Metrics.sm, alignment: .leading)
            .padding(.trailing, Metrics.sm)
            .help(item.text)
            ForEach(data.days) { day in
              cell(item: item, day: day, data: data)
            }
          }
          .frame(height: Self.rowHeight)
          .overlay(alignment: .bottom) { Rectangle().fill(Palette.rule).frame(height: Metrics.hairline) }
        }
      }
      HStack(spacing: 0) {
        Text("这天合计").font(Typo.caption).foregroundStyle(Palette.ink3)
          .frame(width: Self.labelWidth, alignment: .leading)
        ForEach(data.days) { day in
          let minutes = data.minutes(on: day.date)
          Text(minutes == 0 ? "" : DaySchedule.duration(minutes))
            .font(Typo.tabularCaption)
            .foregroundStyle(minutes > 6 * 60 ? Palette.warn : Palette.ink3)
            .frame(width: Self.dayWidth, height: 26)
            .background(column(day, data))
            .help(minutes > 6 * 60 ? "这天排了超过 6 小时，大概排不下" : "")
        }
      }
    }
  }

  @ViewBuilder private func cell(item: CycleScheduleState.Item, day: CycleScheduleState.Day, data: CycleScheduleState) -> some View {
    let sessions = data.schedule?.sessions(item: item.key, on: day.date) ?? []
    let isPast = day.date < data.today
    let deadline = data.schedule?.deadline(item: item.key) == day.date
    ZStack(alignment: .topTrailing) {
      Group {
        if let session = sessions.first {
          let total = sessions.reduce(0) { $0 + $1.minutes }
          Button {
            if editable && !isPast { editing = session }
          } label: {
            Text(session.bigRock ? (session.start ?? "") : DaySchedule.duration(total))
              .font(.system(size: 10, weight: session.bigRock ? .semibold : .regular).monospacedDigit())
              .foregroundStyle(session.bigRock ? Palette.page : Palette.mint800)
              .frame(width: Self.dayWidth - 6, height: 22)
              .background(session.bigRock ? Palette.mint600 : Palette.mint200, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
              .opacity(isPast ? 0.45 : 1)
          }
          .buttonStyle(.plain)
          .help(help(session, total: total))
          .popover(isPresented: editorBinding(session), arrowEdge: .bottom) {
            SessionEditor(
              session: session,
              days: data.days.filter { $0.date >= data.today },
              isDeadline: deadline,
              onSave: { updated, makesDeadline in save(replacing: session, with: updated, deadline: makesDeadline, item: item) },
              onDelete: { remove(session) },
              onCancel: { editing = nil }
            )
          }
        } else if editable && !isPast {
          Button { add(item: item, day: day) } label: {
            Color.clear.frame(width: Self.dayWidth, height: Self.rowHeight).contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .help("在这天排一次（1 小时）")
        } else {
          Color.clear
        }
      }
      .frame(width: Self.dayWidth, height: Self.rowHeight)
      if deadline {
        Rectangle().fill(Palette.q1).frame(width: 7, height: 7).rotationEffect(.degrees(45))
          .padding(4)
          .help("截止 \(Self.short(day.date))")
      }
    }
    .frame(width: Self.dayWidth, height: Self.rowHeight)
    .background(column(day, data))
  }

  /// Rest days tinted, today's column marked.
  private func column(_ day: CycleScheduleState.Day, _ data: CycleScheduleState) -> some View {
    ZStack(alignment: .leading) {
      (day.restDay ? Palette.mint50 : Color.clear)
      if day.date == data.today { Rectangle().fill(Palette.q1).frame(width: 1.5) }
    }
  }

  private var legend: some View {
    HStack(spacing: Metrics.md) {
      legendItem(Palette.mint600, "大石头 · 占了时段")
      legendItem(Palette.mint200, "这天做 · 不定时段")
      HStack(spacing: 4) {
        Rectangle().fill(Palette.q1).frame(width: 7, height: 7).rotationEffect(.degrees(45))
        Text("截止")
      }
      if editable { Text("点空格加一次，点格子改日子、时段、时长") }
    }
    .font(Typo.caption).foregroundStyle(Palette.ink3)
  }

  private func legendItem(_ color: Color, _ label: String) -> some View {
    HStack(spacing: 4) {
      RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 14, height: 10)
      Text(label)
    }
  }

  // MARK: Actions

  private func editorBinding(_ session: ScheduleSession) -> Binding<Bool> {
    Binding(get: { editing?.id == session.id }, set: { if !$0 { editing = nil } })
  }

  private func add(item: CycleScheduleState.Item, day: CycleScheduleState.Day) {
    guard var data else { return }
    var schedule = data.schedule ?? CycleSchedule(sessions: [], deadlines: [])
    schedule.sessions.append(ScheduleSession(id: "u-\(UUID().uuidString.prefix(8).lowercased())", itemKey: item.key, label: item.text, date: day.date, minutes: 60))
    data.schedule = schedule
    self.data = data
    persist(schedule)
  }

  private func save(replacing old: ScheduleSession, with new: ScheduleSession, deadline: Bool, item: CycleScheduleState.Item) {
    editing = nil
    guard var data, var schedule = data.schedule else { return }
    schedule.sessions = schedule.sessions.map { $0.id == old.id ? new : $0 }
    schedule.deadlines.removeAll { $0.itemKey == item.key && (deadline || $0.date == old.date) }
    if deadline { schedule.deadlines.append(ScheduleDeadline(itemKey: item.key, label: item.text, date: new.date)) }
    data.schedule = schedule
    self.data = data
    persist(schedule)
  }

  private func remove(_ session: ScheduleSession) {
    editing = nil
    guard var data, var schedule = data.schedule else { return }
    schedule.sessions.removeAll { $0.id == session.id }
    data.schedule = schedule
    self.data = data
    persist(schedule)
  }

  /// Applied on screen first, then saved whole; a refusal reloads what the
  /// service actually has.
  private func persist(_ schedule: CycleSchedule) {
    Task {
      switch await state.saveCycleSchedule(cycleID: cycle.id, sessions: schedule.sessions, deadlines: schedule.deadlines) {
      case .success(let saved):
        data?.schedule = saved
        state.toast = "排期已保存，明天起的计划按它来"
      case .failure(let error):
        state.toast = error.message
        await load()
      }
    }
  }

  private func generate() {
    guard !isStarting else { return }
    isStarting = true
    Task {
      let outcome = await state.generateCycleSchedule(cycleID: cycle.id)
      isStarting = false
      switch outcome {
      case .ok(let message):
        state.toast = message ?? "开始排期"
        await poll()
      case .failed(let why), .unsupported(let why):
        state.toast = why
      }
    }
  }

  /// Every 5 s for up to 5 minutes, until the run clears.
  private func poll() async {
    for _ in 0..<60 {
      await load()
      if data?.running != true { return }
      try? await Task.sleep(for: .seconds(5))
    }
  }

  private func load() async {
    if data == nil { phase = .loading }
    switch await state.loadCycleSchedule(cycleID: cycle.id) {
    case .success(let loaded):
      data = loaded
      phase = .loaded
      if loaded.running && !isStarting { Task { await poll() } }
    case .failure(let error):
      if data == nil { phase = .failed(error.message) }
    }
  }

  // MARK: Text

  private var subtitle: String {
    guard let schedule = data?.schedule else { return "先排双周，再拆每天" }
    var parts: [String] = []
    if let generated = schedule.generatedAt { parts.append("生成于 \(Fmt.time(generated))") }
    if schedule.editedAt != nil { parts.append("你改过") }
    parts.append("每天的计划从这里取当天那一列")
    return parts.joined(separator: " · ")
  }

  private func generateTitle(_ data: CycleScheduleState) -> String {
    if data.running || isStarting { return "正在排…" }
    return data.schedule == nil ? "生成排期" : "重新排今天以后"
  }

  private func help(_ session: ScheduleSession, total: Int) -> String {
    let when = session.start.map { "\($0) 起 " } ?? ""
    return "\(Self.clean(session.label))\n\(Self.short(session.date)) \(when)\(DaySchedule.duration(total))\(session.bigRock ? " · 大石头" : "")"
  }

  static func short(_ date: String) -> String {
    let parts = date.split(separator: "-")
    guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return date }
    return "\(month).\(day)"
  }

  /// The 要务 text without its markdown emphasis; MIT shows as a pill instead.
  static func clean(_ text: String) -> String {
    text.replacingOccurrences(of: "**MIT**", with: "").replacingOccurrences(of: "**", with: "").trimmingCharacters(in: .whitespaces)
  }
}

/// Change one session: its day, whether it holds a slot (and when), how long,
/// and whether its day is the 要务's deadline.
private struct SessionEditor: View {
  @State private var draft: ScheduleSession
  @State private var makesDeadline: Bool
  let days: [CycleScheduleState.Day]
  let onSave: (ScheduleSession, Bool) -> Void
  let onDelete: () -> Void
  let onCancel: () -> Void

  private static let presets = [15, 30, 45, 60, 90, 120, 180]
  private static let clocks: [String] = stride(from: 7 * 60, through: 22 * 60, by: 30).map { DaySchedule.clock($0) }

  init(session: ScheduleSession, days: [CycleScheduleState.Day], isDeadline: Bool, onSave: @escaping (ScheduleSession, Bool) -> Void, onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
    _draft = State(initialValue: session)
    _makesDeadline = State(initialValue: isDeadline)
    self.days = days
    self.onSave = onSave
    self.onDelete = onDelete
    self.onCancel = onCancel
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.sm) {
      Text(CycleSchedulePanel.clean(draft.label)).font(Typo.bodyStrong).lineLimit(3)
      Picker("哪天", selection: $draft.date) {
        ForEach(days) { day in
          Text("\(CycleSchedulePanel.short(day.date)) \(day.weekday.replacingOccurrences(of: "星期", with: "周"))").tag(day.date)
        }
      }
      Toggle("大石头：占一个具体时段", isOn: Binding(
        get: { draft.bigRock },
        set: { draft.bigRock = $0; if $0 && draft.start == nil { draft.start = "10:00" } }
      ))
      if draft.bigRock {
        Picker("从几点", selection: Binding(get: { draft.start ?? "10:00" }, set: { draft.start = $0 })) {
          ForEach(Self.clocks, id: \.self) { Text($0).tag($0) }
        }
      }
      VStack(alignment: .leading, spacing: Metrics.xxs) {
        Text("时长").font(Typo.caption).foregroundStyle(Palette.ink3)
        HStack(spacing: Metrics.xxs) {
          ForEach(Self.presets, id: \.self) { minutes in
            Button(Fmt.minutes(minutes)) { draft.minutes = minutes }
              .buttonStyle(QuietButtonStyle(tone: draft.minutes == minutes ? .accent : .neutral))
          }
        }
      }
      Toggle("这天是它的截止日", isOn: $makesDeadline)
      HStack {
        Button(role: .destructive, action: onDelete) { Label("删掉这一次", systemImage: "trash") }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
        Spacer()
        Button("取消", action: onCancel).buttonStyle(QuietButtonStyle(tone: .neutral)).keyboardShortcut(.cancelAction)
        Button("保存") {
          var saved = draft
          if !saved.bigRock { saved.start = nil }
          onSave(saved, makesDeadline)
        }
        .buttonStyle(MossButtonStyle(prominent: true))
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(Metrics.md)
    .frame(width: 400)
  }
}
