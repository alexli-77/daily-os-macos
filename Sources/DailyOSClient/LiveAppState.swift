import Foundation
import Observation
import DailyOSCore

/// `AppState` backed by the local daily-os service.
///
/// The whole point of the shell's design lands here: no screen changes, because
/// no screen ever talked to anything but `AppState`. What this class overrides
/// is the handful of intent-named mutations, each of which now writes through
/// to the service and reconciles.
///
/// Writes are optimistic. The alternative — spinner, await, then repaint — makes
/// ticking a checkbox feel like submitting a form, and this is a local service
/// on the same machine where the round trip is a few milliseconds. When a write
/// does fail, the toast says so and `reload()` puts the truth back; nothing is
/// left showing a change that did not happen.
@Observable
@MainActor
public final class LiveAppState: AppState {
  public let connection: ServiceConnection
  public private(set) var lastError: String?
  public private(set) var isLoading = false

  private var client: DailyOSClient? { connection.client }

  public init(connection: ServiceConnection) {
    self.connection = connection
    super.init()
    // Only these three read live data. The rest keep the fixture and are marked
    // in the sidebar — see `wiredSections`.
    wiredSections = [.today, .cycles, .okr, .artifacts, .settings]
  }

  // MARK: - Loading

  /// Empty every collection.
  ///
  /// Called when there is no service to read from. `AppState.init` seeds the
  /// fixture so the first frame is populated rather than blank, which is right
  /// while connecting and dangerous once you can reach the app *without* being
  /// connected: demo cycles and demo todos are plausible enough to be mistaken
  /// for your own, and the mistake is only discovered after you act on one.
  /// Every screen's empty state is the honest rendering of "no service".
  public func clearForDisconnected() {
    cycles = []
    partnerCycles = []
    plan = []
    todos = []
    okrFiles = []
    runs = []
    artifacts = []
    schedules = []
    threads = []
    sources = []
    members = []
    teamSync = nil
    hasPlan = false
    planStaleDate = nil
    selectedCycleID = nil
    selectedRunID = nil
    selectedArtifactID = nil
    selectedThreadID = nil
    service = ServiceStatus(state: .stopped, endpoint: "", uptime: .zero, note: nil)
    // The fixture's identity leaks too. Without this the sidebar footer sat
    // there reading "demo" next to a stopped service — a name nobody has, on
    // the one line of the window that is supposed to say who you are.
    account = Account(id: "", displayName: "未连接", email: "", role: .owner, avatarSeed: "")
    viewingMemberID = ""
    // Computed here, at the one moment the app knows it is disconnected, and
    // from local filesystem reads only — the network is the thing that just
    // failed, so asking it again would be the wrong question.
    serviceDiagnosis = .evaluate(root: connection.repoRoot)
    // Nothing is wired, so no screen claims to be showing real data.
    wiredSections = []
  }

