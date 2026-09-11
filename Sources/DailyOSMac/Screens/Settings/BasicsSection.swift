import AppKit
import SwiftUI
import DailyOSCore

/// Who the assistant is talking to, and where this machine's configuration
/// actually lives.
struct BasicsSection: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    ProfilePanel(store: store)
    IdentityPanel(snapshot: snapshot)
  }
}

/// The console's three Setup fields at the top of the page.
///
/// `user.timezone` is the one people get wrong and never notice: every workflow
/// time — the 08:00 in 排程 — is resolved in it, so a machine left on `UTC`
/// delivers the morning briefing in the middle of the night and nothing on any
/// screen says why.
private struct ProfilePanel: View {
  let store: SettingsStore

  var body: some View {
    @Bindable var store = store
    Panel("个人", subtitle: "模型怎么称呼你，用什么语言，按哪个时区算日子") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        SettingText(label: "显示名", text: $store.draft.displayName, placeholder: "Leon")
        SettingText(
          label: "时区",
          text: $store.draft.timezone,
          placeholder: "America/Toronto",
          hint: "IANA 时区名。排程里的每一个时间都按它解析——留在 UTC 上，早报会在半夜到。",
          mono: true
        )
        SettingText(
          label: "语言",
          text: $store.draft.language,
          placeholder: "zh-CN",
          hint: "写进提示词，决定生成的计划和复盘用哪种语言。",
          mono: true
        )
      }
    } actions: {
      SaveAction(isDirty: store.isBasicsDirty, isBusy: store.isBusy) {
        Task { await store.saveBasics() }
      }
    }
  }
}

/// What used to be 账号, with the dead 退出登录 button replaced by the reason it
/// was dead.
///
/// This app does not sign in. The service mints a runtime token on every start,
/// writes it into `data/runtime/ui.json`, and treats any caller holding it as
/// admin — `resolveAuthContext` in `src/ui/server.ts` says so, and names the Mac
/// companion as the intended caller. `/api/logout` destroys a *browser session
/// cookie*; a token client has no session for it to destroy, so pressing it here
/// would have been a request that legitimately answers `{ ok: true }` and
/// changes nothing at all. Which identity this app runs as is decided entirely
/// by which checkout it is pointed at.
private struct IdentityPanel: View {
  @Environment(AppState.self) private var state
  let snapshot: SettingsSnapshot

  var body: some View {
    Panel("身份", subtitle: "这个 App 没有登录，也就没有可以退出的会话") {
      VStack(spacing: 0) {
        HStack(spacing: Metrics.sm) {
          PixelAvatar(seed: state.account.avatarSeed, size: 44)
          VStack(alignment: .leading, spacing: 2) {
            Text(state.account.displayName).inkStyle(Typo.heading)
            Text(state.account.email).mutedStyle()
          }
          Spacer()
          Pill(state.account.role.label, tone: .accent)
        }
        .padding(.bottom, Metrics.sm)
        PanelDivider()
        KeyValueRow("认证方式", "服务运行时令牌（服务按 admin 对待）")
        PanelDivider()
        KeyValueRow("令牌来源", "\(snapshot.repoRootPath)/data/runtime/ui.json", mono: true)
        PanelDivider()
        KeyValueRow("配置文件", snapshot.configPath, mono: true)
        PanelDivider()
        KeyValueRow("环境变量", snapshot.envPath, mono: true)
        PanelDivider()
        Text(
          """
          服务每次启动都会换一个本地令牌并写进 ui.json；这个 App 读它，所以从来不需要账号密码。\
          换句话说，「退出登录」在这里没有对应的动作——服务端的 /api/logout 只销毁浏览器的 session cookie。\
          要换身份，就换服务仓库：断开连接（或退出重开）会回到「选择仓库目录」那一屏，指到哪个 checkout，\
          就以那个 checkout 的服务身份运行。
          """
        )
        .mutedStyle()
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, Metrics.xs)
      }
    } actions: {
      Button("在访达中显示") { revealRepo() }.buttonStyle(QuietButtonStyle())
    }
  }

  private func revealRepo() {
    let url = URL(filePath: snapshot.repoRootPath)
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}
