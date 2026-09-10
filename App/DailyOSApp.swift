import SwiftUI
import AppKit
import DailyOSCore
import DailyOSMac
import DailyOSClient

/// The Mac app target.
///
/// Everything that can live in a library does; this file is only the scenes,
/// because scenes are the one part Xcode needs to own.
@main
struct DailyOSApp: App {
  /// The connection and the store are owned here rather than inside a view,
  /// because the window and the menu bar item are separate scenes looking at
  /// the same service. Two stores would mean a capture typed into the menu bar
  /// never reaches the window — which is the one thing the menu bar is for.
  ///
  /// The store exists only once a service is reachable. Without one it could
  /// show nothing but fixture data, and fixture data that looks like your own
  /// cycles is the failure worth a wall rather than a banner.
  @State private var connection = ServiceConnection()
  @State private var state: LiveAppState?

  var body: some Scene {
    Window("Daily OS", id: DailyOSWindow.main) {
      Group {
        if let state, connection.state.isConnected {
          RootView(state: state)
        } else {
          SetupScreen(connection: connection)
        }
      }
      .task(id: connection.repoRoot) { await connect() }
    }
    .defaultSize(width: 1_080, height: 720)
    .commands {
      if let state { SectionCommands(state: state) }
    }

    MenuBarExtra {
      if let state, connection.state.isConnected {
        CompanionMenu().environment(state)
      } else {
        DisconnectedMenu(connection: connection)
      }
    } label: {
      // Reflects the *connection*, not the service's own health: from out here
      // "cannot reach it" and "it reports trouble" look identical, and claiming
      // to tell them apart would be a guess.
      Image(systemName: connection.state.isConnected ? "circle.hexagongrid.fill" : "circle.hexagongrid")
        .foregroundStyle(connection.state.isConnected ? Palette.moss : Palette.inkMuted)
    }
    .menuBarExtraStyle(.window)
  }

  private func connect() async {
    // `bringUp`, not `probe`: it starts the launch agent when the service is
    // simply not up yet, which at login is the common case rather than the
    // exceptional one.
    await connection.bringUp()
    guard connection.state.isConnected else { return }
    if state == nil { state = LiveAppState(connection: connection) }
    await state?.reload()
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

/// The menu bar before there is anything to show in it.
///
/// Still useful: it is where you find out the service is down, and the fastest
/// place to retry from.
private struct DisconnectedMenu: View {
  let connection: ServiceConnection
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xs) {
      StatusDot(connection.state.label, tone: connection.state.tone)
      if case .failed(let reason) = connection.state {
        Text(reason)
          .mutedStyle()
          .fixedSize(horizontal: false, vertical: true)
      }
      Divider()
      Button("打开 Daily OS") { openWindow(id: DailyOSWindow.main) }
        .buttonStyle(MossButtonStyle())
      HStack(spacing: Metrics.xs) {
        Button("重试") { Task { await connection.probe() } }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
        Spacer()
        Button("退出") { NSApplication.shared.terminate(nil) }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
      }
    }
    .padding(Metrics.sm)
    .frame(width: 280)
  }
}