  public func reload() async {
    guard let client else {
      clearForDisconnected()
      return
    }
    isLoading = true
    defer { isLoading = false }

    if !connection.state.isConnected { await connection.probe() }
    guard connection.state.isConnected else {
      clearForDisconnected()
      return
    }
    serviceDiagnosis = .reachable

    // Who is *using* the app, restored from this machine's own record. Distinct
    // from the identity the cycle read sets below: that one is the team member
    // these files belong to (`leon`), and putting it on the footer as if it were
    // the logged-in account is the confusion `ConsoleSession` was written to
    // end. Restored here rather than in `init` because a remembered account only
    // means anything once there is a service behind it.
    if session == nil { session = ConsoleSessionStore.restore() }

    // Each read is independent and a failure in one must not blank the others:
    // a broken OKR file should not cost you the cycle you were reading.
    await load("周期") {
      let result = try await client.cycles()
      self.cycles = result.mine
      self.partnerCycles = result.teammates
      self.teamSync = result.sync
      if let me = result.members.first(where: \.isSelf) {
        self.members = result.members
        // `account.id` has to move with `viewingMemberID`, because
        // `isViewingSelf` compares the two. Setting only the latter left the
        // app permanently in "looking at a teammate" mode against an empty
        // teammate list — every cycle decoded correctly and the screen showed
        // "还没有周期". The client-level check never caught it: it called
        // `cycles()` directly and never went through the store.
        self.account = Account(
          id: me.id,
          displayName: me.displayName.isEmpty ? self.account.displayName : me.displayName,
          email: self.account.email,
          role: .owner,
          avatarSeed: me.avatarSeed.isEmpty ? self.account.avatarSeed : me.avatarSeed
        )
        self.viewingMemberID = me.id
      } else {
        // Sync is off, so the service reports no members and no `team.self`.
        // Everything on disk is still yours; say so with one member rather than
        // leaving the identity pointing at fixture data.
        self.members = [
          TeamMember(
            id: self.account.id,
            displayName: self.account.displayName,
            avatarSeed: self.account.avatarSeed,
            isSelf: true,
            lastSyncedAt: nil
          )
        ]
        self.viewingMemberID = self.account.id
      }
      self.cycles = self.cycles.map { cycle in
        var cycle = cycle
        cycle.ownerId = self.account.id
        return cycle
      }
      if self.selectedCycleID == nil || !self.visibleCycles.contains(where: { $0.id == self.selectedCycleID }) {
        // The cycle containing today, not the newest one. Those differ whenever
        // the next cycle has been created early, and opening the app on the one
        // you are not in is a good way to plan into the wrong file.
        self.selectedCycleID = (self.visibleCycles.first { $0.contains(.now) } ?? self.visibleCycles.first)?.id
      }
    }

    await load("待办") {
      let inbox = try await client.todoInbox()
      // `recent` is *all* non-deleted rows, not just the closed ones, so it
      // already contains everything in `open`. Concatenating the two showed
      // every unfinished todo twice — which is what "随手记一条，出现两条"
      // actually was, and it had nothing to do with the capture write.
      // Union rather than `recent` alone: `recent` is capped at 40, and an open
      // row older than that would otherwise vanish.
      var seen = Set<TodoItem.ID>()
      self.todos = (inbox.open + inbox.recent).filter { seen.insert($0.id).inserted }
    }

    await load("今日计划") {
      // The plan and the inbox are different lists. Showing the inbox here was
      // wrong in a way that looked right: plausible rows, but not the ones the
      // web shows and not the ones the planner decided.
      let plan = try await client.todayPlan()
      self.plan = plan.items
      self.planStaleDate = plan.staleDate
      self.hasPlan = plan.hasPlan
    }

    await load("产物") {
      self.artifacts = try await client.artifacts()
      if self.selectedArtifactID == nil || !self.artifacts.contains(where: { $0.id == self.selectedArtifactID }) {
        self.selectedArtifactID = self.artifacts.first?.id
      }
    }

    await load("OKR") {
      self.okrFiles = try await client.okrFiles()
    }

    await load("服务状态") {
      self.service = try await client.serviceStatus()
    }
  }

  /// Run one read, attributing any failure to the thing that failed.
  ///
  /// "周期读取失败：…" is actionable; a bare "加载失败" from a screen with four
  /// independent sources is not.
  private func load(_ what: String, _ body: () async throws -> Void) async {
    do {
      try await body()
    } catch {
      let reason = (error as? ClientError)?.errorDescription ?? error.localizedDescription
      lastError = "\(what)读取失败：\(reason)"
    }
  }

  // MARK: - Writes

  public override func updateSection(cycleID: Cycle.ID, kind: CycleSectionKind, body: String) {
    super.updateSection(cycleID: cycleID, kind: kind, body: body)
    write("保存") { try await $0.saveCycleSection(cycleID: cycleID, kind: kind, body: body) }
  }

  public override func setPriorityStatus(cycleID: Cycle.ID, line: Int, to status: CycleTaskStatus?) {
    super.setPriorityStatus(cycleID: cycleID, line: line, to: status)
    // Send what the local edit produced rather than recomputing it, so the file
    // on disk and the list on screen can never disagree about what a click meant.
    guard let section = cycles.first(where: { $0.id == cycleID })?.section(.priorities) else { return }
    let body = section.body
    write("标记") { try await $0.saveCycleSection(cycleID: cycleID, kind: .priorities, body: body) }
  }

