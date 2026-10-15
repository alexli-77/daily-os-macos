import Foundation
import DailyOSCore

// The 对话 panel's endpoints: `/api/chat/*`.
//
// Until this file the panel never reached the service. `send()` appended a
// canned "UI 骨架" reply and the thread list was the fixture's, so the chat
// looked like it worked and could change nothing.

/// One event from `/api/chat/send`'s server-sent stream.
public enum ChatStreamEvent: Sendable, Equatable {
  case status(String)
  case reply(String)
  /// Refused by the service's control policy, or an error mid-turn.
  case failed(String)
  case stopped
  case done
}

private struct ChatSessionsResponse: Decodable {
  struct Session: Decodable { let id: String; let title: String; let updatedAt: String }
  let sessions: [Session]
}

private struct ChatSessionResponse: Decodable {
  struct Session: Decodable { let id: String; let title: String; let updatedAt: String }
  let session: Session
}

private struct ChatMessagesResponse: Decodable {
  struct Message: Decodable { let id: String; let role: String; let content: String; let createdAt: String }
  let messages: [Message]
}

private struct StateAgentModeResponse: Decodable {
  struct Config: Decodable {
    struct Interaction: Decodable {
      struct Feishu: Decodable {
        struct AgentMode: Decodable { let enabled: Bool }
        let agent_mode: AgentMode
      }
      let feishu: Feishu
    }
    let interaction: Interaction
  }
  let config: Config
}

private struct SessionBody: Encodable { let session: String }
private struct SendBody: Encodable { let session: String; let text: String }

extension DailyOSClient {
  public func chatThreads() async throws -> [ChatThread] {
    let response: ChatSessionsResponse = try await get("/api/chat/sessions")
    return response.sessions.map {
      ChatThread(id: $0.id, title: Self.threadTitle($0.title), updatedAt: TodoWireDate.timestamp($0.updatedAt) ?? .now, messages: [])
    }
  }

  public func chatMessages(session: String) async throws -> [ChatMessage] {
    let query = session.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? session
    let response: ChatMessagesResponse = try await get("/api/chat/messages?session=\(query)")
    return response.messages.compactMap { message in
      guard let role = ChatRole(rawValue: message.role) else { return nil }
      return ChatMessage(id: message.id, role: role, text: message.content, sentAt: TodoWireDate.timestamp(message.createdAt) ?? .now)
    }
  }

  public func createChatThread() async throws -> ChatThread {
    let response: ChatSessionResponse = try await post("/api/chat/session", body: [String: String]())
    return ChatThread(id: response.session.id, title: "新对话", updatedAt: TodoWireDate.timestamp(response.session.updatedAt) ?? .now, messages: [])
  }

  public func deleteChatThread(_ id: String) async throws {
    try await post("/api/chat/session/delete", body: SessionBody(session: id))
  }

  public func stopChat(_ id: String) async throws {
    try await post("/api/chat/stop", body: SessionBody(session: id))
  }

  /// Whether free chat is on. Part of `/api/state`, which the GET reuse window
  /// shares with the other readers of that blob.
  public func agentMode() async throws -> AgentMode {
    let state: StateAgentModeResponse = try await get("/api/state")
    return state.config.interaction.feishu.agent_mode.enabled ? .enabled : .disabled
  }

  /// Send one message and stream the turn back.
  ///
  /// A turn that edits files runs for a minute or more, so this has no request
  /// timeout of its own beyond the service's; the service sends a heartbeat
  /// every 15 seconds while it works.
  public func sendChat(session: String, text: String) async throws -> AsyncThrowingStream<ChatStreamEvent, Error> {
    let endpoint = try currentEndpoint()
    guard let url = Self.url(base: endpoint.url, path: "/api/chat/send") else {
      throw ClientError.http(status: 0, path: "/api/chat/send")
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("Bearer \(endpoint.token)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = 900
    request.httpBody = try JSONEncoder().encode(SendBody(session: session, text: text))
    invalidate()
    return Self.chatStream(request)
  }

  private nonisolated static func chatStream(_ request: URLRequest) -> AsyncThrowingStream<ChatStreamEvent, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          let (bytes, response) = try await URLSession.shared.bytes(for: request)
          let status = (response as? HTTPURLResponse)?.statusCode ?? 0
          guard (200..<300).contains(status) else {
            var body = ""
            for try await line in bytes.lines { body += line }
            let reason = (try? JSONDecoder().decode(ChatErrorBody.self, from: Data(body.utf8)))?.error
            let fallback = status == 401 ? "服务刚重启过，再发一次。" : "对话请求失败（HTTP \(status)）。"
            continuation.yield(.failed(reason ?? fallback))
            continuation.finish()
            return
          }
          for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            if let event = Self.chatEvent(Data(payload.utf8)) { continuation.yield(event) }
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: ClientError.transport(underlying: error))
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// One `data:` payload. Unknown types are skipped rather than failing the turn.
  nonisolated static func chatEvent(_ data: Data) -> ChatStreamEvent? {
    guard let raw = try? JSONDecoder().decode(ChatEventBody.self, from: data) else { return nil }
    switch raw.type {
    case "status": return raw.message.map { .status($0) }
    case "reply": return raw.content.map { .reply($0) }
    case "denied", "error": return .failed(raw.message ?? "对话失败了。")
    case "stopped": return .stopped
    case "done": return .done
    default: return nil
    }
  }

  /// The service titles a thread with its first message, or "New chat".
  static func threadTitle(_ raw: String) -> String {
    raw == "New chat" ? "新对话" : raw
  }
}

private struct ChatEventBody: Decodable {
  let type: String
  let message: String?
  let content: String?
}

private struct ChatErrorBody: Decodable { let error: String? }
