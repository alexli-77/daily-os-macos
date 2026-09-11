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

/// The console account, and where this machine's configuration lives.
///
/// This comment used to argue at length that the app does not sign in and that a
/// 退出登录 button here would be dead. That was true of *connecting* and it is
/// still true: the service mints a runtime token on every start, writes it into
/// `data/runtime/ui.json`, and treats any caller holding it as admin.
///
/// It stopped being the whole story when login arrived. Reaching the service and
/// saying who is using it are two separate questions, and only the first one is
/// answered by the token. So 退出登录 *is* here now, at the foot of the panel —
/// it ends the session in the service's `users` store and returns to the login
/// screen — and the paragraph above it says what it does not do, because
/// "log out" on its own sounds like a lock and this is not one.
private struct IdentityPanel: View {
  @Environment(AppState.self) private var state
  let snapshot: SettingsSnapshot

  var body: some View {
    // Three identities live in this product and this panel is about exactly one
    // of them: the console account you signed in as. The avatar and name used to
    // come from `state.account`, which is filled from `team.self.memberId` — a
    // team member id shown under a heading that says 身份.
    Panel("身份", subtitle: "当前登录的控制台账号") {
      VStack(spacing: 0) {
        HStack(spacing: Metrics.sm) {
          PixelAvatar(seed: avatarSeed, size: 44)
          VStack(alignment: .leading, spacing: 2) {
            Text(state.session?.username ?? "未登录").inkStyle(Typo.heading)
            Text(state.session?.email.isEmpty == false ? state.session!.email : "控制台账号库（服务的 users 表）")
              .mutedStyle()
          }
          Spacer()
          if let session = state.session {
            Pill(session.role.label, tone: .accent)
          }
        }
        .padding(.bottom, Metrics.sm)
        PanelDivider()
        KeyValueRow("连接方式", "服务运行时令牌（服务按 admin 对待）")
        PanelDivider()
        KeyValueRow("令牌来源", "\(snapshot.repoRootPath)/data/runtime/ui.json", mono: true)
        PanelDivider()
        KeyValueRow("配置文件", snapshot.configPath, mono: true)
        PanelDivider()
        KeyValueRow("环境变量", snapshot.envPath, mono: true)
        PanelDivider()
        // The distinction this paragraph exists to make:登录 and 连接 are two
        // different things, and only one of them is a gate. Saying "退出登录"
        // without saying what it does not do would leave someone thinking they
        // had locked the machine.
        Text(
          """
          登录决定的是「谁在用这台 App」——同一台电脑上可以有多个账号轮流用。\
          但连服务靠的是服务自己写下的运行令牌，和登录无关：退出登录只是换掉名字，\
          不会锁上任何东西，能登进这台 Mac 的人照样连得上。
          """
        )
        .mutedStyle()
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, Metrics.xs)

        if state.session != nil {
          PanelDivider()
          HStack(spacing: Metrics.xs) {
            Button("退出登录") { Task { _ = await state.signOut() } }
              .buttonStyle(MossButtonStyle(prominent: false, tone: .danger))
            Text("退出后回到登录页，可以换一个账号登进来。")
              .mutedStyle()
            Spacer(minLength: 0)
          }
          .padding(.top, Metrics.sm)
        }
      }
    } actions: {
      Button("在访达中显示") { revealRepo() }.buttonStyle(QuietButtonStyle())
    }
  }

  /// Same fallback the login response forces: `/api/login` returns a name and
  /// a role and no seed, and the console's own renderer falls back to the
  /// username — so one account draws the same face in both places.
  private var avatarSeed: String {
    guard let session = state.session else { return "" }
    return session.avatarSeed.isEmpty ? session.username : session.avatarSeed
  }

  private func revealRepo() {
    let url = URL(filePath: snapshot.repoRootPath)
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }
}
