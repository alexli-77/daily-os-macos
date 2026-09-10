import AppKit
import SwiftUI
import DailyOSCore

/// The config surface, folded back into the app.
///
/// The web console kept nine admin sections behind a `/console` route that also
/// happened to be where you changed the font size. Three rules here:
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
///
/// This screen talks to the service itself rather than through `AppState`.
/// `AppState` is the shell's store and has no fields for provider, secrets,
/// skills or launchd, and it is not this file's to change; the settings data is
/// read once here and held in `@State`. The transport below is deliberately
/// tiny for the same reason `DailyOSClient` is: the package has no dependency
/// edge from `DailyOSMac` to `DailyOSClient`, so this target cannot import it.
/// `Sources/DailyOSClient/Settings+Client.swift` is the same API for consumers
/// that can — adding `"DailyOSClient"` to this target's dependencies would let
/// this file drop its own copy.
struct SettingsScreen: View {
  @Environment(AppState.self) private var state
  @State private var store = SettingsStore()

  var body: some View {
    ScreenScaffold("设置", subtitle: state.account.role.canConfigure ? "只有所有者能改这里的东西" : nil) {
      if state.account.role.canConfigure {
        owner
      } else {
        Panel {
          EmptyState(
            icon: "lock",
            title: "这台机器的配置属于所有者",
            message: "你可以读写自己的周期和待办，但服务商、密钥和数据源由所有者管理。"
          )
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
    .sheet(isPresented: $store.isShowingLogs) { LogSheet(store: store) }
  }

  @ViewBuilder
  private var owner: some View {
    if let message = store.loadError {
      Panel("读不到服务的配置") {
        VStack(alignment: .leading, spacing: Metrics.sm) {
          Text(message)
            .inkStyle()
            .fixedSize(horizontal: false, vertical: true)
          Text("这一屏的每一项都来自本机的 daily-os 服务。在服务能应答之前，这里不显示任何默认值——写死的示例配置比空白更容易被当成真的。")
            .mutedStyle()
            .fixedSize(horizontal: false, vertical: true)
        }
      } actions: {
        Button("重试") { Task { await store.load() } }.buttonStyle(QuietButtonStyle())
      }
    } else if let snapshot = store.snapshot {
      IdentityPanel(snapshot: snapshot)
      ProviderPanel(store: store, snapshot: snapshot)
      SkillsPanel(store: store, snapshot: snapshot)
      SourcesPanel(store: store, snapshot: snapshot)
      TeamPanel(store: store, snapshot: snapshot)
      ServicePanel(store: store, snapshot: snapshot)
    } else {
      Panel { Text("正在读取服务配置…").mutedStyle() }
    }
    if let banner = store.banner { BannerRow(banner: banner) }
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
        Spacer(minLength: 0)
      }
    }
  }
}

// MARK: - Identity

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

// MARK: - Provider

/// Provider → model → key, in that order, because each choice narrows the next.
private struct ProviderPanel: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    @Bindable var store = store
    Panel("模型", subtitle: "决定工作流和对话用什么跑") {
      VStack(spacing: Metrics.sm) {
        KeyValueRow("服务商") {
          // Bound through the store's setters rather than through `$store` plus
          // `onChange`. Switching provider has to re-pick the model, and an
          // `onChange` cannot tell that apart from a reload repopulating the
          // picker — which would reset the model on every refresh and then offer
          // to save the reset. The setter runs only when the user picks.
          Picker("", selection: Binding(get: { store.draftProvider }, set: { store.selectProvider($0) })) {
            ForEach(store.providerOptions, id: \.self) { Text($0).tag($0) }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(maxWidth: 220, alignment: .leading)
        }
        PanelDivider()
        KeyValueRow("模型") {
          VStack(alignment: .leading, spacing: Metrics.xs) {
            Picker("", selection: Binding(get: { store.modelSelection }, set: { store.selectModel($0) })) {
              ForEach(store.modelOptions) { option in
                Text(option.title).tag(option.id)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 320, alignment: .leading)
            if store.isCustomModel {
              TextField("模型 id", text: $store.draftModel)
                .textFieldStyle(.roundedBorder)
                .font(Typo.monoBody)
                .frame(maxWidth: 320)
            }
            Text("下拉里的都是建议值，不是白名单。服务把 llm.model 原样发给 CLI，所以列表里没有的 id 也能用——当前设置永远留在列表里，打开这一屏不会把它悄悄改掉。")
              .mutedStyle()
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        PanelDivider()
        APIKeyRow(store: store, snapshot: snapshot)
      }
    } actions: {
      if store.hasLLMChanges {
        Button("保存") { store.confirmSaveLLM() }
          .buttonStyle(MossButtonStyle(prominent: false))
          .disabled(store.isBusy)
      }
    }
  }
}

/// The密钥 row, which is three different rows depending on the provider.
///
/// The old screen drew a hardcoded `••••••••••••` for every provider, which was
/// wrong three ways at once: it implied a key existed, it implied this app could
/// see it, and it implied every provider needs one. Codex and Claude authenticate
/// through their own CLI's subscription login and have no key at all;
/// `ANTHROPIC_API_KEY` is needed by the `anthropic` provider but is missing from
/// the service's `SECRET_ENV_KEYS` allow-list, so `/api/env-secret` refuses to
/// read it and `/api/env` refuses to write it.
private struct APIKeyRow: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    @Bindable var store = store
    KeyValueRow("API 密钥") {
      switch store.apiKeyRequirement {
      case .none(let checkName):
        VStack(alignment: .leading, spacing: Metrics.xxs) {
          Pill("不需要", tone: .neutral)
          Text("\(store.draftProvider) 用它自己 CLI 的订阅登录，不存 API key。")
            .mutedStyle()
          if let check = snapshot.doctor.first(where: { $0.name == checkName }) {
            HStack(spacing: Metrics.xs) {
              StatusDot(check.ok ? "已登录" : "未登录", tone: check.ok ? .ok : .danger)
              Text(check.detail.isEmpty ? check.name : check.detail).mutedStyle()
            }
          } else {
            Text("服务的自检里没有 \(checkName) 这一项，登录状态未知。").mutedStyle()
          }
        }

      case .managed(let key):
        VStack(alignment: .leading, spacing: Metrics.xs) {
          HStack(spacing: Metrics.xs) {
            Pill(store.secretPresent ? "已配置" : "未配置", tone: store.secretPresent ? .ok : .neutral)
            Text(store.secretDisplay)
              .font(Typo.monoBody)
              .foregroundStyle(Palette.inkMuted)
              .textSelection(.enabled)
            if store.secretPresent {
              Button(store.isSecretRevealed ? "隐藏" : "显示") {
                Task { await store.toggleReveal(key: key) }
              }
              .buttonStyle(QuietButtonStyle())
              .disabled(store.isBusy)
            }
            Button(store.isEditingSecret ? "取消" : "更换") { store.toggleSecretEditor() }
              .buttonStyle(QuietButtonStyle())
          }
          if store.isEditingSecret {
            HStack(spacing: Metrics.xs) {
              SecureField(key, text: $store.secretDraft)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
              Button("保存") { store.confirmSaveSecret(key: key) }
                .buttonStyle(MossButtonStyle(prominent: false))
                .disabled(store.secretDraft.isEmpty || store.isBusy)
            }
            Text("写进 \(snapshot.envPath)。这个 App 不会把密钥记进日志，也不会存到别的地方。")
              .mutedStyle()
              .fixedSize(horizontal: false, vertical: true)
          }
        }

      case .unmanaged(let key):
        VStack(alignment: .leading, spacing: Metrics.xxs) {
          Pill("服务读不到", tone: .warn)
          Text(unmanagedExplanation(key: key))
            .mutedStyle()
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private func unmanagedExplanation(key: String) -> String {
    guard !key.isEmpty else {
      return "这个服务商不在服务已知的四个里（codex / openai / claude / anthropic），需不需要密钥无从判断。"
    }
    return """
      \(store.draftProvider) 需要 \(key)，但服务的 /api/env-secret 只放行 \
      OPENAI_API_KEY、GITHUB_TOKEN、LINEAR_API_KEY、VAULT_GATE_TOKEN、LARK_APP_SECRET。\
      \(key) 不在这个名单里，读写都会被拒绝，只能直接改 \(snapshot.envPath) 再重启服务。
      """
  }
}

// MARK: - Skills

/// Real installed state for the weekly-review skill.
///
/// The old screen said "已安装 · weekly-review v1.4" for everyone, including
/// people who had never installed it, and there is no version number anywhere in
/// the service — the skill is a git checkout the CLI symlinks to, so its identity
/// is a branch and a commit. `readSkillRepoState` reports all of it from local
/// git without touching the network, including which CLI actually resolves to
/// this directory: without that line an update can report success while the CLI
/// keeps loading an unrelated copy.
private struct SkillsPanel: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    Panel("技能", subtitle: "工作流真正执行的那份 checkout") {
      VStack(alignment: .leading, spacing: Metrics.sm) {
        if !snapshot.skillsEnabled {
          Text("config.yaml 里 skills.enabled=false —— 注册表里的技能都不会被加载。")
            .mutedStyle()
            .fixedSize(horizontal: false, vertical: true)
        }
        HStack(spacing: Metrics.xs) {
          Pill(snapshot.skillRepo.available ? "已安装" : "未安装", tone: snapshot.skillRepo.available ? .ok : .neutral)
          Text(snapshot.skillRepo.skillId).font(Typo.mono).foregroundStyle(Palette.inkMuted)
        }
        if snapshot.skillRepo.available {
          VStack(alignment: .leading, spacing: Metrics.xxs) {
            KeyValueRow("目录", snapshot.skillRepo.workdir, mono: true)
            if snapshot.skillRepo.isGitRepo {
              KeyValueRow("版本", "\(snapshot.skillRepo.branch) @ \(snapshot.skillRepo.commit)", mono: true)
              if !snapshot.skillRepo.subject.isEmpty {
                KeyValueRow("最新提交", snapshot.skillRepo.subject)
              }
              KeyValueRow("与远端", snapshot.skillRepo.behindText)
            }
            KeyValueRow("CLI 链接", snapshot.skillRepo.linkText)
          }
        }
        if !snapshot.skillRepo.blocked.isEmpty {
          Text(snapshot.skillRepo.blocked)
            .foregroundStyle(Palette.foreground(for: .warn))
            .font(Typo.caption)
            .fixedSize(horizontal: false, vertical: true)
        }
        if !snapshot.skills.isEmpty {
          PanelDivider()
          ForEach(snapshot.skills) { skill in
            HStack(spacing: Metrics.xs) {
              Text(skill.id).inkStyle()
              Pill(skill.provider, tone: .neutral)
              if !skill.defaultMode.isEmpty { Pill(skill.defaultMode, tone: .accent) }
              Spacer(minLength: Metrics.xs)
              Text(skill.path).font(Typo.mono).foregroundStyle(Palette.inkMuted).lineLimit(1).truncationMode(.head)
            }
            .frame(minHeight: Metrics.hitTarget)
          }
        }
      }
    } actions: {
      if snapshot.skillRepo.available {
        Button("更新") { store.confirmUpdateSkill() }
          .buttonStyle(QuietButtonStyle())
          .disabled(store.isBusy || !snapshot.skillRepo.canUpdate)
          .help(snapshot.skillRepo.canUpdate ? "git fetch + git pull --ff-only" : snapshot.skillRepo.blocked)
      } else {
        Button("安装") { store.confirmInstallSkill() }
          .buttonStyle(QuietButtonStyle())
          .disabled(store.isBusy)
      }
    }
  }
}

// MARK: - Sources

/// Derived from `config` and `doctor`, never invented.
///
/// The old screen listed five sources with fixed 已连接 / 未配置 pills that came
/// from the fixture. This one asks the service, and keeps a fourth answer for the
/// case the service genuinely cannot report on: `runDoctor` has no calendar check
/// at all, so an enabled calendar reads 未知 — the config says it is switched on,
/// and nothing anywhere says it works.
private struct SourcesPanel: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  /// Which row has its inline form open. One at a time — two open forms in a
  /// six-row list is two places to type and no indication which one is live.
  @State private var openFormID: String?
  @State private var repositoryDraft = ""

  var body: some View {
    Panel("数据源", subtitle: "证据从这些地方来，结论回到你的文件里") {
      VStack(spacing: 0) {
        ForEach(Array(snapshot.sources.enumerated()), id: \.element.id) { index, source in
          if index > 0 { PanelDivider() }
          VStack(alignment: .leading, spacing: Metrics.xxs) {
            HStack(alignment: .top, spacing: Metrics.sm) {
              Image(systemName: source.icon)
                .foregroundStyle(Palette.foreground(for: source.status.tone))
                .frame(width: 20)
              VStack(alignment: .leading, spacing: 2) {
                Text(source.name).inkStyle()
                Text(source.detail)
                  .mutedStyle()
                  .fixedSize(horizontal: false, vertical: true)
              }
              Spacer(minLength: Metrics.xs)
              if let fix = source.fix {
                Button(fix.label) { activate(fix, on: source) }
                  .buttonStyle(QuietButtonStyle())
                  .disabled(store.isBusy)
              }
              Pill(source.status.label, tone: source.status.tone)
            }
            .frame(minHeight: Metrics.hitTarget)

            if openFormID == source.id, source.fix == .addGitHubRepository {
              repositoryForm
            }
          }
          .padding(.vertical, Metrics.xxs)
        }
        PanelDivider()
        // The old sentence here said the service had no "connect this source"
        // endpoint and that this panel would not pretend otherwise. It has a
        // config writer, an env writer and a dozen named actions; what it lacks
        // is one *generic* connect call. Reading that as "nothing is possible"
        // sent people to edit YAML for things that were one request away.
        Text("能在这里做的都做了。剩下的在 \(snapshot.configPath) 和 \(snapshot.envPath) 里——密钥本身请你自己填，这个 App 不替你输入凭据。")
          .mutedStyle()
          .fixedSize(horizontal: false, vertical: true)
          .padding(.top, Metrics.xs)
      }
    } actions: {
      Button("打开配置文件") { reveal(snapshot.configPath) }
        .buttonStyle(QuietButtonStyle(tone: .neutral))
      Button("重新检查") { Task { await store.load() } }
        .buttonStyle(QuietButtonStyle())
        .disabled(store.isBusy)
    }
  }

  private var repositoryForm: some View {
    HStack(spacing: Metrics.xs) {
      TextField("owner/repo", text: $repositoryDraft)
        .textFieldStyle(.plain)
        .font(Typo.mono)
        .padding(Metrics.xxs)
        .background(Palette.surfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
        .onSubmit(submitRepository)
      Button("添加", action: submitRepository)
        .buttonStyle(QuietButtonStyle())
        .disabled(store.isBusy || repositoryDraft.trimmingCharacters(in: .whitespaces).isEmpty)
      Button("取消") { openFormID = nil; repositoryDraft = "" }
        .buttonStyle(QuietButtonStyle(tone: .neutral))
    }
    .padding(.leading, 20 + Metrics.sm)
  }

  private func activate(_ fix: SourceFix, on source: SourceRow) {
    if fix.isInline {
      withAnimation(.snappy(duration: 0.2)) {
        openFormID = openFormID == source.id ? nil : source.id
      }
      repositoryDraft = ""
    } else {
      store.apply(fix)
    }
  }

  private func submitRepository() {
    let slug = repositoryDraft
    openFormID = nil
    repositoryDraft = ""
    Task { await store.addGitHubRepository(slug) }
  }

  /// Selects the file rather than opening it: config.yaml opens in whatever
  /// owns `.yaml`, which on a lot of Macs is nothing useful, and a file that
  /// silently fails to open reads as a broken button.
  private func reveal(_ path: String) {
    NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
  }
}

// MARK: - Team

/// The 邀请码 button, wired to what `teamAction` actually dispatches.
///
/// The panel is four different panels depending on how far along team sync is,
/// because the actions only exist at their own stage: you cannot create a team
/// before signing in to Supabase, and there is no invite code before there is a
/// team. Showing all the buttons and refusing most of them is what the console
/// avoided, and it is worth avoiding here too.
private struct TeamPanel: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    @Bindable var store = store
    Panel("团队", subtitle: "各自的文件仍然在各自机器上，同步只是传输") {
      VStack(alignment: .leading, spacing: Metrics.sm) {
        if !snapshot.team.configured {
          Text("config.yaml 里 team.supabase_url / team.supabase_anon_key 是空的，团队同步整个是关的。填上那两项（anon key，不是 service_role）之后这里才有东西可点。")
            .mutedStyle()
            .fixedSize(horizontal: false, vertical: true)
        } else if !snapshot.team.signedIn {
          VStack(alignment: .leading, spacing: Metrics.xs) {
            Text("Supabase 已配置，这台机器还没登录。").mutedStyle()
            TextField("邮箱", text: $store.teamEmail)
              .textFieldStyle(.roundedBorder)
              .frame(maxWidth: 280)
            SecureField("密码", text: $store.teamPassword)
              .textFieldStyle(.roundedBorder)
              .frame(maxWidth: 280)
            Button("登录") { Task { await store.teamSignIn() } }
              .buttonStyle(MossButtonStyle(prominent: false))
              .disabled(store.teamEmail.isEmpty || store.teamPassword.isEmpty || store.isBusy)
            Text("密码直接发给本机服务，再由它转给 Supabase；服务只把动作名写进日志，不写请求体。")
              .mutedStyle()
              .fixedSize(horizontal: false, vertical: true)
          }
        } else if !snapshot.team.hasTeam {
          signedInWithoutTeam(store: store)
        } else {
          inTeam
        }
      }
    } actions: {
      if snapshot.team.signedIn {
        Button("刷新") { Task { await store.teamRefresh() } }
          .buttonStyle(QuietButtonStyle())
          .disabled(store.isBusy)
        Button("退出 Supabase") { store.confirmTeamSignOut() }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
          .disabled(store.isBusy)
      }
    }
  }

  @ViewBuilder
  private func signedInWithoutTeam(store: SettingsStore) -> some View {
    @Bindable var store = store
    VStack(alignment: .leading, spacing: Metrics.sm) {
      KeyValueRow("已登录", snapshot.team.identityLine)
      PanelDivider()
      Text("还没有团队。建一个，或者用别人给的邀请码加入。").mutedStyle()
      HStack(spacing: Metrics.xs) {
        TextField("团队名称", text: $store.newTeamName)
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 220)
        Button("创建团队") { store.confirmCreateTeam() }
          .buttonStyle(MossButtonStyle(prominent: false))
          .disabled(store.newTeamName.isEmpty || store.isBusy)
      }
      HStack(spacing: Metrics.xs) {
        TextField("邀请码", text: $store.joinCode)
          .textFieldStyle(.roundedBorder)
          .font(Typo.monoBody)
          .frame(maxWidth: 220)
        Button("加入团队") { store.confirmJoinTeam() }
          .buttonStyle(MossButtonStyle(prominent: false))
          .disabled(store.joinCode.isEmpty || store.isBusy)
      }
    }
  }

