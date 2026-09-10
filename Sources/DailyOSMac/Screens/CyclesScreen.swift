import SwiftUI
import DailyOSCore

/// The centre of the product.
///
/// A cycle is one markdown file with three independently-sourced sections. Two
/// things have to be legible at all times and drive the whole layout:
///
/// 1. **Who wrote this section** — planner, you, or the model. A planner rerun
///    that quietly overwrote something you typed would destroy the only copy.
/// 2. **Whose cycle you are looking at.** A teammate's cycle is read-only, and
///    the read-only-ness is a property of the data, not a disabled button.
struct CyclesScreen: View {
  @Environment(AppState.self) private var state

  var body: some View {
    HStack(spacing: 0) {
      ResizableListColumn(id: "cycles") {
        CycleList()
      }
      Group {
        if let cycle = state.selectedCycle {
          CycleDetail(cycle: cycle)
        } else {
          EmptyState(
            icon: "calendar.badge.plus",
            title: "还没有周期",
            message: state.isViewingSelf
              ? "跑一次「周期规划」，或者直接在 20_CYCLES/ 里建一个 Markdown 文件。"
              : "队友还没有同步过任何周期。",
            actionTitle: state.isViewingSelf ? "跑一次规划" : nil,
            action: state.isViewingSelf ? {} : nil
          )
        }
      }
      .frame(maxWidth: .infinity)
    }
    .background(Palette.paper)
  }
}

// MARK: - Member switcher

/// Self vs teammate. Placed above the cycle list rather than in a toolbar
/// because switching it changes what the entire screen means, and a control
/// that changes the meaning of a screen should sit inside it.
private struct MemberSwitcher: View {
  @Environment(AppState.self) private var state

  /// Everyone but me. Zero of these is the common case and is not an error.
  private var teammates: [TeamMember] { state.members.filter { !$0.isSelf } }

  var body: some View {
    @Bindable var state = state
    VStack(alignment: .leading, spacing: Metrics.xs) {
      HStack(spacing: Metrics.xs) {
        Text("团队").mutedStyle(Typo.label)
        Spacer(minLength: 0)
        if let sync = state.teamSync {
          StatusDot(sync.label, tone: sync.tone)
        }
      }

      if teammates.isEmpty {
        // The web shows this area even with nobody in it, and so does this.
        // A team panel that disappears when the team is empty makes "sync is
        // off" and "nobody has joined" look like the same nothing.
        Text(emptyMessage).mutedStyle()
      } else {
        Picker("查看", selection: $state.viewingMemberID) {
          ForEach(state.members) { member in
            Text(member.isSelf ? "我" : member.displayName).tag(member.id)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
      }

      if !state.isViewingSelf, let member = state.viewingMember {
        HStack(spacing: Metrics.xxs) {
          Image(systemName: "lock").font(.caption2)
          Text("来自 \(member.displayName) · 只读")
          if let synced = member.lastSyncedAt {
            Text("· 同步于 \(Fmt.time(synced))")
          }
        }
        .mutedStyle()
      } else if let sync = state.teamSync {
        SyncFootnote(sync: sync)
      }
    }
  }

  private var emptyMessage: String {
    guard let sync = state.teamSync else { return "还没有队友的周期可以看。" }
    if !sync.isReady {
      return sync.reason.isEmpty ? "同步未开启，只能看自己的周期。" : sync.reason
    }
    return "还没有队友的周期可以看。等对方加入并同步之后会出现在这里。"
  }
}

/// When the last sync ran, and what went wrong if something did.
///
/// Freshness is the whole value of a read-only teammate view: a cycle synced
/// three days ago is not what they are working on now, and a view that does not
/// say so invites you to act on it as though it were.
private struct SyncFootnote: View {
  let sync: TeamSyncState

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      if let synced = sync.syncedAt {
        Text("同步于 \(Fmt.stamp(synced))").mutedStyle()
      }
      if !sync.lastError.isEmpty {
        Text(sync.lastError)
          .font(Typo.caption)
          .foregroundStyle(Palette.danger)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }
}

// MARK: - List

private struct CycleList: View {
  @Environment(AppState.self) private var state

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      MemberSwitcher()
        .padding(Metrics.sm)
      Divider()
      CycleTrend()
      Divider()
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2, pinnedViews: .sectionHeaders) {
          ForEach(state.visibleCycleGroups) { group in
            Section {
              ForEach(group.cycles) { cycle in
                SelectableRow(isSelected: cycle.id == state.selectedCycle?.id) {
                  state.selectedCycleID = cycle.id
                } content: {
                  CycleListRow(cycle: cycle, isCurrent: group.kind == .current)
                }
              }
            } header: {
              CycleGroupHeader(group: group)
            }
          }
        }
        .padding(Metrics.xs)
      }
    }
  }
}

