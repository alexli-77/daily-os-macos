import SwiftUI
import DailyOSCore

/// 作息 — the one page in 配置 that is half switches and half prose.
///
/// The split is not an accident of implementation, it is the feature: ranking
/// cannot be driven by prose, so "which days are rest days" has to be a value
/// the scorer can read, while "周二周四 19:00 教球，不可占用" is not expressible
/// as a weight and never will be. The service resolves both halves through one
/// `resolveDayShape`, which is why they can sit on one screen without being able
/// to disagree.
///
/// Two panels, two buttons, on purpose. The settings go to `config.yaml` through
/// `/api/config`; the markdown goes to a file in the memory vault through
/// `/api/rhythm`. One 保存 spanning both would either hide that or lie about
/// which of the two writes failed.
struct RhythmSection: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    ResolvedDayPanel(snapshot: snapshot)
    RestDaysPanel(store: store)
    TimesPanel(store: store)
    NotesPanel(store: store, snapshot: snapshot)
    RhythmExamplePanel()
  }
}

/// What today actually resolves to.
///
/// First panel because it is the only thing here that answers the question
/// people arrive with. Showing `rest_days: ["SAT","SUN"]` and stopping would
/// leave the reader to work out what this particular Sunday gets — and the
/// service already knows, through the same call the planner makes.
private struct ResolvedDayPanel: View {
  let snapshot: SettingsSnapshot

  var body: some View {
    Panel("今天会被当成什么日子", subtitle: "计划真正读到的结论，不是上面设置的回显") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        KeyValueRow("今天") {
          HStack(spacing: Metrics.xs) {
            StatusDot(snapshot.rhythm.today.line, tone: snapshot.rhythm.today.tone)
            if snapshot.rhythm.today.isRestDay {
              Pill("休息日", tone: .accent)
            }
          }
        }
        KeyValueRow("明天", snapshot.rhythm.tomorrow.line)
        if !snapshot.rhythm.today.enabled {
          HintText("作息规则关着，所以每天都按工作日排——跟这个功能上线前一样。")
        } else if snapshot.rhythm.today.isRestDay {
          HintText("休息日只压来自 Linear / 每周要务的条目，自己手记的 todo 不受影响；已经逾期或今天到期的工作项也不受上限压制，仍然会出现。")
        }
      }
    }
  }
}

/// The structured half: seven days, a switch and a number.
private struct RestDaysPanel: View {
  let store: SettingsStore

  var body: some View {
    @Bindable var store = store
    Panel("休息日设置", subtitle: "写进 config.yaml，打分和写计划两边都读这一份") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        SettingToggle(
          label: "启用作息规则",
          isOn: $store.draft.rhythmEnabled,
          hint: "关掉之后每天都按工作日排。周末照常上班的人关掉它，或者把下面七天全部取消。"
        )
        KeyValueRow("休息日") {
          VStack(alignment: .leading, spacing: Metrics.xxs) {
            WeekdayPicker(selection: $store.draft.rhythmRestDays)
              .disabled(!store.draft.rhythmEnabled)
            HintText("默认是周六周日。博士在读、周末反而是整块工作时间的话，这里就该跟着改。")
          }
        }
        SettingNumber(
          label: "休息日工作上限",
          value: $store.draft.rhythmWorkCap,
          hint: "休息日最多留几条工作任务。0 = 一条都不排。上限只管 Linear / 每周要务这类别人在等的事。"
        )
        HintText("改完下一次跑计划立刻生效，不用重启服务。")
      }
    } actions: {
      SaveAction(isDirty: store.isRhythmDirty, isBusy: store.isBusy) {
        Task { await store.saveRhythmSettings() }
      }
    }
  }
}

/// 作息时间 (LEO-333): the clock half — when the work day starts, the meals,
/// and the routines and meetings that are not in any calendar.
///
/// Edited here so nobody has to open config.yaml to say "lunch is at 12:30".
/// Meals show up on today's sheet as rows the user can still move; fixed blocks
/// are drawn as blocks tasks flow around.
private struct TimesPanel: View {
  @Environment(AppState.self) private var state
  let store: SettingsStore

