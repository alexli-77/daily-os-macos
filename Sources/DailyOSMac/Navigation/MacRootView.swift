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
        // A label, not a menu. It was a `Menu`, on the reasoning that account
        // actions belong where people look for them — but the only action it
        // ever held was 退出登录, and a whole disclosure control for one item
        // is a chevron that mostly disappoints. Signing out lives at the foot
        // of 设置 → 基础 now, next to the name and timezone it belongs with.
        //
        // What stays here is what the footer is actually for: who you are and
        // whether the service is up, in one line, from anywhere.
        AccountLabel()
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
        // Names which of the four failures this is. The sentence it replaced —
        // "去设置里指定服务文件夹" — was a dead end on the machine it most
        // needed to help: a teammate's Mac where the service had never been
        // installed, so there was no folder to point at.
        Text(state.serviceDiagnosis.headline).inkStyle(Typo.bodyStrong)
        Text("所有页面都是空的——这里没有示例数据冒充你的内容。")
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

/// Avatar plus name. Not a control.
///
/// The name is the **console account** — the row in the service's `users` table
/// that this app signed in against. It used to be `account.displayName`, which
/// is filled from `team.self.memberId`: a team member id, printed on the one
/// line of the window that claims to say who you are. `ConsoleSession` exists to
/// keep those two apart, and this is the line that was getting them wrong.
///
/// This was a `Menu` for one release. The reasoning was that account actions
/// belong where people look for them, which is true — but the menu held exactly
/// one action, and a disclosure chevron that opens onto a single item is a
/// control that mostly disappoints the person who clicks it. 退出登录 moved to
/// the foot of 设置 → 基础, beside the display name and timezone it belongs
/// with; the footer went back to being a statement rather than a control.
struct AccountLabel: View {
  @Environment(AppState.self) private var state

  var body: some View {
    HStack(spacing: Metrics.xxs) {
      PixelAvatar(seed: avatarSeed, size: 20)
      Text(name)
        .inkStyle(Typo.caption)
        .lineLimit(1)
    }
    .help(state.session.map { "\($0.username) · \($0.role.label)" } ?? "还没有登录")
  }

  /// Never `account.displayName`: connected, that string is the team member id,
  /// which is the whole bug. Without a session there are only two honest things
  /// to say, and which one depends on whether anything is wired at all.
  private var name: String {
    if let session = state.session { return session.username }
    return state.wiredSections.isEmpty ? "未连接" : "未登录"
  }

  /// `/api/login` answers with a name and a role and no seed, so the username
  /// stands in — which is what the console's own renderer falls back to, so one
  /// account draws the same avatar in the browser and here.
  private var avatarSeed: String {
    guard let session = state.session else { return "" }
    return session.avatarSeed.isEmpty ? session.username : session.avatarSeed
  }
}

// MARK: - Previews

#Preview("整个窗口") {
  RootView(state: AppState.previewOwner())
    .frame(width: 1_120, height: 760)
}
