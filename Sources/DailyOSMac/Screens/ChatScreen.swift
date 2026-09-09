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

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text("对话").inkStyle(Typo.heading)
        Spacer()
        Button { state.newThread() } label: { Image(systemName: "square.and.pencil") }
          .buttonStyle(.plain)
          .foregroundStyle(Palette.moss)
      }
      .padding(Metrics.sm)
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(state.threads) { thread in
            SelectableRow(isSelected: thread.id == state.selectedThread?.id) {
              state.selectedThreadID = thread.id
            } content: {
              VStack(alignment: .leading, spacing: Metrics.xxs) {
                Text(thread.title).inkStyle().lineLimit(1)
                Text(Fmt.stamp(thread.updatedAt)).mutedStyle()
              }
            }
          }
        }
        .padding(Metrics.xs)
      }
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
            EmptyState(
              icon: "bubble.left.and.text.bubble.right",
              title: "问点什么",
              message: "它读得到你的周期、OKR 和本地 Vault。问「这一期为什么只完成了一半」比问「帮我总结」有用得多。"
            )
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

private struct Composer: View {
  @Environment(AppState.self) private var state

  var body: some View {
    @Bindable var state = state
    VStack(spacing: 0) {
      Divider()
      HStack(alignment: .bottom, spacing: Metrics.xs) {
        TextField("问一句…", text: $state.composerText, axis: .vertical)
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
}

// MARK: - Previews

#Preview("对话") {
  ChatScreen()
    .environment(AppState.previewOwner())
    .frame(width: 1_040, height: 720)
}

#Preview("对话 · 空状态") {
  ChatScreen()
    .environment(AppState.previewEmpty())
    .frame(width: 1_040, height: 720)
}
