import SwiftUI
import DailyOSCore

/// Chat, with the agent loop showing.
///
/// The differentiator of daily-os is not that it answers, it is that you can see
/// *what it read* before answering. So the tool trace is part of the reply
/// bubble — collapsed by default, one click away — rather than something you go
/// and find in a log screen afterwards. A reply with no visible trace is a reply
/// you have to take on faith, which is the failure mode this product exists to
/// avoid.
struct ChatScreen: View {
  var body: some View {
    HStack(spacing: 0) {
      ListColumn(width: 260) { ThreadList() }
      Conversation().frame(maxWidth: .infinity)
    }
    .background(Palette.paper)
  }
}

// MARK: - Threads

private struct ThreadList: View {
  @Environment(AppState.self) private var state
  @State private var hovered: ChatThread.ID?
  @State private var pendingDelete: ChatThread?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("对话").inkStyle(Typo.heading)
        Spacer()
        Button { state.newThread() } label: { Image(systemName: "square.and.pencil") }
          .buttonStyle(.plain)
          .foregroundStyle(Palette.moss)
          .help("新对话")
      }
      .padding(Metrics.sm)
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(state.threads) { thread in
            SelectableRow(isSelected: thread.id == state.selectedThread?.id) {
              state.selectedThreadID = thread.id
            } content: {
              HStack(spacing: Metrics.xs) {
                VStack(alignment: .leading, spacing: Metrics.xxs) {
                  Text(thread.title).inkStyle().lineLimit(1)
                  Text(Fmt.stamp(thread.updatedAt)).mutedStyle()
                }
                Spacer(minLength: 0)
                // Revealed on hover rather than always present: a delete
                // control on every row in a list you scroll is a control you
                // eventually hit by accident.
                if hovered == thread.id {
                  Button { pendingDelete = thread } label: {
                    Image(systemName: "trash")
                  }
                  .buttonStyle(.plain)
                  .foregroundStyle(Palette.inkMuted)
                  .help("删除对话")
                }
              }
            }
            .onHover { hovered = $0 ? thread.id : (hovered == thread.id ? nil : hovered) }
            .contextMenu {
              Button("删除对话", role: .destructive) { pendingDelete = thread }
            }
          }
        }
        .padding(Metrics.xs)
      }
    }
    .confirmationDialog(
      "删除「\(pendingDelete?.title ?? "")」？",
      isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
      titleVisibility: .visible
    ) {
      Button("删除", role: .destructive) {
        if let thread = pendingDelete { state.deleteThread(thread.id) }
        pendingDelete = nil
      }
      Button("取消", role: .cancel) { pendingDelete = nil }
    } message: {
      Text("对话和它的工具调用记录会一起删除，无法撤销。")
    }
  }
}

// MARK: - Conversation

private struct Conversation: View {
  @Environment(AppState.self) private var state

  var body: some View {
    VStack(spacing: 0) {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: Metrics.md) {
          if let thread = state.selectedThread, !thread.messages.isEmpty {
            ForEach(thread.messages) { MessageBubble(message: $0) }
          } else {
            EmptyChatState()
          }
        }
        .padding(Metrics.screenPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(Palette.paper)
      Composer()
    }
  }
}

/// The empty conversation.
///
/// What goes here depends on whether free chat is on, because the two states
/// want opposite things from you: with agent mode on, a good opening is a
/// question; with it off, the only thing that will work is one of seven words.
/// Showing the same encouraging prompt in both cases is how you get someone
/// typing a paragraph into a command parser.
private struct EmptyChatState: View {
  @Environment(AppState.self) private var state

  var body: some View {
    if state.agentMode.allowsFreeChat {
      EmptyState(
        icon: "bubble.left.and.text.bubble.right",
        title: "问点什么",
        message: "它读得到你的周期、OKR 和本地 Vault。问「这一期为什么只完成了一半」比问「帮我总结」有用得多。"
      )
    } else {
      EmptyState(
        icon: "terminal",
        title: "现在只响应指令",
        message: "自由对话（agent mode）还没开启。下面这些词直接发就能用，或者去设置里打开自由对话。"
      )
    }
  }
}

private struct MessageBubble: View {
  let message: ChatMessage

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xs) {
      if message.role == .user {
        HStack {
          Spacer(minLength: Metrics.xl)
          Text(message.text)
            .font(Typo.body)
            .foregroundStyle(Palette.ink)
            .padding(Metrics.sm)
            .background(Palette.mossSoft)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusMedium, style: .continuous))
            .textSelection(.enabled)
        }
      } else {
        VStack(alignment: .leading, spacing: Metrics.xs) {
          if !message.toolCalls.isEmpty {
            ToolTrace(calls: message.toolCalls)
          }
          Text(message.text)
            .font(Typo.body)
            .foregroundStyle(Palette.ink)
            .textSelection(.enabled)
            .frame(maxWidth: Metrics.readableWidth, alignment: .leading)
        }
      }
      Text(Fmt.time(message.sentAt))
        .mutedStyle(Typo.label)
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
  }
}