  @ViewBuilder
  private var inTeam: some View {
    VStack(alignment: .leading, spacing: 0) {
      KeyValueRow("团队", snapshot.team.teamName.isEmpty ? snapshot.team.teamId : snapshot.team.teamName)
      PanelDivider()
      KeyValueRow("我", snapshot.team.identityLine)
      PanelDivider()
      KeyValueRow("邀请码") {
        if snapshot.team.inviteCode.isEmpty {
          Text("这台机器的缓存里没有邀请码。点「刷新」重新拉一次，或者重新生成一个。").mutedStyle()
        } else {
          HStack(spacing: Metrics.xs) {
            Text(snapshot.team.inviteCode)
              .font(Typo.monoBody)
              .foregroundStyle(Palette.ink)
              .textSelection(.enabled)
            Button("复制") { store.copy(snapshot.team.inviteCode, what: "邀请码") }
              .buttonStyle(QuietButtonStyle())
            Button("重新生成") { store.confirmRotateInviteCode() }
              .buttonStyle(QuietButtonStyle(tone: .danger))
              .disabled(store.isBusy)
          }
        }
      }
      PanelDivider()
      KeyValueRow("同步", snapshot.team.syncLine)
      if !snapshot.team.lastError.isEmpty {
        PanelDivider()
        Text(snapshot.team.lastError)
          .font(Typo.caption)
          .foregroundStyle(Palette.foreground(for: .warn))
          .fixedSize(horizontal: false, vertical: true)
          .padding(.vertical, Metrics.xxs)
      }
      PanelDivider()
      ForEach(snapshot.team.members) { member in
        HStack(spacing: Metrics.sm) {
          PixelAvatar(seed: member.avatarSeed, size: 24)
          Text(member.displayName).inkStyle()
          if member.isSelf { Pill("我", tone: .accent) }
          Spacer(minLength: Metrics.xs)
          if let synced = member.lastSyncedAt {
            Text("同步于 \(Fmt.time(synced))").mutedStyle()
          } else {
            Text("从未同步").mutedStyle()
          }
        }
        .frame(minHeight: Metrics.hitTarget)
      }
      PanelDivider()
      HStack {
        Spacer()
        Button("退出团队") { store.confirmLeaveTeam() }
          .buttonStyle(QuietButtonStyle(tone: .danger))
          .disabled(store.isBusy)
      }
      .padding(.top, Metrics.xxs)
    }
  }
}

