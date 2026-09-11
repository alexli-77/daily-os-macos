import AppKit
import SwiftUI
import DailyOSCore

/// Everything this screen knows, and every write it can perform.
///
/// One store rather than one per section: a save posts the *whole* config file
/// back, so two stores editing two sections would each hand the service a tree
/// built from its own stale read and the later save would silently revert the
/// earlier one.
@Observable
@MainActor
final class SettingsStore {
  struct Banner {
    let ok: Bool
    let text: String
  }

  /// A write the user has not confirmed yet.
  ///
  /// Not every write: typing into a field and pressing 保存 is already an
  /// intent, and a dialog on top of it is a click that teaches people to click
  /// through dialogs. These are the ones with no undo or with an effect outside
  /// this Mac — secrets, skill checkouts, team membership, launchd, and anything
  /// that sends a message to a real Feishu chat.
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

  /// Which section the content area is showing. Lives here rather than in the
  /// view so a panel can send you somewhere — "查看日志" is the same navigation
  /// the sidebar performs, and a second mechanism for it would drift.
  var section: SettingsSection = .overview

  /// The last `/api/action` body, verbatim. Several of these are the point of
  /// pressing the button — `collect` is a JSON dump of today's evidence and
  /// `progress` is a list of candidate lines — and a banner is one line tall.
  private(set) var actionOutput = ""
  private(set) var runningAction = ""
  /// Whether a manual action also pushes its result to Feishu. Mirrors the
  /// console's `send-output` checkbox, and it is on by default there too.
  var sendActionOutput = true

  /// The form, and the copy of it the service last confirmed. Every section asks
  /// `draft != original` to decide whether it has anything to save, so a field
  /// typed and typed back does not leave a 保存 button lit.
  var draft = SettingsDraft()
  private(set) var original = SettingsDraft()

  // Secret editor. The revealed plaintext lives here and nowhere else: it is
  // never logged, never written to disk, and dropped the moment the panel
  // reloads or the user hides it again.
  private(set) var revealedSecret: String?
  private(set) var secretPresent = false
  private(set) var secretMask = ""
  var secretDraft = ""
  var isEditingSecret = false

  /// Presence for the four secrets that are not the model key: they belong to a
  /// source, not to the provider, and each has its own row. Keyed by env name so
  /// a key that moves between panels does not need a second field here.
  private(set) var sourceSecrets: [String: Bool] = [:]
  var editingSourceSecret: String?
  var sourceSecretDraft = ""

  // Team editors
  var teamEmail = ""
  var teamPassword = ""
  var newTeamName = ""
  var joinCode = ""
  /// Typed only when replacing. The current anon key is never read back into the
  /// app — see `SettingsSnapshot.supabaseKeyPresent`.
  var supabaseKeyDraft = ""
  var isEditingSupabaseKey = false

  /// Where `git clone` should put the skill checkout. Empty means the service's
  /// own default, which is what the console's placeholder promises.
  var skillInstallDir = ""

  // MARK: Loading

  func load() async {
    isBusy = true
    defer { isBusy = false }
    do {
      let node = try await ServiceLink.get("/api/state")
      let snapshot = SettingsSnapshot(node: node, repoRootPath: ServiceLink.repoRootPath())
      self.snapshot = snapshot
      loadError = nil
      resetEditors(snapshot: snapshot, node: node)
      await refreshSecret()
      refreshSourceSecrets(env: node["env"])
    } catch {
      loadError = message(from: error)
    }
  }