/// The collapsed trace. Shows the tool names inline when closed, because that
/// alone answers "did it actually look at my cycles?" without a click.
private struct ToolTrace: View {
  let calls: [ToolCall]
  @State private var expanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xs) {
      Button { expanded.toggle() } label: {
        HStack(spacing: Metrics.xs) {
          Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.caption2)
          Text("读了 \(calls.count) 处")
          Text(calls.map(\.name).joined(separator: " · "))
            .font(Typo.mono)
            .lineLimit(1)
        }
        .foregroundStyle(Palette.inkMuted)
        .font(Typo.caption)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      if expanded {
        VStack(alignment: .leading, spacing: Metrics.xxs) {
          ForEach(calls) { call in
            HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
              Image(systemName: call.failed ? "xmark.circle" : "checkmark.circle")
                .font(.caption2)
                .foregroundStyle(call.failed ? Palette.danger : Palette.ok)
              Text(call.name).font(Typo.mono).foregroundStyle(Palette.ink)
              Text(call.summary).mutedStyle()
              Spacer(minLength: Metrics.xs)
              Text(Fmt.duration(call.duration)).font(Typo.tabularCaption).foregroundStyle(Palette.inkMuted)
            }
          }
        }
        .padding(Metrics.xs)
        .background(Palette.surfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
      }
    }
  }
}

// MARK: - Composer

private struct Composer: View {
  @Environment(AppState.self) private var state

  var body: some View {
    @Bindable var state = state
    VStack(spacing: 0) {
      Divider()
      if !state.agentMode.allowsFreeChat {
        AgentModeNotice()
      }
      CommandPalette()
      HStack(alignment: .bottom, spacing: Metrics.xs) {
        TextField(placeholder, text: $state.composerText, axis: .vertical)
          .textFieldStyle(.plain)
          .font(Typo.body)
          .lineLimit(1...6)
          .padding(Metrics.xs)
          .background(Palette.surfaceSunken)
          .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
          .onSubmit { state.send() }
        Button("发送") { state.send() }
          .buttonStyle(MossButtonStyle())
          .disabled(state.composerText.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      .padding(Metrics.sm)
    }
    .background(Palette.surface)
  }

  private var placeholder: String {
    state.agentMode.allowsFreeChat ? "问一句…" : "输入指令，例如 plan"
  }
}

/// Says the free-chat switch is off *before* you type, and says where it is.
///
/// The service already reports this — but only as a reply to a message you have
/// already sent, which is the wrong moment to find out and reads as a rejection
/// rather than as a setting.
private struct AgentModeNotice: View {
  @Environment(AppState.self) private var state

  var body: some View {
    HStack(spacing: Metrics.xs) {
      Image(systemName: "info.circle").foregroundStyle(Palette.inkMuted)
      Text("自由对话未开启，现在只响应下面这些指令。")
        .font(Typo.caption)
        .foregroundStyle(Palette.ink)
      Spacer(minLength: Metrics.xs)
      if state.account.role.canConfigure {
        Button("去开启") { state.section = .settings }
          .buttonStyle(QuietButtonStyle())
          .help("设置 → 模型 → 自由对话（interaction.feishu.agent_mode.enabled）")
      }
    }
    .padding(.horizontal, Metrics.sm)
    .padding(.vertical, Metrics.xs)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Palette.surfaceSunken)
  }
}

/// The commands, as chips.
///
/// Clicking fills the field instead of sending. Several of these take an
/// optional suffix after a colon (`plan：今天优先 X`), and sending on click
/// would hide that the suffix exists — as well as firing a workflow on a single
/// misplaced click.
private struct CommandPalette: View {
  @Environment(AppState.self) private var state

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: Metrics.xs) {
        ForEach(ChatCommand.palette) { command in
          Button {
            state.composerText = command.keyword
          } label: {
            Text(command.label)
              .font(Typo.label)
              .foregroundStyle(Palette.moss)
              .padding(.horizontal, Metrics.xs)
              .padding(.vertical, Metrics.xxs)
              .background(Palette.mossSoft, in: Capsule())
          }
          .buttonStyle(.plain)
          .help("\(command.keyword) — \(command.detail)")
        }
      }
      .padding(.horizontal, Metrics.sm)
      .padding(.top, Metrics.xs)
    }
  }
}

// MARK: - Previews

#Preview("对话") {
  ChatScreen()
    .environment(AppState.previewOwner())
    .frame(width: 1_040, height: 720)
}

/// Free chat switched on — the empty state and the placeholder both change.
#Preview("对话 · 自由对话已开启") {
  let state = AppState.previewOwner()
  state.agentMode = .enabled
  return ChatScreen()
    .environment(state)
    .frame(width: 1_040, height: 720)
}

#Preview("对话 · 空状态") {
  ChatScreen()
    .environment(AppState.previewEmpty())
    .frame(width: 1_040, height: 720)
}
