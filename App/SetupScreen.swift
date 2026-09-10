import SwiftUI
import AppKit
import DailyOSCore
import DailyOSClient
import DailyOSMac

/// The wall you get instead of the app when there is no service.
///
/// The one thing this app must be told is where the service folder is —
/// everything else, including its address and its token, lives inside it. On a
/// machine where the service is installed as a launch agent that is not a
/// question at all: `ServiceConnection` reads the answer out of the agent's own
/// plist, and this screen never appears.
///
/// When it does appear, it is talking to whoever is standing there — which is
/// often not the person who set the service up. It used to open with "选择
/// daily-os 服务仓库的目录", which asks for a word ("仓库") that only means
/// something if you already know the answer, about a folder that person may
/// never have opened.
struct SetupScreen: View {
  let connection: ServiceConnection

  var body: some View {
    VStack(spacing: Metrics.md) {
      Spacer()

      // The mark carries the state, so the screen is not a static wall with a
      // sentence that changes. Waiting looks like waiting.
      DailyOSMark(motion: markMotion)
        .frame(width: 76, height: 76)
      Text("Daily OS").inkStyle(Typo.display)

      switch connection.state {
      case .unconfigured:
        message("找不到这台电脑上的 daily-os 服务。它是一个文件夹——里面装着服务的代码和数据，通常叫 daily-os-feishu。")
        message("找到它，点下面的按钮选中它就行。App 需要知道的只有这一件事，不用输密码，也不用填任何密钥。", tone: .neutral)
      case .connecting:
        // No ProgressView beside the mark: two things spinning at once is one
        // too many, and the mark is the better of the two at saying which of
        // the app's own steps is in flight.
        message(connection.activity.isEmpty ? "正在连接…" : connection.activity)
      case .failed(let reason):
        message(reason, tone: .danger)
      case .connected:
        message("已连接。")
      }

      HStack(spacing: Metrics.xs) {
        Button(connection.repoRoot == nil ? "选择服务文件夹…" : "换一个文件夹…") { pickRepo() }
          .buttonStyle(MossButtonStyle(prominent: connection.repoRoot == nil))
        if connection.repoRoot != nil {
          // 重试 now means "try, and start the service if that is what is
          // wrong" — the same thing launching does. A retry button that only
          // repeats the failing step is a button that repeats the failure.
          Button("重试") { Task { await connection.bringUp() } }
            .buttonStyle(MossButtonStyle(prominent: false))
        }
      }

      if let root = connection.repoRoot {
        VStack(spacing: 2) {
          // Says where it came from. A path that appears on its own, unexplained,
          // reads as the app having decided something behind your back — which
          // costs more trust than the picker it replaced was worth.
          if connection.wasDiscovered {
            Label("自动找到的", systemImage: "sparkle")
              .font(Typo.caption)
              .foregroundStyle(Palette.moss)
          }
          Text(root.path(percentEncoded: false))
            .font(Typo.mono)
            .foregroundStyle(Palette.inkMuted)
            .textSelection(.enabled)
        }
      }

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(Metrics.xl)
    .background(Palette.paper)
  }

  private var markMotion: DailyOSMark.Motion {
    switch connection.state {
    case .connecting: .searching
    case .connected: .settled
    case .unconfigured, .failed: .still
    }
  }

  private func message(_ text: String, tone: Tone = .neutral) -> some View {
    Text(text)
      .font(Typo.body)
      .foregroundStyle(tone == .danger ? Palette.danger : Palette.inkMuted)
      .multilineTextAlignment(.center)
      .frame(maxWidth: 420)
  }

  /// A folder picker rather than a text field. The path is long, easy to
  /// mistype, and the app can check the answer before accepting it.
  private func pickRepo() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "选择"
    panel.message = "选中 daily-os 服务所在的文件夹（里面能看到 package.json 和 src 这两项）"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    connection.use(repoRoot: url)
    Task { await connection.probe() }
  }
}
