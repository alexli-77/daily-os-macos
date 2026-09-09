import Foundation
import Observation

/// The single place the UI reads from and writes to.
///
/// The whole shell talks to this object and to nothing else — no screen reaches
/// for `MockData` directly, no view performs I/O. That is what makes this
/// repository consumable: the private release repository keeps every screen and
/// swaps this one type for a version backed by the local daily-os service.
/// See README §"How the private repo consumes this".
///
/// Not `final`: the mutations below are the seams a live implementation
/// overrides. They are deliberately small and named after the user's intent
/// (`capture`, `acceptDraft`, `toggleTodo`) rather than after the field they
/// touch, so that an override reads as "what happens when the user does this"
/// rather than as a setter.
@Observable
@MainActor
open class AppState {
  // Data
  public var service: ServiceStatus
  public var account: Account
  public var members: [TeamMember]
  public var cycles: [Cycle]
  public var partnerCycles: [Cycle]
  public var plan: [TodoItem]
  public var todos: [TodoItem]
  public var okrFiles: [OkrFile]
  public var runs: [WorkflowRun]
  public var artifacts: [Artifact]
  public var schedules: [ScheduleEntry]
  public var threads: [ChatThread]
  public var sources: [SourceConnection]
  /// Free-form conversation is a service-side config flag; the client reflects
  /// it rather than discovering it by being refused. See `AgentMode`.
  public var agentMode: AgentMode

  // Selection
  public var section: AppSection = .today
  public var selectedCycleID: Cycle.ID?
  public var viewingMemberID: TeamMember.ID
  public var selectedRunID: WorkflowRun.ID?
  public var selectedArtifactID: Artifact.ID?
  public var selectedThreadID: ChatThread.ID?
  public var composerText: String = ""
  public var quickCaptureText: String = ""

  // Transient
  public var toast: String?

  /// Which sections read real data.
  ///
  /// Defaults to everything, because the fixture backs every screen. A live
  /// store narrows it, and the sidebar marks the rest. Half-wired screens that
  /// silently show demo content are worse than unwired ones: the fixture is
  /// plausible enough to be mistaken for your own data, and the mistake is only
  /// discovered when you act on it.
  public var wiredSections: Set<AppSection> = Set(AppSection.allCases)

  /// Seeds every collection from `MockData`. A subclass calls `super.init()`
  /// and then replaces the collections with whatever the service returned, so
  /// the first frame is populated rather than empty.
  public init() {
    service = MockData.service
    account = MockData.account
    members = MockData.members
    cycles = MockData.cycles
    partnerCycles = MockData.partnerCycles
    plan = MockData.plan
    todos = MockData.todos
    okrFiles = MockData.okrFiles
    runs = MockData.runs
    artifacts = MockData.artifacts
    schedules = MockData.schedules
    threads = MockData.threads
    sources = MockData.sources
    agentMode = MockData.agentMode

    viewingMemberID = MockData.account.id
    selectedCycleID = MockData.cycles.first?.id
    selectedRunID = MockData.runs.first?.id
    selectedArtifactID = MockData.artifacts.first?.id
    selectedThreadID = MockData.threads.first?.id
  }

  // MARK: Derived

  public var isViewingSelf: Bool { viewingMemberID == account.id }

  public var viewingMember: TeamMember? {
    members.first { $0.id == viewingMemberID }
  }

  /// The cycles for whoever is currently being viewed. A teammate's cycles come
  /// from the sync cache and are never editable — the read-only guarantee is
  /// enforced by the service and the database, and mirrored here so the UI
  /// cannot even offer the control.
  public var visibleCycles: [Cycle] {
    isViewingSelf ? cycles : partnerCycles
  }

  public var selectedCycle: Cycle? {
    visibleCycles.first { $0.id == selectedCycleID } ?? visibleCycles.first
  }

  public var currentCycle: Cycle? { cycles.first }

