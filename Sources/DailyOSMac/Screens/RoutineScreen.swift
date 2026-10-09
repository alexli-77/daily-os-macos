import SwiftUI
import DailyOSCore

/// 作息 — the frame a period of the user's life runs on.
///
/// One page per period (a residency, a semester): when it runs, when the day
/// starts and ends, its day types (workday / weekend) and their modes (作品集日
/// / Cutto 日), each drawn as the day it describes. A coloured block is time
/// kept for one category — the day's to-dos of that category go into it; a
/// grey one is fixed (getting up, meals, meetings). A solid outline and a 保底
/// tag mark a floor: the least that category gets on a busy day.
///
/// The frame changes rarely and the times inside it more often, so editing is
/// in place: click a block to change it, every change is saved at once.
struct RoutineScreen: View {
  @Environment(AppState.self) private var state

  private enum Phase: Equatable {
    case loading
    case loaded
    case failed(String)
  }

  @State private var phase: Phase = .loading
  @State private var routine: RoutineState?
  @State private var selectedPeriodID: String?
  @State private var selectedDayTypeID: String?
  @State private var selectedModeID: String?
  @State private var editingBlock: RoutineBlock?
  @State private var editsPeriod = false
  @State private var editsWeekdays = false
  @State private var renaming: Renaming?

  private struct Renaming: Identifiable, Equatable {
    enum Target: Equatable { case mode, dayType }
    let target: Target
    var text: String
    var id: String { "\(target)" }
  }

  var body: some View {
    HStack(spacing: 0) {
      ResizableListColumn(id: "routine") { periodList }
      Group {
        switch phase {
        case .loading:
          ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
          EmptyState(icon: "exclamationmark.triangle", title: "读不到作息", message: message, actionTitle: "重试") {
            Task { await load() }
          }
        case .loaded:
          if let period = currentPeriod {
            detail(period)
          } else {
            EmptyState(
              icon: "calendar.day.timeline.left",
              title: "还没有作息",
              message: "作息定义一段时期每天几点起睡、哪段时间做哪类事。今天的计划和双周排期会按它排。",
              actionTitle: "新建作息",
              action: { addPeriod() }
            )
          }
        }
      }
      .frame(maxWidth: .infinity)
    }
    .background(Palette.paper)
    .task { await load() }
    .sheet(isPresented: $editsPeriod) {
      if let period = currentPeriod {
        PeriodEditor(period: period) { updated in
          editsPeriod = false
          mutatePeriod { $0 = updated }
        } onCancel: { editsPeriod = false } onDelete: {
          editsPeriod = false
          deletePeriod(period.id)
        }
      }
    }
  }

  // MARK: Period list

