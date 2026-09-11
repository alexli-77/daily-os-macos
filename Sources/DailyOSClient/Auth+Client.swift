import Foundation
import DailyOSCore

// Sign-in against the console account store — the service's own SQLite `users`
// table, the one the web console logs in against.
//
// These three calls are deliberately *not* routed through `DailyOSClient.post`,
// and both reasons would be bugs if they were ignored:
//
//  * `/api/login`, `/api/logout` and `/api/register` are the only routes that
//    skip the auth gate, so the runtime token buys nothing there — and on
//    logout it actively hurts. `resolveAuthContext` prefers the token, and
//    `handleLogout` only destroys the session it was handed a *cookie* for, so
//    a logout carrying the token would clear this machine's cookie and leave
//    the row sitting on the server.
//  * A wrong password answers 401, and the shared transport reads any 401 as
//    "the runtime token was rejected", re-reads the runtime file and then says
//    "服务拒绝了本地令牌，它可能刚重启过". That is the wrong sentence to put in
//    front of someone who simply mistyped their password.

private struct LoginRequest: Encodable {
  let username: String
  let password: String
}

/// `/api/login` answers `{ ok, role, username }` on success and `{ ok, error }`
/// otherwise. Everything but `ok` is optional here so one failure shape cannot
/// turn into a decode error that hides the service's own message.
private struct LoginResponse: Decodable {
  let ok: Bool
  let error: String?
  let username: String?
  let role: String?
}

private struct RegisterRequest: Encodable {
  let username: String
  let email: String
  let password: String
}

/// `/api/register` answers `{ ok, username, role }` on success and
/// `{ ok: false, errors: { field: message } }` on a validation failure —
/// `errors`, plural and keyed, not the `error` string login uses.
private struct RegisterResponse: Decodable {
  let ok: Bool
  let username: String?
  let role: String?
  let errors: [String: String]?
  /// Not documented as a register failure shape, decoded anyway: an unexpected
  /// refusal should surface whatever the service said rather than a shrug.
  let error: String?
}

extension DailyOSClient {
  /// Check a username and password against the console account store.
  ///
  /// This is an identity check, not an access check. The app can already reach
  /// the service — it holds the runtime token out of `data/runtime/ui.json` —
  /// and signing in changes none of that. What it establishes is whose name is
  /// on the work and whose view the app shows.
  ///
  /// Either the username or the email is accepted, because the service accepts
  /// both and people remember the address they signed up with more reliably
  /// than the handle they picked in the same minute.
  public func signIn(username: String, password: String) async throws -> ConsoleSession {
    let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
    let path = "/api/login"
    let (data, status) = try await postUnauthenticated(
      path: path,
      body: LoginRequest(username: name, password: password)
    )

    let decoded: LoginResponse
    do {
      decoded = try JSONDecoder().decode(LoginResponse.self, from: data)
    } catch {
      throw ClientError.decoding(path: path, underlying: error)
    }

    guard decoded.ok, let account = decoded.username else {
      // The service's own 401 text is English ("Invalid username or password."),
      // and this is the one message on that screen anybody actually reads. Its
      // other refusals — a blank field, for one — are already written in Chinese
      // and are surfaced verbatim.
      if status == 401 {
        throw ClientError.service(message: "用户名或密码不对。连续错几次之后服务会故意变慢，稍等一下再试。")
      }
      throw ClientError.service(message: decoded.error ?? "服务拒绝了这次登录，但没说原因。")
    }

    // An unrecognised role reads as `member`, which is the cautious direction:
    // it hides controls that would have been shown, rather than showing ones the
    // service will then refuse.
    return ConsoleSession(
      username: account,
      role: decoded.role.flatMap(Role.init(rawValue:)) ?? .member
    )
  }