// MARK: - Service

/// 查看日志 is real; 重启 is not, and says so.
///
/// `/api/logs` is `readUiLogs()` — the service's own network-and-action log, with
/// secrets already redacted on the way in. Restarting has no endpoint at all:
/// `runActionInner` dispatches `service_install` and `service_uninstall` and
/// nothing else, and `installLaunchAgent` is not a restart in disguise — it boots
/// the agent out and back in, which kills the process answering the request and
/// mints a new token, so a "重启" button wired to it would hang up on itself.
/// The honest version is the command, which the user can read before running.
private struct ServicePanel: View {
  @Environment(AppState.self) private var state
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    Panel("服务") {
      VStack(alignment: .leading, spacing: 0) {
        KeyValueRow("状态") {
          StatusDot(
            state.service.state.label,
            tone: state.service.state.tone,
            pulsing: state.service.state == .running
          )
        }
        PanelDivider()
        KeyValueRow("地址", state.service.endpoint, mono: true)
        PanelDivider()
        KeyValueRow("launchd") {
          HStack(spacing: Metrics.xs) {
            Pill(snapshot.service.installed ? "已安装 plist" : "没有 plist", tone: snapshot.service.installed ? .ok : .neutral)
            Pill(snapshot.service.registered ? "已注册" : "未注册", tone: snapshot.service.registered ? .ok : .warn)
            Text(snapshot.service.label).font(Typo.mono).foregroundStyle(Palette.inkMuted)
          }
        }
        PanelDivider()
        KeyValueRow("plist", snapshot.service.plistPath, mono: true)
        PanelDivider()
        // No "已运行" row: the service reports no start time anywhere, and the
        // old screen filled that gap with a zero that read as "刚刚启动".
        // The service still has no restart *endpoint* — asking a process to
        // restart itself over its own HTTP server never had a good answer. But
        // launchd does, and this app can talk to launchd, so the paragraph that
        // used to hand over a terminal command is now two buttons.
        VStack(alignment: .leading, spacing: Metrics.xs) {
          Text("控制").mutedStyle(Typo.body)
          Text(snapshot.service.installed
            ? "由 launchd 管理：开机自启，崩了会自动拉起。Daily OS 启动时会检查它，没在跑就顺手启动。"
            : "还没装成后台任务。在服务目录里执行 `npm run service:install` 之后，这里才能控制它，而且它才会开机自启。")
            .mutedStyle()
            .fixedSize(horizontal: false, vertical: true)
          if snapshot.service.installed {
            HStack(spacing: Metrics.xs) {
              Button("重启服务") { Task { await store.restartService() } }
                .buttonStyle(QuietButtonStyle())
              Button("停止服务") { store.confirmStopService() }
                .buttonStyle(QuietButtonStyle(tone: .danger))
              Spacer(minLength: 0)
              Text(snapshot.service.restartCommand(repoRoot: snapshot.repoRootPath))
                .font(Typo.mono)
                .foregroundStyle(Palette.inkMuted)
                .textSelection(.enabled)
                .lineLimit(1)
            }
            // Rebuilding the service is the step people forget, and the symptom
            // — a restart that changes nothing — looks like the restart failing.
            Text("改过服务端代码的话，先在服务目录跑 npm run build 再重启：launchd 跑的是 dist/，不是源码。")
              .mutedStyle()
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(.top, Metrics.xs)
      }
    } actions: {
      Button("查看日志") { Task { await store.showLogs() } }
        .buttonStyle(QuietButtonStyle())
        .disabled(store.isBusy)
    }
  }
}

/// `/api/logs`, newest first, as the service returns it.
private struct LogSheet: View {
  let store: SettingsStore
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("服务日志").inkStyle(Typo.title)
        Spacer()
        Button("刷新") { Task { await store.showLogs() } }.buttonStyle(QuietButtonStyle())
        Button("关闭") { dismiss() }.buttonStyle(QuietButtonStyle(tone: .neutral))
      }
      .padding(Metrics.md)
      Divider()
      if store.logs.isEmpty {
        EmptyState(
          icon: "doc.plaintext",
          title: "还没有日志",
          message: "服务只保留最近 7 天的网络与动作记录，data/logs/ui-network.jsonl 现在是空的。"
        )
        .padding(Metrics.lg)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(store.logs) { entry in
              VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Metrics.xs) {
                  Circle()
                    .fill(Palette.foreground(for: entry.tone))
                    .frame(width: 6, height: 6)
                  Text(entry.time).font(Typo.mono).foregroundStyle(Palette.inkMuted)
                  Text(entry.summary).font(Typo.monoBody).foregroundStyle(Palette.ink)
                  Spacer(minLength: 0)
                }
                if !entry.detail.isEmpty {
                  Text(entry.detail)
                    .mutedStyle()
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 14)
                }
              }
              .padding(.vertical, Metrics.xxs)
              .padding(.horizontal, Metrics.md)
            }
          }
          .padding(.vertical, Metrics.xs)
        }
      }
    }
    .frame(width: 720, height: 520)
    .background(Palette.paper)
  }
}

// MARK: - Store

/// Everything this screen knows, and the six writes it can perform.
@Observable
@MainActor
private final class SettingsStore {
  struct Banner {
    let ok: Bool
    let text: String
  }