/// 要务 completion across cycles, oldest to newest.
///
/// The list answers "which cycle", one at a time. This answers the question the
/// list cannot: whether the last few have been going better or worse. That is a
/// shape, and reading a shape out of twelve rows of dates is not something
/// anybody does.
///
/// Only cycles whose 要务 carry status markers are plotted. This is not a corner
/// case — on a real vault most cycles have some unmarked lines and a few have
/// none at all — and drawing an unmarked cycle as 0% would invent a collapse out
/// of an absence. The count of skipped ones is stated instead, because a gap in
/// a trend line is exactly the kind of thing that gets read as a fact.
private struct CycleTrend: View {
  @Environment(AppState.self) private var state

  /// The newest eight. Enough to see a direction; more than that in a 320pt
  /// column puts the dots closer together than they are wide.
  private static let window = 8

  private var plotted: [(cycle: Cycle, completion: CycleCompletion)] {
    state.visibleCycles
      .compactMap { cycle in cycle.completion.map { (cycle: cycle, completion: $0) } }
      .sorted { $0.cycle.start < $1.cycle.start }
      .suffix(Self.window)
      .map { $0 }
  }

  private var skipped: Int { state.visibleCycles.count - plotted.count }

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xs) {
      HStack(spacing: Metrics.xs) {
        Text("要务完成率").mutedStyle(Typo.label)
        Spacer(minLength: 0)
        if let latest = plotted.last {
          Text(latest.completion.percentText)
            .font(Typo.tabularCaption.weight(.medium))
            .foregroundStyle(Palette.moss)
        }
      }

      if plotted.count < 2 {
        // A line through one point is a dot, and a dot is not a trend. Say
        // which of the two reasons applies rather than drawing a flat line.
        Text(plotted.isEmpty
          ? "还没有标记过状态的周期。在要务里点三色圈之后，这里会画出完成率曲线。"
          : "只有一期标记过状态，还画不出趋势。")
          .mutedStyle()
          .fixedSize(horizontal: false, vertical: true)
      } else {
        TrendLine(points: points) { point in
          state.selectedCycleID = point.id
        }
        .frame(height: 48)

        HStack(spacing: Metrics.xs) {
          Text(plotted.first?.cycle.label ?? "").mutedStyle()
          Spacer(minLength: 0)
          Text(plotted.last?.cycle.label ?? "").mutedStyle()
        }
      }

      // Only alongside a drawn line. With nothing plotted, "另有 12 期" reads as
      // "in addition to the ones above" when there are none above — and the
      // sentence beside it already said so.
      if skipped > 0, plotted.count >= 2 {
        Text("另有 \(skipped) 期没有状态标记，没画进来。").mutedStyle()
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(Metrics.sm)
  }

  private var points: [TrendPoint] {
    plotted.map { entry in
      TrendPoint(
        id: entry.cycle.id,
        label: entry.cycle.label,
        value: entry.completion.fraction,
        isCurrent: entry.cycle.id == state.selectedCycle?.id,
        detail: "\(entry.completion.done)/\(entry.completion.tracked) 完成 · \(entry.completion.percentText)"
      )
    }
  }
}

/// Pinned, so scrolling twelve cycles never leaves you unsure which era you are
/// looking at. Opaque for the same reason — a translucent header with row text
/// sliding under it is unreadable at this type size.
private struct CycleGroupHeader: View {
  let group: CycleGroup

