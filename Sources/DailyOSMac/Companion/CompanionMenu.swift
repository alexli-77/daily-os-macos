import SwiftUI
import DailyOSCore

/// The menu bar item.
///
/// The prototype that preceded this tried two shapes at once — a menu bar badge
/// *and* a floating desktop character that peeked from the screen edge. The
/// floating character solved a real problem (a crowded menu bar hides status
/// items) by creating a worse one: a always-on-top window that follows you
/// between spaces and that you cannot get rid of without quitting. This is the
/// menu bar shape only.
///
/// What it has to answer, in order: is the service alive, what is on today, and
/// let me get one thing out of my head without switching apps.
public struct CompanionMenu: View {
  @Environment(AppState.self) private var state
  @Environment(\.openWindow) private var openWindow

  public init() {}

  public var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xs) {
      HStack(spacing: Metrics.xs) {
        StatusDot(
          state.service.state.label,
          tone: state.service.state.tone,
          pulsing: state.service.state == .running
        )
        Spacer()
        Text(state.service.endpoint).font(Typo.mono).foregroundStyle(Palette.inkMuted)
      }

      Divider()

      QuickCaptureField()

      Divider()

      if state.plan.isEmpty {
        Text("今天没有安排").mutedStyle()
      } else {
        Text("今天").mutedStyle(Typo.label)
        ForEach(state.plan.prefix(4)) { item in
          HStack(spacing: Metrics.xs) {
            Circle().fill(Palette.foreground(for: item.kind.tone)).frame(width: 5, height: 5)
            Text(item.text).inkStyle(Typo.caption).lineLimit(1)
            Spacer(minLength: Metrics.xs)
            if let due = item.due {
              Text(Fmt.time(due)).font(Typo.tabularCaption).foregroundStyle(Palette.inkMuted)
            }
          }
        }
      }

      if !state.activeRuns.isEmpty {
        Divider()
        ForEach(state.activeRuns) { run in
          HStack(spacing: Metrics.xs) {
            ProgressView().controlSize(.small)
            Text(run.workflow).inkStyle(Typo.caption)
            Spacer(minLength: Metrics.xs)
            Text(Fmt.duration(run.duration)).font(Typo.tabularCaption).foregroundStyle(Palette.inkMuted)
          }
        }
      }

      Divider()

      Button("打开 Daily OS") { openWindow(id: DailyOSWindow.main) }
        .buttonStyle(MossButtonStyle())
      HStack(spacing: Metrics.xs) {
        Button("重启服务") {}.buttonStyle(QuietButtonStyle(tone: .neutral))
        Button("查看日志") {}.buttonStyle(QuietButtonStyle(tone: .neutral))
        Spacer()
        Button("退出") { NSApplication.shared.terminate(nil) }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
      }
    }
    .padding(Metrics.sm)
    .frame(width: 300)
  }
}

/// The template icon. A tinted dot rides the glyph so the menu bar itself
/// carries service state — the point of having a menu bar item at all.
public struct CompanionMenuLabel: View {
  @Environment(AppState.self) private var state

  public init() {}

  public var body: some View {
    Image(systemName: state.service.state == .running ? "circle.hexagongrid.fill" : "circle.hexagongrid")
      .foregroundStyle(state.service.state == .running ? Palette.moss : Palette.danger)
  }
}

private struct QuickCaptureField: View {
  @Environment(AppState.self) private var state

  var body: some View {
    @Bindable var state = state
    HStack(spacing: Metrics.xs) {
      Image(systemName: "square.and.pencil").foregroundStyle(Palette.inkMuted)
      TextField("随手记一条…", text: $state.quickCaptureText)
        .textFieldStyle(.plain)
        .font(Typo.caption)
        .onSubmit { state.capture(state.quickCaptureText) }
    }
    .padding(Metrics.xs)
    .background(Palette.surfaceSunken)
    .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
  }
}

public enum DailyOSWindow {
  public static let main = "daily-os.main"
}

// MARK: - Previews

#Preview("菜单栏") {
  CompanionMenu()
    .environment(AppState.previewOwner())
}

#Preview("菜单栏 · 服务降级") {
  CompanionMenu()
    .environment(AppState.previewDegraded())
}