  /// Capture is the one write that is *not* optimistic.
  ///
  /// The service parses the text with its own command grammar — "提醒我 …"
  /// becomes a reminder, not a todo named "提醒我 …" — so the row it creates is
  /// not the row this app would have guessed. Inserting a local copy and then
  /// reloading produced two rows, one real and one wrong, which is exactly what
  /// happened. Send it, then take what comes back.
  public override func capture(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    quickCaptureText = ""
    write("记录", reloadAfter: true) { try await $0.capture(trimmed) }
  }

  public override func setTodo(_ id: TodoItem.ID, to state: TodoState) {
    super.setTodo(id, to: state)
    write("更新待办") { try await $0.setTodo(id: id, to: state) }
  }

  public override func renameTodo(_ id: TodoItem.ID, to text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    super.renameTodo(id, to: trimmed)
    write("改待办") { try await $0.renameTodo(id: id, text: trimmed) }
  }

  public override func planFeedback(
    candidateID: String,
    rank: Int,
    event: String,
    note: String?
  ) async -> ActionOutcome {
    guard let client else { return .failed("没有连接到服务。") }
    // Optimistic, like the other writes: a plan row is ticked far more often
    // than the network fails, and waiting on a local round trip to redraw a
    // checkbox makes it feel like a form submission.
    if let index = plan.firstIndex(where: { $0.id == candidateID }) {
      switch event {
      case "complete": plan[index].state = .done
      case "defer": plan[index].state = .deferred
      case "reopen": plan[index].state = .open
      default: break
      }
    }
    do {
      try await client.recordPlanFeedback(candidateID: candidateID, rank: rank, event: event, note: note)
      return .ok(nil)
    } catch {
      let reason = (error as? ClientError)?.errorDescription ?? error.localizedDescription
      lastActionError = reason
      await reload()
      return .failed(reason)
    }
  }

  /// Send a corrected estimate as an `update` event carrying minutes.
  ///
  /// Not optimistic-and-forget like the ticks: the whole point of editing a
  /// number is that you then read it, so a silent failure would leave the bar
  /// showing a figure the service never accepted.
  public override func setPlanEstimate(candidateID: String, rank: Int, minutes: Int?) async -> ActionOutcome {
    guard let client else { return .failed("没有连接到服务。") }
    let outcome = await super.setPlanEstimate(candidateID: candidateID, rank: rank, minutes: minutes)
    guard case .ok = outcome else { return outcome }
    do {
      // Zero is the wire's way of saying "no estimate": the service drops any
      // non-positive value, so the ledger stops carrying an override and the
      // model's own guess — or nothing — takes over again on the next read.
      try await client.recordPlanFeedback(
        candidateID: candidateID,
        rank: rank,
        event: "update",
        note: nil,
        minutes: minutes ?? 0
      )
      return .ok(minutes.map { "已改为 \(Fmt.minutes($0))" } ?? "已清掉估时")
    } catch {
      let reason = (error as? ClientError)?.errorDescription ?? error.localizedDescription
      lastActionError = reason
      await reload()
      return .failed(reason)
    }
  }

  // MARK: - Console account

  /// Sign in to the console account store.
  ///
  /// Not optimistic, unlike every other write here: the answer *is* the result.
  /// Nothing is worth showing until the service has said which account this is,
  /// and a wrong password is common enough that guessing "it worked" and taking
  /// it back a moment later would be the normal case rather than the rare one.
  public override func signIn(username: String, password: String) async -> ActionOutcome {
    guard let client else { return .failed("没有连接到服务，登录没有地方可去。") }
    do {
      let session = try await client.signIn(username: username, password: password)
      self.session = session
      ConsoleSessionStore.remember(session)
      return .ok(nil)
    } catch {
      let reason = (error as? ClientError)?.errorDescription ?? error.localizedDescription
      return .failed(reason)
    }
  }

