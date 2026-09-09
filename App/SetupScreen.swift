import SwiftUI
import AppKit
import DailyOSCore
import DailyOSClient
import DailyOSMac

/// The wall you get instead of the app when there is no service.
///
/// The one thing this app must be told is where the service checkout is —
/// everything else, including its address and its token, lives inside that
/// folder. So the only first-run question is a folder picker, and it appears
/// exactly when the answer is missing or wrong.
struct SetupScreen: View {
  let connection: ServiceConnection

  var body: some View {
    VStack(spacing: Metrics.md) {
      Spacer()

      Image(systemName: "circle.hexagongrid")
        .font(.system(size: 40, weight: .light))
        .foregroundStyle(Palette.moss)
      Text("Daily OS").inkStyle(Typo.display)

      switch connection.state {
      case .unconfigured:
        message("选择 daily-os 服务仓库的目录。地址和令牌都在它的 data/runtime/ui.json 里，所以这是唯一需要告诉它的事。")
      case .connecting:
        ProgressView().controlSize(.small)
        message("正在连接…")
      case .failed(let reason):
        message(reason, tone: .danger)
      case .connected:
        message("已连接。")
      }

      HStack(spacing: Metrics.xs) {
        Button("选择仓库目录…") { pickRepo() }
          .buttonStyle(MossButtonStyle())
        if connection.repoRoot != nil {
          Button("重试") { Task { await connection.probe() } }
            .buttonStyle(MossButtonStyle(prominent: false))
        }
      }

      if let root = connection.repoRoot {
        Text(root.path(percentEncoded: false))
          .font(Typo.mono)
          .foregroundStyle(Palette.inkMuted)
          .textSelection(.enabled)
      }

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(Metrics.xl)
    .background(Palette.paper)
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
    panel.message = "选择 daily-os 服务仓库（含 package.json 与 src/ui 的那个目录）"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    connection.use(repoRoot: url)
    Task { await connection.probe() }
  }
}
