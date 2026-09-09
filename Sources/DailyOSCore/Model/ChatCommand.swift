import Foundation

/// The commands the service actually accepts.
///
/// Mirrors `BARE_COMMAND_KEYWORDS` and `COMMAND_ALIASES` in the service's
/// `src/ui/chat.ts`. These are typed bare — the console auto-completes them
/// into the full prefixed command — so the client's job is only to make them
/// discoverable. Before this existed you had to already know the word.
public struct ChatCommand: Sendable, Equatable, Identifiable {
  public let keyword: String
  public let label: String
  public let detail: String

  public var id: String { keyword }

  public init(keyword: String, label: String, detail: String) {
    self.keyword = keyword
    self.label = label
    self.detail = detail
  }

  /// Shown as chips above the composer. Deliberately not the full list from the
  /// service — the writeback confirmations (`确认写回`, `确认写入 review`) are
  /// replies to something the agent asked, not things you open a conversation
  /// with, and putting them in the palette invites running them out of order.
  public static let palette: [ChatCommand] = [
    ChatCommand(keyword: "plan", label: "计划", detail: "生成这一期的要务草稿"),
    ChatCommand(keyword: "review", label: "复盘", detail: "对比计划与执行，写出结论"),
    ChatCommand(keyword: "双周复盘", label: "双周复盘", detail: "跑 weekly-review 的双周模式"),
    ChatCommand(keyword: "weekly", label: "周报", detail: "生成本周周报"),
    ChatCommand(keyword: "progress", label: "进度", detail: "当前周期的完成情况"),
    ChatCommand(keyword: "status", label: "状态", detail: "服务与调度的健康状况"),
    ChatCommand(keyword: "help", label: "帮助", detail: "列出全部可用指令"),
  ]
}

/// Whether free-form conversation is on.
///
/// The service supports it — it is gated behind
/// `interaction.feishu.agent_mode.enabled`, and when the flag is off any
/// non-command message comes back with a refusal. That refusal arrives *after*
/// you have typed and sent, which is the wrong time to learn it. The client
/// shows the state up front and points at the switch instead.
public enum AgentMode: Sendable, Equatable {
  case enabled
  case disabled

  public var allowsFreeChat: Bool { self == .enabled }
}