  var body: some View {
    HStack(spacing: Metrics.xs) {
      Text(group.title).mutedStyle(Typo.label)
      if group.cycles.count > 1 {
        Text("\(group.cycles.count)").font(Typo.tabularCaption).foregroundStyle(Palette.inkMuted)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Metrics.xs)
    .padding(.top, Metrics.xs)
    .padding(.bottom, Metrics.xxs)
    .background(Palette.surface)
  }
}

private struct CycleListRow: View {
  let cycle: Cycle
  var isCurrent = false

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xxs) {
      HStack(spacing: Metrics.xs) {
        Text(cycle.label).inkStyle(Typo.bodyStrong)
        Pill(cycle.mode.label)
        if cycle.hasPendingDraft {
          Pill("新草稿", tone: .warn)
        }
      }
      // A moss dot on the row you are inside. The heading already says 本期, but
      // the heading scrolls and a selected row does not always sit under it.
      HStack(spacing: Metrics.xxs) {
        if isCurrent {
          Circle().fill(Palette.moss).frame(width: 5, height: 5)
          Text("进行中").font(Typo.caption).foregroundStyle(Palette.moss)
          Text("·").mutedStyle()
        }
        Text("更新于 \(Fmt.stamp(cycle.updatedAt))").mutedStyle()
      }
    }
  }
}

// MARK: - Detail

private struct CycleDetail: View {
  @Environment(AppState.self) private var state
  let cycle: Cycle

  var body: some View {
    ScreenScaffold(cycle.label, subtitle: subtitle) {
      if let problem = cycle.frontmatterError {
        BrokenFrontmatterBanner(cycle: cycle, problem: problem)
      }
      ForEach(CycleSectionKind.allCases) { kind in
        if let section = cycle.section(kind) {
          CycleSectionPanel(
            cycle: cycle,
            section: section,
            editable: state.isViewingSelf && cycle.isWritable
          )
        }
      }
    } toolbar: {
      if let runId = cycle.runId {
        Pill(runId, tone: .neutral, mono: true)
      }
    }
  }

  private var subtitle: String {
    // Leads with 本期 / 往期. Opening a cycle from the list and then editing it
    // is the whole loop of this screen, and "which one is this" has to survive
    // the moment the list scrolls out of your attention.
    var parts = [era, cycle.mode.label, cycle.relativePath]
    if !state.isViewingSelf { parts.append("只读") }
    return parts.joined(separator: " · ")
  }

  private var era: String {
    if cycle.contains(.now) { return "本期" }
    return cycle.isUpcoming() ? "计划中" : "往期"
  }
}

// MARK: - Section

private enum SectionMode: String, CaseIterable, Identifiable {
  case read
  case edit

  var id: String { rawValue }
  var label: String { self == .read ? "阅读" : "编辑" }
}

/// One of the three sections, in either mode.
///
/// Read mode renders the markdown as the thing it describes — for 要务 that
/// means groups, status dots and badges rather than a wall of `- ` lines. Edit
/// mode shows the file. Both are needed: the rendered view is what you use
/// daily, and the raw view is the escape hatch for everything the renderer does
/// not know about, which in a hand-edited markdown file is always something.
///
/// Switching to 阅读 with unsaved text keeps the draft rather than discarding
/// it, so the toggle can never eat typing and needs no confirmation dialog.
private struct CycleSectionPanel: View {
  @Environment(AppState.self) private var state
  let cycle: Cycle
  let section: CycleSection
  let editable: Bool

  @State private var mode: SectionMode = .read
  @State private var draft: String?
  @State private var showsDraftComparison = false

  private var isDirty: Bool {
    guard let draft else { return false }
    return draft != section.body
  }

