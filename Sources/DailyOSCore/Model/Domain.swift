import Foundation

// The domain, as the UI needs to see it.
//
// These types mirror what the daily-os service already produces — cycle
// markdown with three independently-sourced sections, the todo inbox, the OKR
// snapshot, the workflow run ledger, the artifact index, launchd schedules. They
// are intentionally plain value types with no networking: this repository is the
// shell, and the private release repository supplies the real data by replacing
// `AppState`'s store. See README §"How the private repo consumes this".

// MARK: - Service & account

public enum ServiceState: String, Sendable, CaseIterable {
  case running
  case stopped
  /// Up, but something it depends on is not — Supabase unreachable, a provider
  /// key missing, the vault path gone.
  case degraded

  public var tone: Tone {
    switch self {
    case .running: .ok
    case .degraded: .warn
    case .stopped: .danger
    }
  }

  public var label: String {
    switch self {
    case .running: "运行中"
    case .degraded: "降级运行"
    case .stopped: "已停止"
    }
  }
}

public struct ServiceStatus: Sendable, Equatable {
  public var state: ServiceState
  public var endpoint: String
  public var uptime: Duration
  /// Present when `state == .degraded`; this is what the status strip explains.
  public var note: String?

  public init(state: ServiceState, endpoint: String, uptime: Duration, note: String? = nil) {
    self.state = state
    self.endpoint = endpoint
    self.uptime = uptime
    self.note = note
  }
}

public enum Role: String, Sendable {
  case owner
  case admin
  case member

  /// Only the owner sees the configuration surface — hiding the controls is
  /// presentation; the service still enforces it.
  public var canConfigure: Bool { self == .owner || self == .admin }

  /// The on-screen name. `rawValue` is the wire format and stays English.
  public var label: String {
    switch self {
    case .owner: "所有者"
    case .admin: "管理员"
    case .member: "成员"
    }
  }
}

public struct Account: Sendable, Equatable, Identifiable {
  public let id: String
  public var displayName: String
  public var email: String
  public var role: Role
  /// Assigned once at registration and stored — never derived from the name.
  public var avatarSeed: String

  public init(id: String, displayName: String, email: String, role: Role, avatarSeed: String) {
    self.id = id
    self.displayName = displayName
    self.email = email
    self.role = role
    self.avatarSeed = avatarSeed
  }
}

public struct TeamMember: Sendable, Equatable, Identifiable {
  public let id: String
  public var displayName: String
  public var avatarSeed: String
  public var isSelf: Bool
  public var lastSyncedAt: Date?

  public init(id: String, displayName: String, avatarSeed: String, isSelf: Bool, lastSyncedAt: Date?) {
    self.id = id
    self.displayName = displayName
    self.avatarSeed = avatarSeed
    self.isSelf = isSelf
    self.lastSyncedAt = lastSyncedAt
  }
}

// MARK: - Cycles

public enum CycleMode: String, Sendable, CaseIterable {
  case weekly
  case biweekly

  public var label: String {
    switch self {
    case .weekly: "单周"
    case .biweekly: "双周"
    }
  }
}

/// Who last wrote a section. Surfacing this is the whole point of LEO-279: a
/// planner rerun must never silently overwrite something you typed.
public enum SectionSource: String, Sendable {
  case planner
  case user
  case ai

  public var label: String {
    switch self {
    case .planner: "自动规划"
    case .user: "手工编辑"
    case .ai: "AI"
    }
  }

  public var tone: Tone {
    switch self {
    case .planner: .accent
    case .user: .neutral
    case .ai: .warn
    }
  }
}

public enum CycleSectionKind: String, Sendable, CaseIterable, Identifiable {
  case priorities
  case retro
  case review

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .priorities: "要务"
    case .retro: "复盘"
    case .review: "总结"
    }
  }

  public var hint: String {
    switch self {
    case .priorities: "这一期打算做完的事。自动规划生成，你可以随时改。"
    case .retro: "这一期实际发生了什么。手写为主。"
    case .review: "对比计划与执行之后的结论。"
    }
  }
}

