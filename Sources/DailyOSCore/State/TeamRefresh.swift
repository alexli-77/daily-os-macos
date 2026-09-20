import Foundation

/// When a quiet team refresh is allowed to run, and what it is allowed to touch.
///
/// Both halves live here rather than at the call sites. The numbers, because the
/// window-focus path and the background poll have to share one floor — two
/// timers with two thresholds is how "focused at t, polled at t+2s" becomes two
/// requests for the same file. The mutation, because "a background refresh must
/// not revert what the user just did" is a rule about *which fields get written*,
/// and a rule spread across a network call is a rule nobody can check.
public enum TeamRefreshPolicy {
  /// The least time between two refreshes, whoever asked for one.
  ///
  /// Coming back to the window is the strongest signal that somebody is about to
  /// read the screen — and also the easiest event to produce by accident: ⌘-tab
  /// away and back, click the Dock twice, drag a window off another Space.
  /// Without a floor each of those is a pair of HTTP calls. Ten seconds swallows
  /// that flicker and is still far below the time anyone spends away from the
  /// app before the answer could have changed.
  public static let floor: Duration = .seconds(10)

  /// How often the background poll asks while the app is connected.
  ///
  /// Matched to the service's own loop: it syncs through Supabase every 60 s, so
  /// a client asking faster re-reads a file that nothing has rewritten. Asking
  /// slower would move the worst-case staleness off the service and onto this
  /// app, which is the thing the poll exists to stop.
  public static let interval: Duration = .seconds(60)

  /// Whether enough time has passed since the last refresh of *any* kind —
  /// poll, focus, the 更新 button, or a full reload.
  ///
  /// `nil` is always due: nothing has been read yet.
  public static func isDue(since last: ContinuousClock.Instant?, now: ContinuousClock.Instant) -> Bool {
    guard let last else { return true }
    return last.duration(to: now) >= floor
  }
}

extension AppState {
  // MARK: - What a quiet refresh may write
  //
  // These two methods are the entire write surface of the background refresh,
  // and the list of fields they touch is the guarantee: everything a teammate
  // owns is in here, and everything the person at this machine is holding —
  // the plan they are ticking, the cycle open in the editor, the row they have
  // selected, the toast queue — is not. A refresh that landed mid-edit and
  // reverted an optimistic tick would be worse than no auto-refresh at all,
  // because the user would have no idea what took their click away.

  /// Replace teammates' cycles and the team roster.
  ///
  /// Teammate cycles are safe to swap under the user at any moment: they render
  /// read-only, with no editor and no draft to lose. `cycles` — your own — is
  /// deliberately *not* written here even though the same response carries it,
  /// because that half does have an open `TextEditor` behind it.
  ///
  /// The roster moves with the cycles, since a teammate whose cycles arrived but
  /// whose name did not would be unreachable in the switcher. It is refused in
  /// the one case where accepting it would change what the user is looking at:
  /// a roster that no longer contains the member being viewed would leave the
  /// segmented picker with a selection that matches nothing. `reload()` is
  /// where that gets repaired, because repairing it means re-picking, and
  /// re-picking is not something a background task gets to do.
  public func applyTeamCycles(members: [TeamMember], cycles: [Cycle], sync: TeamSyncState) {
    partnerCycles = cycles
    teamSync = sync
    if members.contains(where: { $0.id == viewingMemberID }) {
      self.members = members
    }
  }

  /// Replace teammates' plans for today.
  ///
  /// Nothing here is editable and nothing here is selectable — `TeamTodayRow`
  /// has the tick and the actions taken away on purpose — so this is a straight
  /// swap with no reconciliation to do.
  public func applyTeamToday(entries: [TeamTodayEntry], sync: TeamSyncState) {
    teamToday = entries
    teamTodaySync = sync
  }
}
