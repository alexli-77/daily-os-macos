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
      SectionView(section: state.section)
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
      HStack(spacing: Metrics.xs) {
        PixelAvatar(seed: state.account.avatarSeed, size: 22)
        VStack(alignment: .leading, spacing: 0) {
          Text(state.account.displayName).inkStyle(Typo.caption)
          StatusDot(state.service.state.label, tone: state.service.state.tone, pulsing: state.service.state == .running)
        }
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

// MARK: - Previews

#Preview("整个窗口") {
  RootView(state: AppState.previewOwner())
    .frame(width: 1_120, height: 760)
}