  /// A write the user has not confirmed yet. Every outward or destructive
  /// action goes through one of these — the service has no undo for any of them.
  struct PendingAction: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let confirmTitle: String
    let isDestructive: Bool
    let run: @MainActor () async -> Void
  }

  private(set) var snapshot: SettingsSnapshot?
  private(set) var loadError: String?
  private(set) var isBusy = false
  private(set) var banner: Banner?
  private(set) var logs: [LogRow] = []
  var pending: PendingAction?
  var isShowingLogs = false

  // Provider / model editor
  var draftProvider = ""
  var draftModel = ""
  var modelSelection = ""

  // Secret editor. The revealed plaintext lives here and nowhere else: it is
  // never logged, never written to disk, and dropped the moment the panel
  // reloads or the user hides it again.
  private(set) var revealedSecret: String?
  private(set) var secretPresent = false
  private(set) var secretMask = ""
  var secretDraft = ""
  var isEditingSecret = false

  // Team editors
  var teamEmail = ""
  var teamPassword = ""
  var newTeamName = ""
  var joinCode = ""

  // MARK: Loading

  func load() async {
    isBusy = true
    defer { isBusy = false }
    do {
      let node = try await ServiceLink.get("/api/state")
      let snapshot = SettingsSnapshot(node: node, repoRootPath: ServiceLink.repoRootPath())
      self.snapshot = snapshot
      loadError = nil
      resetEditors(for: snapshot)
      await refreshSecret()
    } catch {
      loadError = message(from: error)
    }
  }

  private func resetEditors(for snapshot: SettingsSnapshot) {
    draftProvider = snapshot.llmProvider
    draftModel = snapshot.llmModel
    // Always the configured id, never the custom sentinel: `modelOptions`
    // injects an unrecognised current value as a real row, so there is always
    // something to select. Starting in custom mode instead would present the
    // saved model as though the user had typed it, and the first save would
    // turn a value the app simply had not heard of into a hand-entered one.
    modelSelection = draftModel
    isEditingSecret = false
    secretDraft = ""
    revealedSecret = nil
  }

  /// Presence comes from `/api/env-secret` rather than from `/api/state`'s
  /// `<KEY>_present`, so the pill and the reveal button can never disagree about
  /// which key they are describing.
  ///
  /// Keyed off the *draft* provider, not the saved one: the row is part of the
  /// choice being made, and showing OpenAI's key state while the picker says
  /// `anthropic` would answer a question nobody asked.
  private func refreshSecret() async {
    guard case .managed(let key) = apiKeyRequirement else {
      secretPresent = false
      secretMask = ""
      return
    }
    do {
      let node = try await ServiceLink.get("/api/env-secret?key=\(key)&reveal=0")
      secretPresent = node["present"].bool
      secretMask = node["masked"].string
    } catch {
      secretPresent = false
      secretMask = ""
      banner = Banner(ok: false, text: "读取 \(key) 状态失败：\(message(from: error))")
    }
  }

  // MARK: Derived

  var providerOptions: [String] {
    var options = ModelCatalog.providers
    let current = snapshot?.llmProvider ?? ""
    if !current.isEmpty, !options.contains(current) { options.insert(current, at: 0) }
    return options
  }

  var modelOptions: [ModelCatalog.Option] {
    ModelCatalog.options(provider: draftProvider, current: snapshot?.llmModel ?? "")
  }

  var isCustomModel: Bool { modelSelection == ModelCatalog.customSentinel }

  /// Follows the picker, not the saved config, so the key row answers the
  /// provider the user is currently looking at.
  var apiKeyRequirement: APIKeyRequirement { .forProvider(draftProvider) }

  var hasLLMChanges: Bool {
    guard let snapshot else { return false }
    let model = draftModel.trimmingCharacters(in: .whitespaces)
    return !model.isEmpty && (draftProvider != snapshot.llmProvider || model != snapshot.llmModel)
  }

  var isSecretRevealed: Bool { revealedSecret != nil }

  var secretDisplay: String {
    if let revealedSecret { return revealedSecret }
    if secretPresent { return secretMask.isEmpty ? "已设置" : secretMask }
    return "（空）"
  }

  // MARK: Editing

  /// The user picked a provider.
  ///
  /// Re-picks the model, because the previous provider's id almost never means
  /// anything to the new one — `gpt-5.6-terra` under `claude` would be saved
  /// verbatim and fail at run time. The suggestion list's first row is the
  /// provider's own default, which is the only safe pick. The key row is reset
  /// too: a revealed OpenAI key must not stay on screen after switching away
  /// from OpenAI.
  func selectProvider(_ provider: String) {
    guard provider != draftProvider else { return }
    draftProvider = provider
    let options = ModelCatalog.options(provider: provider, current: "")
    draftModel = options.first?.id ?? "default"
    modelSelection = draftModel
    revealedSecret = nil
    isEditingSecret = false
    secretDraft = ""
    // Presence is per-key, so the row has to be re-read for the new provider's
    // key rather than inherited from the old one's.
    Task { await refreshSecret() }
  }

  /// The user picked a model. The `自定义…` row carries no id of its own; it only
  /// reveals the text field, and whatever is already in `draftModel` stays there
  /// as the starting point.
  func selectModel(_ selection: String) {
    modelSelection = selection
    guard selection != ModelCatalog.customSentinel else { return }
    draftModel = selection
  }

  func toggleSecretEditor() {
    isEditingSecret.toggle()
    secretDraft = ""
  }

  func toggleReveal(key: String) async {
    if revealedSecret != nil {
      revealedSecret = nil
      return
    }
    do {
      let node = try await ServiceLink.get("/api/env-secret?key=\(key)&reveal=1")
      guard case .string(let value) = node["value"] else {
        banner = Banner(ok: false, text: "服务没有返回 \(key) 的明文。它只对本机的 admin 调用者揭示密钥。")
        return
      }
      revealedSecret = value
    } catch {
      banner = Banner(ok: false, text: "读取 \(key) 失败：\(message(from: error))")
    }
  }

  func copy(_ text: String, what: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    banner = Banner(ok: true, text: "已复制\(what)。")
  }

  // MARK: Confirmations

  func confirmSaveLLM() {
    let provider = draftProvider
    let model = draftModel.trimmingCharacters(in: .whitespaces)
    pending = PendingAction(
      title: "改写 config.yaml？",
      message: "llm.provider 改成 \(provider)，llm.model 改成 \(model)。下一次工作流和对话立刻按新设置跑。",
      confirmTitle: "保存",
      isDestructive: false
    ) { [weak self] in
      await self?.saveLLM(provider: provider, model: model)
    }
  }

  func confirmSaveSecret(key: String) {
    let value = secretDraft
    pending = PendingAction(
      title: "写入 \(key)？",
      message: "会覆盖 .env 里已有的值，之后所有用这个服务商的调用都改用新密钥。旧值不会留副本。",
      confirmTitle: "写入",
      isDestructive: true
    ) { [weak self] in
      await self?.saveSecret(key: key, value: value)
    }
  }

  func confirmInstallSkill() {
    pending = PendingAction(
      title: "安装 weekly-review 技能？",
      message: "服务会把 life-review-os clone 到默认目录，并写进 config.yaml 的 skills.registry。",
      confirmTitle: "安装",
      isDestructive: false
    ) { [weak self] in
      await self?.write("安装技能", path: "/api/skills/install", body: ["dir": ""])
    }
  }

  func confirmUpdateSkill() {
    pending = PendingAction(
      title: "更新技能 checkout？",
      message: "对 \(snapshot?.skillRepo.workdir ?? "") 执行 git fetch 与 git pull --ff-only。这个目录也是 CLI 通过符号链接加载的那一份，更新后下一次运行就会用新的规则。",
      confirmTitle: "更新",
      isDestructive: false
    ) { [weak self] in
      await self?.write("更新技能", path: "/api/skills/update", body: [:])
    }
  }

  func confirmCreateTeam() {
    let name = newTeamName
    pending = PendingAction(
      title: "创建团队「\(name)」？",
      message: "会在 Supabase 上建一个团队并把你设为成员，同时生成一个邀请码。",
      confirmTitle: "创建",
      isDestructive: false
    ) { [weak self] in
      await self?.write("创建团队", path: "/api/team/create", body: ["name": name]) { $0.newTeamName = "" }
    }
  }

  func confirmJoinTeam() {
    let code = joinCode
    pending = PendingAction(
      title: "用这个邀请码加入团队？",
      message: "加入之后，你的周期会同步给团队里的其他人，他们的周期也会同步到本机缓存。",
      confirmTitle: "加入",
      isDestructive: false
    ) { [weak self] in
      await self?.write("加入团队", path: "/api/team/join", body: ["code": code]) { $0.joinCode = "" }
    }
  }

  func confirmLeaveTeam() {
    pending = PendingAction(
      title: "退出团队？",
      message: "退出后就看不到队友的周期了；已经同步上去的内容仍留在原团队。本机的 markdown 一个字都不会动。",
      confirmTitle: "退出",
      isDestructive: true
    ) { [weak self] in
      await self?.write("退出团队", path: "/api/team/leave", body: [:])
    }
  }

  func confirmRotateInviteCode() {
    pending = PendingAction(
      title: "重新生成邀请码？",
      message: "旧邀请码立即失效，已经发出去还没用的那些都会作废。",
      confirmTitle: "重新生成",
      isDestructive: true
    ) { [weak self] in
      await self?.write("重新生成邀请码", path: "/api/team/rotate-code", body: [:])
    }
  }

  func confirmTeamSignOut() {
    pending = PendingAction(
      title: "退出 Supabase 登录？",
      message: "只清掉这台机器上的团队会话，本地文件和其他功能都不受影响。注意这不是退出这个 App —— 它本来就没有登录。",
      confirmTitle: "退出",
      isDestructive: true
    ) { [weak self] in
      await self?.write("退出 Supabase", path: "/api/team/signout", body: [:])
    }
  }

  // MARK: Writes

  func teamSignIn() async {
    let email = teamEmail
    let password = teamPassword
    // Cleared before the request returns so the field cannot be read off screen
    // afterwards, and so a retry has to be typed rather than replayed.
    teamPassword = ""
    await write("登录 Supabase", path: "/api/team/signin", body: ["email": email, "password": password])
  }

  func teamRefresh() async {
    await write("刷新团队", path: "/api/team/refresh", body: [:])
  }

  func showLogs() async {
    isBusy = true
    defer { isBusy = false }
    do {
      let node = try await ServiceLink.get("/api/logs")
      logs = node["logs"].array.enumerated().map { LogRow(index: $0, node: $1) }
      isShowingLogs = true
    } catch {
      banner = Banner(ok: false, text: "读取日志失败：\(message(from: error))")
    }
  }

  private func saveLLM(provider: String, model: String) async {
    isBusy = true
    defer { isBusy = false }
    do {
      // `POST /api/config` re-parses and rewrites the whole file, and its zod
      // schema drops keys it does not recognise — so the config has to go back
      // exactly as it came, with only these two leaves changed. Re-reading it
      // here rather than reusing the snapshot keeps a concurrent edit from being
      // silently reverted by this save.
      let state = try await ServiceLink.get("/api/state")
      let patched = state["config"]
        .setting(["llm", "provider"], to: .string(provider))
        .setting(["llm", "model"], to: .string(model))
      try await ServiceLink.post("/api/config", body: .object(["config": patched]))
      banner = Banner(ok: true, text: "已保存：\(provider) / \(model)")
      await load()
    } catch {
      banner = Banner(ok: false, text: "保存失败：\(message(from: error))")
    }
  }

  private func saveSecret(key: String, value: String) async {
    isBusy = true
    defer { isBusy = false }
    do {
      // Only the one key. `saveEnv` merges over the existing file and skips an
      // empty secret, so a partial body cannot blank a neighbouring key.
      try await ServiceLink.post("/api/env", body: .object(["values": .object([key: .string(value)])]))
      secretDraft = ""
      isEditingSecret = false
      revealedSecret = nil
      banner = Banner(ok: true, text: "已写入 \(key)。")
      await load()
    } catch {
      // The value is not echoed into the message — an error string ends up in
      // the UI and, if the user copies it, somewhere else too.
      banner = Banner(ok: false, text: "写入 \(key) 失败：\(message(from: error))")
    }
  }

  // MARK: Service control

  /// Restart through launchd, then wait for the service to answer again.
  ///
  /// Reloads afterwards rather than reporting success on `launchctl`'s exit
  /// code: kickstart returning 0 means launchd accepted the request, not that
  /// node came back up. The panel above is the only thing that can tell you
  /// which, and it is one read away.
  func restartService() async {
    isBusy = true
    defer { isBusy = false }
    do {
      try await ServiceSupervisor.restart()
      banner = Banner(ok: true, text: "已请求重启，正在等它回来…")
      for _ in 0..<12 {
        try? await Task.sleep(for: .milliseconds(700))
        await load()
        if loadError == nil { banner = Banner(ok: true, text: "服务已重启。"); return }
      }
      banner = Banner(ok: false, text: "重启后服务还没回来。看看日志。")
    } catch {
      banner = Banner(ok: false, text: message(from: error))
    }
  }

  func confirmStopService() {
    pending = PendingAction(
      title: "停止服务？",
      // Says what stops, not just what the button does. "Stop the service" and
      // "stop the morning briefing from arriving" are the same sentence, and
      // only one of them is what someone actually means to do.
      message: "早报、复盘这些定时任务都会停，飞书那边也收不到消息了。下次登录时它会自己起来，也可以在这里手动启动。",
      confirmTitle: "停止",
      isDestructive: true
    ) { [weak self] in
      do {
        try await ServiceSupervisor.stop()
        self?.banner = Banner(ok: true, text: "服务已停止。")
      } catch {
        self?.banner = Banner(ok: false, text: error.localizedDescription)
      }
      await self?.load()
    }
  }

  // MARK: Source fixes

  func apply(_ fix: SourceFix) {
    switch fix {
    case .enable(let path, let what):
      Task { await enableSource(path: path, what: what) }
    case .chooseVaultFolder:
      Task { await chooseVaultFolder() }
    case .action(let name, _, let what):
      Task { await write(what, path: "/api/action", body: ["action": name]) }
    case .addGitHubRepository:
      break  // The panel opens a field; `addGitHubRepository` runs on submit.
    }
  }

  /// Switch one source on, leaving the rest of the file byte-identical.
  ///
  /// Re-reads the config rather than reusing the snapshot for the same reason
  /// `saveLLM` does: the whole tree goes back on every save, so a stale copy
  /// would silently revert anything changed since this screen loaded.
  private func enableSource(path: [String], what: String) async {
    isBusy = true
    defer { isBusy = false }
    do {
      let state = try await ServiceLink.get("/api/state")
      let patched = state["config"].setting(path + ["enabled"], to: .bool(true))
      try await ServiceLink.post("/api/config", body: .object(["config": patched]))
      // Deliberately not "已连接". Switching a source on only lets the checks
      // run; whether it works is what the pill will say a second from now.
      banner = Banner(ok: true, text: "已启用 \(what)。下面的状态是刚重新检查过的结果。")
      await load()
    } catch {
      banner = Banner(ok: false, text: "启用 \(what) 失败：\(message(from: error))")
    }
  }

  /// Point the local vault at a folder and switch it on, in one write.
  ///
  /// Uses this app's own `NSOpenPanel` rather than the service's
  /// `choose_vault_folder` action. That action exists and works — it shells out
  /// to `osascript choose folder` — but the dialog would belong to the node
  /// process: it can open behind this window, and it is a strange thing to hand
  /// a background daemon when the app asking is a native one on the same Mac.
  ///
  /// All three keys move together. A path with `enabled` still false, or
  /// `enabled` with the old `provider: remote`, are half-configured states
  /// nobody asked for and both of them read as "it didn't work".
  private func chooseVaultFolder() async {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "选择"
    panel.message = "选择 vault 知识库文件夹"
    guard panel.runModal() == .OK, let url = panel.url else { return }

    isBusy = true
    defer { isBusy = false }
    do {
      let state = try await ServiceLink.get("/api/state")
      let patched = state["config"]
        .setting(["sources", "vault", "enabled"], to: .bool(true))
        .setting(["sources", "vault", "provider"], to: .string("local"))
        .setting(["sources", "vault", "local_path"], to: .string(url.path(percentEncoded: false)))
      try await ServiceLink.post("/api/config", body: .object(["config": patched]))
      banner = Banner(ok: true, text: "本地 Vault 已指向 \(url.lastPathComponent)。")
      await load()
    } catch {
      banner = Banner(ok: false, text: "设置 Vault 失败：\(message(from: error))")
    }
  }

  /// Append one `owner/repo`.
  ///
  /// Appends rather than replaces, and reads the list back off the service
  /// first: this screen shows a count, not the repositories themselves, so it
  /// has no business deciding what the whole list should be.
  func addGitHubRepository(_ slug: String) async {
    let trimmed = slug.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    isBusy = true
    defer { isBusy = false }
    do {
      let state = try await ServiceLink.get("/api/state")
      var repositories = state["config"]["sources"]["github"]["repositories"].array
      guard !repositories.contains(where: { $0.string == trimmed }) else {
        banner = Banner(ok: true, text: "\(trimmed) 已经在列表里了。")
        return
      }
      repositories.append(.string(trimmed))
      let patched = state["config"].setting(["sources", "github", "repositories"], to: .array(repositories))
      try await ServiceLink.post("/api/config", body: .object(["config": patched]))
      banner = Banner(ok: true, text: "已添加 \(trimmed)，现在共 \(repositories.count) 个仓库。")
      await load()
    } catch {
      banner = Banner(ok: false, text: "添加仓库失败：\(message(from: error))")
    }
  }

  /// The shape every simple write shares: post, report in the service's own
  /// words, reload.
  private func write(
    _ what: String,
    path: String,
    body: [String: String],
    then cleanup: ((SettingsStore) -> Void)? = nil
  ) async {
    isBusy = true
    defer { isBusy = false }
    do {
      let members = body.mapValues { JSONNode.string($0) }
      let response = try await ServiceLink.post(path, body: .object(members))
      cleanup?(self)
      let text = response["text"].string
      banner = Banner(ok: true, text: text.isEmpty ? "\(what)完成。" : text)
      await load()
    } catch {
      banner = Banner(ok: false, text: "\(what)失败：\(message(from: error))")
      // A refused write leaves the screen showing what it showed before, which
      // is still the truth — the service changed nothing.
      await load()
    }
  }

  private func message(from error: any Error) -> String {
    (error as? ServiceLink.Failure)?.errorDescription ?? error.localizedDescription
  }
}