  /// Rebuild the form from what the service just said.
  ///
  /// The strategy editor is the one field that does not simply follow the
  /// service: it has a file picker above it, and reseeding to the first file on
  /// every reload would throw away the selection every time a save came back.
  private func resetEditors(snapshot: SettingsSnapshot, node: JSONNode) {
    let chosen = draft.strategyFileID
    var next = SettingsDraft(snapshot: snapshot, config: node["config"], env: node["env"])
    if let keep = snapshot.strategy.first(where: { $0.id == chosen }) {
      next.strategyFileID = keep.id
      next.strategyMd = keep.markdown
    }
    draft = next
    original = next
    isEditingSecret = false
    secretDraft = ""
    revealedSecret = nil
    editingSourceSecret = nil
    sourceSecretDraft = ""
    isEditingSupabaseKey = false
    supabaseKeyDraft = ""
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

  /// Presence only, straight out of `/api/state`'s `redactedEnv`, which reports
  /// `<KEY>_present` and never the value. Four extra round trips to
  /// `/api/env-secret` would tell this screen exactly the same thing.
  private func refreshSourceSecrets(env: JSONNode) {
    sourceSecrets = Dictionary(uniqueKeysWithValues: SettingsStore.sourceSecretKeys.map {
      ($0, env["\($0)_present"].bool)
    })
  }

  static let sourceSecretKeys = ["GITHUB_TOKEN", "LINEAR_API_KEY", "VAULT_GATE_TOKEN", "LARK_APP_SECRET"]

  // MARK: Derived

  var providerOptions: [String] {
    var options = ModelCatalog.providers
    let current = snapshot?.llmProvider ?? ""
    if !current.isEmpty, !options.contains(current) { options.insert(current, at: 0) }
    return options
  }

  var modelOptions: [ModelCatalog.Option] {
    ModelCatalog.options(provider: draft.provider, current: snapshot?.llmModel ?? "")
  }

  var isCustomModel: Bool { draft.modelSelection == ModelCatalog.customSentinel }

  /// Follows the picker, not the saved config, so the key row answers the
  /// provider the user is currently looking at.
  var apiKeyRequirement: APIKeyRequirement { .forProvider(draft.provider) }

  var hasLLMChanges: Bool {
    guard let snapshot else { return false }
    let model = draft.model.trimmingCharacters(in: .whitespaces)
    return !model.isEmpty && (draft.provider != snapshot.llmProvider || model != snapshot.llmModel)
  }

  var isSecretRevealed: Bool { revealedSecret != nil }

  var secretDisplay: String {
    if let revealedSecret { return revealedSecret }
    if secretPresent { return secretMask.isEmpty ? "已设置" : secretMask }
    return "（空）"
  }

  /// Which strategy file the editor is on, resolved against what the service
  /// actually listed — the list shrinks when life-review-os is not checked out.
  var selectedStrategyFile: StrategyFileRow? {
    guard let snapshot else { return nil }
    return snapshot.strategy.first { $0.id == draft.strategyFileID } ?? snapshot.strategy.first
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
    guard provider != draft.provider else { return }
    draft.provider = provider
    let options = ModelCatalog.options(provider: provider, current: "")
    draft.model = options.first?.id ?? "default"
    draft.modelSelection = draft.model
    revealedSecret = nil
    isEditingSecret = false
    secretDraft = ""
    // Presence is per-key, so the row has to be re-read for the new provider's
    // key rather than inherited from the old one's.
    Task { await refreshSecret() }
  }

  /// The user picked a model. The `自定义…` row carries no id of its own; it only
  /// reveals the text field, and whatever is already in `draft.model` stays there
  /// as the starting point.
  func selectModel(_ selection: String) {
    draft.modelSelection = selection
    guard selection != ModelCatalog.customSentinel else { return }
    draft.model = selection
  }

  /// The user switched strategy files. The editor is reseeded from the service's
  /// copy of the new file, so an unsaved edit to the old one is dropped rather
  /// than carried across and written into the wrong path on the next save.
  func selectStrategyFile(_ id: String) {
    guard let file = snapshot?.strategy.first(where: { $0.id == id }) else { return }
    draft.strategyFileID = file.id
    draft.strategyMd = file.markdown
    original.strategyFileID = file.id
    original.strategyMd = file.markdown
  }

  func toggleSecretEditor() {
    isEditingSecret.toggle()
    secretDraft = ""
  }

  func toggleSourceSecretEditor(key: String) {
    editingSourceSecret = editingSourceSecret == key ? nil : key
    sourceSecretDraft = ""
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

  func revealInFinder(_ path: String) {
    guard !path.isEmpty else { return }
    NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: path)])
  }

  // MARK: Section saves

  /// Each section describes its own write as a value, and asks that value twice:
  /// once from the draft and once from the last confirmed copy. Equal means
  /// there is nothing to save and no button to show. Comparing whole drafts
  /// instead would light every panel's 保存 the moment any field on the screen
  /// changed.

  /// 基础: who the assistant thinks it is talking to.
  ///
  /// `user.timezone` is why this is not cosmetic: every workflow time is
  /// resolved in it.
  func basicsEdits(_ draft: SettingsDraft) -> ConfigEdits {
    ConfigEdits(config: [
      ConfigEdit(path: ["user", "display_name"], value: .string(draft.displayName)),
      ConfigEdit(path: ["user", "timezone"], value: .string(draft.timezone)),
      ConfigEdit(path: ["assistant", "language"], value: .string(draft.language)),
    ])
  }

  /// CLI paths. Separate from the provider save because they are `.env` rather
  /// than config, and because someone whose PATH cannot find `codex` needs to
  /// fix that without also changing which model runs.
  func cliEdits(_ draft: SettingsDraft) -> ConfigEdits {
    ConfigEdits(env: [
      "CODEX_BIN": draft.codexBin,
      "CODEX_HOME": draft.codexHome,
      "CLAUDE_BIN": draft.claudeBin,
    ])
  }

  func feishuEdits(_ draft: SettingsDraft) -> ConfigEdits {
    ConfigEdits(
      config: [
        ConfigEdit(path: ["output", "feishu", "enabled"], value: .bool(draft.outputEnabled)),
        ConfigEdit(path: ["output", "feishu", "provider"], value: .string(draft.outputProvider)),
        ConfigEdit(path: ["output", "feishu", "send_mode"], value: .string(draft.outputSendMode)),
        ConfigEdit(path: ["feedback", "feishu", "enabled"], value: .bool(draft.feedbackEnabled)),
        ConfigEdit(path: ["feedback", "feishu", "command_prefix"], value: .string(draft.feedbackPrefix)),
        ConfigEdit(path: ["feedback", "feishu", "poll_limit"], value: .number(Double(draft.feedbackPollLimit))),
        ConfigEdit(path: ["interaction", "feishu", "enabled"], value: .bool(draft.interactionEnabled)),
        ConfigEdit(path: ["interaction", "feishu", "command_prefix"], value: .string(draft.interactionPrefix)),
        ConfigEdit(path: ["interaction", "feishu", "reply_mode"], value: .string(draft.interactionReplyMode)),
        ConfigEdit(path: ["interaction", "feishu", "debounce_ms"], value: .number(Double(draft.interactionDebounce))),
        ConfigEdit(path: ["interaction", "feishu", "require_mention_in_groups"], value: .bool(draft.interactionRequireMention)),
        ConfigEdit(path: ["interaction", "feishu", "security", "access_level"], value: .string(draft.interactionAccessLevel)),
        ConfigEdit(path: ["interaction", "feishu", "security", "admin_open_ids"], value: .lines(draft.interactionAdmins)),
        ConfigEdit(path: ["interaction", "feishu", "security", "allowed_user_open_ids"], value: .lines(draft.interactionUsers)),
        ConfigEdit(path: ["interaction", "feishu", "security", "allowed_chat_ids"], value: .lines(draft.interactionChats)),
        ConfigEdit(path: ["interaction", "feishu", "security", "allowed_workspaces"], value: .lines(draft.interactionWorkspaces)),
        ConfigEdit(path: ["decision", "onboarding", "chat_name"], value: .string(draft.decisionChatName)),
        ConfigEdit(path: ["decision", "onboarding", "auto_create_on_setup"], value: .bool(draft.decisionAutoCreate)),
      ],
      env: [
        "LARK_APP_ID": draft.larkAppID,
        "FEISHU_CHAT_ID": draft.feishuChatID,
        "FEISHU_OWNER_OPEN_ID": draft.ownerOpenID,
        "DAILY_OS_DECISION_CHAT_ID": draft.decisionChatID,
      ]
    )
  }

  func sourcesEdits(_ draft: SettingsDraft) -> ConfigEdits {
    ConfigEdits(
      config: [
        ConfigEdit(path: ["sources", "vault", "enabled"], value: .bool(draft.vaultEnabled)),
        ConfigEdit(path: ["sources", "vault", "provider"], value: .string(draft.vaultProvider)),
        ConfigEdit(path: ["sources", "vault", "local_path"], value: .string(draft.vaultLocalPath)),
        ConfigEdit(path: ["memory", "repository_path"], value: .string(draft.memoryRepositoryPath)),
        ConfigEdit(path: ["memory", "long_term_path"], value: .string(draft.memoryLongTermPath)),
        ConfigEdit(path: ["memory", "daily_dir"], value: .string(draft.memoryDailyDir)),
        ConfigEdit(path: ["sources", "feishu", "enabled"], value: .bool(draft.feishuSourceEnabled)),
        ConfigEdit(path: ["sources", "github", "enabled"], value: .bool(draft.githubEnabled)),
        ConfigEdit(path: ["sources", "github", "repositories"], value: .lines(draft.githubRepositories)),
        ConfigEdit(path: ["sources", "github", "per_repo_limit"], value: .number(Double(draft.githubPerRepoLimit))),
        ConfigEdit(path: ["sources", "linear", "enabled"], value: .bool(draft.linearEnabled)),
        ConfigEdit(path: ["sources", "linear", "assignee"], value: .string(draft.linearAssignee.trimmingCharacters(in: .whitespaces))),
        ConfigEdit(path: ["sources", "linear", "active_cycle_only"], value: .bool(draft.linearActiveCycleOnly)),
        ConfigEdit(path: ["sources", "linear", "query"], value: .string(draft.linearQuery)),
        ConfigEdit(path: ["sources", "linear", "projects_allowlist"], value: .lines(draft.linearProjectsAllow)),
        ConfigEdit(path: ["sources", "linear", "projects_blocklist"], value: .lines(draft.linearProjectsBlock)),
        ConfigEdit(path: ["sources", "linear", "teams_allowlist"], value: .lines(draft.linearTeamsAllow)),
        ConfigEdit(path: ["sources", "linear", "teams_blocklist"], value: .lines(draft.linearTeamsBlock)),
        ConfigEdit(path: ["sources", "chrome_snapshot", "enabled"], value: .bool(draft.chromeSnapshotEnabled)),
        ConfigEdit(path: ["sources", "apple_calendar_snapshot", "enabled"], value: .bool(draft.appleCalendarEnabled)),
        ConfigEdit(path: ["sources", "local_files", "enabled"], value: .bool(draft.localFilesEnabled)),
        ConfigEdit(path: ["sources", "local_files", "files"], value: SettingsStore.namedPaths(draft.localFiles)),
      ],
      env: ["VAULT_GATE_URL": draft.vaultGateURL]
    )
  }

  func workflowEdits(_ draft: SettingsDraft) -> ConfigEdits {
    ConfigEdits(config: [
      ConfigEdit(path: ["calendar", "enabled"], value: .bool(draft.calendarEnabled)),
      ConfigEdit(path: ["calendar", "engine", "mode"], value: .string(draft.calendarMode)),
      ConfigEdit(path: ["calendar", "engine", "command"], value: .string(draft.calendarCommand)),
      ConfigEdit(path: ["calendar", "engine", "workdir"], value: .string(draft.calendarWorkdir)),
      ConfigEdit(path: ["calendar", "engine", "cli_path"], value: .string(draft.calendarCLIPath)),
      ConfigEdit(path: ["calendar", "engine", "policy_file"], value: .string(draft.calendarPolicyFile)),
      ConfigEdit(path: ["calendar", "engine", "routines_file"], value: .string(draft.calendarRoutinesFile)),
      ConfigEdit(path: ["calendar", "draft", "week_days"], value: .number(Double(draft.calendarWeekDays))),
      ConfigEdit(path: ["calendar", "draft", "max_tasks"], value: .number(Double(draft.calendarMaxTasks))),
      ConfigEdit(path: ["background_suggestions", "enabled"], value: .bool(draft.backgroundEnabled)),
      ConfigEdit(path: ["background_suggestions", "mode"], value: .string(draft.backgroundMode)),
      ConfigEdit(path: ["background_suggestions", "interval_minutes"], value: .number(Double(draft.backgroundInterval))),
      ConfigEdit(path: ["background_suggestions", "min_confidence"], value: .string(draft.backgroundConfidence)),
      ConfigEdit(path: ["background_suggestions", "send_to_feishu"], value: .bool(draft.backgroundSendFeishu)),
      ConfigEdit(path: ["background_suggestions", "send_on_change_only"], value: .bool(draft.backgroundChangeOnly)),
    ])
  }

  var isBasicsDirty: Bool { basicsEdits(draft) != basicsEdits(original) }
  var isCLIDirty: Bool { cliEdits(draft) != cliEdits(original) }
  var isFeishuDirty: Bool { feishuEdits(draft) != feishuEdits(original) }
  var isSourcesDirty: Bool { sourcesEdits(draft) != sourcesEdits(original) }
  var isWorkflowsDirty: Bool { workflowEdits(draft) != workflowEdits(original) }
  /// The URL, or a key the user has started typing. The stored key is never read
  /// back, so it can only ever be compared against "did you type a new one".
  var isTeamConnectionDirty: Bool {
    draft.supabaseURL != original.supabaseURL || !supabaseKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty
  }

  func saveBasics() async { await save("基础设置", basicsEdits(draft)) }
  func saveCLIPaths() async { await save("CLI 路径", cliEdits(draft)) }
  func saveFeishu() async { await save("飞书设置", feishuEdits(draft)) }
  func saveSources() async { await save("数据源", sourcesEdits(draft)) }
  func saveWorkflows() async { await save("工作流", workflowEdits(draft)) }

  /// `caffeinate` only applies while the service process is alive, so this is a
  /// service setting and lives with the launchd panel rather than with the
  /// workflows it protects.
  func savePreventSleep(_ enabled: Bool) async {
    await save("防止休眠", ConfigEdits(config: [
      ConfigEdit(path: ["service", "prevent_sleep", "enabled"], value: .bool(enabled)),
    ]))
  }

  func saveSkillsEnabled(_ enabled: Bool) async {
    await save("技能开关", ConfigEdits(config: [ConfigEdit(path: ["skills", "enabled"], value: .bool(enabled))]))
  }

  /// The Supabase URL, and the anon key only when the user typed a new one.
  ///
  /// Sending an empty key would blank a working one — `POST /api/config` writes
  /// whatever it is handed, with none of `/api/env`'s "skip empty secrets"
  /// mercy — so the leaf is omitted entirely unless it is being replaced.
  func saveTeamConnection() async {
    var edits = ConfigEdits(config: [
      ConfigEdit(path: ["team", "supabase_url"], value: .string(draft.supabaseURL.trimmingCharacters(in: .whitespaces))),
    ])
    let key = supabaseKeyDraft.trimmingCharacters(in: .whitespaces)
    if !key.isEmpty {
      edits.config.append(ConfigEdit(path: ["team", "supabase_anon_key"], value: .string(key)))
    }
    supabaseKeyDraft = ""
    isEditingSupabaseKey = false
    await save("Supabase 连接", edits)
  }

  // MARK: Markdown saves

  func saveDecisionPolicy() async {
    await post("保存决策规则", path: "/api/decision-policy", body: .object(["policyMd": .string(draft.decisionPolicyMd)]))
  }

  func saveStrategy() async {
    guard let file = selectedStrategyFile else { return }
    await post("保存复盘策略", path: "/api/strategy", body: .object([
      "id": .string(file.id),
      "markdown": .string(draft.strategyMd),
    ]))
  }

  func saveOKR(level: String) async {
    await post("保存 OKR", path: "/api/okr", body: .object([
      "level": .string(level),
      "markdown": .string(draft.okrMarkdown[level] ?? ""),
    ]))
  }

  /// Rewrites the editor in place rather than saving.
  ///
  /// This is the console's 整理格式 button: `normalizeOkrMarkdown` turns loose
  /// lines into the table shape the readers expect, and the point is that you
  /// look at the result before it touches the file. Saving here would remove the
  /// only step where a mangled objective can still be undone with ⌘Z.
  func formatOKR(level: String) async {
    isBusy = true
    defer { isBusy = false }
    do {
      let node = try await ServiceLink.post("/api/okr/format", body: .object([
        "level": .string(level),
        "markdown": .string(draft.okrMarkdown[level] ?? ""),
      ]))
      draft.okrMarkdown[level] = node["formatted"].string
      banner = Banner(ok: true, text: "已整理格式，还没有写盘——检查一遍再保存。")
    } catch {
      banner = Banner(ok: false, text: "整理格式失败：\(message(from: error))")
    }
  }

  // MARK: Actions

  /// Run one of `runActionInner`'s named actions and keep its whole answer.
  ///
  /// `send` is only meaningful to the handful that produce a report — the
  /// service reads it as "also push this to Feishu" — but it is harmless on the
  /// rest, which is why the console sends it on every action too.
  func runAction(_ name: String, label: String) async {
    isBusy = true
    runningAction = name
    defer {
      isBusy = false
      runningAction = ""
    }
    do {
      let node = try await ServiceLink.post("/api/action", body: .object([
        "action": .string(name),
        "send": .bool(sendActionOutput),
      ]))
      actionOutput = node["text"].string
      banner = Banner(ok: true, text: "\(label)完成。")
      await load()
    } catch {
      actionOutput = message(from: error)
      banner = Banner(ok: false, text: "\(label)失败：\(message(from: error))")
      await load()
    }
  }

  func clearActionOutput() {
    actionOutput = ""
  }

  // MARK: Confirmations

  func confirmSaveLLM() {
    let provider = draft.provider
    let model = draft.model.trimmingCharacters(in: .whitespaces)
    pending = PendingAction(
      title: "改写 config.yaml？",
      message: "llm.provider 改成 \(provider)，llm.model 改成 \(model)。下一次工作流和对话立刻按新设置跑。",
      confirmTitle: "保存",
      isDestructive: false
    ) { [weak self] in
      await self?.save("模型", ConfigEdits(config: [
        ConfigEdit(path: ["llm", "provider"], value: .string(provider)),
        ConfigEdit(path: ["llm", "model"], value: .string(model)),
      ]))
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

  func confirmSaveSourceSecret(key: String) {
    let value = sourceSecretDraft
    pending = PendingAction(
      title: "写入 \(key)？",
      message: "会覆盖 .env 里已有的值，之后这个数据源的所有请求都改用新凭据。旧值不会留副本。",
      confirmTitle: "写入",
      isDestructive: true
    ) { [weak self] in
      await self?.saveSecret(key: key, value: value)
    }
  }

  func confirmInstallSkill() {
    let dir = skillInstallDir.trimmingCharacters(in: .whitespaces)
    pending = PendingAction(
      title: "安装 weekly-review 技能？",
      message: dir.isEmpty
        ? "服务会把 life-review-os clone 到默认目录，并写进 config.yaml 的 skills.registry。"
        : "服务会把 life-review-os clone 到 \(dir)，并写进 config.yaml 的 skills.registry。",
      confirmTitle: "安装",
      isDestructive: false
    ) { [weak self] in
      await self?.post("安装技能", path: "/api/skills/install", body: .object(["dir": .string(dir)]))
    }
  }

  func confirmUpdateSkill() {
    pending = PendingAction(
      title: "更新技能 checkout？",
      message: "对 \(snapshot?.skillRepo.workdir ?? "") 执行 git fetch 与 git pull --ff-only。这个目录也是 CLI 通过符号链接加载的那一份，更新后下一次运行就会用新的规则。",
      confirmTitle: "更新",
      isDestructive: false
    ) { [weak self] in
      await self?.post("更新技能", path: "/api/skills/update", body: .object([:]))
    }
  }

  /// Sends a real message into a real chat, which is why it asks first — the
  /// other 概览 buttons only read.
  func confirmFeishuTest() {
    pending = PendingAction(
      title: "往飞书发一条测试消息？",
      message: "会发到 FEISHU_CHAT_ID 指向的那个会话里，你的同事如果在那个群里也会看到。",
      confirmTitle: "发送",
      isDestructive: false
    ) { [weak self] in
      await self?.runAction("feishu_test", label: "测试飞书")
    }
  }

  /// Creates a group chat and invites the owner into it. Undoing that means
  /// going into Feishu and dissolving a group, so it asks.
  func confirmDecisionOnboarding() {
    pending = PendingAction(
      title: "开始决策校准？",
      message: "会在飞书里创建（或复用）一个私有群并发一张欢迎卡片。需要飞书应用已开通 im:chat 权限。",
      confirmTitle: "开始",
      isDestructive: false
    ) { [weak self] in
      await self?.runAction("decision_onboarding_start", label: "决策校准")
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
      await self?.post("创建团队", path: "/api/team/create", body: .object(["name": .string(name)])) { $0.newTeamName = "" }
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
      await self?.post("加入团队", path: "/api/team/join", body: .object(["code": .string(code)])) { $0.joinCode = "" }
    }
  }

  func confirmLeaveTeam() {
    pending = PendingAction(
      title: "退出团队？",
      message: "退出后就看不到队友的周期了；已经同步上去的内容仍留在原团队。本机的 markdown 一个字都不会动。",
      confirmTitle: "退出",
      isDestructive: true
    ) { [weak self] in
      await self?.post("退出团队", path: "/api/team/leave", body: .object([:]))
    }
  }

  func confirmRotateInviteCode() {
    pending = PendingAction(
      title: "重新生成邀请码？",
      message: "旧邀请码立即失效，已经发出去还没用的那些都会作废。",
      confirmTitle: "重新生成",
      isDestructive: true
    ) { [weak self] in
      await self?.post("重新生成邀请码", path: "/api/team/rotate-code", body: .object([:]))
    }
  }

  func confirmTeamSignOut() {
    pending = PendingAction(
      title: "退出 Supabase 登录？",
      message: "只清掉这台机器上的团队会话，本地文件和其他功能都不受影响。注意这不是退出这个 App —— 它本来就没有登录。",
      confirmTitle: "退出",
      isDestructive: true
    ) { [weak self] in
      await self?.post("退出 Supabase", path: "/api/team/signout", body: .object([:]))
    }
  }

  func confirmClearLogs() {
    pending = PendingAction(
      title: "清空服务日志？",
      // Says what is lost, because the answer to "为什么昨天没发早报" usually
      // lives in exactly these lines and there is no second copy.
      message: "data/logs/ui-network.jsonl 会被清空。排查问题要用的那些记录也一起没了，而且没有备份。",
      confirmTitle: "清空",
      isDestructive: true
    ) { [weak self] in
      await self?.clearLogs()
    }
  }

  // MARK: Writes

  func teamSignIn() async {
    let email = teamEmail
    let password = teamPassword
    // Cleared before the request returns so the field cannot be read off screen
    // afterwards, and so a retry has to be typed rather than replayed.
    teamPassword = ""
    await post("登录 Supabase", path: "/api/team/signin", body: .object([
      "email": .string(email),
      "password": .string(password),
    ]))
  }

  func teamRefresh() async {
    await post("刷新团队", path: "/api/team/refresh", body: .object([:]))
  }

  func teamSyncNow() async {
    await post("同步周期", path: "/api/team/sync", body: .object([:]))
  }

  func loadLogs() async {
    isBusy = true
    defer { isBusy = false }
    do {
      let node = try await ServiceLink.get("/api/logs")
      logs = node["logs"].array.enumerated().map { LogRow(index: $0, node: $1) }
    } catch {
      banner = Banner(ok: false, text: "读取日志失败：\(message(from: error))")
    }
  }

  private func clearLogs() async {
    isBusy = true
    defer { isBusy = false }
    do {
      let node = try await ServiceLink.delete("/api/logs")
      logs = node["logs"].array.enumerated().map { LogRow(index: $0, node: $1) }
      banner = Banner(ok: true, text: "日志已清空。")
    } catch {
      banner = Banner(ok: false, text: "清空日志失败：\(message(from: error))")
    }
  }

  /// The one write path for config and `.env`.
  ///
  /// `POST /api/config` re-parses and rewrites the whole file, and its zod
  /// schema drops keys it does not recognise — so the config has to go back
  /// exactly as it came, with only these leaves changed. Re-reading it here
  /// rather than reusing the snapshot keeps a concurrent edit from being
  /// silently reverted by this save.
  ///
  /// Config goes first: if the env write fails, the config half is already on
  /// disk and the reload below will show it, which is a state the user can see
  /// and retry. The other order leaves a key in `.env` that no config references.
  private func save(_ what: String, _ edits: ConfigEdits) async {
    guard !edits.isEmpty else { return }
    isBusy = true
    defer { isBusy = false }
    do {
      if !edits.config.isEmpty {
        let state = try await ServiceLink.get("/api/state")
        var patched = state["config"]
        for edit in edits.config { patched = patched.setting(edit.path, to: edit.value) }
        try await ServiceLink.post("/api/config", body: .object(["config": patched]))
      }
      if !edits.env.isEmpty {
        // Only plain keys ever reach here. `saveEnv` merges over the existing
        // file, so a key left out is a key left alone.
        try await ServiceLink.post("/api/env", body: .object(["values": .object(edits.env.mapValues(JSONNode.string))]))
      }
      banner = Banner(ok: true, text: savedText(what))
      await load()
    } catch {
      banner = Banner(ok: false, text: "保存\(what)失败：\(message(from: error))")
      await load()
    }
  }

  /// Names the file that changed, per DESIGN §"保存反馈" — the only unshouty way
  /// to tell someone which of two dozen paths this button just rewrote.
  private func savedText(_ what: String) -> String {
    guard let snapshot else { return "已保存\(what)。" }
    return "已保存\(what) → \(snapshot.configPath)"
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
      sourceSecretDraft = ""
      editingSourceSecret = nil
      revealedSecret = nil
      banner = Banner(ok: true, text: "已写入 \(key)。")
      await load()
    } catch {
      // The value is not echoed into the message — an error string ends up in
      // the UI and, if the user copies it, somewhere else too.
      banner = Banner(ok: false, text: "写入 \(key) 失败：\(message(from: error))")
    }
  }

  /// The shape every simple write shares: post, report in the service's own
  /// words, reload.
  private func post(
    _ what: String,
    path: String,
    body: JSONNode,
    then cleanup: ((SettingsStore) -> Void)? = nil
  ) async {
    isBusy = true
    defer { isBusy = false }
    do {
      let response = try await ServiceLink.post(path, body: body)
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

  // MARK: Finding the service

  /// Run the search again, by hand.
  ///
  /// Useful after installing the launch agent or starting the service for the
  /// first time — both of which create exactly the evidence discovery looks for.
  func rediscoverService() async {
    isBusy = true
    defer { isBusy = false }
    guard let found = RepoRoot.discover() else {
      banner = Banner(ok: false, text: "还是没找到。服务如果从来没启动过，就还没有可找的痕迹——先在它的目录里跑一次 npm run ui。")
      return
    }
    adopt(found, how: "找到了")
    await load()
  }

  /// The escape hatch that used to be the app's front door.
  ///
  /// Everything about finding the service is automatic — the launch agent, the
  /// common folders, Spotlight. This is for the case none of them cover: two
  /// checkouts, an external disk, a folder Spotlight has not indexed. Rare, and
  /// rare is exactly what belongs in Settings rather than in front of everyone.
  func pickServiceFolder() async {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "选择"
    panel.message = "选中 daily-os 服务所在的文件夹（里面能看到 package.json 和 src 这两项）"
    guard panel.runModal() == .OK, let url = panel.url else { return }
    guard RepoRoot.looksValid(url) else {
      banner = Banner(ok: false, text: "这个文件夹里没有 daily-os 服务（找不到 package.json 和 src）。选服务代码所在的那一层。")
      return
    }
    adopt(url, how: "已指向")
    await load()
  }

  /// Remember the path and tell the rest of the app.
  ///
  /// The notification exists because this screen and the app's
  /// `ServiceConnection` cannot see each other — `DailyOSMac` has no dependency
  /// edge to `DailyOSClient`. Writing the preference alone would fix this
  /// screen's own requests and leave the window still showing "未连接", which is
  /// the kind of half-applied change that reads as the button not working.
  private func adopt(_ url: URL, how: String) {
    RepoRoot.store(url)
    NotificationCenter.default.post(name: .dailyOSRepoRootChanged, object: nil)
    banner = Banner(ok: true, text: "\(how)：\(url.lastPathComponent)")
  }

  /// Register the launch agent, through the service's own installer.
  ///
  /// `/api/action service_install` rather than writing the plist from here: the
  /// service knows its own node path, its own working directory and its own
  /// argument list, and a second copy of that knowledge in this app would be
  /// wrong the first time any of them changed.
  func installAgent() async {
    await post("装成后台任务", path: "/api/action", body: .object(["action": .string("service_install")]))
  }

  func confirmUninstallAgent() {
    pending = PendingAction(
      title: "取消开机自启？",
      message: "服务会从 launchd 注销：不再开机自启，崩了也不会自动拉起，早报和复盘这些定时任务都不会再按时跑。本地文件和配置都不动，随时可以再装回来。",
      confirmTitle: "取消自启",
      isDestructive: true
    ) { [weak self] in
      await self?.post("取消开机自启", path: "/api/action", body: .object(["action": .string("service_uninstall")]))
    }
  }

  /// Open the browser console, already signed in.
  ///
  /// `?token=` is the service's own mechanism — `resolveAuthContext` accepts the
  /// runtime token from the query string and `npm run ui:open` uses exactly this
  /// — so the alternative is presenting a login form for an account many people
  /// running this have never created.
  ///
  /// The cost is real and worth knowing: the token lands in browser history. It
  /// is a localhost URL, the service refuses non-local hostnames, and the token
  /// is regenerated on every service start, so the window is small — but it is
  /// not zero.
  func openWebConsole() {
    guard let endpoint = try? ServiceLink.endpointForConsole() else {
      banner = Banner(ok: false, text: "读不到服务地址，先确认服务在跑。")
      return
    }
    NSWorkspace.shared.open(endpoint)
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
      Task {
        await save("启用 \(what)", ConfigEdits(config: [
          ConfigEdit(path: path + ["enabled"], value: .bool(true)),
        ]))
      }
    case .chooseVaultFolder:
      Task { await chooseVaultFolder() }
    case .action(let name, _, let what):
      Task { await runAction(name, label: what) }
    case .addGitHubRepository:
      break  // The panel opens a field; `addGitHubRepository` runs on submit.
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
    guard let url = pickFolder(message: "选择 vault 知识库文件夹") else { return }
    await save("本地 Vault", ConfigEdits(config: [
      ConfigEdit(path: ["sources", "vault", "enabled"], value: .bool(true)),
      ConfigEdit(path: ["sources", "vault", "provider"], value: .string("local")),
      ConfigEdit(path: ["sources", "vault", "local_path"], value: .string(url.path(percentEncoded: false))),
    ]))
  }

  /// A folder picker that only fills a field. Nothing is written until the
  /// section's own 保存 — picking a folder and having it save itself is how you
  /// end up pointing the memory repository somewhere you were only browsing.
  func pickFolder(into field: WritableKeyPath<SettingsDraft, String>, message: String) {
    guard let url = pickFolder(message: message) else { return }
    draft[keyPath: field] = url.path(percentEncoded: false)
  }

  /// Same, for the CLI binaries, which are files rather than folders.
  func pickFile(into field: WritableKeyPath<SettingsDraft, String>, message: String) {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.showsHiddenFiles = true
    panel.prompt = "选择"
    panel.message = message
    guard panel.runModal() == .OK, let url = panel.url else { return }
    draft[keyPath: field] = url.path(percentEncoded: false)
  }

  private func pickFolder(message: String) -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.showsHiddenFiles = true
    panel.prompt = "选择"
    panel.message = message
    guard panel.runModal() == .OK else { return nil }
    return panel.url
  }

  /// Append one `owner/repo`.
  ///
  /// Appends rather than replaces, and reads the list back off the service
  /// first: this row shows a count, not the repositories themselves, so it has
  /// no business deciding what the whole list should be.
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

  /// `name | path` per line, which is the console's `parseFiles` format.
  ///
  /// A line missing either half is dropped rather than saved with an empty
  /// field: the collector opens `path`, and a row with no path is a file read
  /// that fails once a day forever with nothing on screen to explain it.
  private static func namedPaths(_ text: String) -> JSONNode {
    var rows: [JSONNode] = []
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2 else { continue }
      let name = parts[0].trimmingCharacters(in: .whitespaces)
      let path = parts[1].trimmingCharacters(in: .whitespaces)
      guard !name.isEmpty, !path.isEmpty else { continue }
      rows.append(.object(["name": .string(name), "path": .string(path)]))
    }
    return .array(rows)
  }

  private func message(from error: any Error) -> String {
    (error as? ServiceLink.Failure)?.errorDescription ?? error.localizedDescription
  }
}
