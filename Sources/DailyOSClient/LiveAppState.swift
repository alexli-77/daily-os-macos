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

  public func reload() async {
    guard let client else { return }
    isLoading = true
    defer { isLoading = false }

    if !connection.state.isConnected { await connection.probe() }
    guard connection.state.isConnected else { return }

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