// MARK: - View models

private struct SettingsSnapshot {
  var repoRootPath: String
  var configPath: String
  var envPath: String
  var llmProvider: String
  var llmModel: String
  var doctor: [DoctorRow]
  var sources: [SourceRow]
  var skillsEnabled: Bool
  var skills: [SkillRow]
  var skillRepo: SkillRepoRow
  var team: TeamRow
  var service: ServiceRow
}

private struct DoctorRow {
  let name: String
  let ok: Bool
  let level: String
  let detail: String

  /// The service distinguishes "failed" from "passed with a caveat"; a warning
  /// is still working, and calling it 未配置 would be as wrong as calling it fine.
  var status: SourceStatusKind {
    if !ok { return .trouble }
    return level == "warning" ? .trouble : .connected
  }

  var text: String { detail.isEmpty ? name : detail }
}

/// Four values, not two. The service reports nothing at all about some sources,
/// and 未知 is the only honest label for those — collapsing it into 未配置 would
/// be a guess and collapsing it into 已连接 would be a lie.
private enum SourceStatusKind {
  case connected
  case notConfigured
  case trouble
  case unknown

  var label: String {
    switch self {
    case .connected: "已连接"
    case .notConfigured: "未配置"
    case .trouble: "有问题"
    case .unknown: "未知"
    }
  }

