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
  public var teamSync: TeamSyncState?
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

  /// Set when the newest plan is not today's — today's has not run yet.
  ///
  /// Surfaced rather than hidden: yesterday's plan is still the most recent
  /// plan, and quietly presenting it as today's is how someone works a day
  /// behind without noticing.
  public var planStaleDate: String?
  /// False when no `daily_plan` has ever run, which wants a different empty
  /// state from "ran and produced nothing".
  public var hasPlan = true

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
    teamSync = MockData.teamSync
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
    selectedCycleID = (MockData.cycles.first { $0.contains(.now) } ?? MockData.cycles.first)?.id
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

  /// The cycle today actually falls inside.
  ///
  /// Not `cycles.first`. The list is newest-first, so "first" is the right
  /// answer only until someone creates the next cycle a few days early or a gap
  /// opens between two of them — both of which are normal, which is exactly
  /// what makes the wrong answer hard to notice. Falls back to the newest so
  /// the Today subtitle still says something during a gap.
  public var currentCycle: Cycle? {
    cycles.first { $0.contains(.now) } ?? cycles.first
  }

  /// The cycle list, split into 本期 / 计划中 / 往期 for whoever is being viewed.
  public var visibleCycleGroups: [CycleGroup] { CycleGroup.group(visibleCycles) }

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

  /// Rewrite one inbox row's text.
  ///
  /// A capture is one sentence typed in a hurry, so this is the second most
  /// likely thing to want after ticking one off — and until now the only way to
  /// fix a typo was to delete the row and retype it, which loses its id and
  /// therefore everything the scorer had learned about it.
  open func renameTodo(_ id: TodoItem.ID, to text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, let index = todos.firstIndex(where: { $0.id == id }) else { return }
    todos[index].text = trimmed
    toast = "已改好"
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

  // MARK: Service actions

  /// The result of a service action a screen invoked.
  ///
  /// `unsupported` is the case that matters: the service genuinely cannot do
  /// the thing, and the screen is expected to say so rather than leave a button
  /// that appears to work. That was the complaint this whole pass came from.
  public enum ActionOutcome: Sendable, Equatable {
    case ok(String?)
    case failed(String)
    case unsupported(String)
  }

  /// The last failure from a service action, for a screen to show inline.
  public var lastActionError: String?

  /// Record feedback against one plan row: `complete` / `defer` / `update`.
  ///
  /// `rank` is part of the ledger key, not decoration — the feedback exists to
  /// tell the scorer how a ranked list performed, and an event without the rank
  /// it was acted on at is half a signal.
  open func planFeedback(
    candidateID: String,
    rank: Int,
    event: String,
    note: String?
  ) async -> ActionOutcome {
    .unsupported("这一版没有连接到服务。")
  }

  /// Correct one plan row's time estimate.
  ///
  /// Separate from `planFeedback` even though it travels on the same endpoint,
  /// because it is a different user intent: the other three resolve a row, this
  /// one says the machine guessed wrong about the work. The shell applies it
  /// locally so the bar redraws; a live store also records it.
  ///
  /// `nil` clears the estimate back to "unknown", which has to stay reachable —
  /// otherwise a mis-tap turns an honest blank into a wrong number that can
  /// never be taken back.
  open func setPlanEstimate(candidateID: String, rank: Int, minutes: Int?) async -> ActionOutcome {
    guard let index = plan.firstIndex(where: { $0.id == candidateID }) else {
      return .failed("这条计划已经不在了。")
    }
    plan[index].estimatedMinutes = minutes
    return .ok(nil)
  }

  // MARK: Seams added for the parallel build
  //
  // Declared here, in one place, before the work was split across agents. Each
  // is the shell's default — refuse, and say so — and each is overridden in
  // `LiveAppState`. They live in the class body rather than in per-feature
  // extensions because Swift cannot override a method declared in an extension,
  // and `open` is the whole point of these.

  /// Today's weather, or nil when it has never been fetched.
  public var weather: WeatherSnapshot?

  /// Who is signed in to the console, as opposed to which team member this
  /// machine syncs as. Nil when nobody is.
  public var session: ConsoleSession?

  /// Fetch weather for the configured place. Cheap to call — the live version
  /// only goes to the network when the cache is stale.
  open func refreshWeather(force: Bool = false) async {}

  /// Ask the service to run `daily_plan` now.
  open func generatePlan() async -> ActionOutcome {
    .unsupported("这一版没有连接到服务。")
  }

  /// Create the next cycle. Every field is optional; the service fills the rest
  /// from the previous cycle.
  open func createCycle(_ request: NewCycleRequest) async -> ActionOutcome {
    .unsupported("这一版没有连接到服务。")
  }

  /// Generate a section the cycle file does not have yet (retro / review).
  open func generateCycleSection(cycleID: Cycle.ID, kind: CycleSectionKind) async -> ActionOutcome {
    .unsupported("这一版没有连接到服务。")
  }

  /// Sign in to the console account store.
  open func signIn(username: String, password: String) async -> ActionOutcome {
    .unsupported("这一版没有连接到服务。")
  }

  /// End the console session on this machine.
  open func signOut() async -> ActionOutcome {
    .unsupported("这一版没有连接到服务。")
  }

  open func newThread() {
    let thread = ChatThread(id: "th_\(UUID().uuidString.prefix(8))", title: "新对话", updatedAt: .now, messages: [])
    threads.insert(thread, at: 0)
    selectedThreadID = thread.id
  }
}
