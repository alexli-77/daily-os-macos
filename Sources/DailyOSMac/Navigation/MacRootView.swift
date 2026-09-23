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
        } else if !state.loadFailures.isEmpty {
          LoadFailureBanner()
        }
        SectionView(section: state.section)
      }
      .frame(minWidth: 560, minHeight: 420)
    }
    .background(Palette.paper)
    .toastOverlay()
    // The chat panel drops from the top on the right, over the detail column —
    // same conversation as the Chat section, reachable from anywhere without
    // leaving the current screen. topTrailing so it hangs under the toolbar's
    // chat button; the transition slides it down from the top edge.
    .overlay(alignment: .topTrailing) {
      if state.chatPanelOpen {
        ChatPanel(isOpen: $state.chatPanelOpen)
          .padding(.trailing, Metrics.sm)
          .transition(.move(edge: .top).combined(with: .opacity))
          .zIndex(1)
      }
    }
    .animation(.spring(response: 0.32, dampingFraction: 0.86), value: state.chatPanelOpen)
    .toolbar {
      ToolbarItem(placement: .automatic) {
        Button {
          state.chatPanelOpen.toggle()
        } label: {
          Image(systemName: "bubble.left.and.bubble.right")
        }
        .help("聊天（⌘⇧C）")
      }
    }
  }
}

/// Hand-drawn rather than `List(selection:).listStyle(.sidebar)`.
///
/// The stock sidebar paints its selected row in the system accent — blue on a
/// default Mac. There is no blue in this product, and the row was also reversed
/// out to white type, which the palette forbids outright. Both were wrong in the
/// most-looked-at control in the app.
///
/// `.tint()` does not fix it: on macOS the sidebar's selection is drawn by the
/// platform and ignores the tint, so the only way to own the colour is to draw
/// the row. What that costs is the List's built-in arrow-key navigation, which
/// `SectionCommands` in the app target already covers with ⌘1…⌘7.
///
/// Geometry and colour follow the Today-page comp (`spec/today-page.html`,
/// `.side`), which is the authority for this screen.
///
/// Deliberately not `SelectableRow` from the design system, which the Settings
/// screen's left column uses: that one is a 4pt-radius row filled with `mossSoft`,
/// and widening it to cover this case would change Settings in a PR that is not
/// about Settings. Worth merging once both have settled.
private struct Sidebar: View {
  @Environment(AppState.self) private var state
  @Binding var selection: AppSection

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: Metrics.xxs) {
        ForEach(AppSection.workGroup) { row(for: $0) }
        SectionLabel("系统")
        ForEach(AppSection.systemGroup) { row(for: $0) }
      }
      .padding(Metrics.xs)
    }
    .scrollContentBackground(.hidden)
    .safeAreaInset(edge: .bottom, spacing: 0) {
      SidebarFooter()
    }
    // After the inset, so paper covers the footer strip too. Applied inside the
    // scroll view instead, the footer would keep sitting on the split view's
    // own translucent sidebar material.
    .background(Palette.paper)
    .navigationTitle("Daily OS")
  }

  private func row(for section: AppSection) -> some View {
    SidebarRow(
      section: section,
      isSelected: section == selection,
      badge: section == .cycles && state.pendingDraftCount > 0 ? state.pendingDraftCount : nil
    ) {
      selection = section
    }
  }
}

