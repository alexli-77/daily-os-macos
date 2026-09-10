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
        // there is no session; a correct explanation nobody finds is not an
        // answer, it is the same dead end with better prose.
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
/// What "退出登录" can honestly mean here, in order:
///
/// 1. **The team session.** Supabase is the one real account this app holds —
///    an email, a password, a session on this machine. Signing out of it is a
///    genuine sign-out and it is what the menu offers when there is one.
/// 2. **Nothing else.** The app's own access is the service's runtime token,
///    read from a file on this disk. There is no session to end; "logging out"
///    would mean deleting someone else's file. The menu says so in one line
///    rather than offering a button that cannot work.
///
/// The old screen got (2) right and buried it three panels down in Settings.
struct AccountMenu: View {
  @Environment(AppState.self) private var state

  var body: some View {
    Menu {
      Section(state.account.displayName) {
        Button("账号与服务设置…") { state.section = .settings }
      }
      Divider()
      // `isReady` is the closest thing to "signed in" the service reports: team
      // sync only reaches ready once this machine has a Supabase session. Not
      // renamed to `isSignedIn` here because the service's word is `ready` and
      // inventing a synonym in the client is how two vocabularies start.
      if state.teamSync?.isReady == true {
        Button("退出团队登录…") { state.section = .settings }
        Text("在设置 → 团队里确认。退出只清掉这台机器上的团队会话，本地文件不动。")
      } else {
        Text("这个 App 用本机服务的令牌工作，没有账号会话，也就没有可以退出的登录。")
        Text("唯一的真实登录是团队同步（Supabase），去设置 → 团队里登录。")
      }
    } label: {
      HStack(spacing: Metrics.xs) {
        PixelAvatar(seed: state.account.avatarSeed, size: 20)
        Text(state.account.displayName)
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
    .help("账号")
  }
}

// MARK: - Previews

#Preview("整个窗口") {
  RootView(state: AppState.previewOwner())
    .frame(width: 1_120, height: 760)
}