  private var periodList: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("作息").font(Typo.heading).foregroundStyle(Palette.ink)
        Spacer()
        Button { addPeriod() } label: { Image(systemName: "plus") }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
          .help("新建一个时期的作息（复制当前这个）")
      }
      .padding(Metrics.md)
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(routine?.periods ?? []) { period in
            SelectableRow(isSelected: period.id == currentPeriod?.id) {
              selectedPeriodID = period.id
              selectedDayTypeID = nil
              selectedModeID = nil
            } content: {
              VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Metrics.xxs) {
                  Text(period.name).font(Typo.body).foregroundStyle(Palette.ink).lineLimit(1)
                  if let today = routine?.today, period.contains(today) {
                    Pill("现在", tone: .accent)
                  }
                }
                Text("\(Self.short(period.from)) – \(Self.short(period.to))").font(Typo.caption).foregroundStyle(Palette.ink3)
              }
            }
          }
        }
        .padding(Metrics.xs)
      }
    }
    .background(Palette.paper)
  }

  // MARK: Detail

  private func detail(_ period: RoutinePeriod) -> some View {
    ScreenScaffold(period.name, subtitle: subtitle(period)) {
      if let problems = routine?.problems, !problems.isEmpty {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(problems, id: \.self) { Text($0) }
        }
        .font(Typo.caption).foregroundStyle(Palette.warn)
      }
      pickers(period)
      if let dayType = currentDayType(period), let mode = currentMode(dayType) {
        HStack(alignment: .top, spacing: Metrics.md) {
          dayView(period, mode: mode)
            .frame(maxWidth: .infinity)
          VStack(alignment: .leading, spacing: Metrics.md) {
            totals(period, dayType: dayType, mode: mode)
            CategoriesPanel(period: period) { categories in mutatePeriod { $0.categories = categories } }
            RulesPanel(rules: period.rules) { rules in mutatePeriod { $0.rules = rules } }
          }
          .frame(width: 280)
        }
      } else {
        EmptyState(icon: "plus.square.dashed", title: "这个时期还没有日型", message: "日型是安排相同的几天，比如工作日、周末。", actionTitle: "加一个日型") {
          addDayType()
        }
      }
    } toolbar: {
      Button("编辑时期") { editsPeriod = true }
        .buttonStyle(QuietButtonStyle(tone: .neutral))
    }
  }

  /// One line: where, when, and the period's own summary. Wake and sleep
  /// times are left out when the summary already says them.
  private func subtitle(_ period: RoutinePeriod) -> String {
    let summary = period.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    func said(_ clock: String) -> Bool {
      summary.contains(clock) || (clock.hasPrefix("0") && summary.contains(String(clock.dropFirst())))
    }
    var parts: [String] = []
    if let subtitle = period.subtitle, !subtitle.isEmpty { parts.append(subtitle) }
    parts.append("\(Self.short(period.from)) – \(Self.short(period.to))")
    if let wake = period.wake, !said(wake) { parts.append("\(wake) 起") }
    if let sleep = period.sleep, !said(sleep) { parts.append("\(sleep) 睡") }
    if !summary.isEmpty { parts.append(summary) }
    return parts.joined(separator: " · ")
  }

  /// 日型 then 模式, the two choices that pick which day is on screen.
  private func pickers(_ period: RoutinePeriod) -> some View {
    VStack(alignment: .leading, spacing: Metrics.xs) {
      HStack(spacing: Metrics.sm) {
        Text("日型").font(Typo.caption).foregroundStyle(Palette.ink3).frame(width: 32, alignment: .leading)
        Picker("", selection: Binding(get: { currentDayType(period)?.id ?? "" }, set: { selectedDayTypeID = $0; selectedModeID = nil })) {
          ForEach(period.dayTypes) { type in
            Text("\(type.label) · \(type.weekdays.map(RoutineWeekday.label).joined())").tag(type.id)
          }
        }
        .pickerStyle(.segmented).labelsHidden().fixedSize()
        Menu {
          Button("改星期几…") { editsWeekdays = true }
          Button("改名…") { renaming = .init(target: .dayType, text: currentDayType(period)?.label ?? "") }
          Button("加一个日型") { addDayType() }
          Divider()
          Button("删掉这个日型", role: .destructive) { deleteDayType() }
        } label: { Image(systemName: "ellipsis.circle") }
          .menuStyle(.borderlessButton).fixedSize()
          .popover(isPresented: $editsWeekdays) {
            if let type = currentDayType(period) {
              WeekdayPicker(selected: type.weekdays, taken: period.dayTypes.filter { $0.id != type.id }.flatMap(\.weekdays)) { weekdays in
                mutateDayType { $0.weekdays = weekdays }
              }
            }
          }
      }
      if let dayType = currentDayType(period) {
        HStack(spacing: Metrics.sm) {
          Text("模式").font(Typo.caption).foregroundStyle(Palette.ink3).frame(width: 32, alignment: .leading)
          Picker("", selection: Binding(get: { currentMode(dayType)?.id ?? "" }, set: { selectedModeID = $0 })) {
            ForEach(dayType.modes) { mode in
              Text(mode.id == dayType.defaultMode ? "\(mode.label)（默认）" : mode.label).tag(mode.id)
            }
          }
          .pickerStyle(.segmented).labelsHidden().fixedSize()
          Menu {
            Button("设为默认") { mutateDayType { type in type.defaultMode = currentMode(type)?.id ?? type.defaultMode } }
            Button("改名…") { renaming = .init(target: .mode, text: currentMode(dayType)?.label ?? "") }
            Button("复制成新模式") { duplicateMode() }
            Divider()
            Button("删掉这个模式", role: .destructive) { deleteMode() }
              .disabled(dayType.modes.count < 2)
          } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).fixedSize()
          if dayType.modes.count > 1 {
            Text("当天用哪个模式，在「今天」页切换").font(Typo.caption).foregroundStyle(Palette.ink3)
          }
        }
      }
    }
    .popover(item: $renaming) { item in
      RenameField(text: item.text) { name in
        renaming = nil
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        switch item.target {
        case .mode: mutateMode { $0.label = trimmed }
        case .dayType: mutateDayType { $0.label = trimmed }
        }
      }
    }
  }

  // MARK: Day

  private static let pointsPerMinute: CGFloat = 0.9

  private func dayView(_ period: RoutinePeriod, mode: RoutineMode) -> some View {
    let first = min(mode.blocks.map(\.startMinute).min() ?? 7 * 60, period.wake.flatMap(DayStart.minute(fromClock:)) ?? 24 * 60) / 60 * 60
    let last = max(mode.blocks.map(\.endMinute).max() ?? 22 * 60, period.sleep.flatMap(DayStart.minute(fromClock:)) ?? 0)
    let hours = Array(stride(from: first / 60, through: min(24, (last + 59) / 60), by: 1))
    let y = { (minute: Int) in CGFloat(minute - first) * Self.pointsPerMinute }
    return Panel(mode.label) {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        ZStack(alignment: .topLeading) {
          ForEach(hours, id: \.self) { hour in
            HStack(spacing: 4) {
              Text(String(format: "%02d:00", hour)).font(Typo.tabularCaption).foregroundStyle(Palette.ink3).frame(width: 40, alignment: .trailing)
              Rectangle().fill(Palette.rule).frame(height: Metrics.hairline)
            }
            .offset(y: y(hour * 60) - 7)
          }
          ForEach(mode.blocks) { block in
            RoutineBlockView(block: block, category: period.category(block.category))
              .frame(height: max(16, CGFloat(block.minutes) * Self.pointsPerMinute - 2))
              .padding(.leading, 50)
              .offset(y: y(block.startMinute) + 1)
              .onTapGesture { editingBlock = block }
              .popover(isPresented: Binding(get: { editingBlock?.id == block.id }, set: { if !$0 { editingBlock = nil } }), arrowEdge: .trailing) {
                BlockEditor(block: block, categories: period.categories) { updated in
                  editingBlock = nil
                  mutateMode { mode in mode.blocks = mode.blocks.map { $0.id == block.id ? updated : $0 }.sorted { $0.startMinute < $1.startMinute } }
                } onDelete: {
                  editingBlock = nil
                  mutateMode { $0.blocks.removeAll { $0.id == block.id } }
                } onCancel: { editingBlock = nil }
              }
          }
        }
        .frame(height: y(hours.last.map { $0 * 60 } ?? last) + 8, alignment: .top)
        Button { addBlock() } label: { Label("加一块", systemImage: "plus") }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
      }
    } actions: {
      EmptyView()
    }
  }

  private func totals(_ period: RoutinePeriod, dayType: RoutineDayType, mode: RoutineMode) -> some View {
    Panel("\(dayType.label) · \(mode.label)") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        let totals = mode.minutesByCategory()
        let longest = max(totals.first?.minutes ?? 1, 1)
        if totals.isEmpty {
          Text("给时间块选类别后，这里显示每类的时长。").font(Typo.caption).foregroundStyle(Palette.ink3)
        }
        ForEach(totals, id: \.key) { entry in
          let category = period.category(entry.key)
          HStack(spacing: Metrics.xs) {
            Text(category?.label ?? entry.key).font(Typo.caption).foregroundStyle(Palette.ink2).frame(width: 52, alignment: .leading)
            GeometryReader { geo in
              ZStack(alignment: .leading) {
                Capsule().fill(Palette.surfaceSunken)
                Capsule().fill(Self.color(category)).frame(width: geo.size.width * CGFloat(entry.minutes) / CGFloat(longest))
              }
            }
            .frame(height: 8)
            Text(DaySchedule.duration(entry.minutes)).font(Typo.tabularCaption).foregroundStyle(Palette.ink3).frame(width: 44, alignment: .trailing)
          }
        }
      }
    } actions: { EmptyView() }
  }

  // MARK: Selection

  private var currentPeriod: RoutinePeriod? {
    guard let periods = routine?.periods, !periods.isEmpty else { return nil }
    if let id = selectedPeriodID, let period = periods.first(where: { $0.id == id }) { return period }
    if let today = routine?.today, let period = periods.last(where: { $0.contains(today) }) { return period }
    return periods.last
  }

  private func currentDayType(_ period: RoutinePeriod) -> RoutineDayType? {
    if let id = selectedDayTypeID, let type = period.dayTypes.first(where: { $0.id == id }) { return type }
    return period.dayTypes.first
  }

  private func currentMode(_ dayType: RoutineDayType) -> RoutineMode? {
    if let id = selectedModeID, let mode = dayType.modes.first(where: { $0.id == id }) { return mode }
    return dayType.modes.first { $0.id == dayType.defaultMode } ?? dayType.modes.first
  }

  // MARK: Mutations

  private func mutatePeriod(_ change: (inout RoutinePeriod) -> Void) {
    guard var routine, let period = currentPeriod, let index = routine.periods.firstIndex(where: { $0.id == period.id }) else { return }
    change(&routine.periods[index])
    self.routine = routine
    persist(routine.periods)
  }

  private func mutateDayType(_ change: (inout RoutineDayType) -> Void) {
    mutatePeriod { period in
      guard let type = currentDayType(period), let index = period.dayTypes.firstIndex(where: { $0.id == type.id }) else { return }
      change(&period.dayTypes[index])
    }
  }

  private func mutateMode(_ change: (inout RoutineMode) -> Void) {
    mutateDayType { type in
      guard let mode = currentMode(type), let index = type.modes.firstIndex(where: { $0.id == mode.id }) else { return }
      change(&type.modes[index])
    }
  }

  private func addBlock() {
    mutateMode { mode in
      let start = mode.blocks.map(\.endMinute).max() ?? 9 * 60
      let begin = min(start, 23 * 60)
      mode.blocks.append(RoutineBlock(id: Self.newID("b"), start: DaySchedule.clock(begin), end: DaySchedule.clock(min(begin + 60, 24 * 60 - 1)), title: "新的一块", kind: .slot))
    }
  }

  private func duplicateMode() {
    mutateDayType { type in
      guard let mode = currentMode(type) else { return }
      let copy = RoutineMode(id: Self.newID("m"), label: "\(mode.label) 副本", blocks: mode.blocks)
      type.modes.append(copy)
      selectedModeID = copy.id
    }
  }

  private func deleteMode() {
    mutateDayType { type in
      guard type.modes.count > 1, let mode = currentMode(type) else { return }
      type.modes.removeAll { $0.id == mode.id }
      if type.defaultMode == mode.id { type.defaultMode = type.modes[0].id }
      selectedModeID = nil
    }
  }

  private func addDayType() {
    mutatePeriod { period in
      let taken = Set(period.dayTypes.flatMap(\.weekdays))
      let free = RoutineWeekday.codes.filter { !taken.contains($0) }
      let mode = RoutineMode(id: Self.newID("m"), label: "平常", blocks: [])
      let type = RoutineDayType(id: Self.newID("d"), label: "新日型", weekdays: free.isEmpty ? ["SAT"] : free, defaultMode: mode.id, modes: [mode])
      period.dayTypes.append(type)
      selectedDayTypeID = type.id
      selectedModeID = nil
    }
  }

  private func deleteDayType() {
    mutatePeriod { period in
      guard let type = currentDayType(period) else { return }
      period.dayTypes.removeAll { $0.id == type.id }
      selectedDayTypeID = nil
      selectedModeID = nil
    }
  }

  /// A new period starts as a copy of the one on screen: the frame stays, the
  /// times change — which is how the user described changing it.
  private func addPeriod() {
    var routine = self.routine ?? RoutineState(today: "", periods: [])
    let today = routine.today.isEmpty ? Self.dayString(Date()) : routine.today
    let base = currentPeriod
    let period = RoutinePeriod(
      id: Self.newID("p"),
      name: base.map { "\($0.name) 副本" } ?? "新的作息",
      from: today,
      to: Self.dayString(Calendar.current.date(byAdding: .day, value: 13, to: Self.date(today) ?? Date()) ?? Date()),
      wake: base?.wake ?? "07:00",
      sleep: base?.sleep ?? "23:00",
      summary: base?.summary,
      categories: base?.categories ?? [
        RoutineCategory(key: "work", label: "工作", color: "green"),
        RoutineCategory(key: "habit", label: "习惯", color: "blue"),
      ],
      dayTypes: base?.dayTypes ?? [],
      rules: base?.rules ?? []
    )
    routine.periods.append(period)
    self.routine = routine
    selectedPeriodID = period.id
    selectedDayTypeID = nil
    selectedModeID = nil
    phase = .loaded
    persist(routine.periods)
    editsPeriod = true
  }

  private func deletePeriod(_ id: String) {
    guard var routine else { return }
    routine.periods.removeAll { $0.id == id }
    self.routine = routine
    selectedPeriodID = nil
    persist(routine.periods)
  }

  private func persist(_ periods: [RoutinePeriod]) {
    Task {
      switch await state.saveRoutines(periods) {
      case .success(let saved):
        routine = saved
        state.toast = saved.problems.isEmpty ? "作息已保存" : "已保存，有 \(saved.problems.count) 处未存入"
      case .failure(let error):
        state.toast = error.message
        await load()
      }
    }
  }

  private func load() async {
    switch await state.loadRoutines() {
    case .success(let loaded):
      routine = loaded
      phase = .loaded
    case .failure(let error):
      if routine == nil { phase = .failed(error.message) }
    }
  }

  // MARK: Helpers

  static func color(_ category: RoutineCategory?) -> Color {
    category.flatMap { Palette.rowColor($0.color) } ?? Palette.ink3
  }

  static func short(_ date: String) -> String {
    let parts = date.split(separator: "-")
    guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return date }
    return "\(month)/\(day)"
  }

  static func newID(_ prefix: String) -> String {
    "\(prefix)-\(UUID().uuidString.prefix(6).lowercased())"
  }

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }
  static func date(_ string: String) -> Date? { dayFormatter.date(from: string) }
}