/// One navigation row.
///
/// Selected is a sheet of `page` lifted off the `paper` sidebar by a hairline
/// under it — the same two-paper relationship the Today sheet has with its
/// background, at pill scale. Not a mint fill: the accent is spent inside the
/// day (the now-line, a completed dot, overdue text), and a permanently mint row
/// in the corner of every screen would be the loudest thing in the window while
/// saying the least. See `.side a[aria-current]` in the comp.
///
/// No hover state, also from the comp. Seven rows that all light up under the
/// pointer turn a quiet rail into something that flickers on the way to the
/// content, and the selected row already says where you are.
private struct SidebarRow: View {
  let section: AppSection
  let isSelected: Bool
  let badge: Int?
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: Metrics.xs) {
        Image(systemName: section.icon).frame(width: 18)
        Text(section.title)
        if let badge {
          Pill("\(badge)", tone: .warn)
        }
        Spacer(minLength: 0)
      }
      .font(Typo.body)
      // The whole row, icon included, is one colour. Tinting the icon and
      // leaving the label ink — which the Settings list does — reads as two
      // states on one row when the row already has a fill saying "selected".
      .foregroundStyle(isSelected ? Palette.ink : Palette.ink2)
      .padding(.horizontal, Metrics.sm)
      .padding(.vertical, Metrics.xs)
      .frame(maxWidth: .infinity, alignment: .leading)
      .frame(minHeight: Metrics.hitTarget)
      .background {
        if isSelected {
          // `box-shadow: 0 1px 0 var(--rule)` in the comp — a hard 1pt line
          // directly under the pill, not a blur. Radius 0 is what makes it a
          // line: any blur reads as a drop shadow, and this palette has no
          // depth effects in it.
          shape
            .fill(Palette.page)
            .shadow(color: Palette.rule, radius: 0, x: 0, y: Metrics.hairline)
        }
      }
      .contentShape(shape)
    }
    .buttonStyle(.plain)
    // The row is a button drawing its own selection, so nothing else tells
    // VoiceOver which section you are in.
    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: Metrics.radiusPill, style: .continuous)
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

/// Says which of the reload's independent reads did not come back.
///
/// Same slot as `DisconnectedBanner`, and there for the same reason: a failed
/// chunk empties one panel and leaves the other six alone, so the panel it
/// empties is indistinguishable from a panel with nothing in it. The
/// attribution `reload()` computes had no reader in the app at all — it went to
/// `lastError`, which only the command-line probe looked at — so "团队面板是空
/// 的" and "团队读取失败了" were the same picture.
///
/// Never both banners at once: with nothing wired every panel is empty for one
/// reason, and that one is the reason.
private struct LoadFailureBanner: View {
  @Environment(AppState.self) private var state

  var body: some View {
    HStack(spacing: Metrics.xs) {
      Image(systemName: "exclamationmark.triangle").foregroundStyle(Palette.warn)
      VStack(alignment: .leading, spacing: 1) {
        // Wraps rather than truncates, unlike most one-line headlines: the list
        // of names *is* the message here, and with all seven chunks down the
        // string is long enough that a narrow window would ellipsize away the
        // only part worth reading. The detail line below has always wrapped for
        // the same reason.
        Text("\(names)没读到")
          .inkStyle(Typo.bodyStrong)
          .fixedSize(horizontal: false, vertical: true)
        // Absent, not blank. A transport error can carry an empty description,
        // and an empty `Text` still takes a line's height — a gap under the
        // headline that reads as something failing to render.
        if let detail {
          Text(detail)
            .mutedStyle()
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: Metrics.xs)
    }
    .padding(.horizontal, Metrics.lg)
    .padding(.vertical, Metrics.sm)
    .background(Palette.softBackground(for: .warn))
    .overlay(alignment: .bottom) {
      Rectangle().fill(Palette.line).frame(height: Metrics.hairline)
    }
  }

  /// In `allCases` order rather than the dictionary's, which is unordered and
  /// would let two failures swap places between redraws.
  private var failures: [(chunk: ReloadChunk, reason: String)] {
    ReloadChunk.allCases.compactMap { chunk in
      state.loadFailures[chunk].map { (chunk, $0) }
    }
  }

  private var names: String { failures.map(\.chunk.label).joined(separator: "、") }

  /// One reason, not all of them. When several reads fail together it is almost
  /// always the same sentence about the same service, and a banner is one line
  /// tall — the list of *what* failed is the part that differs.
  ///
  /// The first one that says something, rather than the first one: reasons come
  /// from `localizedDescription` and can be empty, and skipping a blank to reach
  /// a real sentence is strictly better than showing neither.
  private var detail: String? { failures.first { !$0.reason.isEmpty }?.reason }
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
