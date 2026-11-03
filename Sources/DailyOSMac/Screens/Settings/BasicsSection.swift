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
  @Environment(AppState.self) private var state
  let store: SettingsStore

  /// Every IANA zone, sorted, with the saved value kept in the list even if it
  /// is an alias the system no longer enumerates — a picker that silently drops
  /// the current setting reads as "unset".
  static func timezoneOptions(current: String) -> [(value: String, title: String)] {
    var ids = TimeZone.knownTimeZoneIdentifiers.sorted()
    if !current.isEmpty, !ids.contains(current) { ids.insert(current, at: 0) }
    return ids.map { ($0, $0) }
  }

  /// A curated set of the languages plans and reviews are actually generated in.
  /// The saved value is kept even when it is not one of them, for the same reason.
  static func languageOptions(current: String) -> [(value: String, title: String)] {
    var options: [(String, String)] = [
      ("zh-CN", "简体中文 (zh-CN)"),
      ("zh-TW", "繁體中文 (zh-TW)"),
      ("en-US", "English (en-US)"),
      ("en-GB", "English (en-GB)"),
      ("ja-JP", "日本語 (ja-JP)"),
      ("ko-KR", "한국어 (ko-KR)"),
      ("fr-FR", "Français (fr-FR)"),
      ("de-DE", "Deutsch (de-DE)"),
      ("es-ES", "Español (es-ES)"),
    ]
    if !current.isEmpty, !options.contains(where: { $0.0 == current }) {
      options.insert((current, current), at: 0)
    }
    return options
  }

  var body: some View {
    @Bindable var store = store
    Panel("个人") {
      // Divider-separated rows, so 个人 reads as one profile card the way 身份
      // below it already does — the rows line up down a hairline instead of
      // floating in a stack.
      VStack(alignment: .leading, spacing: Metrics.xs) {
        // 称呼 for plans and reviews — kept editable and distinct from the login
        // account, but defaulted to the account name so an unset field no longer
        // reads "User" next to a sidebar that says admin.
        SettingText(
          label: "显示名",
          text: $store.draft.displayName,
          placeholder: state.session?.username ?? "Leon"
        )
        PanelDivider()
        // Timezone and language are closed sets, not free text: typing `UTC` by
        // mistake delivers the morning briefing at midnight, and a dropdown that
        // starts on the current value makes a wrong one a choice rather than a
        // typo.
        SettingPicker(
          label: "时区",
          selection: $store.draft.timezone,
          options: Self.timezoneOptions(current: store.draft.timezone),
          hint: "IANA 时区名。排程时间都按它算，设成 UTC 早报会半夜到。"
        )
        PanelDivider()
        SettingPicker(
          label: "语言",
          selection: $store.draft.language,
          options: Self.languageOptions(current: store.draft.language),
          hint: "计划和复盘用这个语言生成。"
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
    Panel("身份") {
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
        // The identity line is the whole answer most of the time: who am I
        // signed in as. The machine paths and the login-vs-connect caveat are
        // true and worth keeping, but they are reference material, not the first
        // thing this panel should say — folded into 高级 so the panel opens on
        // the account, not on three file paths.
        DisclosureGroup("高级") {
          VStack(spacing: 0) {
            KeyValueRow("连接方式", "服务运行时令牌（服务按 admin 对待）")
            PanelDivider()
            KeyValueRow("令牌来源", "\(snapshot.repoRootPath)/data/runtime/ui.json", mono: true)
            PanelDivider()
            KeyValueRow("配置文件", snapshot.configPath, mono: true)
            PanelDivider()
            KeyValueRow("环境变量", snapshot.envPath, mono: true)
            PanelDivider()
            // 登录 and 连接 are two different things, and only one of them is a
            // gate. Saying "退出登录" without saying what it does not do would
            // leave someone thinking they had locked the machine.
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
          }
          .padding(.top, Metrics.xs)
        }
        .font(Typo.label)
        .tint(Palette.mint600)
        .padding(.vertical, Metrics.xxs)

        if state.session != nil {
          PanelDivider()
          HStack(spacing: Metrics.xs) {
            Button("退出登录") { Task { _ = await state.signOut() } }
              .buttonStyle(MossButtonStyle(prominent: false, tone: .danger))
            Text("退出后可以换账号登录。")
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