// MARK: - One block

private struct RoutineBlockView: View {
  let block: RoutineBlock
  let category: RoutineCategory?

  var body: some View {
    let color = RoutineScreen.color(category)
    let isSlot = block.kind == .slot
    HStack(alignment: .top, spacing: Metrics.xs) {
      Text(block.start).font(Typo.tabularCaption).foregroundStyle(isSlot ? color : Palette.ink3).frame(width: 38, alignment: .leading)
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: Metrics.xxs) {
          Text(block.title).font(Typo.label).foregroundStyle(Palette.ink).lineLimit(1)
          if let category, isSlot { Text(category.label).font(Typo.caption).foregroundStyle(color) }
          if block.floor == true { FloorTag(color: color) }
        }
        if let note = block.note, !note.isEmpty, block.minutes >= 40 {
          Text(note).font(Typo.caption).foregroundStyle(Palette.ink3).lineLimit(2)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Metrics.sm)
    .padding(.vertical, 3)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(isSlot ? color.opacity(0.14) : Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay {
      if block.floor == true {
        RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(color, lineWidth: 1.5)
      }
    }
    .contentShape(Rectangle())
    .help(block.kind == .slot ? "时段格子：\(category?.label ?? "未分类")的 to-do 放进这里" : "固定：这段时间不排 to-do")
  }
}

// MARK: - Editors

private struct BlockEditor: View {
  @State private var draft: RoutineBlock
  let categories: [RoutineCategory]
  let onSave: (RoutineBlock) -> Void
  let onDelete: () -> Void
  let onCancel: () -> Void