public struct CycleSection: Sendable, Equatable, Identifiable {
  public let kind: CycleSectionKind
  public var body: String
  public var source: SectionSource
  public var updatedAt: Date
  /// A newer planner draft that is *not* being applied because the section was
  /// edited by hand. The UI shows it side by side and lets you merge.
  public var pendingDraft: String?
  /// Still the placeholder the service seeds a new section with.
  ///
  /// Worth a badge rather than nothing: an untouched template reads exactly
  /// like real content at a glance, and "why is my cycle full of things I never
  /// wrote" is a confusing five minutes.
  public var isTemplate: Bool

  public var id: String { kind.rawValue }

  public init(
    kind: CycleSectionKind,
    body: String,
    source: SectionSource,
    updatedAt: Date,
    pendingDraft: String? = nil,
    isTemplate: Bool = false
  ) {
    self.kind = kind
    self.body = body
    self.source = source
    self.updatedAt = updatedAt
    self.pendingDraft = pendingDraft
    self.isTemplate = isTemplate
  }

  /// The 要务 body, parsed into groups. Empty for the other two sections, which
  /// are prose and stay prose.
  public var priorities: PrioritiesDocument {
    kind == .priorities ? PrioritiesDocument(markdown: body) : PrioritiesDocument(markdown: "")
  }
}

public struct Cycle: Sendable, Equatable, Identifiable {
  public let id: String
  /// The human label the whole system uses: "8.24-9.6".
  public var label: String
  public var mode: CycleMode
  public var start: Date
  public var end: Date
  public var ownerId: String
  public var runId: String?
  public var sections: [CycleSection]
  public var updatedAt: Date

  public init(
    id: String,
    label: String,
    mode: CycleMode,
    start: Date,
    end: Date,
    ownerId: String,
    runId: String?,
    sections: [CycleSection],
    updatedAt: Date
  ) {
    self.id = id
    self.label = label
    self.mode = mode
    self.start = start
    self.end = end
    self.ownerId = ownerId
    self.runId = runId
    self.sections = sections
    self.updatedAt = updatedAt
  }

  public func section(_ kind: CycleSectionKind) -> CycleSection? {
    sections.first { $0.kind == kind }
  }

  public var hasPendingDraft: Bool {
    sections.contains { $0.pendingDraft != nil }
  }

  /// `20_CYCLES/2026-08-24_8.24-9.6.md` — shown verbatim, because the file *is*
  /// the source of truth and people go and open it.
  public var relativePath: String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    return "20_CYCLES/\(formatter.string(from: start))_\(label).md"
  }
}

// MARK: - Todos

public enum TodoKind: String, Sendable {
  case priority
  case schedule
  case habit

  public var label: String {
    switch self {
    case .priority: "要务"
    case .schedule: "日程"
    case .habit: "习惯"
    }
  }

  public var tone: Tone {
    switch self {
    case .priority: .accent
    case .schedule: .neutral
    case .habit: .neutral
    }
  }
}

public enum TodoState: String, Sendable {
  case open
  case done
  case deferred
}

public struct TodoItem: Sendable, Equatable, Identifiable {
  public let id: String
  public var text: String
  public var kind: TodoKind
  public var due: Date?
  public var state: TodoState
  /// e.g. `LEO-287` — the evidence link back to Linear.
  public var sourceRef: String?
  /// How long the planner thinks this needs.
  ///
  /// A *suggestion*, not a commitment — the Today screen shows it so the day
  /// has a shape, and so that "four priorities" can be recognised as six hours
  /// of work before the day starts rather than after it fails. Optional because
  /// habits and short captures do not carry one.
  public var estimatedMinutes: Int?

  public init(
    id: String,
    text: String,
    kind: TodoKind,
    due: Date? = nil,
    state: TodoState = .open,
    sourceRef: String? = nil,
    estimatedMinutes: Int? = nil
  ) {
    self.id = id
    self.text = text
    self.kind = kind
    self.due = due
    self.state = state
    self.sourceRef = sourceRef
    self.estimatedMinutes = estimatedMinutes
  }
}

/// What the Today screen puts across the top.
///
/// Replaces the token / cost / in-flight tiles that used to sit there. Those
/// were about the machine; this is about the day. Cost still exists — it lives
/// on the Runs screen, which is where you go when you are asking about the
/// machine.
public struct DayProgress: Sendable, Equatable {
  public let done: Int
  public let target: Int
  /// Suggested minutes across everything still open.
  public let plannedMinutes: Int
  public let remainingMinutes: Int

