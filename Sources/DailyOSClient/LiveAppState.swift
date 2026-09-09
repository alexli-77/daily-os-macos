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
    wiredSections = [.today, .cycles, .okr, .settings]
  }

  // MARK: - Loading

  public func reload() async {
    guard let client else { return }
    isLoading = true
    defer { isLoading = false }

    await connection.probe()
    guard connection.state.isConnected else { return }

    // Each read is independent and a failure in one must not blank the others:
    // a broken OKR file should not cost you the cycle you were reading.
    await load("周期") {
      let result = try await client.cycles()
      self.cycles = result.mine
      self.partnerCycles = result.teammates
      if !result.members.isEmpty {
        self.members = result.members
        if let me = result.members.first(where: \.isSelf) {
          self.account.displayName = me.displayName.isEmpty ? self.account.displayName : me.displayName
          self.viewingMemberID = me.id
        }
      }
      if self.selectedCycleID == nil || !self.visibleCycles.contains(where: { $0.id == self.selectedCycleID }) {
        self.selectedCycleID = self.visibleCycles.first?.id
      }
    }

    await load("待办") {
      let inbox = try await client.todoInbox()
      self.todos = inbox.open + inbox.recent
      // The service has no notion of "today's plan" as a separate list; the
      // open inbox is the closest honest thing, so Today shows that rather than
      // inventing a plan the planner never produced.
      self.plan = inbox.open
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

  public override func capture(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    super.capture(text)
    // Deliberately not pre-parsed. The service runs its own command grammar on
    // this string, so "提醒我 …" works from the Mac app for free — parsing it
    // here would only be a second, worse copy of that grammar.
    write("记录", reloadAfter: true) { try await $0.capture(trimmed) }
  }

  public override func setTodo(_ id: TodoItem.ID, to state: TodoState) {
    super.setTodo(id, to: state)
    write("更新待办") { try await $0.setTodo(id: id, to: state) }
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