  private static let clocks: [String] = stride(from: 5 * 60, through: 24 * 60, by: 15).map { $0 == 24 * 60 ? "24:00" : DaySchedule.clock($0) }

  init(block: RoutineBlock, categories: [RoutineCategory], onSave: @escaping (RoutineBlock) -> Void, onDelete: @escaping () -> Void, onCancel: @escaping () -> Void) {
    _draft = State(initialValue: block)
    self.categories = categories
    self.onSave = onSave
    self.onDelete = onDelete
    self.onCancel = onCancel
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.sm) {
      TextField("这一块叫什么", text: $draft.title).textFieldStyle(.roundedBorder)
      TextField("备注（可留空）", text: Binding(get: { draft.note ?? "" }, set: { draft.note = $0.isEmpty ? nil : $0 }), axis: .vertical)
        .textFieldStyle(.roundedBorder).lineLimit(1...3)
      HStack {
        Picker("从", selection: $draft.start) { ForEach(Self.clocks, id: \.self) { Text($0).tag($0) } }
        Picker("到", selection: $draft.end) { ForEach(Self.clocks, id: \.self) { Text($0).tag($0) } }
      }
      Picker("", selection: $draft.kind) {
        Text("时段格子 · 放 to-do").tag(RoutineBlock.Kind.slot)
        Text("固定 · 不放 to-do").tag(RoutineBlock.Kind.fixed)
      }
      .pickerStyle(.segmented).labelsHidden()
      Picker("类别", selection: Binding(get: { draft.category ?? "" }, set: { draft.category = $0.isEmpty ? nil : $0 })) {
        Text("不分类").tag("")
        ForEach(categories) { Text($0.label).tag($0.key) }
      }
      if draft.kind == .slot {
        Toggle("保底：再忙也留着这段", isOn: Binding(get: { draft.floor ?? false }, set: { draft.floor = $0 ? true : nil }))
      }
      if draft.endMinute <= draft.startMinute {
        Text("结束要晚于开始").font(Typo.caption).foregroundStyle(Palette.warn)
      }
      HStack {
        Button(role: .destructive, action: onDelete) { Label("删掉", systemImage: "trash") }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
        Spacer()
        Button("取消", action: onCancel).buttonStyle(QuietButtonStyle(tone: .neutral)).keyboardShortcut(.cancelAction)
        Button("保存") {
          var saved = draft
          if saved.kind == .fixed { saved.floor = nil }
          onSave(saved)
        }
        .buttonStyle(MossButtonStyle(prominent: true))
        .keyboardShortcut(.defaultAction)
        .disabled(draft.endMinute <= draft.startMinute || draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding(Metrics.md)
    .frame(width: 340)
  }
}

private struct PeriodEditor: View {
  @State private var draft: RoutinePeriod
  @State private var confirmsDelete = false
  let onSave: (RoutinePeriod) -> Void
  let onCancel: () -> Void
  let onDelete: () -> Void

  init(period: RoutinePeriod, onSave: @escaping (RoutinePeriod) -> Void, onCancel: @escaping () -> Void, onDelete: @escaping () -> Void) {
    _draft = State(initialValue: period)
    self.onSave = onSave
    self.onCancel = onCancel
    self.onDelete = onDelete
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.sm) {
      Text("这段时期").font(Typo.heading)
      TextField("名字，比如「东京工作日」", text: $draft.name).textFieldStyle(.roundedBorder)
      TextField("一句话说明，比如「AG1 Residency · 西麻布」", text: Binding(get: { draft.subtitle ?? "" }, set: { draft.subtitle = $0.isEmpty ? nil : $0 }))
        .textFieldStyle(.roundedBorder)
      HStack {
        DatePicker("从", selection: dateBinding(\.from), displayedComponents: .date)
        DatePicker("到", selection: dateBinding(\.to), displayedComponents: .date)
      }
      HStack {
        TextField("几点起 07:00", text: Binding(get: { draft.wake ?? "" }, set: { draft.wake = $0.isEmpty ? nil : $0 })).textFieldStyle(.roundedBorder)
        TextField("几点睡 23:00", text: Binding(get: { draft.sleep ?? "" }, set: { draft.sleep = $0.isEmpty ? nil : $0 })).textFieldStyle(.roundedBorder)
      }
      TextField("这段时期的总体安排（可留空）", text: Binding(get: { draft.summary ?? "" }, set: { draft.summary = $0.isEmpty ? nil : $0 }), axis: .vertical)
        .textFieldStyle(.roundedBorder).lineLimit(2...5)
      HStack {
        Button("删掉这段时期", role: .destructive) { confirmsDelete = true }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
        Spacer()
        Button("取消", action: onCancel).buttonStyle(QuietButtonStyle(tone: .neutral)).keyboardShortcut(.cancelAction)
        Button("保存") { onSave(draft) }
          .buttonStyle(MossButtonStyle(prominent: true))
          .keyboardShortcut(.defaultAction)
          .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty || draft.from > draft.to)
      }
    }
    .padding(Metrics.lg)
    .frame(width: 460)
    .confirmationDialog("删掉「\(draft.name)」？", isPresented: $confirmsDelete) {
      Button("删掉", role: .destructive, action: onDelete)
      Button("取消", role: .cancel) {}
    } message: {
      Text("日型、模式和规则会一起删除。今天的计划改用设置里的默认作息。")
    }
  }

