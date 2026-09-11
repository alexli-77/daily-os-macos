import SwiftUI
import DailyOSCore

/// Supabase connection, then sign-in, then membership.
///
/// Three stages that only exist in order: there is nothing to sign in to before
/// the project is configured, and no invite code before there is a team. The
/// console showed all three blocks and hid two of them; this shows the one you
/// are actually at, plus the connection panel, which is the one thing you can
/// always change.
struct TeamSection: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    ConnectionPanel(store: store, snapshot: snapshot)
    if snapshot.team.configured {
      MembershipPanel(store: store, snapshot: snapshot)
    }
  }
}

/// The two fields that used to be "go and edit config.yaml".
///
/// The anon key is write-only here. `/api/state` does hand it back in plaintext
/// and the web console prints it into an input — it is a public key by design —
/// but a settings screen that displays one is a settings screen people will
/// paste a `service_role` key into next, and that key bypasses every RLS policy
/// in the project. The service refuses that key on save; not showing either of
/// them is the cheaper half of the same defence.
private struct ConnectionPanel: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    @Bindable var store = store
    Panel("Supabase 项目", subtitle: "本地 markdown 永远是真相源，这只是一个中转") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        SettingText(
          label: "项目地址",
          text: $store.draft.supabaseURL,
          placeholder: "https://xxxxxxxx.supabase.co",
          mono: true
        )
        KeyValueRow("anon key") {
          VStack(alignment: .leading, spacing: Metrics.xs) {
            HStack(spacing: Metrics.xs) {
              Pill(snapshot.supabaseKeyPresent ? "已配置" : "未配置", tone: snapshot.supabaseKeyPresent ? .ok : .neutral)
              Button(store.isEditingSupabaseKey ? "取消" : (snapshot.supabaseKeyPresent ? "更换" : "填写")) {
                store.isEditingSupabaseKey.toggle()
                store.supabaseKeyDraft = ""
              }
              .buttonStyle(QuietButtonStyle())
            }
            if store.isEditingSupabaseKey {
              SecureField("eyJhbGciOi…", text: $store.supabaseKeyDraft)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 360)
            }
            HintText("只能填 anon key（它本来就是公开的）。service_role key 会绕过所有 RLS 策略，服务保存时会直接拒绝。两个 key 在 Supabase 后台是挨着的，很容易拿错。")
          }
        }
        HintText("没配置、没登录、断网时，周期和其它本地功能全部照常工作——同步是附加的，不是前提。")
      }
    } actions: {
      SaveAction(isDirty: store.isTeamConnectionDirty, isBusy: store.isBusy) {
        Task { await store.saveTeamConnection() }
      }
    }
  }
}

