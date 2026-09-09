import SwiftUI
import DailyOSCore

/// The config surface, folded back into the app.
///
/// The web console kept nine admin sections behind a `/console` route that also
/// happened to be where you changed the font size. Two rules here:
///
/// - **Owner-only.** Non-owners do not get a disabled version of this screen,
///   they get an explanation. Hiding controls is presentation only — the
///   service enforces the same boundary.
/// - **Configuration lives on the Mac.** The iOS app (a separate repository)
///   shows what this screen is set to and stops — no API keys, no provider
///   switching, no skill installs on a phone.
struct SettingsScreen: View {
  @Environment(AppState.self) private var state
  @State private var provider = MockData.providers.first ?? ""
  @State private var model = MockData.models.first ?? ""

  var body: some View {
    ScreenScaffold("设置", subtitle: state.account.role.canConfigure ? "只有所有者能改这里的东西" : nil) {
      if state.account.role.canConfigure {
        AccountPanel()
        ProviderPanel(provider: $provider, model: $model)
        SourcesPanel()
        TeamPanel()
        ServicePanel()
      } else {
        Panel {
          EmptyState(
            icon: "lock",
            title: "这台机器的配置属于所有者",
            message: "你可以读写自己的周期和待办，但服务商、密钥和数据源由所有者管理。"
          )
        }
      }
    }
  }
}

// MARK: - Account

private struct AccountPanel: View {
  @Environment(AppState.self) private var state

  var body: some View {
    Panel("账号") {
      VStack(spacing: 0) {
        HStack(spacing: Metrics.sm) {
          PixelAvatar(seed: state.account.avatarSeed, size: 44)
          VStack(alignment: .leading, spacing: 2) {
            Text(state.account.displayName).inkStyle(Typo.heading)
            Text(state.account.email).mutedStyle()
          }
          Spacer()
          Pill(state.account.role.label, tone: .accent)
        }
        .padding(.bottom, Metrics.sm)
        PanelDivider()
        KeyValueRow("头像种子", state.account.avatarSeed, mono: true)
      }
    } actions: {
      Button("退出登录") {}.buttonStyle(QuietButtonStyle(tone: .danger))
    }
  }
}

// MARK: - Provider

/// Provider → model → skills, in that order, because each choice narrows the
/// next. The skill row shows installed state and offers the install inline;
/// making someone open a terminal in the middle of a settings screen is how a
/// local-first app loses the person who was willing to try it.
private struct ProviderPanel: View {
  @Binding var provider: String
  @Binding var model: String

  var body: some View {
    Panel("模型", subtitle: "决定工作流和对话用什么跑") {
      VStack(spacing: Metrics.sm) {
        KeyValueRow("服务商") {
          Picker("", selection: $provider) {
            ForEach(MockData.providers, id: \.self) { Text($0).tag($0) }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(maxWidth: 220, alignment: .leading)
        }
        PanelDivider()
        KeyValueRow("模型") {
          Picker("", selection: $model) {
            ForEach(MockData.models, id: \.self) { Text($0).tag($0) }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(maxWidth: 220, alignment: .leading)
        }
        PanelDivider()
        KeyValueRow("API 密钥") {
          HStack(spacing: Metrics.xs) {
            Text("••••••••••••").font(Typo.monoBody).foregroundStyle(Palette.inkMuted)
            Button("显示") {}.buttonStyle(QuietButtonStyle())
            Button("更换") {}.buttonStyle(QuietButtonStyle())
          }
        }
        PanelDivider()
        KeyValueRow("技能") {
          HStack(spacing: Metrics.xs) {
            Pill("已安装", tone: .ok)
            Text("weekly-review v1.4").font(Typo.mono).foregroundStyle(Palette.inkMuted)
            Button("检查更新") {}.buttonStyle(QuietButtonStyle())
          }
        }
      }
    }
  }
}

// MARK: - Sources

private struct SourcesPanel: View {
  @Environment(AppState.self) private var state

  var body: some View {
    Panel("数据源", subtitle: "证据从这些地方来，结论回到你的文件里") {
      VStack(spacing: 0) {
        ForEach(Array(state.sources.enumerated()), id: \.element.id) { index, source in
          if index > 0 { PanelDivider() }
          HStack(spacing: Metrics.sm) {
            Image(systemName: source.icon)
              .foregroundStyle(source.connected ? Palette.moss : Palette.inkMuted)
              .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
              Text(source.name).inkStyle()
              Text(source.detail).mutedStyle()
            }
            Spacer(minLength: Metrics.xs)
            Pill(source.connected ? "已连接" : "未配置", tone: source.connected ? .ok : .neutral)
            Button(source.connected ? "管理" : "连接") {}
              .buttonStyle(QuietButtonStyle())
          }
          .frame(minHeight: Metrics.hitTarget)
        }
      }
    }
  }
}

// MARK: - Team

private struct TeamPanel: View {
  @Environment(AppState.self) private var state

  var body: some View {
    Panel("团队", subtitle: "各自的文件仍然在各自机器上，同步只是传输") {
      VStack(spacing: 0) {
        ForEach(Array(state.members.enumerated()), id: \.element.id) { index, member in
          if index > 0 { PanelDivider() }
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
      }
    } actions: {
      Button("邀请码") {}.buttonStyle(QuietButtonStyle())
    }
  }
}

// MARK: - Service

private struct ServicePanel: View {
  @Environment(AppState.self) private var state

  var body: some View {
    Panel("服务") {
      VStack(spacing: 0) {
        KeyValueRow("状态") {
          StatusDot(state.service.state.label, tone: state.service.state.tone, pulsing: state.service.state == .running)
        }
        PanelDivider()
        KeyValueRow("地址", state.service.endpoint, mono: true)
        PanelDivider()
        KeyValueRow("已运行", Fmt.duration(state.service.uptime))
      }
    } actions: {
      Button("查看日志") {}.buttonStyle(QuietButtonStyle())
      Button("重启") {}.buttonStyle(QuietButtonStyle(tone: .danger))
    }
  }
}

// MARK: - Previews

#Preview("设置 · owner") {
  SettingsScreen()
    .environment(AppState.previewOwner())
    .frame(width: 940, height: 800)
}

/// A member gets an explanation, not a disabled form.
#Preview("设置 · member") {
  SettingsScreen()
    .environment(AppState.previewMember())
    .frame(width: 940, height: 800)
}
