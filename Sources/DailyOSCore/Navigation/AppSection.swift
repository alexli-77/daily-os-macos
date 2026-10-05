import SwiftUI

/// The eight destinations.
///
/// The web console has nine pages plus a nine-section config screen. Two of them
/// do not survive the move to a native app:
///
/// - **Dashboard** was "today's workflows + recent runs + token usage" — three
///   unrelated things stacked because a browser tab had room. Runs has its own
///   screen; the rest is one status strip on Today.
/// - **Config** was a nine-section admin surface. On macOS it becomes Settings
///   (⌘,) with the same sections; on iOS it becomes a read-only status view,
///   because nobody pastes an API key on a phone.
public enum AppSection: String, CaseIterable, Identifiable, Sendable {
  case today
  case cycles
  case okr
  case countdown
  case runs
  case artifacts
  case schedules
  case settings

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .today: "今天"
    case .cycles: "周期"
    case .okr: "OKR"
    case .countdown: "倒数日"
    case .runs: "运行"
    case .artifacts: "产物"
    case .schedules: "排程"
    case .settings: "设置"
    }
  }

  public var icon: String {
    switch self {
    case .today: "sun.horizon"
    case .cycles: "calendar.badge.clock"
    case .okr: "target"
    case .countdown: "hourglass"
    case .runs: "waveform.path.ecg"
    case .artifacts: "shippingbox"
    case .schedules: "clock.arrow.circlepath"
    case .settings: "gearshape"
    }
  }

  /// ⌘1…⌘7. Settings keeps the platform-standard ⌘, instead. Chat is no longer a
  /// section — it lives in the top-right drop-down panel (⌘⇧C), not the sidebar.
  ///
  /// Adding 倒数日 in the middle pushed 运行/产物/排程 from ⌘4/5/6 to ⌘5/6/7. The
  /// alternative was to hand the new section ⌘7 and leave the others alone,
  /// which keeps three months of muscle memory at the price of a sidebar whose
  /// order and whose shortcuts disagree forever. The order is the thing people
  /// actually read off the screen.
  public var shortcut: KeyEquivalent? {
    switch self {
    case .today: "1"
    case .cycles: "2"
    case .okr: "3"
    case .countdown: "4"
    case .runs: "5"
    case .artifacts: "6"
    case .schedules: "7"
    case .settings: nil
    }
  }

  /// The sidebar groups. Work you do, then work the machine did, then config.
  public static let workGroup: [AppSection] = [.today, .cycles, .okr, .countdown]
  public static let systemGroup: [AppSection] = [.runs, .artifacts, .schedules]

  /// The iOS tabs. Everything in `systemGroup` plus settings lives behind
  /// "更多" — on a phone you check state, you do not administer a service.
  public static let phoneTabs: [AppSection] = [.today, .cycles, .okr]
}