  var body: some View {
    Panel(section.kind.label, subtitle: section.kind.hint) {
      VStack(alignment: .leading, spacing: Metrics.sm) {
        if section.pendingDraft != nil {
          DraftBanner(
            expanded: $showsDraftComparison,
            onAccept: { state.acceptDraft(cycleID: cycle.id, kind: section.kind) },
            onDiscard: { state.discardDraft(cycleID: cycle.id, kind: section.kind) }
          )
        }

        if showsDraftComparison, let pending = section.pendingDraft {
          TwoColumns {
            LabeledBody(label: "当前（你的版本）", text: section.body)
          } trailing: {
            LabeledBody(label: "自动规划的新草稿", text: pending, tone: .warn)
          }
        } else if mode == .edit {
          TextEditor(text: Binding(
            get: { draft ?? section.body },
            set: { draft = $0 }
          ))
          .font(Typo.monoBody)
          .scrollContentBackground(.hidden)
          .padding(Metrics.xs)
          .frame(minHeight: 220)
          .background(Palette.surfaceSunken)
          .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
        } else if section.kind == .priorities {
          PrioritiesView(cycle: cycle, section: section, editable: editable)
        } else {
          Text(section.body.isEmpty ? "（空）" : section.body)
            .font(Typo.body)
            .foregroundStyle(section.body.isEmpty ? Palette.inkMuted : Palette.ink)
            .textSelection(.enabled)
            .frame(maxWidth: Metrics.readableWidth, alignment: .leading)
        }

        HStack(spacing: Metrics.xs) {
          Pill(section.source.label, tone: section.source.tone)
          Text("更新于 \(Fmt.stamp(section.updatedAt))").mutedStyle()
          if isDirty {
            Pill("未保存", tone: .warn)
          }
        }
      }
    } actions: {
      if section.isTemplate {
        Pill("模板", tone: .neutral)
      }
      if editable {
        Picker("", selection: $mode) {
          ForEach(SectionMode.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 130)

        if mode == .edit {
          Button("保存") {
            state.updateSection(cycleID: cycle.id, kind: section.kind, body: draft ?? section.body)
            draft = nil
            mode = .read
          }
          .buttonStyle(QuietButtonStyle())
          .disabled(!isDirty)
        }
      }
    }
  }
}

// MARK: - Priorities

/// 要务 in read mode: OKR-row groups, each item with its three status dots.
private struct PrioritiesView: View {
  @Environment(AppState.self) private var state
  let cycle: Cycle
  let section: CycleSection
  let editable: Bool

  var body: some View {
    let doc = section.priorities
    if doc.isEmpty {
      Text("（空）").mutedStyle(Typo.body)
    } else {
      VStack(alignment: .leading, spacing: Metrics.md) {
        if doc.markedCount > 0 {
          HStack(spacing: Metrics.xs) {
            Text("\(doc.doneCount) / \(doc.trackedCount) 完成")
              .font(Typo.tabularCaption)
              .foregroundStyle(Palette.inkMuted)
            ProgressTrack(fraction: Double(doc.doneCount) / Double(doc.trackedCount), tone: .ok)
              .frame(maxWidth: 160)
          }
        } else if doc.trackedCount > 0 {
          // Gated on markers rather than on items. An untouched cycle drew a
          // full-width empty bar reading "0 / 13 完成", which says the work was
          // attempted and none of it landed — while the trend beside it
          // correctly refused to plot the same cycle as zero. One file, two
          // stories, and the discouraging one was the lie.
          Text("\(doc.trackedCount) 条要务，还没标记过状态")
            .font(Typo.tabularCaption)
            .foregroundStyle(Palette.inkMuted)
        }

        if !doc.loose.isEmpty {
          itemList(doc.loose)
        }
        ForEach(doc.groups) { group in
          VStack(alignment: .leading, spacing: Metrics.xs) {
            Text(group.title).inkStyle(Typo.heading)
            if group.items.isEmpty {
              Text("这一行下没有条目。").mutedStyle()
            } else {
              itemList(group.items)
            }
          }
        }
      }
    }
  }

  private func itemList(_ items: [PriorityItem]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(items) { item in
        PriorityRow(cycle: cycle, item: item, editable: editable)
      }
    }
  }
}

private struct PriorityRow: View {
  @Environment(AppState.self) private var state
  let cycle: Cycle
  let item: PriorityItem
  let editable: Bool

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
      TaskDots(current: item.status, enabled: editable) { status in
        state.setPriorityStatus(cycleID: cycle.id, line: item.sourceLine, to: status)
      }
      if item.isMIT {
        Text("MIT")
          .font(Typo.label)
          .foregroundStyle(.white)
          .padding(.horizontal, Metrics.xs)
          .padding(.vertical, 2)
          .background(Palette.danger, in: Capsule())
      }
      Text(item.text)
        .font(Typo.body)
        .foregroundStyle(item.status == .done ? Palette.inkMuted : Palette.ink)
        .strikethrough(item.status == .done, color: Palette.inkMuted)
        .textSelection(.enabled)
      ForEach(item.refs, id: \.self) { ref in
        Pill(ref, tone: .neutral, mono: true)
      }
      Spacer(minLength: 0)
    }
    .padding(.vertical, Metrics.xxs)
    .overlay(alignment: .leading) {
      Rectangle()
        .fill(item.status.map { Palette.foreground(for: $0.tone) } ?? Palette.line)
        .frame(width: 2)
        .offset(x: -Metrics.xs)
    }
  }
}