  public init(done: Int, target: Int, plannedMinutes: Int, remainingMinutes: Int) {
    self.done = done
    self.target = target
    self.plannedMinutes = plannedMinutes
    self.remainingMinutes = remainingMinutes
  }

  public var fraction: Double {
    target > 0 ? min(Double(done) / Double(target), 1) : 0
  }

  /// Deliberately not a percentage of *time*. Hours spent is not progress, and
  /// a bar that fills as the day burns down would say the opposite of what it
  /// looks like it says.
  public var isComplete: Bool { target > 0 && done >= target }
}

// MARK: - OKR

public enum KeyResultHealth: String, Sendable {
  case onTrack
  case atRisk
  case off

  public var label: String {
    switch self {
    case .onTrack: "在轨"
    case .atRisk: "有风险"
    case .off: "脱轨"
    }
  }

  public var tone: Tone {
    switch self {
    case .onTrack: .ok
    case .atRisk: .warn
    case .off: .danger
    }
  }
}

public struct KeyResult: Sendable, Equatable, Identifiable {
  public let id: String
  public var title: String
  public var priority: String
  public var progress: Double
  public var detail: String?
  public var health: KeyResultHealth

  public init(
    id: String,
    title: String,
    priority: String,
    progress: Double,
    detail: String? = nil,
    health: KeyResultHealth
  ) {
    self.id = id
    self.title = title
    self.priority = priority
    self.progress = progress
    self.detail = detail
    self.health = health
  }
}

public struct Objective: Sendable, Equatable, Identifiable {
  public let id: String
  public var title: String
  public var keyResults: [KeyResult]

  public init(id: String, title: String, keyResults: [KeyResult]) {
    self.id = id
    self.title = title
    self.keyResults = keyResults
  }

  public var progress: Double {
    guard !keyResults.isEmpty else { return 0 }
    return keyResults.reduce(0) { $0 + $1.progress } / Double(keyResults.count)
  }
}

public struct OkrFile: Sendable, Equatable, Identifiable {
  public let id: String
  public var label: String
  public var fileName: String
  public var objectives: [Objective]

  public init(id: String, label: String, fileName: String, objectives: [Objective]) {
    self.id = id
    self.label = label
    self.fileName = fileName
    self.objectives = objectives
  }
}

// MARK: - Runs

public enum RunState: String, Sendable {
  case running
  case succeeded
  case failed
  case canceled

  public var label: String {
    switch self {
    case .running: "运行中"
    case .succeeded: "成功"
    case .failed: "失败"
    case .canceled: "已取消"
    }
  }

  public var tone: Tone {
    switch self {
    case .running: .accent
    case .succeeded: .ok
    case .failed: .danger
    case .canceled: .neutral
    }
  }
}

public enum RunStepKind: String, Sendable {
  case plan
  case tool
  case write
  case confirm

  public var icon: String {
    switch self {
    case .plan: "list.bullet.rectangle"
    case .tool: "wrench.and.screwdriver"
    case .write: "square.and.pencil"
    case .confirm: "hand.raised"
    }
  }
}

public struct RunStep: Sendable, Equatable, Identifiable {
  public let id: String
  public var title: String
  public var kind: RunStepKind
  public var duration: Duration
  public var detail: String?

  public init(id: String, title: String, kind: RunStepKind, duration: Duration, detail: String? = nil) {
    self.id = id
    self.title = title
    self.kind = kind
    self.duration = duration
    self.detail = detail
  }
}

public struct WorkflowRun: Sendable, Equatable, Identifiable {
  public let id: String
  public var workflow: String
  public var startedAt: Date
  public var duration: Duration
  public var state: RunState
  public var promptTokens: Int
  public var completionTokens: Int
  public var costUSD: Double
  public var steps: [RunStep]
  /// 0…1 while running.
  public var progress: Double?

  public init(
    id: String,
    workflow: String,
    startedAt: Date,
    duration: Duration,
    state: RunState,
    promptTokens: Int,
    completionTokens: Int,
    costUSD: Double,
    steps: [RunStep],
    progress: Double? = nil
  ) {
    self.id = id
    self.workflow = workflow
    self.startedAt = startedAt
    self.duration = duration
    self.state = state
    self.promptTokens = promptTokens
    self.completionTokens = completionTokens
    self.costUSD = costUSD
    self.steps = steps
    self.progress = progress
  }

