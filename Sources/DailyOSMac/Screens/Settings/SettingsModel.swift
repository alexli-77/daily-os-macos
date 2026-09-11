import Foundation
import DailyOSCore

// MARK: - Sections

/// The left column, which is the web console's nav bar with its nine buttons
/// regrouped.
///
/// Nine flat buttons was already one screen's worth of scanning, and this build
/// adds the panels the console kept inside its "Setup" accordion — model, CLI,
/// Feishu, team and skills were four fieldsets deep in one page. Grouping is
/// what keeps that from becoming a fourteen-item flat list: 配置 is what the
/// service runs on, 文档 is prose the model reads, 系统 is what you open when
/// something is wrong.
///
/// Deliberately absent: the console's per-workflow enable/time fields. Those
/// schedules are the 排程 screen's subject, and two places to set the same
/// morning time is two places that can disagree.
enum SettingsSection: String, CaseIterable, Identifiable {
  case overview
  case basics
  case model
  case feishu
  case sources
  case workflows
  case team
  case skills
  case decision
  case strategy
  case okr
  case guide
  case service
  case logs

  var id: String { rawValue }

  var title: String {
    switch self {
    case .overview: "概览"
    case .basics: "基础"
    case .model: "模型"
    case .feishu: "飞书"
    case .sources: "数据源"
    case .workflows: "工作流"
    case .team: "团队"
    case .skills: "技能"
    case .decision: "决策规则"
    case .strategy: "复盘策略"
    case .okr: "OKR"
    case .guide: "指南"
    case .service: "服务"
    case .logs: "日志"
    }
  }

  var icon: String {
    switch self {
    case .overview: "checklist"
    case .basics: "person.crop.circle"
    case .model: "cpu"
    case .feishu: "bubble.left.and.bubble.right"
    case .sources: "tray.and.arrow.down"
    case .workflows: "arrow.triangle.branch"
    case .team: "person.2"
    case .skills: "puzzlepiece.extension"
    case .decision: "text.book.closed"
    case .strategy: "doc.text"
    case .okr: "target"
    case .guide: "book"
    case .service: "gearshape.2"
    case .logs: "doc.plaintext"
    }
  }

  /// One line under the screen title, so the content area always says what it is
  /// for without the panels having to repeat it.
  var summary: String {
    switch self {
    case .overview: "自检结果，以及可以手动跑一次的动作"
    case .basics: "身份、称呼、时区、语言"
    case .model: "工作流和对话用什么跑，以及它怎么认证"
    case .feishu: "消息发出去和指令收进来的那条通道"
    case .sources: "证据从这些地方来，结论回到你的文件里"
    case .workflows: "日历桥接和后台建议；定时时间在「排程」里改"
    case .team: "各自的文件仍然在各自机器上，同步只是传输"
    case .skills: "工作流真正执行的那份 checkout"
    case .decision: "模型做决定时读的那份 markdown"
    case .strategy: "决定要务怎么生成的几个文件"
    case .okr: "五年 / 年度 / 本季三层目标的原文"
    case .guide: "怎么用；先看这里，再回去填配置"
    case .service: "本机后台服务的状态与开机自启"
    case .logs: "最近 7 天的网络与动作记录"
    }
  }

  static let configGroup: [SettingsSection] = [.overview, .basics, .model, .feishu, .sources, .workflows, .team, .skills]
  static let documentGroup: [SettingsSection] = [.decision, .strategy, .okr, .guide]
  static let systemGroup: [SettingsSection] = [.service, .logs]
}

// MARK: - Snapshot

struct SettingsSnapshot {
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
  var feishuProfiles: [FeishuProfileRow]
  var background: BackgroundRow
  var decisionPolicy: DecisionPolicyRow
  var strategy: [StrategyFileRow]
  var defaultStrategy: String
  var okrDir: String
  var okr: [OkrFileRow]
  /// Whether `team.supabase_anon_key` has a value. The value itself is never
  /// read into this app: the panel offers to replace it, not to look at it.
  var supabaseKeyPresent: Bool
  var supabaseURL: String
  /// `caffeinate` while the service runs. Read from the snapshot rather than the
  /// draft because its switch writes on the flip — a draft copy would show the
  /// new position for the half-second before the service confirmed it.
  var preventSleep: Bool
}