  var body: some View {
    @Bindable var store = store
    let problems = store.rhythmTimeProblems(store.draft)
    Panel("作息时间", subtitle: "写进 config.yaml。保存后今天的时间轴马上按新的时间重画") {
      VStack(alignment: .leading, spacing: Metrics.sm) {
        KeyValueRow("工作时间") {
          VStack(alignment: .leading, spacing: Metrics.xxs) {
            HStack(spacing: Metrics.xs) {
              ClockField(text: $store.draft.rhythmWorkStart)
              Text("–").foregroundStyle(Palette.ink3)
              ClockField(text: $store.draft.rhythmWorkEnd)
            }
            HintText("没拖过的任务从开始时间起按估时自动排。")
          }
        }
        KeyValueRow("吃饭") {
          VStack(alignment: .leading, spacing: Metrics.xs) {
            ForEach($store.draft.rhythmMeals) { $block in
              HStack(spacing: Metrics.xs) {
                TextField("午餐", text: $block.label)
                  .textFieldStyle(.roundedBorder)
                  .frame(width: 140)
                ClockField(text: $block.start)
                Text("–").foregroundStyle(Palette.ink3)
                ClockField(text: $block.end)
                RemoveButton { store.draft.rhythmMeals.removeAll { $0.id == block.id } }
              }
            }
            Button("加一个吃饭时段") {
              store.draft.rhythmMeals.append(RhythmBlockDraft(label: "", start: "12:00", end: "13:00"))
            }
            .buttonStyle(QuietButtonStyle())
            HintText("吃饭会作为一行出现在今天的通告单上，当天可以拖走、改时长或删掉。")
          }
        }
        KeyValueRow("固定日程") {
          VStack(alignment: .leading, spacing: Metrics.xs) {
            ForEach($store.draft.rhythmFixed) { $block in
              FixedBlockEditor(block: $block) {
                store.draft.rhythmFixed.removeAll { $0.id == block.id }
              }
            }
            Button("加一个固定日程") {
              store.draft.rhythmFixed.append(RhythmBlockDraft(label: "", start: "07:00", end: "08:00"))
            }
            .buttonStyle(QuietButtonStyle())
            HintText("起床、晚饭后散步这类作息，或者不在日历里的固定会议。画成不能拖的块，任务会绕开它们。哪几天都不选就是每天。英语口语这类要做的事别放这里，记成 todo。")
          }
        }
        if !problems.isEmpty {
          VStack(alignment: .leading, spacing: 2) {
            ForEach(problems, id: \.self) { problem in
              Text(problem).font(Typo.caption).foregroundStyle(Palette.danger)
            }
          }
        }
      }
    } actions: {
      SaveAction(isDirty: store.isRhythmTimesDirty && problems.isEmpty, isBusy: store.isBusy, title: "保存作息时间") {
        Task {
          await store.saveRhythmTimes()
          if store.banner?.ok == true { await state.reloadToday() }
        }
      }
    }
  }
}

/// One fixed block: name, time, kind on the first line; which days and a note
/// under it.
private struct FixedBlockEditor: View {
  @Binding var block: RhythmBlockDraft
  let onRemove: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.xxs) {
      HStack(spacing: Metrics.xs) {
        TextField("名称，比如 起床、周会", text: $block.label)
          .textFieldStyle(.roundedBorder)
          .frame(width: 180)
        ClockField(text: $block.start)
        Text("–").foregroundStyle(Palette.ink3)
        ClockField(text: $block.end)
        Picker("类型", selection: $block.kind) {
          Text("作息").tag("routine")
          Text("会议").tag("meeting")
        }
        .labelsHidden()
        .frame(width: 80)
        RemoveButton(action: onRemove)
      }
      HStack(spacing: Metrics.xs) {
        WeekdayPicker(selection: $block.days)
        TextField("或者只在这些日期：2026-10-06", text: $block.dates)
          .textFieldStyle(.roundedBorder)
          .frame(width: 220)
      }
      TextField("备注（块里的第二行小字，可留空）", text: $block.note)
        .textFieldStyle(.roundedBorder)
        .frame(maxWidth: 420)
    }
    .padding(Metrics.xs)
    .background(Palette.surfaceSunken, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
  }
}

/// "HH:mm", typed. A text field rather than a clock picker: the config stores
/// the string, and typing 07:00 is faster than scrolling to it.
private struct ClockField: View {
  @Binding var text: String

  var body: some View {
    TextField("07:00", text: $text)
      .textFieldStyle(.roundedBorder)
      .font(Typo.tabularBody)
      .frame(width: 64)
  }
}

private struct RemoveButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: "minus.circle")
        .foregroundStyle(Palette.ink3)
    }
    .buttonStyle(.plain)
    .help("删掉这一条")
    .accessibilityLabel("删掉这一条")
  }
}

