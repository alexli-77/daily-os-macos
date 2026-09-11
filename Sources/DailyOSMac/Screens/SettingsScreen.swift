import AppKit
import SwiftUI
import DailyOSCore

/// The config surface, folded back into the app.
///
/// The web console kept nine admin sections behind a `/console` route that also
/// happened to be where you changed the font size. Four rules here:
///
/// - **Owner-only.** Non-owners do not get a disabled version of this screen,
///   they get an explanation. Hiding controls is presentation only — the
///   service enforces the same boundary.
/// - **Configuration lives on the Mac.** The iOS app (a separate repository)
///   shows what this screen is set to and stops — no API keys, no provider
///   switching, no skill installs on a phone.
/// - **Nothing here may claim a capability the service does not have.** Every
///   control below is wired to a real endpoint in `src/ui/server.ts`. Where
///   there is no endpoint — restarting the service, ending a session this app
///   never had, reading an Anthropic key — the screen says so in a sentence
///   instead of offering a button that quietly does nothing. That is the whole
///   defect this file was rewritten to fix.
/// - **Nothing here duplicates another screen.** The console set the workflow
///   schedules; 排程 does that now, so this screen has no times, no enable
///   switches for daily plan / review / weekly, and no scheduler driver.
///
/// **Layout** is the console's own: a section list on the left, panels on the
/// right. Not a single scroll — this is fourteen sections and about a hundred
/// fields, and one column of that is a page you navigate by scrollbar position.
/// Not a `NavigationSplitView` either: this screen is already inside the
/// window's split view, and nesting two gives you two sets of collapse
/// behaviour fighting over the same drag. `ListColumn` is the in-screen
/// list-detail the other screens use, for exactly this reason.
///
/// This screen talks to the service itself rather than through `AppState`.
/// `AppState` is the shell's store and has no fields for provider, secrets,
/// skills or launchd, and it is not this file's to change; the settings data is
/// read once here and held in `@State`. The transport in
/// `Settings/SettingsTransport.swift` is deliberately tiny for the same reason
/// `DailyOSClient` is: the package has no dependency edge from `DailyOSMac` to
/// `DailyOSClient`, so this target cannot import it.
/// `Sources/DailyOSClient/Settings+Client.swift` is the same API for consumers
/// that can — adding `"DailyOSClient"` to this target's dependencies would let
/// this file drop its own copy.
struct SettingsScreen: View {
  @Environment(AppState.self) private var state
  @State private var store = SettingsStore()

  var body: some View {
    Group {
      if state.account.role.canConfigure {
        owner
      } else {
        ScreenScaffold("设置") {
          Panel {
            EmptyState(
              icon: "lock",
              title: "这台机器的配置属于所有者",
              message: "你可以读写自己的周期和待办，但服务商、密钥和数据源由所有者管理。"
            )
          }
        }
      }
    }
    .task { await store.load() }
    .alert(
      store.pending?.title ?? "",
      isPresented: Binding(get: { store.pending != nil }, set: { if !$0 { store.pending = nil } }),
      presenting: store.pending
    ) { request in
      Button("取消", role: .cancel) { store.pending = nil }
      Button(request.confirmTitle, role: request.isDestructive ? .destructive : nil) {
        store.pending = nil
        Task { await request.run() }
      }
    } message: { request in
      Text(request.message)
    }
  }

  private var owner: some View {
    HStack(spacing: 0) {
      ListColumn(width: Metrics.listMin) { SectionList(store: store) }
      ScreenScaffold(store.section.title, subtitle: store.section.summary) {
        content
        if let banner = store.banner { BannerRow(banner: banner) }
      }
      .frame(maxWidth: .infinity)
    }
    .background(Palette.paper)
    // The log list is the one section whose data is not in `/api/state`, so it
    // is fetched when you arrive rather than on every settings load — nobody
    // opening 模型 needs seven days of request records pulled first.
    .task(id: store.section) {
      if store.section == .logs { await store.loadLogs() }
    }
  }

  @ViewBuilder
  private var content: some View {
    if let message = store.loadError {
      LoadErrorPanel(store: store, message: message)
    } else if let snapshot = store.snapshot {
      switch store.section {
      case .overview: OverviewSection(store: store, snapshot: snapshot)
      case .basics: BasicsSection(store: store, snapshot: snapshot)
      case .model: ModelSection(store: store, snapshot: snapshot)
      case .feishu: FeishuSection(store: store, snapshot: snapshot)
      case .sources: SourcesSection(store: store, snapshot: snapshot)
      case .workflows: WorkflowsSection(store: store, snapshot: snapshot)
      case .team: TeamSection(store: store, snapshot: snapshot)
      case .skills: SkillsSection(store: store, snapshot: snapshot)
      case .decision: DecisionSection(store: store, snapshot: snapshot)
      case .strategy: StrategySection(store: store, snapshot: snapshot)
      case .okr: OKRSection(store: store, snapshot: snapshot)
      case .guide: GuideSection()
      case .service: ServiceSection(store: store, snapshot: snapshot)
      case .logs: LogsSection(store: store)
      }
    } else {
      Panel { Text("正在读取服务配置…").mutedStyle() }
    }
  }
}

