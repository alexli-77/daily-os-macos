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
      ListColumn {
        CycleList()
      }
      Group {
        if let cycle = state.selectedCycle {
          CycleDetail(cycle: cycle)
        } else {
          emptyDetail
        }
      }
      .frame(maxWidth: .infinity)
    }
    .background(Palette.paper)
  }

  private var emptyDetail: some View {
    EmptyState(
      icon: "calendar.badge.plus",
      title: "还没有周期",
      message: state.isViewingSelf
        ? "跑一次「周期规划」，或者直接在 20_CYCLES/ 里建一个 markdown 文件。"
        : "队友还没有同步过任何周期。",
      actionTitle: state.isViewingSelf ? "跑一次规划" : nil,
      action: state.isViewingSelf ? {} : nil
    )
  }
}

// MARK: - Member switcher

/// Self vs teammate. Placed above the cycle list rather than in a toolbar
/// because switching it changes what the entire screen means, and a control
/// that changes the meaning of a screen should sit inside it.
private struct MemberSwitcher: View {
  @Environment(AppState.self) private var state

  var body: some View {
    @Bindable var state = state
    VStack(alignment: .leading, spacing: Metrics.xs) {
      Picker("查看", selection: $state.viewingMemberID) {
        ForEach(state.members) { member in
          Text(member.isSelf ? "我" : member.displayName).tag(member.id)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()

      if !state.isViewingSelf, let member = state.viewingMember {
        HStack(spacing: Metrics.xxs) {
          Image(systemName: "lock").font(.caption2)
          Text("来自 \(member.displayName) · 只读")
          if let synced = member.lastSyncedAt {
            Text("· 同步于 \(Fmt.time(synced))")
          }
        }
        .mutedStyle()
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
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 2) {
          ForEach(state.visibleCycles) { cycle in
            SelectableRow(isSelected: cycle.id == state.selectedCycle?.id) {
              state.selectedCycleID = cycle.id
            } content: {
              CycleListRow(cycle: cycle)
            }
          }
        }
        .padding(Metrics.xs)
      }
    }
  }
}

private struct CycleListRow: View {
  let cycle: Cycle

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xxs) {
      HStack(spacing: Metrics.xs) {
        Text(cycle.label).inkStyle(Typo.bodyStrong)
        Pill(cycle.mode.label)
        if cycle.hasPendingDraft {
          Pill("新草稿", tone: .warn)
        }
      }
      Text("更新于 \(Fmt.stamp(cycle.updatedAt))").mutedStyle()
    }
  }
}

// MARK: - Detail

private struct CycleDetail: View {
  @Environment(AppState.self) private var state
  let cycle: Cycle

  var body: some View {
    ScreenScaffold(cycle.label, subtitle: subtitle) {
      ForEach(CycleSectionKind.allCases) { kind in
        if let section = cycle.section(kind) {
          CycleSectionPanel(cycle: cycle, section: section, editable: state.isViewingSelf)
        }
      }
    } toolbar: {
      if let runId = cycle.runId {
        Pill(runId, tone: .neutral, mono: true)
      }
    }
  }

  private var subtitle: String {
    var parts = [cycle.mode.label, cycle.relativePath]
    if !state.isViewingSelf { parts.append("只读") }
    return parts.joined(separator: " · ")
  }
}

/// One of the three sections. Body, provenance, and — when the planner has
/// produced something newer than your edits — the merge affordance.
private struct CycleSectionPanel: View {
  @Environment(AppState.self) private var state
  let cycle: Cycle
  let section: CycleSection
  let editable: Bool

  @State private var isEditing = false
  @State private var draft = ""
  @State private var showsDraftComparison = false

  var body: some View {
    Panel(section.kind.label, subtitle: section.kind.hint) {
      VStack(alignment: .leading, spacing: Metrics.sm) {
        // Gated on `editable`, not just on the draft existing. `acceptDraft`
        // only ever writes to `cycles` — your own — so on a teammate's cycle the
        // 合入 and 丢弃 buttons would render and then do nothing. Read-only means
        // the control is absent, and a control that is present but inert is the
        // worst of the three options.
        if section.pendingDraft != nil, editable {
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
            LabeledBody(label: "planner 新草稿", text: pending, tone: .warn)
          }
        } else if isEditing {
          TextEditor(text: $draft)
            .font(Typo.monoBody)
            .scrollContentBackground(.hidden)
            .padding(Metrics.xs)
            .frame(minHeight: 180)
            .background(Palette.surfaceSunken)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
        } else {
          Text(section.body.isEmpty ? "（空）" : section.body)
            .font(Typo.body)
            .foregroundStyle(section.body.isEmpty ? Palette.inkMuted : Palette.ink)
            .textSelection(.enabled)
            .frame(maxWidth: Metrics.readableWidth, alignment: .leading)
        }

        HStack(spacing: Metrics.xs) {
          Pill(section.source.label, tone: section.source.tone)
          // On a teammate's cycle the draft is still worth knowing about — it
          // explains why their 要务 and their retro disagree — so the fact
          // survives read-only even though the merge actions do not.
          if section.pendingDraft != nil, !editable {
            Pill("有新草稿", tone: .warn)
          }
          Text("更新于 \(Fmt.stamp(section.updatedAt))").mutedStyle()
        }
      }
    } actions: {
      if editable {
        if isEditing {
          Button("保存") {
            state.updateSection(cycleID: cycle.id, kind: section.kind, body: draft)
            isEditing = false
          }
          .buttonStyle(QuietButtonStyle())
          Button("取消") { isEditing = false }
            .buttonStyle(QuietButtonStyle(tone: .neutral))
        } else {
          Button("编辑") {
            draft = section.body
            isEditing = true
          }
          .buttonStyle(QuietButtonStyle())
        }
      }
    }
  }
}

private struct DraftBanner: View {
  @Binding var expanded: Bool
  let onAccept: () -> Void
  let onDiscard: () -> Void

  var body: some View {
    HStack(spacing: Metrics.xs) {
      Image(systemName: "arrow.triangle.branch").foregroundStyle(Palette.warn)
      Text("planner 有一版新草稿。你手工改过这一段，所以没有自动覆盖。")
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
/// no edit controls and no merge banner, from the same view.
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