  /// Register, and land signed in.
  ///
  /// Identical to `signIn` once the service has answered — deliberately, since
  /// "registered but not logged in" is a state nobody wants and the service does
  /// not produce one.
  public override func register(username: String, email: String, password: String) async -> ActionOutcome {
    guard let client else { return .failed("没有连接到服务，注册没有地方可去。") }
    do {
      let session = try await client.register(username: username, email: email, password: password)
      self.session = session
      ConsoleSessionStore.remember(session)
      return .ok(session.role == .owner || session.role == .admin ? nil : "注册成功。这台机器上已经有所有者了，所以这个账号是成员——配置和密钥看不到。")
    } catch {
      let reason = (error as? ClientError)?.errorDescription ?? error.localizedDescription
      return .failed(reason)
    }
  }

  /// End the console session on this machine.
  ///
  /// The local record goes first and unconditionally, because it is the thing
  /// that decides what the app shows; a service that fails to answer must not
  /// leave someone stuck signed in as a name they just asked to drop. The call
  /// to the service is what stops the session row from outliving this — it is
  /// reported when it fails and nothing is rolled back, because nothing about
  /// the local state was wrong.
  ///
  /// Worth being exact about what this is: it changes who the app says is using
  /// it. It does not lock anything. The runtime token stays on disk and the
  /// service stays reachable from this Mac account either way.
  public override func signOut() async -> ActionOutcome {
    session = nil
    ConsoleSessionStore.forget()
    guard let client else { return .ok(nil) }
    do {
      try await client.signOut()
      return .ok(nil)
    } catch {
      let reason = (error as? ClientError)?.errorDescription ?? error.localizedDescription
      return .failed("已经退出，但服务那边的会话没能销毁：\(reason)")
    }
  }

  // MARK: - Today's plan, on demand

  /// The poll that waits for the plan a rerun will eventually write. Held so a
  /// second press replaces it rather than adding a second one.
  private var planWatcher: Task<Void, Never>?

  /// Ask the service to run `daily_plan` now.
  ///
  /// Returns when the run has *started*, which is all `/api/runs/rerun` ever
  /// reports: it registers the run and answers immediately rather than holding
  /// the socket open for a workflow that takes minutes. So this cannot say "计划
  /// 好了" and must not be presented as if it could — the caller's job is to say
  /// what was started, and the two facts a person needs before pressing it are
  /// that it costs model budget and that it also sends them a Feishu message.
  public override func generatePlan() async -> ActionOutcome {
    guard let client else { return .failed("没有连接到服务。") }
    do {
      try await client.rerunWorkflow("daily_plan")
      watchForPlan()
      return .ok("已让 daily_plan 跑起来了，跑完会发一条飞书")
    } catch {
      let reason = (error as? ClientError)?.errorDescription ?? error.localizedDescription
      lastActionError = reason
      return .failed(reason)
    }
  }

  /// Re-read until today's plan shows up.
  ///
  /// Without this the button has no visible result: the run writes the plan
  /// minutes after the POST returns, and nothing else in this app asks again
  /// until it is relaunched — which is the "按了没反应" that the old empty
  /// state was at least honest about. Polling is the shape the service leaves:
  /// it offers no completion event to subscribe to. So it is bounded at ten
  /// minutes, spaced far enough apart to be free on a local service, and stops
  /// the moment a plan dated today exists.
  private func watchForPlan() {
    planWatcher?.cancel()
    planWatcher = Task { [weak self] in
      for _ in 0..<20 {
        try? await Task.sleep(for: .seconds(30))
        guard !Task.isCancelled, let self else { return }
        await self.reload()
        if self.hasPlan, self.planStaleDate == nil, !self.plan.isEmpty { return }
      }
    }
  }

  // MARK: - Cycles

  /// Create the cycle after the current one.
  ///
  /// Not optimistic, unlike the section writes: there is no local edit to show
  /// while this runs, and the dates are the one thing the call exists to decide.
  /// The service reads the previous cycle off disk and copies its length —
  /// guessing it here would be guessing the answer.
  ///
  /// What comes back is two facts with different tenses. The file exists once
  /// this returns; the 要务 inside it do not, because the planning run that
  /// writes them takes about ten minutes. Both sentences are handed to the
  /// caller rather than raised as a toast, which is two seconds long and one
  /// line wide.
  public override func createCycle(_ request: NewCycleRequest) async -> ActionOutcome {
    guard let client else { return .failed("没有连接到服务。") }
    do {
      let created = try await client.createCycle(
        days: request.days,
        taskCount: request.taskCount,
        note: request.note
      )
      await reload()
      // After the reload, not before: `reload()` repairs a selection that is not
      // in the list, and the new cycle is not in the list until it has run.
      if let id = created.id, visibleCycles.contains(where: { $0.id == id }) {
        selectedCycleID = id
      }
      return .ok(created.message)
    } catch {
      let reason = (error as? ClientError)?.errorDescription ?? error.localizedDescription
      lastActionError = reason
      return .failed(reason)
    }
  }