/// The three dots: 完成 / 部分 / 未做.
///
/// Clicking the one that is already set clears it, matching the web console —
/// there is no fourth "unset" dot to aim at, and marking something by mistake
/// has to be undoable in the same gesture that caused it.
private struct TaskDots: View {
  let current: CycleTaskStatus?
  let enabled: Bool
  let onPick: (CycleTaskStatus?) -> Void

  var body: some View {
    HStack(spacing: 3) {
      ForEach(CycleTaskStatus.allCases) { status in
        let isOn = current == status
        Button {
          onPick(isOn ? nil : status)
        } label: {
          Circle()
            .strokeBorder(Palette.foreground(for: status.tone), lineWidth: 1.5)
            .background(Circle().fill(isOn ? Palette.foreground(for: status.tone) : .clear))
            .frame(width: 11, height: 11)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(isOn ? "\(status.label)（再点一次取消）" : status.label)
        .accessibilityLabel(Text(status.label))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
      }
    }
    .opacity(enabled ? 1 : 0.55)
  }
}

/// A cycle whose YAML front matter does not parse.
///
/// The service refuses to write *any* section of such a file, so the honest
/// thing is to withdraw the edit controls and say why. The alternative — which
/// is what this screen did until the wire format was checked — is an edit
/// button that accepts your typing and then fails on save, teaching you that
/// the app is broken rather than that the file is.
private struct BrokenFrontmatterBanner: View {
  let cycle: Cycle
  let problem: String

  var body: some View {
    Panel {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        HStack(spacing: Metrics.xs) {
          Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.danger)
          Text("这个周期文件的 front matter 解析不了，暂时不能编辑").inkStyle(Typo.bodyStrong)
        }
        Text(problem)
          .font(Typo.mono)
          .foregroundStyle(Palette.inkMuted)
          .textSelection(.enabled)
        Text("在编辑器里打开 \(cycle.relativePath) 修好文件顶部的 YAML，之后这里会自动恢复可编辑。")
          .mutedStyle(Typo.body)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(Metrics.xs)
      .background(Palette.softBackground(for: .danger))
      .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
    }
  }
}

// MARK: - Draft

private struct DraftBanner: View {
  @Binding var expanded: Bool
  let onAccept: () -> Void
  let onDiscard: () -> Void

  var body: some View {
    HStack(spacing: Metrics.xs) {
      Image(systemName: "arrow.triangle.branch").foregroundStyle(Palette.warn)
      Text("自动规划生成了新草稿。你手工改过这一段，所以没有自动覆盖。")
        .font(Typo.caption)
        .foregroundStyle(Palette.ink)
      Spacer(minLength: Metrics.xs)
      Button(expanded ? "收起" : "对比") { expanded.toggle() }
        .buttonStyle(QuietButtonStyle(tone: .warn))
      Button("合入", action: onAccept).buttonStyle(QuietButtonStyle())
      Button("丢弃", action: onDiscard).buttonStyle(QuietButtonStyle(tone: .neutral))
    }
    .padding(Metrics.xs)
    .background(Palette.softBackground(for: .warn))
    .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
  }
}

private struct LabeledBody: View {
  let label: String
  let text: String
  var tone: Tone = .neutral

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xxs) {
      Text(label).mutedStyle(Typo.label)
      Text(text)
        .font(Typo.mono)
        .foregroundStyle(Palette.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.xs)
        .background(Palette.softBackground(for: tone))
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
    }
  }
}

// MARK: - Previews

#Preview("周期 · 我的") {
  CyclesScreen()
    .environment(AppState.previewOwner())
    .frame(width: 1_040, height: 760)
}

/// The one that has already produced a bug: a teammate's cycle must render with
/// no edit controls, no mode toggle and no clickable dots, from the same view.
#Preview("周期 · 队友只读") {
  CyclesScreen()
    .environment(AppState.previewTeammate())
    .frame(width: 1_040, height: 760)
}

#Preview("周期 · 空状态") {
  CyclesScreen()
    .environment(AppState.previewEmpty())
    .frame(width: 1_040, height: 760)
}