  /// Create an account, and be signed in as it.
  ///
  /// `/api/register` mints a session on success exactly like `/api/login` does,
  /// so there is no second round trip to "log in after registering" — the
  /// cookie is already set by the time this returns.
  ///
  /// **The first account on a machine becomes the owner; every one after it is
  /// a member.** That is the service's rule (`registerUser`), written so a
  /// stranger who reaches a sign-up form on a public build cannot land as
  /// owner. It is also the single most surprising thing about this screen, so
  /// the caller is expected to say it *before* the form is filled in, not after
  /// the second person finds Settings missing.
  public func register(username: String, email: String, password: String) async throws -> ConsoleSession {
    let path = "/api/register"
    let (data, status) = try await postUnauthenticated(
      path: path,
      body: RegisterRequest(
        username: username.trimmingCharacters(in: .whitespacesAndNewlines),
        email: email.trimmingCharacters(in: .whitespacesAndNewlines),
        password: password
      )
    )

    let decoded: RegisterResponse
    do {
      decoded = try JSONDecoder().decode(RegisterResponse.self, from: data)
    } catch {
      throw ClientError.decoding(path: path, underlying: error)
    }

    guard decoded.ok, let account = decoded.username else {
      // Registration refuses with `errors` — a *map*, one entry per bad field —
      // where login refuses with a single `error`. Reading only `error` here
      // would turn "密码需要 8-72 个字符" into "没说原因", which is the one
      // thing a validation failure must never do.
      let reasons = decoded.errors?.values.sorted().joined(separator: "；")
      throw ClientError.service(
        message: reasons?.isEmpty == false
          ? reasons!
          : (decoded.error ?? "服务拒绝了这次注册（HTTP \(status)），但没说原因。")
      )
    }

    return ConsoleSession(
      username: account,
      role: decoded.role.flatMap(Role.init(rawValue:)) ?? .member,
      email: email.trimmingCharacters(in: .whitespacesAndNewlines)
    )
  }

  /// End the console session on the service.
  ///
  /// Best-effort on purpose. The thing that decides who the app thinks you are
  /// is the record on this machine, and `LiveAppState.signOut` clears that
  /// first; this call is what stops the session row from lingering on the
  /// server for the rest of its week-long cookie life.
  public func signOut() async throws {
    let path = "/api/logout"
    let (_, status) = try await postUnauthenticated(path: path, body: [String: String]())
    // The route answers `{ ok: true }` to anyone, cookie or not, so anything
    // other than a 2xx is the service being unwell rather than a refusal. Worth
    // reporting even though the local sign-out has already happened: it is the
    // difference between "the session is gone" and "a session may still be
    // sitting on the server for the rest of the week".
    guard (200..<300).contains(status) else {
      throw ClientError.http(status: status, path: path)
    }
  }

  /// POST to one of the three public auth routes and hand back the raw answer.
  ///
  /// Returns the status alongside the body rather than throwing on it, because
  /// 401 means something different here than it does anywhere else in this
  /// client and the caller is the only place that knows so.
  private func postUnauthenticated(path: String, body: some Encodable) async throws -> (Data, Int) {
    let endpoint = try currentEndpoint()
    guard let url = Self.url(base: endpoint.url, path: path) else {
      throw ClientError.http(status: 0, path: path)
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    // No Authorization and no Origin. Same reasoning as the main transport for
    // Origin — a fabricated one fails the hostname allow-list, and a request
    // without one is treated as the non-browser client this is.
    request.timeoutInterval = 30
    // The session cookie is the whole point: login stores it and logout is only
    // able to destroy the server-side row because it is sent back.
    request.httpShouldHandleCookies = true
    request.httpBody = try JSONEncoder().encode(body)

    do {
      // `URLSession.shared` rather than the transport's own session, which is
      // private to that file. It is the same session in practice — the client
      // is constructed with `.shared` — and the shared cookie storage is what
      // carries the cookie from login to logout.
      let (data, response) = try await URLSession.shared.data(for: request)
      return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    } catch {
      throw ClientError.transport(underlying: error)
    }
  }
}

/// Remembers which console account is using this Mac.
///
/// Persisted, so that relaunching does not ask for a password again. That is a
/// defensible trade only because this sign-in is not a lock: the runtime token
/// sits in a file any process running as this macOS user can read, so the
/// service was always reachable and still is. Storing the name changes nothing
/// about who *can* get in — only about who the app says is in.
///
/// The password is never stored, because nothing here ever needs it a second
/// time: the service is asked once and answers with a name and a role.
public enum ConsoleSessionStore {
  static let defaultsKey = "com.dailyos.mac.consoleSession"

  private enum Field {
    static let username = "username"
    static let role = "role"
  }

  public static func restore(from defaults: UserDefaults = .standard) -> ConsoleSession? {
    guard let record = defaults.dictionary(forKey: defaultsKey),
          let username = record[Field.username] as? String,
          !username.isEmpty
    else { return nil }
    let role = (record[Field.role] as? String).flatMap(Role.init(rawValue:)) ?? .member
    return ConsoleSession(username: username, role: role)
  }

  public static func remember(_ session: ConsoleSession, in defaults: UserDefaults = .standard) {
    defaults.set(
      [Field.username: session.username, Field.role: session.role.rawValue],
      forKey: defaultsKey
    )
  }

  public static func forget(in defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: defaultsKey)
  }
}