  var tone: Tone {
    switch self {
    case .connected: .ok
    case .notConfigured: .neutral
    case .trouble: .warn
    case .unknown: .neutral
    }
  }
}

private struct SourceRow: Identifiable {
  let id: String
  let name: String
  let icon: String
  let status: SourceStatusKind
  let detail: String
  /// The one thing this app can actually do about this row, if anything.
  var fix: SourceFix?
}

/// What a source row offers when it is not connected.
///
/// The panel used to say the service had no "connect this source" endpoint. That
/// was true of a *generic* one and wrong about everything specific: there is a
/// config writer, an env writer, and a dozen named actions including
/// `calendar_test`, `discover_linear_token` and `discover_github_token`. Reading
/// the absence of one endpoint as the absence of all of them left the panel
/// telling people to go and edit YAML for things it could have done in a click.
///
/// The rule that survives is narrower and still holds: **a row only gets a
/// button when there is a real call behind it.** Anything this app cannot do is
/// still an honest sentence plus a way to open the file.
private enum SourceFix: Equatable {
  /// Flip `<path>.enabled` to true. For a source that is fully configured and
  /// merely switched off, this is the entire distance to 已连接.
  case enable(path: [String], what: String)
  /// Pick a folder, then point local vault at it and switch it on — one write,
  /// because a path without `enabled` and an `enabled` without a path are both
  /// half-configured states nobody asked for.
  case chooseVaultFolder
  /// Ask the service to run a named action and report back in its own words.
  case action(name: String, label: String, what: String)
  /// Append one `owner/repo` to `sources.github.repositories`.
  case addGitHubRepository

  var label: String {
    switch self {
    case .enable(_, let what): "启用 \(what)"
    case .chooseVaultFolder: "选择文件夹…"
    case .action(_, let label, _): label
    case .addGitHubRepository: "添加仓库…"
    }
  }

  /// Whether picking it opens an inline form rather than acting immediately.
  var isInline: Bool { self == .addGitHubRepository }
}

/// What the chosen provider needs, and whether this app can supply it. Three
/// genuinely different situations that one masked text field cannot serve.
private enum APIKeyRequirement {
  /// Authenticated through the provider's own CLI login; the associated value
  /// names the doctor check that reports on it.
  case none(doctorCheck: String)
  /// On the service's `SECRET_ENV_KEYS` allow-list: readable and writable here.
  case managed(key: String)
  /// Needed, but the service refuses to read or write it.
  case unmanaged(key: String)

  static func forProvider(_ provider: String) -> APIKeyRequirement {
    switch provider {
    case "codex": .none(doctorCheck: "Codex login")
    case "claude": .none(doctorCheck: "Claude Code auth")
    case "openai": .managed(key: "OPENAI_API_KEY")
    // `apiKeyEnvVar` in src/cli/setup-wizard.ts says this provider needs
    // ANTHROPIC_API_KEY, but SECRET_ENV_KEYS does not list it — so
    // /api/env-secret answers "Secret key is not allowed" and /api/env drops it.
    case "anthropic": .unmanaged(key: "ANTHROPIC_API_KEY")
    default: .unmanaged(key: "")
    }
  }
}

private struct SkillRow: Identifiable {
  let id: String
  let provider: String
  let path: String
  let defaultMode: String
}

private struct SkillRepoRow {
  let skillId: String
  let workdir: String
  let available: Bool
  let isGitRepo: Bool
  let branch: String
  let commit: String
  let subject: String
  let behind: Int
  let blocked: String
  let linkedCLIs: [String]

  var canUpdate: Bool { isGitRepo && blocked.isEmpty }

  /// `-1` is git failing to answer, not "up to date"; and "up to date" here means
  /// "as of the last fetch", because `readSkillRepoState` never touches the
  /// network.
  var behindText: String {
    if behind < 0 { return "未知（git 没能报告落后多少）" }
    if behind == 0 { return "与上次 fetch 时的远端一致" }
    return "落后 \(behind) 个提交"
  }

  var linkText: String {
    linkedCLIs.isEmpty ? "没有 CLI 链接到这个目录" : linkedCLIs.joined(separator: " / ") + " CLI 已链接"
  }
}

private struct TeamRow {
  let configured: Bool
  let signedIn: Bool
  let email: String
  let displayName: String
  let memberId: String
  let teamId: String
  let teamName: String
  let inviteCode: String
  let members: [TeamMember]
  let syncStatus: String
  let syncedAt: Date?
  let lastError: String

  var hasTeam: Bool { !teamId.isEmpty }

  var identityLine: String {
    let name = [displayName, memberId].first { !$0.isEmpty } ?? "（没有名字）"
    return email.isEmpty ? name : "\(name) · \(email)"
  }

  var syncLine: String {
    let status = syncStatus.isEmpty ? "未知" : syncStatus
    guard let syncedAt else { return "\(status)；还没有同步过" }
    return "\(status)；上次同步 \(Fmt.stamp(syncedAt))"
  }
}

private struct ServiceRow {
  let label: String
  let plistPath: String
  let installed: Bool
  let registered: Bool

  /// A registered agent is kickstarted; an unregistered one has to be started by
  /// hand, and pretending otherwise would hand the user a command that fails.
  func restartCommand(repoRoot: String) -> String {
    registered
      ? "launchctl kickstart -k gui/$(id -u)/\(label)"
      : "cd \(repoRoot) && npm run ui"
  }
}

private struct LogRow: Identifiable {
  let id: Int
  let time: String
  let summary: String
  let detail: String
  let tone: Tone

  init(index: Int, node: JSONNode) {
    id = index
    let stamp = node["timestamp"].string
    time = WireDate.parse(stamp).map(Fmt.time) ?? stamp
    let head = [node["action"].string, [node["method"].string, node["path"].string].filter { !$0.isEmpty }.joined(separator: " "), node["event"].string]
      .first { !$0.isEmpty } ?? ""
    let code = node["status_code"].int.map { " → \($0)" } ?? ""
    let took = node["duration_ms"].int.map { " · \($0)ms" } ?? ""
    summary = "\(head)\(code)\(took)"
    detail = node["detail"].string
    tone = switch node["level"].string {
    case "error": .danger
    case "warning": .warn
    default: .neutral
    }
  }
}

// MARK: - Model suggestions

/// Ported from `MODEL_SUGGESTIONS` in `src/ui/server.ts`.
///
/// Suggestions, never the allowed set: the service passes `llm.model` straight
/// through to the CLI, and model ids move faster than a shipped app does. Two of
/// the web console's behaviours are reproduced deliberately and must not be
/// dropped — an id this build has never heard of stays selectable, and `自定义…`
/// always allows a typed one. Without the first, opening this screen would
/// silently rewrite a working setting on the next save.
private enum ModelCatalog {
  struct Option: Identifiable {
    let id: String
    let note: String

    var title: String {
      if id == ModelCatalog.customSentinel { return "自定义…" }
      return note.isEmpty ? id : "\(id) — \(note)"
    }
  }

  static let customSentinel = "__custom__"
  static let providers = ["codex", "openai", "claude", "anthropic"]

  private static let claudeModels: [(String, String)] = [
    ("default", "claude-sonnet-5"),
    ("claude-haiku-4-5", "最快最便宜"),
    ("claude-sonnet-5", "均衡"),
    ("claude-opus-5", "最强"),
    // No row in DEFAULT_PRICE_TABLE resolves this one, so the budget meter would
    // score it as $0 until billing.price_overrides names a price.
    ("claude-fable-5-1", "需要 billing.price_overrides"),
  ]

  private static let suggestions: [String: [(String, String)]] = [
    "codex": [
      ("default", "跟随 Codex CLI 自己的默认值"),
      ("gpt-6-astra", "最强，复杂任务"),
      ("gpt-5.6-terra", "均衡，日常任务"),
      ("gpt-5.6-sol", "稳定的日常主力"),
      ("gpt-5.6-luna", "快且便宜"),
      ("gpt-5.5", "上一代，已验证"),
      ("gpt-5.4-mini", "小、快、省"),
    ],
    "openai": [
      ("default", "gpt-4o-mini"),
      ("gpt-4.1-mini", ""),
      ("gpt-4.1", ""),
      ("gpt-4o-mini", ""),
      ("gpt-4o", ""),
      ("o3-mini", ""),
      ("o3", ""),
    ],
    "claude": claudeModels,
    "anthropic": claudeModels,
  ]

  static func options(provider: String, current: String) -> [Option] {
    var rows = (suggestions[provider] ?? [("default", "")]).map { Option(id: $0.0, note: $0.1) }
    if !current.isEmpty, !rows.contains(where: { $0.id == current }) {
      rows.insert(Option(id: current, note: "当前设置"), at: 0)
    }
    rows.append(Option(id: customSentinel, note: ""))
    return rows
  }
}

// MARK: - Snapshot mapping