  public var openTodos: [TodoItem] { todos.filter { $0.state == .open } }
  public var doneTodos: [TodoItem] { todos.filter { $0.state == .done } }
  public var deferredTodos: [TodoItem] { todos.filter { $0.state == .deferred } }

  public var activeRuns: [WorkflowRun] { runs.filter { $0.state == .running } }
  public var recentRuns: [WorkflowRun] { runs.filter { $0.state != .running } }

  public var selectedRun: WorkflowRun? {
    runs.first { $0.id == selectedRunID } ?? runs.first
  }

  public var selectedArtifact: Artifact? {
    artifacts.first { $0.id == selectedArtifactID } ?? artifacts.first
  }

  public var selectedThread: ChatThread? {
    threads.first { $0.id == selectedThreadID } ?? threads.first
  }

  /// Today's token spend. Still derived — the Runs screen shows it. It left the
  /// Today screen because cost is a question about the machine, and Today is a
  /// question about the day.
  public var todayTokens: Int { runs.reduce(0) { $0 + $1.totalTokens } }
  public var todayCost: Double { runs.reduce(0) { $0 + $1.costUSD } }

  /// What the Today header reports.
  ///
  /// Counts the plan, not the inbox: the plan is what you said you would do
  /// today, and progress against a list you keep adding to is not progress.
  /// Captures land in 我的待办 and are counted there.
  public var dayProgress: DayProgress {
    let target = plan.count
    let done = plan.filter { $0.state == .done }.count
    let planned = plan.reduce(0) { $0 + ($1.estimatedMinutes ?? 0) }
    let remaining = plan
      .filter { $0.state == .open }
      .reduce(0) { $0 + ($1.estimatedMinutes ?? 0) }
    return DayProgress(done: done, target: target, plannedMinutes: planned, remainingMinutes: remaining)
  }

  /// Drives the sidebar badge and the menu bar dot.
  public var pendingDraftCount: Int {
    cycles.filter(\.hasPendingDraft).count
  }

  // MARK: Mutations
  //
  // Local-only in the shell. Each one is the seam where the private repo calls
  // the service and then reconciles — hence they are all small and named after
  // the user's intent rather than after the field they touch.

  open func setTodo(_ id: TodoItem.ID, to state: TodoState) {
    guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
    todos[index].state = state
    toast = state == .done ? "已完成" : (state == .deferred ? "已顺延" : "已恢复")
  }

  open func toggleTodo(_ id: TodoItem.ID) {
    guard let item = todos.first(where: { $0.id == id }) else { return }
    setTodo(id, to: item.state == .done ? .open : .done)
  }

  open func capture(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    todos.insert(
      TodoItem(id: "cap_\(UUID().uuidString.prefix(8))", text: trimmed, kind: .priority),
      at: 0
    )
    quickCaptureText = ""
    toast = "已记到收件箱"
  }

  open func updateSection(cycleID: Cycle.ID, kind: CycleSectionKind, body: String) {
    guard isViewingSelf,
          let cycleIndex = cycles.firstIndex(where: { $0.id == cycleID }),
          let sectionIndex = cycles[cycleIndex].sections.firstIndex(where: { $0.kind == kind })
    else { return }
    cycles[cycleIndex].sections[sectionIndex].body = body
    cycles[cycleIndex].sections[sectionIndex].source = .user
    cycles[cycleIndex].sections[sectionIndex].updatedAt = .now
    cycles[cycleIndex].updatedAt = .now
    toast = "已保存到 \(cycles[cycleIndex].relativePath)"
  }

  /// Take the planner's newer draft. The old body is gone from the UI but not
  /// from the file — the service keeps it as a prior version.
  open func acceptDraft(cycleID: Cycle.ID, kind: CycleSectionKind) {
    guard let cycleIndex = cycles.firstIndex(where: { $0.id == cycleID }),
          let sectionIndex = cycles[cycleIndex].sections.firstIndex(where: { $0.kind == kind }),
          let draft = cycles[cycleIndex].sections[sectionIndex].pendingDraft
    else { return }
    cycles[cycleIndex].sections[sectionIndex].body = draft
    cycles[cycleIndex].sections[sectionIndex].pendingDraft = nil
    cycles[cycleIndex].sections[sectionIndex].source = .planner
    cycles[cycleIndex].sections[sectionIndex].updatedAt = .now
    toast = "已合入草稿"
  }

