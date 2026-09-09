#if DEBUG
import Foundation

/// Fixtures for previews.
///
/// The interesting states of this app are not "has data" and "has no data" —
/// they are *whose* data, and *what you are allowed to do to it*. A cycle you
/// own and a teammate's cycle render from the same view with different controls,
/// and that difference has already produced one bug. So each of these is a
/// preview worth having on the canvas, not a variation to imagine.
extension AppState {
  /// The default: your own cycles, owner role, everything editable.
  public static func previewOwner() -> AppState {
    AppState()
  }

  /// A teammate's cycles. Read-only, sourced from the sync cache.
  public static func previewTeammate() -> AppState {
    let state = AppState()
    state.viewingMemberID = "u_partner"
    state.selectedCycleID = state.partnerCycles.first?.id
    return state
  }

  /// Signed in as a member rather than the owner — the settings screen becomes
  /// an explanation instead of a form.
  public static func previewMember() -> AppState {
    let state = AppState()
    state.account.role = .member
    return state
  }

  /// Nothing has run yet. Every screen's empty state at once, which is the
  /// state a new install actually opens in and the one least likely to get
  /// looked at otherwise.
  public static func previewEmpty() -> AppState {
    let state = AppState()
    state.cycles = []
    state.partnerCycles = []
    state.plan = []
    state.todos = []
    state.runs = []
    state.artifacts = []
    state.schedules = []
    state.threads = []
    state.selectedCycleID = nil
    state.selectedRunID = nil
    state.selectedArtifactID = nil
    state.selectedThreadID = nil
    return state
  }

  /// The service is up but something it depends on is not.
  public static func previewDegraded() -> AppState {
    let state = AppState()
    state.service = ServiceStatus(
      state: .degraded,
      endpoint: "127.0.0.1:14573",
      uptime: .seconds(3 * 3600),
      note: "同步不可用：远端无法连接。本地读写不受影响。"
    )
    return state
  }
}
#endif
