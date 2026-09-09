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
  case chat
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
    case .chat: "对话"
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
    case .chat: "bubble.left.and.text.bubble.right"
    case .runs: "waveform.path.ecg"
    case .artifacts: "shippingbox"
    case .schedules: "clock.arrow.circlepath"
    case .settings: "gearshape"
    }
  }

  /// ⌘1…⌘7. Settings keeps the platform-standard ⌘, instead.
  public var shortcut: KeyEquivalent? {
    switch self {
    case .today: "1"
    case .cycles: "2"
    case .okr: "3"
    case .chat: "4"
    case .runs: "5"
    case .artifacts: "6"
    case .schedules: "7"
    case .settings: nil
    }
  }

  /// The sidebar groups. Work you do, then work the machine did, then config.
  public static let workGroup: [AppSection] = [.today, .cycles, .okr, .chat]
  public static let systemGroup: [AppSection] = [.runs, .artifacts, .schedules]

  /// The four iOS tabs. Everything in `systemGroup` plus settings lives behind
  /// "更多" — on a phone you check state, you do not administer a service.
  public static let phoneTabs: [AppSection] = [.today, .cycles, .chat]
}
