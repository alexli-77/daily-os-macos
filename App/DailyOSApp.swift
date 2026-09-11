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
  /// True only between a successful sign-in and the end of its animation.
  ///
  /// The first attempt at this was a `hasEnteredApp` flag defaulting to false,
  /// which locked out the case it was never thinking about: a *restored*
  /// session. At launch the session is non-nil and no login ever ran, so
  /// "has not entered yet" was true and the app held an already-signed-in
  /// person at the login form with no way forward. Framing it as "a login is
  /// currently finishing" has no such state — nothing is finishing at launch.
  @State private var isFinishingLogin = false

  var body: some Scene {
    Window("Daily OS", id: DailyOSWindow.main) {
      Group {
        // The wall is now only for the moment we are still looking. Failing to
        // find the service used to drop you onto a folder picker as the very
        // first thing the app ever showed you — a question about a word
        // ("仓库") and a folder that most people opening this have no reason to
        // know. You get into the app instead, with an unmissable banner and the
        // picker in Settings where a fix belongs.
        //
        // Safe only because `clearForDisconnected` empties the fixture first: an
        // app full of plausible demo cycles would be a worse lie than the wall.
        if connection.state.isConnecting {
          SetupScreen(connection: connection)
        } else if let state {
          // Who is using it, asked only once there is a service to ask against.
          // Disconnected, the app still opens into itself with the banner — a
          // login screen there would be a wall in front of a wall, and the one
          // thing that is actually wrong is not the account.
          // The second clause keeps the login screen up for the length of its
          // own success animation. Gating purely on `session == nil` swaps the
          // window on the frame the service answers, which leaves the
          // transition no time to play — the mark would jump straight from the
          // form to the sidebar.
          if connection.state.isConnected, state.session == nil || isFinishingLogin {
            LoginScreen(state: state, isFinishing: $isFinishingLogin) {
              withAnimation(.easeOut(duration: 0.3)) { isFinishingLogin = false }
            }
          } else {
            RootView(state: state)
              .transition(.opacity)
          }
        } else {
          SetupScreen(connection: connection)
        }
      }
      .task(id: connection.repoRoot) { await connect() }
      // Settings can change the folder, and it lives in a module that cannot
      // reach this connection. See `Notification.Name.dailyOSRepoRootChanged`.
      .onReceive(NotificationCenter.default.publisher(for: .dailyOSRepoRootChanged)) { _ in
        Task {
          await connection.adoptStoredRoot()
          await connect()
        }
      }
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
    // The store is created either way now. Without a connection it holds
    // nothing — which is what lets the app open to its own empty screens
    // instead of to a folder picker.
    if state == nil { state = LiveAppState(connection: connection) }
    if connection.state.isConnected {
      await state?.reload()
    } else {
      state?.clearForDisconnected()
    }
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