  public var totalTokens: Int { promptTokens + completionTokens }
}

// MARK: - Artifacts

public enum ArtifactType: String, Sendable {
  case markdown
  case json
  case image
  case csv
  case pdf

  public var icon: String {
    switch self {
    case .markdown: "doc.text"
    case .json: "curlybraces"
    case .image: "photo"
    case .csv: "tablecells"
    case .pdf: "doc.richtext"
    }
  }

  public var isPreviewable: Bool {
    switch self {
    case .markdown, .json, .csv, .image: true
    case .pdf: false
    }
  }

  /// Format names stay as they are written everywhere else; only the one that
  /// is a common noun rather than a format gets translated.
  public var label: String {
    switch self {
    case .markdown: "Markdown"
    case .json: "JSON"
    case .image: "图片"
    case .csv: "CSV"
    case .pdf: "PDF"
    }
  }
}

public struct Artifact: Sendable, Equatable, Identifiable {
  public let id: String
  public var name: String
  public var type: ArtifactType
  public var byteSize: Int
  public var createdAt: Date
  public var runId: String?
  public var preview: String?

  public init(
    id: String,
    name: String,
    type: ArtifactType,
    byteSize: Int,
    createdAt: Date,
    runId: String?,
    preview: String?
  ) {
    self.id = id
    self.name = name
    self.type = type
    self.byteSize = byteSize
    self.createdAt = createdAt
    self.runId = runId
    self.preview = preview
  }
}

// MARK: - Schedules

public struct ScheduleEntry: Sendable, Equatable, Identifiable {
  public let id: String
  public var label: String
  public var workflow: String
  /// Human form ("每天 08:30"), with `cron` kept for the detail row.
  public var cadence: String
  public var cron: String
  public var enabled: Bool
  public var lastRun: Date?
  public var nextRun: Date?

  public init(
    id: String,
    label: String,
    workflow: String,
    cadence: String,
    cron: String,
    enabled: Bool,
    lastRun: Date?,
    nextRun: Date?
  ) {
    self.id = id
    self.label = label
    self.workflow = workflow
    self.cadence = cadence
    self.cron = cron
    self.enabled = enabled
    self.lastRun = lastRun
    self.nextRun = nextRun
  }
}

// MARK: - Chat

public enum ChatRole: String, Sendable {
  case user
  case assistant
}

public struct ToolCall: Sendable, Equatable, Identifiable {
  public let id: String
  public var name: String
  public var summary: String
  public var duration: Duration
  public var failed: Bool

  public init(id: String, name: String, summary: String, duration: Duration, failed: Bool = false) {
    self.id = id
    self.name = name
    self.summary = summary
    self.duration = duration
    self.failed = failed
  }
}

public struct ChatMessage: Sendable, Equatable, Identifiable {
  public let id: String
  public var role: ChatRole
  public var text: String
  public var sentAt: Date
  /// Shown as a collapsed trace under the reply. The point of daily-os is that
  /// the agent loop is inspectable, so this is a first-class part of the bubble
  /// rather than something buried in a log screen.
  public var toolCalls: [ToolCall]
  public var isStreaming: Bool

  public init(
    id: String,
    role: ChatRole,
    text: String,
    sentAt: Date,
    toolCalls: [ToolCall] = [],
    isStreaming: Bool = false
  ) {
    self.id = id
    self.role = role
    self.text = text
    self.sentAt = sentAt
    self.toolCalls = toolCalls
    self.isStreaming = isStreaming
  }
}

public struct ChatThread: Sendable, Equatable, Identifiable {
  public let id: String
  public var title: String
  public var updatedAt: Date
  public var messages: [ChatMessage]

  public init(id: String, title: String, updatedAt: Date, messages: [ChatMessage]) {
    self.id = id
    self.title = title
    self.updatedAt = updatedAt
    self.messages = messages
  }
}

// MARK: - Connected sources

public struct SourceConnection: Sendable, Equatable, Identifiable {
  public let id: String
  public var name: String
  public var icon: String
  public var connected: Bool
  public var detail: String

  public init(id: String, name: String, icon: String, connected: Bool, detail: String) {
    self.id = id
    self.name = name
    self.icon = icon
    self.connected = connected
    self.detail = detail
  }
}