/// Sign in, create or join, and then the roster.
private struct MembershipPanel: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    @Bindable var store = store
    Panel("成员", subtitle: "各自的文件仍然在各自机器上，同步只是传输") {
      VStack(alignment: .leading, spacing: Metrics.sm) {
        if !snapshot.team.signedIn {
          VStack(alignment: .leading, spacing: Metrics.xs) {
            Text("Supabase 已配置，这台机器还没登录。").mutedStyle()
            TextField("邮箱", text: $store.teamEmail)
              .textFieldStyle(.roundedBorder)
              .frame(maxWidth: 280)
            SecureField("密码", text: $store.teamPassword)
              .textFieldStyle(.roundedBorder)
              .frame(maxWidth: 280)
            Button("登录") { Task { await store.teamSignIn() } }
              .buttonStyle(MossButtonStyle(prominent: false))
              .disabled(store.teamEmail.isEmpty || store.teamPassword.isEmpty || store.isBusy)
            HintText("密码直接发给本机服务，再由它转给 Supabase；服务只把动作名写进日志，不写请求体。")
          }
        } else if !snapshot.team.hasTeam {
          signedInWithoutTeam
        } else {
          inTeam
        }
      }
    } actions: {
      if snapshot.team.signedIn {
        if snapshot.team.hasTeam {
          Button("立即同步") { Task { await store.teamSyncNow() } }
            .buttonStyle(QuietButtonStyle())
            .disabled(store.isBusy)
        }
        Button("刷新") { Task { await store.teamRefresh() } }
          .buttonStyle(QuietButtonStyle())
          .disabled(store.isBusy)
        Button("退出 Supabase") { store.confirmTeamSignOut() }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
          .disabled(store.isBusy)
      }
    }
  }

  @ViewBuilder
  private var signedInWithoutTeam: some View {
    @Bindable var store = store
    VStack(alignment: .leading, spacing: Metrics.sm) {
      KeyValueRow("已登录", snapshot.team.identityLine)
      PanelDivider()
      Text("还没有团队。建一个，或者用别人给的邀请码加入。").mutedStyle()
      HStack(spacing: Metrics.xs) {
        TextField("团队名称", text: $store.newTeamName)
          .textFieldStyle(.roundedBorder)
          .frame(maxWidth: 220)
        Button("创建团队") { store.confirmCreateTeam() }
          .buttonStyle(MossButtonStyle(prominent: false))
          .disabled(store.newTeamName.isEmpty || store.isBusy)
      }
      HStack(spacing: Metrics.xs) {
        TextField("邀请码", text: $store.joinCode)
          .textFieldStyle(.roundedBorder)
          .font(Typo.monoBody)
          .frame(maxWidth: 220)
        Button("加入团队") { store.confirmJoinTeam() }
          .buttonStyle(MossButtonStyle(prominent: false))
          .disabled(store.joinCode.isEmpty || store.isBusy)
      }
    }
  }

  @ViewBuilder
  private var inTeam: some View {
    VStack(alignment: .leading, spacing: 0) {
      KeyValueRow("团队", snapshot.team.teamName.isEmpty ? snapshot.team.teamId : snapshot.team.teamName)
      PanelDivider()
      KeyValueRow("我", snapshot.team.identityLine)
      PanelDivider()
      KeyValueRow("邀请码") {
        if snapshot.team.inviteCode.isEmpty {
          Text("这台机器的缓存里没有邀请码。点「刷新」重新拉一次，或者重新生成一个。").mutedStyle()
        } else {
          HStack(spacing: Metrics.xs) {
            Text(snapshot.team.inviteCode)
              .font(Typo.monoBody)
              .foregroundStyle(Palette.ink)
              .textSelection(.enabled)
            Button("复制") { store.copy(snapshot.team.inviteCode, what: "邀请码") }
              .buttonStyle(QuietButtonStyle())
            Button("重新生成") { store.confirmRotateInviteCode() }
              .buttonStyle(QuietButtonStyle(tone: .danger))
              .disabled(store.isBusy)
          }
        }
      }
      PanelDivider()
      KeyValueRow("同步", snapshot.team.syncLine)
      if !snapshot.team.lastError.isEmpty {
        PanelDivider()
        Text(snapshot.team.lastError)
          .font(Typo.caption)
          .foregroundStyle(Palette.foreground(for: .warn))
          .fixedSize(horizontal: false, vertical: true)
          .padding(.vertical, Metrics.xxs)
      }
      PanelDivider()
      ForEach(snapshot.team.members) { member in
        HStack(spacing: Metrics.sm) {
          PixelAvatar(seed: member.avatarSeed, size: 24)
          Text(member.displayName).inkStyle()
          if member.isSelf { Pill("我", tone: .accent) }
          Spacer(minLength: Metrics.xs)
          if let synced = member.lastSyncedAt {
            Text("同步于 \(Fmt.time(synced))").mutedStyle()
          } else {
            Text("从未同步").mutedStyle()
          }
        }
        .frame(minHeight: Metrics.hitTarget)
      }
      PanelDivider()
      HStack {
        Spacer()
        Button("退出团队") { store.confirmLeaveTeam() }
          .buttonStyle(QuietButtonStyle(tone: .danger))
          .disabled(store.isBusy)
      }
      .padding(.top, Metrics.xxs)
    }
  }
}