// MARK: - Section list

/// The left column. Grouped, because fourteen flat rows is a list you read
/// rather than a list you aim at.
private struct SectionList: View {
  let store: SettingsStore

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: Metrics.xxs) {
        SectionLabel("配置")
        ForEach(SettingsSection.configGroup) { row(for: $0) }
        SectionLabel("文档")
        ForEach(SettingsSection.documentGroup) { row(for: $0) }
        SectionLabel("系统")
        ForEach(SettingsSection.systemGroup) { row(for: $0) }
      }
      .padding(Metrics.xs)
    }
  }

  private func row(for section: SettingsSection) -> some View {
    SelectableRow(isSelected: section == store.section) {
      store.section = section
    } content: {
      HStack(spacing: Metrics.xs) {
        Image(systemName: section.icon)
          .foregroundStyle(section == store.section ? Palette.moss : Palette.inkMuted)
          .frame(width: 18)
        Text(section.title).inkStyle()
        Spacer(minLength: 0)
      }
    }
  }
}

// MARK: - Load failure

/// What the whole screen becomes when the service cannot be reached.
///
/// Deliberately not a partially-filled form: this screen has about a hundred
/// fields and every one of them would have to show a default, which is the
/// exact failure this file was rewritten to remove — a plausible-looking config
/// nobody configured.
private struct LoadErrorPanel: View {
  @Environment(AppState.self) private var state
  let store: SettingsStore
  let message: String

  var body: some View {
    // Titled by what is wrong, not by what this screen failed to do. "读不到
    // 服务的配置" describes the symptom from the screen's own point of view and
    // is equally true of four different problems — which is how someone on a
    // machine with no service installed ended up being told to 指定服务文件夹.
    Panel(state.serviceDiagnosis.headline) {
      VStack(alignment: .leading, spacing: Metrics.sm) {
        Text(state.serviceDiagnosis.advice)
          .inkStyle()
          .fixedSize(horizontal: false, vertical: true)

        PanelDivider()

        Text("Daily OS 会自己找服务：先读 launchd 里登记的路径，再翻常见的代码目录，最后问 Spotlight。")
          .mutedStyle()
          .fixedSize(horizontal: false, vertical: true)
        HStack(spacing: Metrics.xs) {
          Button("重新查找") { Task { await store.rediscoverService() } }
            .buttonStyle(MossButtonStyle())
          // Offered only when there is plausibly another folder to point at.
          // When the service simply has not been started, the folder is already
          // right and picking it again would change nothing — a button that
          // cannot help is worse than no button, because it gets tried first.
          if state.serviceDiagnosis.wantsFolderPicker {
            Button("手动指定文件夹…") { Task { await store.pickServiceFolder() } }
              .buttonStyle(MossButtonStyle(prominent: false))
          }
          // Opens the pane directly. Telling someone to "去系统设置 → 隐私与安全性
          // → 完全磁盘访问权限" is four levels of navigation described in prose,
          // and this URL is the whole reason macOS exposes it.
          if state.serviceDiagnosis.wantsFullDiskAccess {
            Button("打开「完全磁盘访问权限」") {
              if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
              }
            }
            .buttonStyle(MossButtonStyle(prominent: false))
          }
        }

        PanelDivider()

        // The transport's own sentence, kept but demoted. It is the precise
        // thing that failed and it is worth having when the advice above turns
        // out not to apply — but it is written for whoever wrote the client,
        // not for whoever is standing at the machine.
        Text("技术细节：\(message)")
          .mutedStyle()
          .fixedSize(horizontal: false, vertical: true)
      }
    } actions: {
      Button("重试") { Task { await store.load() } }.buttonStyle(QuietButtonStyle())
    }
  }
}

// MARK: - Banner

/// The result of the last write, kept on screen until the next one.
///
/// Not a toast: several of these carry the service's own multi-line explanation
/// of why something was refused, and a message that disappears after two seconds
/// is a message the user has to reproduce to read.
private struct BannerRow: View {
  let banner: SettingsStore.Banner

  var body: some View {
    Panel {
      HStack(alignment: .top, spacing: Metrics.sm) {
        Image(systemName: banner.ok ? "checkmark.circle" : "exclamationmark.triangle")
          .foregroundStyle(Palette.foreground(for: banner.ok ? .ok : .danger))
        Text(banner.text)
          .inkStyle()
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
        Spacer(minLength: 0)
      }
    }
  }
}

// MARK: - Previews

/// Both previews run without a service, so the screen shows its "读不到服务的配置"
/// state rather than fixture configuration. That is the point: a settings screen
/// full of plausible defaults is the thing this rewrite removed.
#Preview("设置 · owner") {
  SettingsScreen()
    .environment(AppState.previewOwner())
    .frame(width: 1080, height: 800)
}

/// A member gets an explanation, not a disabled form.
#Preview("设置 · member") {
  SettingsScreen()
    .environment(AppState.previewMember())
    .frame(width: 1080, height: 800)
}