private extension SettingsSnapshot {
  /// Built from a JSON tree rather than from a mirror of the config schema.
  ///
  /// This screen reads about two dozen leaves out of an object with twenty-two
  /// top-level config keys, and a typed mirror would fail the entire screen over
  /// one renamed key it does not even display. Reading leaves also means the
  /// config can be handed back to `POST /api/config` byte-identical, which that
  /// endpoint requires — see `SettingsStore.saveLLM`.
  init(node: JSONNode, repoRootPath: String) {
    let config = node["config"]
    let provider = config["llm"]["provider"].string
    let doctor = node["doctor"].array.map {
      DoctorRow(name: $0["name"].string, ok: $0["ok"].bool, level: $0["level"].string, detail: $0["detail"].string)
    }
    self.repoRootPath = repoRootPath
    configPath = node["configPath"].string
    envPath = node["envPath"].string
    llmProvider = provider
    llmModel = config["llm"]["model"].string
    self.doctor = doctor
    skillsEnabled = config["skills"]["enabled"].bool
    skills = config["skills"]["registry"].array.map {
      SkillRow(
        id: $0["id"].string,
        provider: $0["provider"].string,
        path: $0["path"].string,
        defaultMode: $0["default_mode"].string
      )
    }
    let repo = node["skillRepo"]
    skillRepo = SkillRepoRow(
      skillId: repo["skillId"].string,
      workdir: repo["workdir"].string,
      available: repo["available"].bool,
      isGitRepo: repo["isGitRepo"].bool,
      branch: repo["branch"].string,
      commit: repo["commit"].string,
      subject: repo["subject"].string,
      behind: repo["behind"].int ?? -1,
      blocked: repo["blocked"].string,
      linkedCLIs: repo["installs"].array.filter { $0["linked"].bool }.map { $0["cli"].string }
    )
    team = TeamRow(node: node["team"])
    service = ServiceRow(
      label: node["service"]["label"].string,
      plistPath: node["service"]["plistPath"].string,
      installed: node["service"]["installed"].bool,
      registered: node["service"]["registered"].bool
    )
    sources = SettingsSnapshot.sources(config: config, team: team, doctor: doctor)
  }

  /// Six sources, each derived from config plus whatever doctor happens to say.
  static func sources(config: JSONNode, team: TeamRow, doctor: [DoctorRow]) -> [SourceRow] {
    func check(_ name: String) -> DoctorRow? { doctor.first { $0.name == name } }

    var rows: [SourceRow] = []

    // Linear. A missing LINEAR_API_KEY is a *warning* in doctor, not a failure —
    // the service falls back to collecting through Codex — so it reads 有问题
    // rather than 未配置, with the service's own sentence explaining the fallback.
    let linear = config["sources"]["linear"]
    if !linear["enabled"].bool {
      rows.append(SourceRow(id: "linear", name: "Linear", icon: "square.stack.3d.up", status: .notConfigured, detail: "config.yaml 里 sources.linear.enabled=false", fix: .enable(path: ["sources", "linear"], what: "Linear")))
    } else if let row = check("LINEAR_API_KEY") {
      let scope = [linear["workspace"].string, linear["assignee"].string].filter { !$0.isEmpty }.joined(separator: " · ")
      rows.append(SourceRow(
        id: "linear", name: "Linear", icon: "square.stack.3d.up", status: row.status,
        detail: row.detail.isEmpty ? "LINEAR_API_KEY 已配置\(scope.isEmpty ? "" : "；\(scope)")" : row.text,
        // Only when the key is actually missing. `discover_linear_token` reads
        // the key out of a local Linear install; offering it beside a working
        // key would be a button whose success changes nothing.
        fix: row.status == .connected ? nil : .action(name: "discover_linear_token", label: "自动查找密钥", what: "查找 Linear 密钥")
      ))
    } else {
      rows.append(SourceRow(id: "linear", name: "Linear", icon: "square.stack.3d.up", status: .unknown, detail: "已启用，但服务的自检里没有 LINEAR_API_KEY 这一项。"))
    }

    // Calendar. The one source the service genuinely cannot describe: runDoctor
    // has no calendar check at all, so "开着" is all anyone can honestly say.
    if config["calendar"]["enabled"].bool {
      rows.append(SourceRow(
        id: "calendar", name: "日历", icon: "calendar", status: .unknown,
        detail: "calendar.enabled=true，引擎 mode=\(config["calendar"]["engine"]["mode"].string)；服务的自检里没有日历检查项，接没接通要跑一次 calendar_test 才知道。",
        // The sentence named the thing to run and then made you go and run it
        // somewhere else. This is that sentence with a button on it.
        fix: .action(name: "calendar_test", label: "测试连接", what: "测试日历")
      ))
    } else {
      rows.append(SourceRow(id: "calendar", name: "日历", icon: "calendar", status: .notConfigured, detail: "config.yaml 里 calendar.enabled=false", fix: .enable(path: ["calendar"], what: "日历")))
    }

    // Vault, local or remote — two different sets of checks behind one row.
    let vault = config["sources"]["vault"]
    if !vault["enabled"].bool {
      rows.append(SourceRow(id: "vault", name: "本地 Vault", icon: "folder", status: .notConfigured, detail: "config.yaml 里 sources.vault.enabled=false", fix: .chooseVaultFolder))
    } else if vault["provider"].string == "local" {
      if let row = check("vault.local_path") {
        // A local vault in trouble is almost always a path that moved, so the
        // fix is the same control as the one that set it.
        rows.append(SourceRow(id: "vault", name: "本地 Vault", icon: "folder", status: row.status, detail: row.text, fix: row.status == .connected ? nil : .chooseVaultFolder))
      } else {
        rows.append(SourceRow(id: "vault", name: "本地 Vault", icon: "folder", status: .unknown, detail: "已启用，但服务的自检里没有 vault.local_path。"))
      }
    } else {
      let urlEnv = vault["remote"]["base_url_env"].string
      let tokenEnv = vault["remote"]["token_env"].string
      let both = [check(urlEnv), check(tokenEnv)].compactMap { $0 }
      if both.count < 2 {
        rows.append(SourceRow(id: "vault", name: "本地 Vault", icon: "folder", status: .unknown, detail: "远程 vault 已启用，但自检里没有 \(urlEnv) / \(tokenEnv)。"))
      } else {
        let missing = both.filter { !$0.ok }.map(\.name)
        rows.append(SourceRow(
          id: "vault", name: "本地 Vault", icon: "folder",
          status: missing.isEmpty ? .connected : .trouble,
          detail: missing.isEmpty ? "远程 vault：\(urlEnv) 与 \(tokenEnv) 都已配置" : "缺少 \(missing.joined(separator: "、"))"
        ))
      }
    }

    let github = config["sources"]["github"]
    if !github["enabled"].bool {
      rows.append(SourceRow(id: "github", name: "GitHub", icon: "chevron.left.forwardslash.chevron.right", status: .notConfigured, detail: "config.yaml 里 sources.github.enabled=false", fix: .enable(path: ["sources", "github"], what: "GitHub")))
    } else if let row = check("GITHUB_TOKEN") {
      let repos = github["repositories"].array.count
      rows.append(SourceRow(
        id: "github", name: "GitHub", icon: "chevron.left.forwardslash.chevron.right",
        status: row.status,
        detail: row.ok ? "GITHUB_TOKEN 已配置；\(repos == 0 ? "没有配置仓库" : "\(repos) 个仓库")" : row.text,
        // A configured token with no repositories collects nothing, which is
        // why the pill can say 已连接 while the source is doing no work at all.
        fix: !row.ok ? .action(name: "discover_github_token", label: "自动查找令牌", what: "查找 GitHub 令牌")
          : (repos == 0 ? .addGitHubRepository : nil)
      ))
    } else {
      rows.append(SourceRow(id: "github", name: "GitHub", icon: "chevron.left.forwardslash.chevron.right", status: .unknown, detail: "已启用，但服务的自检里没有 GITHUB_TOKEN 这一项。"))
    }

    // Team sync. Every field behind this row is a local disk read; none of it
    // proves Supabase is reachable right now, so a cached sync error is reported
    // as trouble rather than as 已连接.
    if !team.configured {
      rows.append(SourceRow(id: "team", name: "团队同步", icon: "person.2", status: .notConfigured, detail: "config.yaml 里没填 team.supabase_url / team.supabase_anon_key"))
    } else if !team.signedIn {
      rows.append(SourceRow(id: "team", name: "团队同步", icon: "person.2", status: .notConfigured, detail: "Supabase 已配置，但这台机器还没登录。"))
    } else if !team.lastError.isEmpty {
      rows.append(SourceRow(id: "team", name: "团队同步", icon: "person.2", status: .trouble, detail: team.lastError))
    } else {
      rows.append(SourceRow(
        id: "team", name: "团队同步", icon: "person.2",
        status: team.hasTeam ? .connected : .trouble,
        detail: team.hasTeam ? "\(team.teamName)（\(team.members.count) 名成员）" : "已登录，但还没加入任何团队。"
      ))
    }

    // Feishu is two independent switches — inbound interaction and outbound
    // output — over one transport. The worst related check decides the pill, so
    // a working bot with a broken sender does not read as fine.
    let inbound = config["interaction"]["feishu"]["enabled"].bool
    let outbound = config["output"]["feishu"]["enabled"].bool
    let related = doctor.filter {
      $0.name.hasPrefix("Feishu") || $0.name.hasPrefix("LARK_") || $0.name.hasPrefix("lark-cli") || $0.name.hasSuffix("FEISHU_CHAT_ID")
    }
    if !inbound && !outbound {
      rows.append(SourceRow(id: "im", name: "IM 机器人（飞书）", icon: "bubble.left.and.bubble.right", status: .notConfigured, detail: "interaction.feishu 和 output.feishu 都是关的"))
    } else if related.isEmpty {
      rows.append(SourceRow(id: "im", name: "IM 机器人（飞书）", icon: "bubble.left.and.bubble.right", status: .unknown, detail: "已启用，但服务的自检里没有任何飞书相关的检查项。", fix: .action(name: "discover_feishu_setup", label: "自动查找配置", what: "查找飞书配置")))
    } else if let bad = related.first(where: { !$0.ok }) ?? related.first(where: { $0.level == "warning" }) {
      rows.append(SourceRow(id: "im", name: "IM 机器人（飞书）", icon: "bubble.left.and.bubble.right", status: .trouble, detail: "\(bad.name)：\(bad.text)", fix: .action(name: "feishu_test", label: "测试发送", what: "测试飞书")))
    } else {
      let direction = [inbound ? "接收" : nil, outbound ? "发送" : nil].compactMap { $0 }.joined(separator: " + ")
      rows.append(SourceRow(id: "im", name: "IM 机器人（飞书）", icon: "bubble.left.and.bubble.right", status: .connected, detail: "\(direction)；\(related.count) 项自检全部通过"))
    }

    return rows
  }
}