struct DoctorRow: Identifiable {
  let name: String
  let ok: Bool
  let level: String
  let detail: String

  var id: String { name }

  /// The service distinguishes "failed" from "passed with a caveat"; a warning
  /// is still working, and calling it 未配置 would be as wrong as calling it fine.
  var status: SourceStatusKind {
    if !ok { return .trouble }
    return level == "warning" ? .trouble : .connected
  }

  var text: String { detail.isEmpty ? name : detail }

  var tone: Tone {
    if !ok { return .danger }
    return level == "warning" ? .warn : .ok
  }

  var label: String {
    if !ok { return "失败" }
    return level == "warning" ? "警告" : "通过"
  }
}

/// Four values, not two. The service reports nothing at all about some sources,
/// and 未知 is the only honest label for those — collapsing it into 未配置 would
/// be a guess and collapsing it into 已连接 would be a lie.
enum SourceStatusKind {
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

struct SourceRow: Identifiable {
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
enum SourceFix: Equatable {
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
enum APIKeyRequirement {
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

struct SkillRow: Identifiable {
  let id: String
  let provider: String
  let path: String
  let defaultMode: String
}

struct SkillRepoRow {
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

struct TeamRow {
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

struct ServiceRow {
  let label: String
  let plistPath: String
  let installed: Bool
  let registered: Bool
}

/// One `sources.feishu.profiles[]` entry, read-only.
///
/// A profile is four nested collectors plus a document list, and
/// `JSONNode.setting` addresses object keys, not array indices — so this app
/// cannot edit one leaf of one profile without rewriting the array from a model
/// it does not fully own. Rewriting it from a partial model is exactly how the
/// `docs.documents` list would quietly lose entries this build never learned to
/// display, so profiles are shown and not edited.
struct FeishuProfileRow: Identifiable {
  let id: String
  let label: String
  let enabled: Bool
  let identity: String
  let collectors: [String]
  let documentCount: Int
}

struct BackgroundRow {
  let lastStatus: String
  let lastError: String
  let nextRunAt: Date?

  var statusTone: Tone {
    switch lastStatus {
    case "ok", "sent": .ok
    case "error": .danger
    case "": .neutral
    default: .warn
    }
  }

  var line: String {
    let status = lastStatus.isEmpty ? "还没跑过" : lastStatus
    guard let nextRunAt else { return status }
    return "\(status)；下次 \(Fmt.stamp(nextRunAt))"
  }
}

struct DecisionPolicyRow {
  let repositoryPath: String
  let notesPath: String
  let markdown: String
}

struct StrategyFileRow: Identifiable {
  let id: String
  let label: String
  let hint: String
  let path: String
  let exists: Bool
  let markdown: String
}

struct OkrFileRow: Identifiable {
  let id: String
  let label: String
  let fileName: String
  let path: String
  let markdown: String
}

struct LogRow: Identifiable {
  let id: Int
  let time: String
  let summary: String
  let detail: String
  let status: String
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
    status = node["status"].string
    tone = switch node["level"].string {
    case "error": .danger
    case "warning": .warn
    default: .neutral
    }
  }
}

// MARK: - Draft

/// Every editable field on the screen, in one value.
///
/// Held here rather than as `@State` inside each panel because a reload has to
/// reseed all of them at once: `POST /api/config` answers with the whole file it
/// just wrote, and a panel holding its own copy would keep showing what the user
/// typed even when the service normalised or rejected it. Being one `Equatable`
/// value is also what lets each section decide whether it is dirty without
/// tracking a flag per field.
///
/// Secrets are deliberately not in here. They are never read into a draft, never
/// compared, and never round-tripped through a save — see `SettingsStore`.
struct SettingsDraft: Equatable {
  // 基础
  var displayName = ""
  var timezone = ""
  var language = ""

