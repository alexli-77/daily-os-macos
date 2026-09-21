import Foundation

/// One of the independent reads a live store performs on every reload.
///
/// The names used to be string literals passed to a logging helper, which could
/// answer one question — what to call the thing that failed — and not the other
/// one: which collections that read owns. Without the second answer a failed
/// read left its collections holding whatever was there before, and before the
/// first successful read that is `MockData`. A missing endpoint on an older
/// service therefore showed the demo teammate and their demo tasks, which is
/// the one thing the fixture must never be mistaken for.
public enum ReloadChunk: String, CaseIterable, Sendable {
  case cycles = "周期"
  case todos = "待办"
  case plan = "今日计划"
  case teamToday = "团队今天"
  case artifacts = "产物"
  case okr = "OKR"
  case service = "服务状态"

  /// What a failure line calls it. "周期读取失败：…" is actionable; a bare
  /// "加载失败" from a reload with seven independent sources is not.
  public var label: String { rawValue }
}

extension AppState {
  // MARK: - What a failed chunk does to the screen
  //
  // The rule lives here, beside the fields it empties, rather than at the call
  // site in the live store: "a failed read must not leave demo data on screen"
  // is a rule about *which fields get written*, and a rule spread across a
  // network call is a rule nobody can check. Same reasoning as
  // `TeamRefreshPolicy` and the two `apply…` methods next to it.

  /// Take a chunk's read as successful.
  ///
  /// Recorded rather than inferred from the collection being non-empty: an
  /// empty inbox and an inbox that never arrived look identical afterwards, and
  /// only the second one is allowed to be replaced by the fixture's absence.
  public func markLoaded(_ chunk: ReloadChunk) {
    loadedChunks.insert(chunk)
    loadFailures[chunk] = nil
  }

  /// Record a chunk's failed read, emptying it only if it has never held
  /// anything real.
  ///
  /// The condition is the entire design. `clearForDisconnected()` settled the
  /// principle — no service, no data, no fixture standing in for it — but
  /// applying it to every failed refresh would trade one lie for a worse one:
  /// a reload that fails at 3pm would take away the plan you have been ticking
  /// all day. Data that arrived an hour ago is still true, only older. Data
  /// that never arrived is the fixture.
  public func markFailed(_ chunk: ReloadChunk, reason: String) {
    loadFailures[chunk] = reason
    guard !loadedChunks.contains(chunk) else { return }
    empty(chunk)
  }

  /// Empty the collections one chunk owns.
  ///
  /// Deliberately not a call into `clearForDisconnected()`'s list: that one
  /// answers a different question (nothing is reachable) and also drops the
  /// identity, the diagnosis and `wiredSections`, none of which one failed
  /// endpoint has any standing to touch. What a chunk may empty is what that
  /// chunk writes on success, plus the selection into it — a selected id
  /// pointing at a row that is gone renders as an empty detail pane.
  private func empty(_ chunk: ReloadChunk) {
    switch chunk {
    case .cycles:
      cycles = []
      partnerCycles = []
      teamSync = nil
      members = []
      selectedCycleID = nil
      // `account` and `viewingMemberID` stay. The read sets them, but they are
      // not what shows through: the roster above is. Rewriting the identity
      // from a failed read would flip `isViewingSelf` — and with it which list
      // every cycle screen reads — over an endpoint that may answer fine a
      // minute from now.
    case .todos:
      todos = []
    case .plan:
      plan = []
      planStaleDate = nil
      planGeneratedAt = nil
      hasPlan = false
    case .teamToday:
      teamToday = []
      teamTodaySync = nil
    case .artifacts:
      artifacts = []
      selectedArtifactID = nil
    case .okr:
      okrFiles = []
    case .service:
      // Degraded rather than stopped, which is what a disconnect sets: the
      // connection was probed a moment ago and answered. Something behind this
      // one endpoint is wrong, and the fixture's "运行中，已跑 4 小时 12 分"
      // is the one reading that is certainly false.
      service = ServiceStatus(
        state: .degraded,
        endpoint: "",
        uptime: .zero,
        note: "服务状态没读到，下面的运行时间和地址都不作数。"
      )
    }
  }
}
