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
      ResizableListColumn(id: "chat", defaultWidth: 260) { ThreadList() }
      Conversation().frame(maxWidth: .infinity)
    }
    .background(Palette.paper)
  }
}

/// The chat as a right-side panel that drops from the top (⌘⇧C or the toolbar
/// bubble). Narrow by design — so the thread list is a popover off the header
/// rather than a permanent second column, and the conversation gets the whole
/// width. Same store as the `.chat` section: it is the one conversation, not a
/// copy. Lives here, not in its own file, because it reuses the private
/// `Conversation` / `ThreadList` above.
struct ChatPanel: View {
  @Binding var isOpen: Bool
  @Environment(AppState.self) private var state
  @State private var showHistory = false

  var body: some View {
    VStack(spacing: 0) {
      header
      Conversation()
    }
    .frame(width: 420)
    .frame(maxHeight: .infinity)
    // One continuous green canvas top-to-bottom — header, body and composer all
    // sit on it, no white strips (LEO-346).
    .background(Palette.chatCanvas)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Palette.line)
    )
    .shadow(color: .black.opacity(0.16), radius: 18, y: 6)
    .padding(.top, Metrics.xs)
    .padding(.bottom, Metrics.md)
  }

  private var header: some View {
    HStack(spacing: Metrics.xs) {
      Text("聊天").font(Typo.label)
      Spacer()
      Button { showHistory.toggle() } label: {
        Image(systemName: "clock.arrow.circlepath")
      }
      .help("历史对话")
      .popover(isPresented: $showHistory, arrowEdge: .bottom) {
        ThreadList()
          .frame(width: 260, height: 380)
          .environment(state)
      }
      Button { state.newThread() } label: {
        Image(systemName: "square.and.pencil")
      }
      .help("新对话")
      Button { isOpen = false } label: {
        Image(systemName: "xmark")
      }
      .help("收起（⌘⇧C）")
    }
    .buttonStyle(QuietButtonStyle(tone: .neutral))
    .padding(.horizontal, Metrics.sm)
    .padding(.vertical, Metrics.xs)
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
              state.selectThread(thread.id)
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
/// Example prompts shown on a fresh free-chat session — a greeting plus a few
/// taps that teach the range of what the assistant does. Tapping fills the
/// composer rather than sending, so a data-changing example is reviewed first.
private let chatExamplePrompts = [
  "把午餐挪到 12:30",
  "本期要务加一条：联系导师",
  "这一期为什么只完成了一半",
  "看书挪到口语后面",
  "怎么关掉通知",
]

private struct EmptyChatState: View {
  @Environment(AppState.self) private var state

  var body: some View {
    if state.agentMode.allowsFreeChat {
      VStack(spacing: Metrics.lg) {
        VStack(spacing: Metrics.sm) {
          ChatBotMark().frame(width: 60, height: 60)
          Text("你好，我是 Daily OS 助手")
            .font(Typo.heading)
            .foregroundStyle(Palette.ink)
          Text("能看也能改你的作息、排期、要务和 OKR，也能告诉你怎么改设置。试试点下面的例子：")
            .font(Typo.body)
            .foregroundStyle(Palette.inkMuted)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        VStack(spacing: Metrics.xs) {
          ForEach(chatExamplePrompts, id: \.self) { prompt in
            Button { state.composerText = prompt } label: {
              Text(prompt)
                .font(Typo.body)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, Metrics.md)
                .padding(.vertical, Metrics.xs + 2)
                .frame(maxWidth: .infinity, alignment: .leading)
                // White pills read cleanly on the green canvas.
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
          }
        }
        .frame(maxWidth: 420)
      }
      .frame(maxWidth: .infinity)
      .padding(Metrics.lg)
    } else {
      EmptyState(
        icon: "terminal",
        title: "现在只响应指令",
        message: "自由对话（agent mode）未开启。可以发下面的指令，或去设置里打开。"
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
          HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
            if message.isStreaming { ProgressView().controlSize(.small) }
            Text(message.text)
              .font(Typo.body)
              .foregroundStyle(message.isStreaming ? Palette.inkMuted : Palette.ink)
              .textSelection(.enabled)
          }
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
      if !state.agentMode.allowsFreeChat {
        AgentModeNotice()
        // Command chips are the command-mode fallback. In free chat you just
        // talk (and the empty state teaches how), so the row is dropped there.
        CommandPalette()
      }
      // One white pill holding the field and a green circular send button,
      // matching the design (LEO-346) rather than a text button.
      HStack(alignment: .bottom, spacing: Metrics.xs) {
        TextField(placeholder, text: $state.composerText, axis: .vertical)
          .textFieldStyle(.plain)
          .font(Typo.body)
          .lineLimit(1...6)
          .padding(.vertical, 6)
          .onSubmit { state.send() }
        Button { state.send() } label: {
          Image(systemName: "arrow.up")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color(white: 0.97))
            .frame(width: 30, height: 30)
            .background(Circle().fill(Palette.chatAccent))
        }
        .buttonStyle(.plain)
        .opacity(state.composerText.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
        .disabled(state.composerText.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      .padding(.leading, Metrics.md)
      .padding(.trailing, 6)
      .padding(.vertical, 6)
      .background(Palette.surface)
      .clipShape(Capsule(style: .continuous))
      .overlay(Capsule(style: .continuous).strokeBorder(Palette.line, lineWidth: 0.5))
      .padding(Metrics.sm)
    }
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
              .foregroundStyle(Palette.ink)
              .padding(.horizontal, Metrics.sm)
              .padding(.vertical, Metrics.xxs)
              .background(Palette.surfaceSunken, in: Capsule())
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