  /// Create a section the cycle file does not have yet.
  ///
  /// The three sections are not symmetrical, and flattening them into one
  /// "generate" would be the lie this method exists to avoid:
  ///
  /// - 总结 is drafted by life-review-os from this cycle's own 要务 and 复盘, and
  ///   the service saves it as `ai`.
  /// - 复盘 has no generator anywhere in the system and should not have one —
  ///   it is the record of what actually happened to you. What can be created is
  ///   the empty scaffold, written as your own text for you to fill in.
  /// - 要务 come out of a planning run against the whole vault rather than out of
  ///   one cycle, so there is nothing here to call.
  public override func generateCycleSection(cycleID: Cycle.ID, kind: CycleSectionKind) async -> ActionOutcome {
    guard let client else { return .failed("没有连接到服务。") }
    if kind == .priorities {
      return .unsupported("要务由周期规划生成，这里生成不了。创建新周期时会自动跑一次规划。")
    }
    do {
      let message: String
      if kind == .retro {
        try await client.saveCycleSection(cycleID: cycleID, kind: .retro, body: RetroScaffold.body)
        message = "复盘模板已经放好，接下来是你写"
      } else {
        message = "已生成 \(try await client.generateCycleReview(cycleID: cycleID)) 字的总结"
      }
      await reload()
      return .ok(message)
    } catch {
      // A timeout on the review is not a failed review: the drafting model runs
      // for one to two minutes, this client hangs up at thirty seconds, and the
      // service writes the prose itself precisely so that it survives the
      // disconnect. Reporting "生成失败" here would send someone looking for a
      // problem in a file that is about to be written.
      if kind == .review, case .transport(let underlying)? = error as? ClientError,
         (underlying as? URLError)?.code == .timedOut {
        return .failed("等了 30 秒还没写完，服务那边还在跑。生成好会自己写进文件，过一会儿刷新就能看到。")
      }
      let reason = (error as? ClientError)?.errorDescription ?? error.localizedDescription
      lastActionError = reason
      return .failed(reason)
    }
  }

  // MARK: - Weather

  /// Owned here rather than by the strip, so the cache outlives leaving the
  /// Today screen and coming back to it.
  private let weatherStore = WeatherStore()

  /// Three readings a day — morning, afternoon, evening — and nothing in
  /// between. See `WeatherSnapshot.isFresh(at:)` for what the slots are.
  ///
  /// The in-memory check is first so that the common call costs nothing at all:
  /// Today appearing asks for the weather every time, and all but three of
  /// those a day must not reach an actor, a file, or the network.
  public override func refreshWeather(force: Bool = false) async {
    if !force, let current = weather, current.isFresh() { return }
    // Nil means every source failed and there was nothing cached either. Leave
    // whatever is there — the strip's quiet state is the honest rendering of
    // "no reading", and a half-drawn one would be worse.
    guard let snapshot = await weatherStore.snapshot(force: force) else { return }
    weather = snapshot
  }

  /// Fire a write, and put the truth back if it fails.
  private func write(
    _ what: String,
    reloadAfter: Bool = false,
    _ body: @escaping (DailyOSClient) async throws -> Void
  ) {
    guard let client else { return }
    Task {
      do {
        try await body(client)
        if reloadAfter { await reload() }
      } catch {
        let reason = (error as? ClientError)?.errorDescription ?? error.localizedDescription
        lastError = "\(what)失败：\(reason)"
        toast = "\(what)失败"
        // The optimistic edit is now a lie. Re-read rather than trying to undo
        // it locally: the service is the only thing that knows what the file
        // actually says after a partial failure.
        await reload()
      }
    }
  }
}