  // 模型
  var provider = ""
  var model = ""
  var modelSelection = ""
  var codexBin = ""
  var codexHome = ""
  var claudeBin = ""

  // 飞书
  var outputEnabled = false
  var outputProvider = "auto"
  var outputSendMode = "markdown"
  var feedbackEnabled = false
  var feedbackPrefix = ""
  var feedbackPollLimit = 20
  var larkAppID = ""
  var feishuChatID = ""
  var ownerOpenID = ""
  var interactionEnabled = false
  var interactionPrefix = ""
  var interactionReplyMode = "markdown"
  var interactionDebounce = 600
  var interactionRequireMention = false
  var interactionAccessLevel = "read_only"
  var interactionAdmins = ""
  var interactionUsers = ""
  var interactionChats = ""
  var interactionWorkspaces = ""
  var decisionChatName = ""
  var decisionChatID = ""
  var decisionAutoCreate = false

  // 数据源
  var vaultEnabled = false
  var vaultProvider = "local"
  var vaultLocalPath = ""
  var vaultGateURL = ""
  var memoryRepositoryPath = ""
  var memoryLongTermPath = ""
  var memoryDailyDir = ""
  var feishuSourceEnabled = false
  var githubEnabled = false
  var githubRepositories = ""
  var githubPerRepoLimit = 20
  var linearEnabled = false
  var linearAssignee = ""
  var linearActiveCycleOnly = false
  var linearQuery = ""
  var linearProjectsAllow = ""
  var linearProjectsBlock = ""
  var linearTeamsAllow = ""
  var linearTeamsBlock = ""
  var chromeSnapshotEnabled = false
  var appleCalendarEnabled = false
  var localFilesEnabled = false
  var localFiles = ""

  // 工作流
  var calendarEnabled = false
  var calendarMode = "auto"
  var calendarCommand = ""
  var calendarWorkdir = ""
  var calendarCLIPath = ""
  var calendarPolicyFile = ""
  var calendarRoutinesFile = ""
  var calendarWeekDays = 5
  var calendarMaxTasks = 8
  var backgroundEnabled = false
  var backgroundMode = "review"
  var backgroundInterval = 120
  var backgroundConfidence = "medium"
  var backgroundSendFeishu = true
  var backgroundChangeOnly = true

  // 团队
  var supabaseURL = ""

  // 文档
  var decisionPolicyMd = ""
  var strategyFileID = ""
  var strategyMd = ""
  var okrMarkdown: [String: String] = [:]

  init() {}

