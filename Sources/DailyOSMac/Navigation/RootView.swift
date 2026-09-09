import SwiftUI
import DailyOSCore

/// The app's entry view.
///
/// Owns the store and injects it; the shell itself is `MacRootView`. Kept as a
/// separate type because the app target should not have to know how the store
/// is wired — the private release repo hands `RootView` a live `AppState` and
/// changes nothing else.
public struct RootView: View {
  @State private var state: AppState

  public init(state: AppState = AppState()) {
    _state = State(initialValue: state)
  }

  public var body: some View {
    MacRootView()
      .environment(state)
      .tint(Palette.moss)
  }
}

/// Routes a section to its screen.
struct SectionView: View {
  let section: AppSection

  var body: some View {
    switch section {
    case .today: TodayScreen()
    case .cycles: CyclesScreen()
    case .okr: OKRScreen()
    case .chat: ChatScreen()
    case .runs: RunsScreen()
    case .artifacts: ArtifactsScreen()
    case .schedules: SchedulesScreen()
    case .settings: SettingsScreen()
    }
  }
}