/// Seven toggle buttons in a row.
///
/// A row of buttons rather than seven `SettingToggle` rows: this is one
/// question — which days — and seven labelled switches down the page reads as
/// seven independent settings. Buttons also put the whole week in one glance,
/// which is the only way "周六周日" is verifiable at a look.
private struct WeekdayPicker: View {
  @Binding var selection: Set<String>

  var body: some View {
    HStack(spacing: Metrics.xxs) {
      ForEach(SettingsStore.weekdayOrder, id: \.code) { day in
        Toggle(day.label, isOn: binding(for: day.code))
          .toggleStyle(DayChipStyle())
      }
    }
  }

  private func binding(for code: String) -> Binding<Bool> {
    Binding(
      get: { selection.contains(code) },
      set: { isOn in
        if isOn {
          selection.insert(code)
        } else {
          selection.remove(code)
        }
      }
    )
  }
}

/// A selected day, in the same mint the 休息日 pill above it uses.
///
/// `.toggleStyle(.button)` was the obvious choice and it is the wrong one here:
/// on this palette its on-state is a shade of grey about one step from its
/// off-state, so a rendered screenshot of 周六周日 selected is indistinguishable
/// from nothing selected. This control has exactly one job — say which days are
/// rest days without being clicked — and the system style cannot do it.
///
/// Still a `Toggle`, so each day keeps its checkbox role for VoiceOver; only the
/// drawing is ours.
private struct DayChipStyle: ToggleStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    Button {
      configuration.isOn.toggle()
    } label: {
      configuration.label
        .font(Typo.label)
        .foregroundStyle(configuration.isOn ? Palette.foreground(for: .accent) : Palette.inkMuted)
        .padding(.horizontal, Metrics.xs)
        .padding(.vertical, Metrics.xxs + 1)
        .background(configuration.isOn ? Palette.softBackground(for: .accent) : Palette.surfaceSunken)
        .clipShape(Capsule())
        .overlay(
          Capsule().strokeBorder(
            configuration.isOn ? Color.clear : Palette.line,
            lineWidth: Metrics.hairline
          )
        )
    }
    .buttonStyle(.plain)
    // A custom background does not dim itself the way a system style would, and
    // the picker is disabled whenever the rhythm switch is off.
    .opacity(isEnabled ? 1 : 0.4)
  }
}

/// The prose half: `rhythm.md`, as raw markdown.
///
/// Names the file it writes, for the same reason the other markdown editors do:
/// "已保存" with no path is how people end up editing one copy and wondering why
/// the plan never changed.
private struct NotesPanel: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    @Bindable var store = store
    Panel("rhythm.md", subtitle: "排不成设置项的规则写这里，大白话就行，模型做计划时原样读") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        KeyValueRow("文件", snapshot.rhythm.notesPath, mono: true)
        KeyValueRow("记忆仓库", snapshot.rhythm.repositoryPath, mono: true)
        if snapshot.rhythm.isTemplate {
          Pill("还是空模板——写之前它不影响任何计划", tone: .warn)
        }
        PlainTextEditor(text: $store.draft.rhythmMd, height: 340)
        HintText("这里写的优先级高于上面的默认规则，冲突时听你的。这是个普通 markdown 文件，在 Obsidian 里直接改效果完全一样。")
      }
    } actions: {
      Button("在访达中显示") { store.revealInFinder(snapshot.rhythm.notesPath) }
        .buttonStyle(QuietButtonStyle(tone: .neutral))
      SaveAction(
        isDirty: store.draft.rhythmMd != store.original.rhythmMd,
        isBusy: store.isBusy,
        title: "保存 Markdown"
      ) {
        Task { await store.saveRhythmNotes() }
      }
    }
  }
}

/// An empty markdown box is the hardest empty state: nothing about it says what
/// a rhythm rule looks like. Same remedy as the decision-policy page.
private struct RhythmExamplePanel: View {
  var body: some View {
    Panel("示例", subtitle: "照着改，或者整段拷过去当起点") {
      OutputBlock(text: RhythmExamplePanel.sample, height: 300)
    }
  }

  private static let sample = """
    # 作息

    ## 工作日

    - 工作时间 09:30-18:30，19:00 之后不要再排工作任务。
    - 上午留给需要安静的活，会议尽量排下午。

    ## 休息日

    - 只处理已经逾期的事，其余时间留给生活、家人、爱好。
    - 可以排个人项目，但不要排别人在等的工作。

    ## 固定占用

    - 周二、周四 19:00-21:00 打球，不要排任何事。

    ## 其他

    - 连续两天高强度之后，第三天不要排重活。
    """
}
