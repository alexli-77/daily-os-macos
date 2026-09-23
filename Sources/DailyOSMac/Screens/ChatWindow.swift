import SwiftUI
import DailyOSCore

/// The Chat section, hosted in its own detachable window.
///
/// It is the *same* conversation as the `.chat` section inside the main window,
/// because it takes the same `AppState` — threads, history and the in-flight run
/// are one store, not two. So a message sent here shows up in the tab and vice
/// versa; the window is another way to look at the one chat, not a second chat.
///
/// Stored in `@State` and injected exactly the way `RootView` does it, so the
/// `@Environment(AppState.self)` reads inside `ChatScreen` resolve identically
/// whether the screen is shown as a section or as this window.
public struct ChatWindow: View {
  @State private var state: AppState

  public init(state: AppState) {
    _state = State(initialValue: state)
  }

  public var body: some View {
    ChatScreen()
      .environment(state)
      .tint(Palette.moss)
      .background(Palette.paper)
      .frame(minWidth: 420, minHeight: 480)
  }
}

/// Shown in the chat window when there is no service to talk to yet, so opening
/// it never lands on empty fixture-shaped data. Mirrors the main window's rule:
/// the honest thing to show is "not connected", with the fix living in the main
/// window's Settings rather than duplicated here.
public struct ChatWindowUnavailable: View {
  public init() {}

  public var body: some View {
    VStack(spacing: Metrics.sm) {
      Image(systemName: "bubble.left.and.bubble.right")
        .font(.system(size: 28))
        .foregroundStyle(Palette.inkMuted)
      Text("聊天暂时不可用")
        .font(.headline)
      Text("服务未连接。回到 Daily OS 主窗口，连接恢复后再打开聊天。")
        .mutedStyle()
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(Metrics.lg)
    .frame(minWidth: 420, minHeight: 480)
    .background(Palette.paper)
  }
}