  private func dateBinding(_ key: WritableKeyPath<RoutinePeriod, String>) -> Binding<Date> {
    Binding(
      get: { RoutineScreen.date(draft[keyPath: key]) ?? Date() },
      set: { draft[keyPath: key] = RoutineScreen.dayString($0) }
    )
  }
}

private struct WeekdayPicker: View {
  @State var selected: [String]
  let taken: [String]
  let onChange: ([String]) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xs) {
      Text("这个日型是星期几").font(Typo.caption).foregroundStyle(Palette.ink3)
      HStack(spacing: 4) {
        ForEach(RoutineWeekday.codes, id: \.self) { code in
          let on = selected.contains(code)
          Button(RoutineWeekday.label(code)) {
            selected = on ? selected.filter { $0 != code } : RoutineWeekday.codes.filter { selected.contains($0) || $0 == code }
            if !selected.isEmpty { onChange(selected) }
          }
          .buttonStyle(QuietButtonStyle(tone: on ? .accent : .neutral))
          .help(taken.contains(code) && !on ? "另一个日型也用了这天，只有一个会生效" : "")
        }
      }
    }
    .padding(Metrics.md)
  }
}

private struct RenameField: View {
  @State var text: String
  let onDone: (String) -> Void

  var body: some View {
    HStack {
      TextField("名字", text: $text).textFieldStyle(.roundedBorder).frame(width: 180).onSubmit { onDone(text) }
      Button("好") { onDone(text) }.buttonStyle(MossButtonStyle(prominent: true))
    }
    .padding(Metrics.md)
  }
}