  init(snapshot: SettingsSnapshot, config: JSONNode, env: JSONNode) {
    displayName = config["user"]["display_name"].string
    timezone = config["user"]["timezone"].string
    language = config["assistant"]["language"].string

    provider = snapshot.llmProvider
    model = snapshot.llmModel
    // Always the configured id, never the custom sentinel: `modelOptions`
    // injects an unrecognised current value as a real row, so there is always
    // something to select. Starting in custom mode instead would present the
    // saved model as though the user had typed it, and the first save would
    // turn a value the app simply had not heard of into a hand-entered one.
    modelSelection = model
    codexBin = env["CODEX_BIN"].string
    codexHome = env["CODEX_HOME"].string
    claudeBin = env["CLAUDE_BIN"].string

    let output = config["output"]["feishu"]
    outputEnabled = output["enabled"].bool
    outputProvider = output["provider"].string.isEmpty ? "auto" : output["provider"].string
    outputSendMode = output["send_mode"].string.isEmpty ? "markdown" : output["send_mode"].string
    let feedback = config["feedback"]["feishu"]
    feedbackEnabled = feedback["enabled"].bool
    feedbackPrefix = feedback["command_prefix"].string
    feedbackPollLimit = feedback["poll_limit"].int ?? 20
    larkAppID = env["LARK_APP_ID"].string
    feishuChatID = env["FEISHU_CHAT_ID"].string
    ownerOpenID = env["FEISHU_OWNER_OPEN_ID"].string
    let interaction = config["interaction"]["feishu"]
    interactionEnabled = interaction["enabled"].bool
    interactionPrefix = interaction["command_prefix"].string
    interactionReplyMode = interaction["reply_mode"].string.isEmpty ? "markdown" : interaction["reply_mode"].string
    interactionDebounce = interaction["debounce_ms"].int ?? 600
    interactionRequireMention = interaction["require_mention_in_groups"].bool
    let security = interaction["security"]
    interactionAccessLevel = security["access_level"].string.isEmpty ? "read_only" : security["access_level"].string
    interactionAdmins = security["admin_open_ids"].lineText
    interactionUsers = security["allowed_user_open_ids"].lineText
    interactionChats = security["allowed_chat_ids"].lineText
    interactionWorkspaces = security["allowed_workspaces"].lineText
    decisionChatName = config["decision"]["onboarding"]["chat_name"].string
    decisionChatID = env["DAILY_OS_DECISION_CHAT_ID"].string
    decisionAutoCreate = config["decision"]["onboarding"]["auto_create_on_setup"].bool

    let vault = config["sources"]["vault"]
    vaultEnabled = vault["enabled"].bool
    vaultProvider = vault["provider"].string.isEmpty ? "local" : vault["provider"].string
    vaultLocalPath = vault["local_path"].string
    vaultGateURL = env["VAULT_GATE_URL"].string
    memoryRepositoryPath = config["memory"]["repository_path"].string
    memoryLongTermPath = config["memory"]["long_term_path"].string
    memoryDailyDir = config["memory"]["daily_dir"].string
    feishuSourceEnabled = config["sources"]["feishu"]["enabled"].bool
    let github = config["sources"]["github"]
    githubEnabled = github["enabled"].bool
    githubRepositories = github["repositories"].lineText
    githubPerRepoLimit = github["per_repo_limit"].int ?? 20
    let linear = config["sources"]["linear"]
    linearEnabled = linear["enabled"].bool
    linearAssignee = linear["assignee"].string
    linearActiveCycleOnly = linear["active_cycle_only"].bool
    linearQuery = linear["query"].string
    linearProjectsAllow = linear["projects_allowlist"].lineText
    linearProjectsBlock = linear["projects_blocklist"].lineText
    linearTeamsAllow = linear["teams_allowlist"].lineText
    linearTeamsBlock = linear["teams_blocklist"].lineText
    chromeSnapshotEnabled = config["sources"]["chrome_snapshot"]["enabled"].bool
    appleCalendarEnabled = config["sources"]["apple_calendar_snapshot"]["enabled"].bool
    localFilesEnabled = config["sources"]["local_files"]["enabled"].bool
    localFiles = config["sources"]["local_files"]["files"].array
      .map { "\($0["name"].string) | \($0["path"].string)" }
      .joined(separator: "\n")

    let calendar = config["calendar"]
    calendarEnabled = calendar["enabled"].bool
    calendarMode = calendar["engine"]["mode"].string.isEmpty ? "auto" : calendar["engine"]["mode"].string
    calendarCommand = calendar["engine"]["command"].string
    calendarWorkdir = calendar["engine"]["workdir"].string
    calendarCLIPath = calendar["engine"]["cli_path"].string
    calendarPolicyFile = calendar["engine"]["policy_file"].string
    calendarRoutinesFile = calendar["engine"]["routines_file"].string
    calendarWeekDays = calendar["draft"]["week_days"].int ?? 5
    calendarMaxTasks = calendar["draft"]["max_tasks"].int ?? 8
    let background = config["background_suggestions"]
    backgroundEnabled = background["enabled"].bool
    backgroundMode = background["mode"].string.isEmpty ? "review" : background["mode"].string
    backgroundInterval = background["interval_minutes"].int ?? 120
    backgroundConfidence = background["min_confidence"].string.isEmpty ? "medium" : background["min_confidence"].string
    backgroundSendFeishu = background["send_to_feishu"].bool
    backgroundChangeOnly = background["send_on_change_only"].bool

    supabaseURL = snapshot.supabaseURL

    decisionPolicyMd = snapshot.decisionPolicy.markdown
    strategyFileID = snapshot.strategy.first?.id ?? ""
    strategyMd = snapshot.strategy.first?.markdown ?? ""
    okrMarkdown = Dictionary(uniqueKeysWithValues: snapshot.okr.map { ($0.id, $0.markdown) })
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
enum ModelCatalog {
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

extension SettingsSnapshot {
  /// Built from a JSON tree rather than from a mirror of the config schema.
  ///
  /// This screen reads about a hundred leaves out of an object with twenty-two
  /// top-level config keys, and a typed mirror would fail the entire screen over
  /// one renamed key it does not even display. Reading leaves also means the
  /// config can be handed back to `POST /api/config` byte-identical, which that
  /// endpoint requires — see `SettingsStore.save`.
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
    feishuProfiles = config["sources"]["feishu"]["profiles"].array.enumerated().map { index, profile in
      let collectors = [
        profile["calendar"]["enabled"].bool ? "日历" : nil,
        profile["tasks"]["enabled"].bool ? "任务" : nil,
        profile["docs"]["enabled"].bool ? "文档" : nil,
        profile["im_history"]["enabled"].bool ? "群聊" : nil,
      ].compactMap { $0 }
      let id = profile["id"].string
      return FeishuProfileRow(
        id: id.isEmpty ? "profile-\(index)" : id,
        label: profile["label"].string.isEmpty ? id : profile["label"].string,
        enabled: profile["enabled"].bool,
        identity: profile["identity"].string,
        collectors: collectors,
        documentCount: profile["docs"]["documents"].array.count
      )
    }
    let background = node["backgroundSuggestions"]
    self.background = BackgroundRow(
      lastStatus: background["last_status"].string,
      lastError: background["last_error"].string,
      nextRunAt: WireDate.parse(background["next_run_at"].string)
    )
    decisionPolicy = DecisionPolicyRow(
      repositoryPath: node["decisionPolicy"]["repositoryPath"].string,
      notesPath: node["decisionPolicy"]["notesPath"].string,
      markdown: node["decisionPolicy"]["policyMd"].string
    )
    strategy = node["strategy"]["files"].array.map {
      StrategyFileRow(
        id: $0["id"].string,
        label: $0["label"].string,
        hint: $0["hint"].string,
        path: $0["path"].string,
        exists: $0["exists"].bool,
        markdown: $0["markdown"].string
      )
    }
    defaultStrategy = node["strategy"]["defaultStrategy"].string
    okrDir = node["okr"]["dir"].string
    okr = node["okr"]["files"].array.map {
      OkrFileRow(
        id: $0["level"].string,
        label: $0["label"].string,
        fileName: $0["fileName"].string,
        path: $0["path"].string,
        markdown: $0["markdown"].string
      )
    }
    supabaseURL = config["team"]["supabase_url"].string
    // Presence, not the value. `/api/state` does hand the anon key back in
    // plaintext — it is a public key by design — but a settings screen that
    // prints one teaches the habit that puts a service_role key on screen next.
    supabaseKeyPresent = !config["team"]["supabase_anon_key"].string.isEmpty
    preventSleep = config["service"]["prevent_sleep"]["enabled"].bool
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

extension TeamRow {
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
enum WireDate {
  private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
  private static let withoutFraction = Date.ISO8601FormatStyle()

  static func parse(_ raw: String) -> Date? {
    guard !raw.isEmpty else { return nil }
    return (try? Date(raw, strategy: withFraction)) ?? (try? Date(raw, strategy: withoutFraction))
  }
}