  open func discardDraft(cycleID: Cycle.ID, kind: CycleSectionKind) {
    guard let cycleIndex = cycles.firstIndex(where: { $0.id == cycleID }),
          let sectionIndex = cycles[cycleIndex].sections.firstIndex(where: { $0.kind == kind })
    else { return }
    cycles[cycleIndex].sections[sectionIndex].pendingDraft = nil
    toast = "已丢弃草稿"
  }

  open func toggleSchedule(_ id: ScheduleEntry.ID) {
    guard let index = schedules.firstIndex(where: { $0.id == id }) else { return }
    schedules[index].enabled.toggle()
    toast = schedules[index].enabled ? "已启用" : "已停用"
  }

  open func send() {
    let trimmed = composerText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty,
          let threadIndex = threads.firstIndex(where: { $0.id == selectedThread?.id })
    else { return }
    threads[threadIndex].messages.append(
      ChatMessage(id: "m_\(UUID().uuidString.prefix(8))", role: .user, text: trimmed, sentAt: .now)
    )
    threads[threadIndex].updatedAt = .now
    composerText = ""
    // The shell stops here. The private repo opens an SSE stream and appends an
    // assistant message with `isStreaming = true`.
    threads[threadIndex].messages.append(
      ChatMessage(
        id: "m_\(UUID().uuidString.prefix(8))",
        role: .assistant,
        text: "（这是 UI 骨架，没有接后端。真实实现在私有仓库里接 /api/chat 的 SSE 流。）",
        sentAt: .now
      )
    )
  }

  /// Delete a conversation.
  ///
  /// Keeps a selection: dropping the selected thread and leaving nothing
  /// selected shows an empty pane that reads like a failure rather than like a
  /// completed delete.
  open func deleteThread(_ id: ChatThread.ID) {
    guard let index = threads.firstIndex(where: { $0.id == id }) else { return }
    threads.remove(at: index)
    if selectedThreadID == id {
      selectedThreadID = threads.indices.contains(index) ? threads[index].id : threads.last?.id
    }
    toast = "已删除对话"
  }

  /// Click one of the three dots on a 要务 item.
  ///
  /// Rewrites the single source line in the section's markdown and leaves the
  /// rest byte-identical — the file is the truth, and a status click must not
  /// reformat someone's hand-written list as a side effect. Passing the same
  /// status that is already set clears it, matching the web console.
  open func setPriorityStatus(
    cycleID: Cycle.ID,
    line: Int,
    to status: CycleTaskStatus?
  ) {
    guard isViewingSelf,
          let cycleIndex = cycles.firstIndex(where: { $0.id == cycleID }),
          let sectionIndex = cycles[cycleIndex].sections.firstIndex(where: { $0.kind == .priorities })
    else { return }
    let section = cycles[cycleIndex].sections[sectionIndex]
    cycles[cycleIndex].sections[sectionIndex].body = PrioritiesDocument.markdown(
      section.body,
      settingLine: line,
      to: status
    )
    cycles[cycleIndex].sections[sectionIndex].source = .user
    cycles[cycleIndex].sections[sectionIndex].updatedAt = .now
    cycles[cycleIndex].sections[sectionIndex].isTemplate = false
    cycles[cycleIndex].updatedAt = .now
  }

  open func newThread() {
    let thread = ChatThread(id: "th_\(UUID().uuidString.prefix(8))", title: "新对话", updatedAt: .now, messages: [])
    threads.insert(thread, at: 0)
    selectedThreadID = thread.id
  }
}