private extension TeamRow {
  init(node: JSONNode) {
    let syncedAt = WireDate.parse(node["view"]["syncedAt"].string)
    var roster = node["members"].array.map { member -> TeamMember in
      let id = member["userId"].string
      let name = [member["displayName"].string, member["memberId"].string, id].first { !$0.isEmpty } ?? id
      return TeamMember(
        id: id,
        displayName: name,
        // Seeded from the account id, never from the name: a rename must not
        // change the face beside it.
        avatarSeed: id,
        isSelf: false,
        lastSyncedAt: syncedAt
      )
    }
    let mine = node["memberId"].string
    // The cached roster already includes the signed-in user, so mark that row
    // rather than appending a second one for the same person.
    if let index = roster.firstIndex(where: { $0.displayName == node["displayName"].string || $0.id == mine }) {
      roster[index].isSelf = true
    }
    configured = node["configured"].bool
    signedIn = node["signedIn"].bool
    email = node["email"].string
    displayName = node["displayName"].string
    memberId = mine
    teamId = node["teamId"].string
    teamName = node["teamName"].string
    inviteCode = node["inviteCode"].string
    members = roster
    syncStatus = node["view"]["status"].string
    self.syncedAt = syncedAt
    lastError = node["view"]["lastError"].string
  }
}

/// ISO-8601 with and without fractional seconds; `""` is the service's way of
/// saying "never recorded" and is not an error. `Date.ISO8601FormatStyle` rather
/// than `ISO8601DateFormatter` because it is a `Sendable` value and can live in a
/// `static let` under Swift 6 concurrency checking.
private enum WireDate {
  private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
  private static let withoutFraction = Date.ISO8601FormatStyle()

  static func parse(_ raw: String) -> Date? {
    guard !raw.isEmpty else { return nil }
    return (try? Date(raw, strategy: withFraction)) ?? (try? Date(raw, strategy: withoutFraction))
  }
}

// MARK: - JSON

/// A JSON tree kept exactly as the service sent it.
///
/// Two jobs. Reading: every accessor answers a default instead of an optional,
/// so a key that moved costs one row rather than the whole screen. Writing:
/// `POST /api/config` re-parses and rewrites the entire config file and its zod
/// schema strips keys it does not recognise, so a client changing `llm.model`
/// has to hand every other key back untouched — a typed mirror would delete
/// anything this app had not been taught about, permanently.
private enum JSONNode: Codable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONNode])
  case object([String: JSONNode])

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([JSONNode].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: JSONNode].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(in: container, debugDescription: "不认识的 JSON 值")
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null: try container.encodeNil()
    case .bool(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    }
  }

  subscript(key: String) -> JSONNode {
    if case .object(let members) = self, let value = members[key] { return value }
    return .null
  }

  var string: String {
    if case .string(let value) = self { return value }
    return ""
  }

  var bool: Bool {
    if case .bool(let value) = self { return value }
    return false
  }

  var int: Int? {
    if case .number(let value) = self { return Int(value) }
    return nil
  }

  var array: [JSONNode] {
    if case .array(let value) = self { return value }
    return []
  }

  /// Replace one leaf. A path that runs into something other than an object is
  /// left alone rather than overwritten — better to save nothing than to reshape
  /// somebody's config file.
  func setting(_ path: [String], to value: JSONNode) -> JSONNode {
    guard let key = path.first else { return value }
    guard case .object(var members) = self else { return self }
    let child = members[key] ?? .object([:])
    members[key] = child.setting(Array(path.dropFirst()), to: value)
    return .object(members)
  }
}

// MARK: - Transport

/// The smallest thing that can talk to the local service.
///
/// Discovery is the same as `DailyOSClient`'s and for the same reason: the
/// service rewrites `data/runtime/ui.json` on every start with its address and a
/// fresh admin token, so knowing where the checkout is means knowing everything
/// else. This copy exists only because `DailyOSMac` has no dependency edge to
/// `DailyOSClient` in `Package.swift`; it re-reads the runtime file on every
/// request instead of caching it, which costs one small file read and removes
/// the retry-after-restart case entirely.
private enum ServiceLink {
  /// Duplicated from `RepoRoot.defaultsKey` for the same module reason. Changing
  /// one without the other points this screen at a different service than the
  /// rest of the app.
  static let repoRootDefaultsKey = "com.dailyos.mac.repoRoot"

  struct Failure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
  }

  static func repoRootPath() -> String {
    UserDefaults.standard.string(forKey: repoRootDefaultsKey) ?? ""
  }

  private static func endpoint() throws -> (url: URL, token: String) {
    let root = repoRootPath()
    guard !root.isEmpty else {
      throw Failure("还没有选择 daily-os 服务仓库。退出重开会回到「选择仓库目录」那一屏。")
    }
    let path = URL(filePath: root).appending(path: "data/runtime/ui.json")
    guard let data = try? Data(contentsOf: path) else {
      throw Failure("服务没在跑：\(root) 下没有 data/runtime/ui.json。在那里执行 `npm run ui`，或检查 launchd 任务。")
    }
    guard let node = try? JSONDecoder().decode(JSONNode.self, from: data),
          let url = URL(string: node["url"].string),
          !node["token"].string.isEmpty
    else {
      throw Failure("读不懂 ui.json。服务可能正在启动，或者这个目录不是 daily-os 仓库。")
    }
    return (url, node["token"].string)
  }

  static func get(_ path: String) async throws -> JSONNode {
    try await send(path: path, method: "GET", body: nil)
  }

  @discardableResult
  static func post(_ path: String, body: JSONNode) async throws -> JSONNode {
    try await send(path: path, method: "POST", body: body)
  }

  private static func send(path: String, method: String, body: JSONNode?) async throws -> JSONNode {
    let endpoint = try endpoint()
    // Concatenated rather than `URL.appending(path:)`, which percent-encodes `?`
    // into `%3F` — `/api/env-secret?key=…` would then arrive as a path with no
    // route behind it and come back as a 404 that reads like a missing endpoint
    // rather than an eaten query string.
    let base = endpoint.url.absoluteString.hasSuffix("/")
      ? String(endpoint.url.absoluteString.dropLast())
      : endpoint.url.absoluteString
    guard let url = URL(string: base + path) else {
      throw Failure("拼不出请求地址：\(base)\(path)")
    }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
    request.timeoutInterval = 30
    // No Origin header on purpose: the service treats a request without one as a
    // non-browser client and skips the CSRF check, while a fabricated one would
    // fail its hostname allow-list.
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(body)
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw Failure(error.localizedDescription)
    }

    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    if status == 401 || status == 403 {
      throw Failure("服务拒绝了本地令牌。它可能刚重启过——重试一次；仍然失败就确认连的是同一个仓库。")
    }
    guard let node = try? JSONDecoder().decode(JSONNode.self, from: data) else {
      throw Failure("\(path) 的响应解析失败。多半是服务端和客户端版本对不上。")
    }
    // A refused call still answers 200 with `{ ok: false }`, and the sentence
    // beside it is written for a person. `error` is what most handlers set;
    // `message` is what the skills endpoints set instead, and reading only the
    // first would replace "工作区有未提交的改动" with "服务返回了失败但没说原因".
    if case .bool(false) = node["ok"] {
      let reason = [node["error"].string, node["message"].string].first { !$0.isEmpty }
      throw Failure(reason ?? "服务返回了失败但没说原因。")
    }
    guard (200..<300).contains(status) else {
      throw Failure("\(path) 返回 HTTP \(status)。")
    }
    return node
  }
}

// MARK: - Previews

/// Both previews run without a service, so the screen shows its "读不到服务的配置"
/// state rather than fixture configuration. That is the point: a settings screen
/// full of plausible defaults is the thing this rewrite removed.
#Preview("设置 · owner") {
  SettingsScreen()
    .environment(AppState.previewOwner())
    .frame(width: 940, height: 800)
}

/// A member gets an explanation, not a disabled form.
#Preview("设置 · member") {
  SettingsScreen()
    .environment(AppState.previewMember())
    .frame(width: 940, height: 800)
}