private struct CategoriesPanel: View {
  let period: RoutinePeriod
  let onChange: ([RoutineCategory]) -> Void
  @State private var newLabel = ""

  var body: some View {
    Panel("类别") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        ForEach(period.categories) { category in
          HStack(spacing: Metrics.xs) {
            Menu {
              ForEach(Palette.rowColorNames, id: \.self) { name in
                Button(name) { update(category.key) { $0.color = name } }
              }
            } label: {
              Circle().fill(RoutineScreen.color(category)).frame(width: 12, height: 12)
            }
            .menuStyle(.borderlessButton).fixedSize()
            Text(category.label).font(Typo.body).foregroundStyle(Palette.ink)
            Spacer()
            Toggle("习惯", isOn: Binding(get: { category.habit ?? false }, set: { on in update(category.key) { $0.habit = on ? true : nil } }))
              .toggleStyle(.checkbox)
              .font(Typo.caption)
              .help("习惯类的每个格子在「今天」显示为一条 to-do")
            Button { onChange(period.categories.filter { $0.key != category.key }) } label: { Image(systemName: "minus.circle") }
              .buttonStyle(.plain).foregroundStyle(Palette.ink3)
              .help("删掉这个类别；用了它的时间块会变成不分类")
          }
        }
        HStack {
          TextField("加一个类别", text: $newLabel).textFieldStyle(.roundedBorder).onSubmit(add)
          Button("加", action: add).buttonStyle(QuietButtonStyle(tone: .neutral)).disabled(newLabel.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
    } actions: { EmptyView() }
  }

  private func update(_ key: String, _ change: (inout RoutineCategory) -> Void) {
    onChange(period.categories.map { category in
      var copy = category
      if copy.key == key { change(&copy) }
      return copy
    })
  }

  private func add() {
    let label = newLabel.trimmingCharacters(in: .whitespaces)
    guard !label.isEmpty else { return }
    let color = Palette.rowColorNames[period.categories.count % Palette.rowColorNames.count]
    onChange(period.categories + [RoutineCategory(key: RoutineScreen.newID("c"), label: label, color: color)])
    newLabel = ""
  }
}

private struct RulesPanel: View {
  let rules: [String]
  let onChange: ([String]) -> Void
  @State private var newRule = ""

  var body: some View {
    Panel("置换规则") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        ForEach(Array(rules.enumerated()), id: \.offset) { index, rule in
          HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
            Text("\(index + 1)").font(Typo.tabularCaption).foregroundStyle(Palette.ink3)
            Text(rule).font(Typo.body).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button { onChange(rules.enumerated().filter { $0.offset != index }.map(\.element)) } label: { Image(systemName: "minus.circle") }
              .buttonStyle(.plain).foregroundStyle(Palette.ink3)
          }
        }
        TextField("加一条规则，回车保存", text: $newRule, axis: .vertical)
          .textFieldStyle(.roundedBorder).lineLimit(1...3)
          .onSubmit {
            let rule = newRule.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rule.isEmpty else { return }
            onChange(rules + [rule])
            newRule = ""
          }
      }
    } actions: { EmptyView() }
  }
}

#Preview("作息") {
  RoutineScreen().environment(AppState.previewOwner())
}

/// 保底: filled, so a floor reads as a commitment, not as a maybe.
struct FloorTag: View {
  let color: Color

  var body: some View {
    Text("保底")
      .font(Typo.caption.weight(.semibold))
      .foregroundStyle(Palette.page)
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .background(color, in: Capsule())
  }
}
