import SwiftUI
import DailyOSCore
import DailyOSMac

/// The Mac app target.
///
/// Everything that can live in a library does; this file is only the scenes,
/// because scenes are the one part Xcode needs to own. Keeping it this thin is
/// what lets the private release repository reuse the whole UI by depending on
/// the package and shipping its own `AppState`.
@main
struct DailyOSApp: App {
  /// One store for every scene. The menu bar item and the main window are
  /// looking at the same service, so they must not each hold their own copy —
  /// a capture typed into the menu bar has to appear in the window immediately.
  @State private var state = AppState()

  var body: some Scene {
    Window("Daily OS", id: DailyOSWindow.main) {
      RootView(state: state)
    }
    .defaultSize(width: 1_080, height: 720)
    .commands { SectionCommands(state: state) }

    MenuBarExtra {
      CompanionMenu().environment(state)
    } label: {
      CompanionMenuLabel().environment(state)
    }
    .menuBarExtraStyle(.window)
  }
}

/// ⌘1…⌘7 for the sections, under the View menu so the shortcuts are
/// discoverable rather than folklore.
private struct SectionCommands: Commands {
  let state: AppState

  var body: some Commands {
    CommandGroup(after: .toolbar) {
      Divider()
      ForEach(AppSection.allCases) { section in
        if let shortcut = section.shortcut {
          Button(section.title) { state.section = section }
            .keyboardShortcut(shortcut, modifiers: .command)
        }
      }
      Divider()
      Button("设置…") { state.section = .settings }
        .keyboardShortcut(",", modifiers: .command)
    }
  }
}
