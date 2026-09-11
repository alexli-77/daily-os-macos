import SwiftUI
import DailyOSCore

/// The Mac shell: a source list on the left, the section on the right.
///
/// Two columns, not three. Several sections *do* need a list-plus-detail
/// layout (cycles, runs, artifacts, chat), but each of them owns that split
/// internally — a global three-column `NavigationSplitView` would leave Today,
/// OKR and Settings with a dead middle column, and the collapse behaviour of
/// a column that is sometimes meaningless is worse than no column at all.
struct MacRootView: View {
  @Environment(AppState.self) private var state

  var body: some View {
    @Bindable var state = state
    NavigationSplitView {
      Sidebar(selection: $state.section)
        .navigationSplitViewColumnWidth(
          min: Metrics.sidebarMin,
          ideal: Metrics.sidebarIdeal,
          max: Metrics.sidebarMax
        )
    } detail: {
      VStack(spacing: 0) {
        // Above the section rather than inside it, because it is true of the
        // whole app: every screen is empty for the same one reason, and six
        // identical empty states would each look like their own problem.
        if state.wiredSections.isEmpty {
          DisconnectedBanner()
        }
        SectionView(section: state.section)
      }
      .frame(minWidth: 560, minHeight: 420)
    }
    .background(Palette.paper)
    .toastOverlay()
  }
}

private struct Sidebar: View {
  @Environment(AppState.self) private var state
  @Binding var selection: AppSection

  var body: some View {
    List(selection: $selection) {
      Section {
        ForEach(AppSection.workGroup) { item(for: $0) }
      }
      Section("系统") {
        ForEach(AppSection.systemGroup) { item(for: $0) }
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      SidebarFooter()
    }
    .navigationTitle("Daily OS")
  }

  private func item(for section: AppSection) -> some View {
    Label {
      HStack(spacing: Metrics.xs) {
        Text(section.title)
        if section == .cycles, state.pendingDraftCount > 0 {
          Pill("\(state.pendingDraftCount)", tone: .warn)
        }
      }
    } icon: {
      Image(systemName: section.icon)
    }
    .tag(section)
  }
}

/// Account, service health and the way into Settings — the three things that
/// have to be reachable from anywhere and belong to no section.
private struct SidebarFooter: View {
  @Environment(AppState.self) private var state

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xs) {
      Divider()
      // Name and status share one line, matching the web console. Stacked, the
      // footer was two lines tall for two short strings and read as two
      // separate facts rather than one line about this account.
      HStack(spacing: Metrics.xs) {
        // The name is a menu, because that is where everyone looks for account
        // actions — it is where every other Mac app puts them. The previous
        // answer to "怎么退出登录" was a paragraph in Settings explaining that
        // there is no session to end; there is one now, and this is where the
        // person asking that question was already looking.
        AccountMenu()
        StatusDot(
          state.service.state.label,
          tone: state.service.state.tone,
          pulsing: state.service.state == .running
        )
        Spacer(minLength: 0)
        Button {
          state.section = .settings
        } label: {
          Image(systemName: "gearshape")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.inkMuted)
        .help("设置 (⌘,)")
      }
      .padding(.horizontal, Metrics.sm)
      .padding(.bottom, Metrics.xs)
    }
  }
}

/// Says once, at the top, why every screen is empty.
///
/// Replaces the folder picker that used to be the first thing the app showed.
/// The difference that matters is not the wording — it is that you are *inside*
/// the app, can look around, and can fix it from Settings when you feel like
/// it, rather than being held at a question before you have seen anything.
private struct DisconnectedBanner: View {
  @Environment(AppState.self) private var state

  var body: some View {
    HStack(spacing: Metrics.xs) {
      Image(systemName: "bolt.horizontal.circle").foregroundStyle(Palette.warn)
      VStack(alignment: .leading, spacing: 1) {
        Text("没有连接到 daily-os 服务").inkStyle(Typo.bodyStrong)
        Text("所有页面都是空的——这里没有示例数据冒充你的内容。去设置里指定服务文件夹，或者让它再找一次。")
          .mutedStyle()
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: Metrics.xs)
      Button("去设置") { state.section = .settings }
        .buttonStyle(MossButtonStyle())
    }
    .padding(.horizontal, Metrics.lg)
    .padding(.vertical, Metrics.sm)
    .background(Palette.softBackground(for: .warn))
    .overlay(alignment: .bottom) {
      Rectangle().fill(Palette.line).frame(height: Metrics.hairline)
    }
  }
}

/// Avatar plus name, as a menu.
///
/// The name is the **console account** — the row in the service's `users` table
/// that this app signed in against. It used to be `account.displayName`, which
/// is filled from `team.self.memberId`: a team member id, printed on the one
/// line of the window that claims to say who you are. `ConsoleSession` exists to
/// keep those two apart, and this is the line that was getting them wrong.
///
/// The avatar is a sibling of the menu rather than part of its label. It was
/// inside, and `.menuStyle(.borderlessButton)` clamps the label to the height of
/// a line of text — about 16pt — so a 20pt canvas was cropped until there was
/// nothing left to see. Nothing about a menu requires its label to carry the
/// picture, so the picture sits outside where no menu style can shrink it.
///
/// 退出团队登录 is deliberately not here. Team sign-out is a different account
/// (Supabase), it already has a confirm flow in 设置 → 团队, and a second door
/// to it from the account menu only makes the two identities look like one.
struct AccountMenu: View {
  @Environment(AppState.self) private var state

  var body: some View {
    HStack(spacing: Metrics.xxs) {
      PixelAvatar(seed: avatarSeed, size: 20)
      Menu {
        if let session = state.session {
          Section("\(session.username) · \(session.role.label)") {
            Button("退出登录") { Task { _ = await state.signOut() } }
          }
          Divider()
        }
        Button("账号与服务设置…") { state.section = .settings }
        Divider()
        // Said here because this is where someone decides what 退出登录 means,
        // and the honest answer is narrower than the words suggest.
        Text("登录只决定「谁在用这台 App」。连服务靠的是本机的运行令牌，退出登录不会锁上任何东西——能登进这台 Mac 的人照样连得上。")
        Text("退出后会回到登录页，可以换个人登录。")
      } label: {
        HStack(spacing: Metrics.xxs) {
          Text(name)
            .inkStyle(Typo.caption)
            .lineLimit(1)
          Image(systemName: "chevron.up.chevron.down")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(Palette.inkMuted)
        }
        .contentShape(Rectangle())
      }
      .menuStyle(.borderlessButton)
      .menuIndicator(.hidden)
      .fixedSize()
    }
    .help("账号")
  }
}

private extension AccountMenu {
  /// Never `account.displayName`: connected, that string is the team member id,
  /// which is the whole bug. Without a session there are only two honest things
  /// to say, and which one depends on whether anything is wired at all.
  var name: String {
    if let session = state.session { return session.username }
    return state.wiredSections.isEmpty ? "未连接" : "未登录"
  }

  /// `/api/login` answers with a name and a role and no seed, so the username
  /// stands in — which is what the console's own renderer falls back to, so one
  /// account draws the same avatar in the browser and here.
  var avatarSeed: String {
    guard let session = state.session else { return "" }
    return session.avatarSeed.isEmpty ? session.username : session.avatarSeed
  }
}

// MARK: - Previews

#Preview("整个窗口") {
  RootView(state: AppState.previewOwner())
    .frame(width: 1_120, height: 760)
}
