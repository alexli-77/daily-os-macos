import SwiftUI
import DailyOSCore

/// Who is using this app.
///
/// Not a gate on the service. The app reaches the service with the runtime
/// token out of `data/runtime/ui.json`, it did so before this screen existed,
/// and it still does while this screen is up — that file is readable by anything
/// running as this macOS user, and signing out does not change that. Saying so
/// on the screen itself is not modesty; a login that implies a lock it does not
/// have is worse than no login, because someone will rely on it.
///
/// What it *is*: the console's own account store, the same `users` table the web
/// console logs in against. That is what makes it worth having — two people on
/// one Mac get their own name on the work instead of sharing whatever
/// `team.self.memberId` happened to say.
///
/// Only shown when the service is reachable. A login in front of an app that
/// cannot reach anything would be a second wall between the user and the one
/// thing actually wrong, and this app decided a while ago to open into itself
/// with a banner rather than hold people at a question.
struct LoginScreen: View {
  let state: AppState

  @State private var username = ""
  @State private var password = ""
  @State private var failure: String?
  @State private var isSigningIn = false
  @FocusState private var focused: Field?

  private enum Field { case username, password }

  var body: some View {
    VStack(spacing: Metrics.md) {
      Spacer()

      DailyOSMark(motion: isSigningIn ? .searching : .settled)
        .frame(width: 76, height: 76)
      Text("Daily OS").inkStyle(Typo.display)

      message("用控制台账号登录——和网页控制台是同一套账号，不是团队同步的 Supabase 账号。")

      VStack(spacing: Metrics.xs) {
        TextField("用户名或邮箱", text: $username)
          .textFieldStyle(.roundedBorder)
          .focused($focused, equals: .username)
          .onSubmit { focused = .password }
        SecureField("密码", text: $password)
          .textFieldStyle(.roundedBorder)
          .focused($focused, equals: .password)
          // Enter from the password field signs in, because that is the only
          // thing left to do and reaching for the mouse to finish a two-field
          // form is the kind of small friction people feel every single day.
          .onSubmit { submit() }
      }
      .font(Typo.body)
      .frame(maxWidth: 320)

      if let failure {
        message(failure, tone: .danger)
      }

      Button(isSigningIn ? "登录中…" : "登录") { submit() }
        .buttonStyle(MossButtonStyle())
        .disabled(isSigningIn || !isFilled)

      // The honest scope of all this, where it cannot be missed. It sits under
      // the button rather than in a help popover for the same reason: someone
      // who thinks this screen protects their data has to read it before they
      // decide that, not after.
      message(
        "这一步只是说明「谁在用」。App 连本机服务用的是服务自己写下的运行令牌，登不登录都连得上；退出登录也只是换掉名字，不会把数据锁起来。",
        tone: .neutral
      )

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(Metrics.xl)
    .background(Palette.paper)
    .onAppear { focused = .username }
  }

  private var isFilled: Bool {
    !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
  }

  private func message(_ text: String, tone: Tone = .neutral) -> some View {
    Text(text)
      .font(Typo.body)
      .foregroundStyle(tone == .danger ? Palette.danger : Palette.inkMuted)
      .multilineTextAlignment(.center)
      .frame(maxWidth: 420)
  }

  /// The password is dropped on the way out whether or not it worked. It is
  /// needed exactly once — the service answers with a name and a role — and
  /// keeping it in a `@State` afterwards would be holding a secret for no
  /// reason. Clearing it on failure too costs one retype and means a shoulder
  /// never reads it off a screen left open.
  private func submit() {
    guard isFilled, !isSigningIn else { return }
    let name = username
    let secret = password
    password = ""
    failure = nil
    isSigningIn = true
    Task {
      let outcome = await state.signIn(username: name, password: secret)
      isSigningIn = false
      switch outcome {
      case .ok:
        // Nothing to do: the window swaps this screen for the app the moment
        // `session` is set.
        break
      case .failed(let reason), .unsupported(let reason):
        failure = reason
        focused = .password
      }
    }
  }
}
