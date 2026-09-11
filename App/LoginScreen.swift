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
  /// Set the moment the service accepts, cleared by `onFinished`. It is what
  /// holds this screen on-window while the mark finishes its transition; the
  /// app cannot infer that from `session` alone, because a session restored at
  /// launch looks identical to one that just arrived.
  @Binding var isFinishing: Bool
  /// Called once the success animation has finished, not when the service
  /// answered.
  let onFinished: () -> Void

  /// Sign in or sign up. One screen rather than two, because they differ by one
  /// field and a verb, and a second full-window screen for that is navigation
  /// nobody asked for.
  private enum Mode { case signIn, register }

  /// What the screen is doing. `.succeeded` exists so the mark can finish its
  /// transition before the app replaces this view — without it the window swaps
  /// on the same frame the service answers, and the animation has nowhere to
  /// play.
  private enum Phase { case editing, working, succeeded }

  @State private var mode: Mode = .signIn
  @State private var username = ""
  @State private var email = ""
  @State private var password = ""
  @State private var failure: String?
  @State private var phase: Phase = .editing
  @FocusState private var focused: Field?

  private enum Field { case username, email, password }

  var body: some View {
    VStack(spacing: Metrics.md) {
      Spacer()

      DailyOSMark(motion: markMotion, gradient: DailyOSMark.houseGradient)
        .frame(width: markSide, height: markSide)
        // The whole transition, in three lines. On success the form leaves and
        // the mark grows into the space it vacated — the same object the screen
        // opened with, carried across into the app rather than replaced by it.
        .scaleEffect(phase == .succeeded ? 1.25 : 1)
        .animation(.spring(response: 0.55, dampingFraction: 0.62), value: phase)

      Text("Daily OS").inkStyle(Typo.display)

      if phase == .succeeded {
        // One line, and it names who you are. Anything longer would be read
        // half-way and then vanish.
        message("欢迎，\(state.session?.username ?? username)")
          .transition(.opacity)
      } else {
        form
          .transition(.opacity.combined(with: .move(edge: .bottom)))
      }

      Spacer()
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(Metrics.xl)
    .background(Palette.paper)
    .animation(.snappy(duration: 0.35), value: phase)
    .onAppear { focused = .username }
  }

  private var markSide: CGFloat { 76 }

  private var markMotion: DailyOSMark.Motion {
    switch phase {
    case .editing: .still
    case .working: .searching
    case .succeeded: .settled
    }
  }

  // MARK: Form

  @ViewBuilder private var form: some View {
    VStack(spacing: Metrics.md) {
      message(
        mode == .signIn
          ? "用控制台账号登录——和网页控制台是同一套账号，不是团队同步的 Supabase 账号。"
          : "在这台机器的服务上建一个账号，建完直接就是登录状态。"
      )

      VStack(spacing: Metrics.xs) {
        TextField(mode == .signIn ? "用户名或邮箱" : "用户名", text: $username)
          .textFieldStyle(.roundedBorder)
          .focused($focused, equals: .username)
          .onSubmit { focused = mode == .signIn ? .password : .email }

        if mode == .register {
          TextField("邮箱", text: $email)
            .textFieldStyle(.roundedBorder)
            .focused($focused, equals: .email)
            .onSubmit { focused = .password }
        }

        SecureField(mode == .signIn ? "密码" : "密码（至少 8 位）", text: $password)
          .textFieldStyle(.roundedBorder)
          .focused($focused, equals: .password)
          // Enter from the password field submits, because that is the only
          // thing left to do and reaching for the mouse to finish a short form
          // is the kind of small friction people feel every single day.
          .onSubmit { submit() }
      }
      .font(Typo.body)
      .frame(maxWidth: 320)
      .disabled(phase == .working)

      if let failure {
        message(failure, tone: .danger)
      }

      Button(buttonTitle) { submit() }
        .buttonStyle(MossButtonStyle())
        .disabled(phase == .working || !isFilled)

      Button(mode == .signIn ? "没有账号？注册一个" : "已经有账号了，去登录") {
        withAnimation(.snappy(duration: 0.2)) {
          mode = mode == .signIn ? .register : .signIn
          failure = nil
          password = ""
        }
        focused = .username
      }
      .buttonStyle(QuietButtonStyle())
      .disabled(phase == .working)

      footnote
    }
  }

  private var buttonTitle: String {
    if phase == .working { return mode == .signIn ? "登录中…" : "注册中…" }
    return mode == .signIn ? "登录" : "注册并登录"
  }

  /// The two things someone should know *before* filling the form in, not after.
  @ViewBuilder private var footnote: some View {
    if mode == .register {
      // The service's rule, surfaced at the moment it still matters. Discovering
      // it afterwards means discovering that Settings is missing and not knowing
      // why.
      message(
        "这台机器上的第一个账号是所有者，之后注册的都是成员——成员看不到配置和密钥。",
        tone: .neutral
      )
    } else {
      // The honest scope of all this, where it cannot be missed. Under the
      // button rather than in a help popover for the same reason: someone who
      // thinks this screen protects their data has to read it before they
      // decide that.
      message(
        "这一步只是说明「谁在用」。App 连本机服务用的是服务自己写下的运行令牌，登不登录都连得上；退出登录也只是换掉名字，不会把数据锁起来。",
        tone: .neutral
      )
    }
  }

  private var isFilled: Bool {
    let name = !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let mail = !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    return name && !password.isEmpty && (mode == .signIn || mail)
  }

  private func message(_ text: String, tone: Tone = .neutral) -> some View {
    Text(text)
      .font(Typo.body)
      .foregroundStyle(tone == .danger ? Palette.danger : Palette.inkMuted)
      .multilineTextAlignment(.center)
      .frame(maxWidth: 420)
  }

  // MARK: Submit

  /// The password is dropped on the way out whether or not it worked. It is
  /// needed exactly once — the service answers with a name and a role — and
  /// keeping it in a `@State` afterwards would be holding a secret for no
  /// reason. Clearing it on failure too costs one retype and means a shoulder
  /// never reads it off a screen left open.
  private func submit() {
    guard isFilled, phase == .editing else { return }
    let name = username
    let mail = email
    let secret = password
    password = ""
    failure = nil
    phase = .working

    Task {
      let outcome = mode == .signIn
        ? await state.signIn(username: name, password: secret)
        : await state.register(username: name, email: mail, password: secret)

      switch outcome {
      case .ok(let note):
        // A member account carries a note worth reading; it goes to the toast
        // so it survives this screen being replaced a moment later.
        if let note { state.toast = note }
        isFinishing = true
        phase = .succeeded
        // Long enough for the form to leave and the mark to settle, short
        // enough that nobody waits on it. Measured against the two animations
        // above, not picked round.
        try? await Task.sleep(for: .milliseconds(900))
        onFinished()
      case .failed(let reason), .unsupported(let reason):
        failure = reason
        phase = .editing
        focused = .password
      }
    }
  }
}
