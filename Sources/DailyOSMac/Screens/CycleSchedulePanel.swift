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
  @State private var selectedWeek: Int?
  @State private var drag: Drag?
  @State private var adding: AddRequest?

  private struct AddRequest: Equatable { let date: String; let start: Int }

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
            week(data)
            legend
          }
        }
      }
    }
  }

  // MARK: Week

  private static let gutter: CGFloat = 46
  private static let pointsPerMinute: CGFloat = 0.8
  private static let firstHour = 7
  private static let lastHour = 24
  private static let minColumn: CGFloat = 96

  private func y(_ minute: Int) -> CGFloat { CGFloat(minute - Self.firstHour * 60) * Self.pointsPerMinute }

  private func weekIndex(_ data: CycleScheduleState) -> Int {
    if let chosen = selectedWeek { return min(chosen, max(data.weeks.count - 1, 0)) }
    return data.weeks.firstIndex { week in week.contains { $0.date == data.today } } ?? 0
  }

  private func week(_ data: CycleScheduleState) -> some View {
    let weeks = data.weeks
    let index = weekIndex(data)
    let days = weeks.isEmpty ? [] : weeks[index]
    return VStack(alignment: .leading, spacing: Metrics.xs) {
      if weeks.count > 1 {
        Picker("", selection: Binding(get: { index }, set: { selectedWeek = $0 })) {
          ForEach(weeks.indices, id: \.self) { i in
            Text("第 \(i + 1) 周 · \(Self.short(weeks[i].first?.date ?? ""))–\(Self.short(weeks[i].last?.date ?? ""))").tag(i)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 360)
      }
      GeometryReader { geo in
        let column = max(Self.minColumn, (geo.size.width - Self.gutter) / CGFloat(max(days.count, 1)))
        ScrollView(.horizontal) {
          VStack(alignment: .leading, spacing: 0) {
            weekHeader(days, data: data, column: column)
            allDayStrip(days, data: data, column: column)
            ZStack(alignment: .topLeading) {
              hourGrid(width: Self.gutter + column * CGFloat(days.count))
              HStack(spacing: 0) {
                Color.clear.frame(width: Self.gutter)
                ForEach(days) { day in
                  dayColumn(day, data: data, column: column, days: days)
                }
              }
            }
            .frame(height: y(Self.lastHour * 60))
            .coordinateSpace(name: "schedule.week")
          }
        }
      }
      .frame(height: weekHeight(days, data: data))
    }
  }

  private func weekHeight(_ days: [CycleScheduleState.Day], data: CycleScheduleState) -> CGFloat {
    48 + allDayHeight(days, data: data) + y(Self.lastHour * 60) + 8
  }

  private func allDayHeight(_ days: [CycleScheduleState.Day], data: CycleScheduleState) -> CGFloat {
    let rows = days.map { day in
      let layout = CycleWeekLayout.layout(day, in: data)
      return layout.allDay.count + layout.unplaced.count
    }.max() ?? 0
    return rows == 0 ? 0 : CGFloat(rows) * 20 + 8
  }

  private func weekHeader(_ days: [CycleScheduleState.Day], data: CycleScheduleState, column: CGFloat) -> some View {
    HStack(spacing: 0) {
      Color.clear.frame(width: Self.gutter, height: 48)
      ForEach(days) { day in
        let isToday = day.date == data.today
        VStack(spacing: 2) {
          Text(day.weekday.replacingOccurrences(of: "星期", with: "周"))
            .font(Typo.caption)
            .foregroundStyle(isToday ? Palette.mint600 : Palette.ink3)
          Text(Self.dayNumber(day.date))
            .font(.system(size: 18, weight: isToday ? .semibold : .regular).monospacedDigit())
            .foregroundStyle(isToday ? Palette.page : (day.date < data.today ? Palette.ink3 : Palette.ink))
            .frame(width: 30, height: 30)
            .background(Circle().fill(isToday ? Palette.mint600 : Color.clear))
        }
        .frame(width: column, height: 48)
        .background(day.restDay ? Palette.mint50.opacity(0.6) : Color.clear)
      }
    }
  }

  @ViewBuilder private func allDayStrip(_ days: [CycleScheduleState.Day], data: CycleScheduleState, column: CGFloat) -> some View {
    let height = allDayHeight(days, data: data)
    if height > 0 {
      HStack(alignment: .top, spacing: 0) {
        Text("全天").font(Typo.caption).foregroundStyle(Palette.ink3)
          .frame(width: Self.gutter, alignment: .trailing).padding(.trailing, 6).padding(.top, 4)
        ForEach(days) { day in
          let layout = CycleWeekLayout.layout(day, in: data)
          VStack(alignment: .leading, spacing: 2) {
            ForEach(layout.allDay, id: \.self) { text in
              chip(Self.clean(text), fill: text.hasPrefix("截止") ? Palette.q1.opacity(0.15) : Palette.surfaceSunken, ink: text.hasPrefix("截止") ? Palette.q1 : Palette.ink2)
            }
            ForEach(layout.unplaced) { session in
              chip("排不下 · \(Self.clean(session.title))", fill: Palette.mint100, ink: Palette.mint800)
                .onTapGesture { if editable { editing = session } }
            }
          }
          .padding(.horizontal, 2)
          .padding(.top, 4)
          .frame(width: column, height: height, alignment: .topLeading)
        }
      }
      .overlay(alignment: .bottom) { Rectangle().fill(Palette.rule).frame(height: Metrics.hairline) }
    }
  }

  private func chip(_ text: String, fill: Color, ink: Color) -> some View {
    Text(text)
      .font(.system(size: 10))
      .foregroundStyle(ink)
      .lineLimit(1)
      .padding(.horizontal, 5)
      .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
      .background(fill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
  }

  private func hourGrid(width: CGFloat) -> some View {
    ZStack(alignment: .topLeading) {
      ForEach(Self.firstHour...Self.lastHour, id: \.self) { hour in
        HStack(spacing: 4) {
          Text(String(format: "%02d:00", hour)).font(Typo.tabularCaption).foregroundStyle(Palette.ink3)
            .frame(width: Self.gutter - 6, alignment: .trailing)
          Rectangle().fill(Palette.rule).frame(height: Metrics.hairline)
        }
        .frame(width: width, alignment: .leading)
        .offset(y: y(hour * 60) - 7)
      }
    }
  }

  private func dayColumn(_ day: CycleScheduleState.Day, data: CycleScheduleState, column: CGFloat, days: [CycleScheduleState.Day]) -> some View {
    let layout = CycleWeekLayout.layout(day, in: data)
    let columns = TimelineColumns.assign(layout.blocks.map { .init(id: $0.id, start: $0.start, end: $0.end) })
    let isPast = day.date < data.today
    return ZStack(alignment: .topLeading) {
      // Work hours lightly lit, so the free time reads at a glance.
      Rectangle().fill(Palette.page.opacity(0.6))
        .frame(height: max(0, y(day.workEnd) - y(day.workStart)))
        .offset(y: y(day.workStart))
      Rectangle().fill(Color.clear).contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { point in
          guard editable, !isPast else { return }
          let minute = Self.firstHour * 60 + Int(point.y / Self.pointsPerMinute)
          adding = AddRequest(date: day.date, start: min(23 * 60, minute / 30 * 30))
        }
      ForEach(layout.blocks) { block in
        let placement = columns[block.id] ?? .init(column: 0, count: 1)
        let width = (column - 4) / CGFloat(placement.count)
        blockView(block, isPast: isPast, height: max(14, CGFloat(block.end - block.start) * Self.pointsPerMinute - 2))
          .frame(width: max(width - 2, 10))
          .offset(x: 2 + width * CGFloat(placement.column), y: y(drag?.id == block.id ? drag!.start : block.start) + 1)
          .offset(x: drag?.id == block.id ? drag!.dx : 0)
          .gesture(moveGesture(block, day: day, days: days, column: column, isPast: isPast))
      }
      if day.date == data.today, let now = data.nowMinute, now >= Self.firstHour * 60 {
        ZStack(alignment: .leading) {
          Rectangle().fill(Palette.danger).frame(height: 1.5)
          Circle().fill(Palette.danger).frame(width: 8, height: 8).offset(x: -4)
        }
        .offset(y: y(now) - 1)
        .allowsHitTesting(false)
      }
    }
    .frame(width: column, height: y(Self.lastHour * 60), alignment: .topLeading)
    .background(day.restDay ? Palette.mint50.opacity(0.6) : Color.clear)
    .overlay(alignment: .leading) { Rectangle().fill(Palette.rule).frame(width: Metrics.hairline) }
    .opacity(isPast ? 0.55 : 1)
    .popover(isPresented: addBinding(day.date), arrowEdge: .leading) {
      if let adding {
        AddSessionPicker(items: data.items, start: adding.start) { item in
          add(item: item, date: day.date, start: adding.start)
        }
      }
    }
  }

  @ViewBuilder private func blockView(_ block: CycleWeekLayout.Placed, isPast: Bool, height: CGFloat) -> some View {
    let style = Self.style(block.kind)
    let time = "\(DaySchedule.clock(block.start))–\(DaySchedule.clock(min(block.end, 24 * 60 - 1)))"
    // A step leads; the 要务 it belongs to follows in small type, so a day
    // reads as what gets done rather than as the cycle's list again.
    let parent = block.session.flatMap { $0.step == nil ? nil : Self.clean($0.label) }
    let content = VStack(alignment: .leading, spacing: 1) {
      Text(Self.clean(block.title))
        .font(.system(size: 11, weight: block.kind == .bigRock ? .semibold : .medium))
        .lineLimit(height > 40 ? 2 : 1)
      if height > 30 {
        Text(time).font(.system(size: 10).monospacedDigit()).opacity(0.85)
      }
      if let parent, height > 56 {
        Text(parent).font(.system(size: 9)).opacity(0.75).lineLimit(1)
      }
    }
    .foregroundStyle(style.ink)
    .padding(.horizontal, 5)
    .padding(.vertical, 2)
    .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
    .background(style.fill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    .overlay {
      if block.kind == .suggested {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .strokeBorder(Palette.mint400, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
      }
    }
    .help("\(Self.clean(block.title))\n\(time)\(Self.kindNote(block.kind))")
    if let session = block.session {
      content
        .contentShape(Rectangle())
        .onTapGesture { if editable && !isPast { editing = session } }
        .popover(isPresented: editorBinding(session), arrowEdge: .trailing) {
          SessionEditor(
            session: session,
            days: (data?.days ?? []).filter { $0.date >= (data?.today ?? "") },
            isDeadline: data?.schedule?.deadline(item: session.itemKey) == session.date,
            onSave: { updated, makesDeadline in save(replacing: session, with: updated, deadline: makesDeadline) },
            onDelete: { remove(session) },
            onCancel: { editing = nil }
          )
        }
    } else {
      content.allowsHitTesting(block.kind == .event)
    }
  }

  private static func style(_ kind: CycleWeekLayout.Kind) -> (fill: Color, ink: Color) {
    switch kind {
    case .event: (Palette.series[4].opacity(0.85), Palette.page)
    case .routine: (Palette.surfaceSunken, Palette.ink3)
    case .bigRock: (Palette.mint600, Palette.page)
    case .suggested: (Palette.mint100, Palette.mint800)
    }
  }

  private static func kindNote(_ kind: CycleWeekLayout.Kind) -> String {
    switch kind {
    case .event: "\n飞书日程"
    case .routine: "\n作息"
    case .bigRock: "\n大石头 · 占了这个时段"
    case .suggested: "\n建议时段 · 拖到一个钟点就固定下来"
    }
  }

  private var legend: some View {
    HStack(spacing: Metrics.md) {
      legendItem(Palette.mint600, "大石头 · 占了时段")
      HStack(spacing: 4) {
        RoundedRectangle(cornerRadius: 3).fill(Palette.mint100)
          .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.mint400, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
          .frame(width: 14, height: 10)
        Text("建议时段 · 只定了哪天")
      }
      legendItem(Palette.series[4].opacity(0.85), "飞书日程")
      if editable { Text("点空白处加一项 · 拖动改时间和日子") }
    }
    .font(Typo.caption).foregroundStyle(Palette.ink3)
  }

  private func legendItem(_ color: Color, _ label: String) -> some View {
    HStack(spacing: 4) {
      RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 14, height: 10)
      Text(label)
    }
  }

  // MARK: Drag

  private struct Drag: Equatable { let id: String; var start: Int; var dx: CGFloat }

  private func moveGesture(_ block: CycleWeekLayout.Placed, day: CycleScheduleState.Day, days: [CycleScheduleState.Day], column: CGFloat, isPast: Bool) -> some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { value in
        guard editable, !isPast, block.session != nil else { return }
        let minutes = Int((value.translation.height / Self.pointsPerMinute).rounded())
        let start = max(Self.firstHour * 60, min(Self.lastHour * 60 - (block.end - block.start), (block.start + minutes) / 15 * 15))
        drag = Drag(id: block.id, start: start, dx: value.translation.width)
      }
      .onEnded { value in
        guard let drag, drag.id == block.id, var session = block.session else { self.drag = nil; return }
        self.drag = nil
        let shift = Int((value.translation.width / column).rounded())
        let index = (days.firstIndex(where: { $0.date == day.date }) ?? 0) + shift
        let target = days[max(0, min(days.count - 1, index))]
        guard target.date >= (data?.today ?? "") else { state.toast = "排不到今天以前"; return }
        guard drag.start != block.start || target.date != day.date else { return }
        session.date = target.date
        session.start = DaySchedule.clock(drag.start)
        // Put at a time on purpose: that is a reservation now.
        session.bigRock = true
        save(replacing: block.session!, with: session, deadline: nil)
      }
  }

  // MARK: Actions

  private func editorBinding(_ session: ScheduleSession) -> Binding<Bool> {
    Binding(get: { editing?.id == session.id }, set: { if !$0 { editing = nil } })
  }

  private func addBinding(_ date: String) -> Binding<Bool> {
    Binding(get: { adding?.date == date }, set: { if !$0 { adding = nil } })
  }

  /// Added at a clicked time: a reserved slot, an hour long.
  private func add(item: CycleScheduleState.Item, date: String, start: Int) {
    adding = nil
    guard var data else { return }
    var schedule = data.schedule ?? CycleSchedule(sessions: [], deadlines: [])
    schedule.sessions.append(ScheduleSession(
      id: "u-\(UUID().uuidString.prefix(8).lowercased())", itemKey: item.key, label: item.text,
      date: date, start: DaySchedule.clock(start), minutes: 60, bigRock: true
    ))
    data.schedule = schedule
    self.data = data
    persist(schedule)
  }

  /// `deadline` nil leaves the 要务's deadline as it was.
  private func save(replacing old: ScheduleSession, with new: ScheduleSession, deadline: Bool?) {
    editing = nil
    guard var data, var schedule = data.schedule else { return }
    schedule.sessions = schedule.sessions.map { $0.id == old.id ? new : $0 }
    if let deadline {
      schedule.deadlines.removeAll { $0.itemKey == old.itemKey && (deadline || $0.date == old.date) }
      if deadline { schedule.deadlines.append(ScheduleDeadline(itemKey: old.itemKey, label: old.label, date: new.date)) }
    }
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
    return "\(Self.clean(session.title))\n\(Self.short(session.date)) \(when)\(DaySchedule.duration(total))\(session.bigRock ? " · 大石头" : "")"
  }

  static func dayNumber(_ date: String) -> String {
    Int(date.split(separator: "-").last ?? "").map(String.init) ?? date
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

/// Which 要务 to put at a clicked time.
private struct AddSessionPicker: View {
  let items: [CycleScheduleState.Item]
  let start: Int
  let onPick: (CycleScheduleState.Item) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xxs) {
      Text("\(DaySchedule.clock(start)) 起排一项（1 小时）").font(Typo.caption).foregroundStyle(Palette.ink3)
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(items) { item in
            Button { onPick(item) } label: {
              HStack(spacing: Metrics.xxs) {
                Text(CycleSchedulePanel.clean(item.text)).font(Typo.body).foregroundStyle(Palette.ink).lineLimit(1)
                if item.mit { Text("MIT").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.q1) }
                Spacer(minLength: 0)
              }
              .padding(.vertical, 5)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }
        }
      }
      .frame(maxHeight: 320)
    }
    .padding(Metrics.md)
    .frame(width: 320)
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
      Text(CycleSchedulePanel.clean(draft.label)).font(Typo.caption).foregroundStyle(Palette.ink3).lineLimit(2)
      TextField("这一次具体做什么，比如「整理回访表格，分析国内外用户」", text: Binding(
        get: { draft.step ?? "" },
        set: { draft.step = $0.isEmpty ? nil : String($0.prefix(80)) }
      ), axis: .vertical)
      .textFieldStyle(.roundedBorder)
      .font(Typo.bodyStrong)
      .lineLimit(1...3)
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
