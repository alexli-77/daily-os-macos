import SwiftUI
import DailyOSCore

/// The two workflow settings that are not a schedule.
///
/// The console's Workflows page also held the enable switch and time for daily
/// plan, daily review and weekly review. Those are not here on purpose: 排程 is
/// where this app shows and toggles them, and a second place to set the morning
/// time is a second place for it to be wrong.
struct WorkflowsSection: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    CalendarPanel(store: store)
    BackgroundSuggestionsPanel(store: store, snapshot: snapshot)
  }
}

/// The optional bridge to `calendar-planning-os`.
///
/// Everything here is a path on this Mac, which is why it is worth its own
/// panel: the failure is always "the engine is not where the config says", and
/// the test button is the only thing that distinguishes that from the engine
/// itself being broken.
private struct CalendarPanel: View {
  let store: SettingsStore

  var body: some View {
    @Bindable var store = store
    Panel("日历草稿", subtitle: "只生成草稿，不写你的日历") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        SettingToggle(label: "启用", isOn: $store.draft.calendarEnabled)
        SettingPicker(
          label: "引擎",
          selection: $store.draft.calendarMode,
          options: [("auto", "自动"), ("external", "外部 CLI"), ("builtin", "内置")],
          hint: "自动：外部 CLI 能用就用，否则用内置简易排布。"
        )
        SettingText(label: "启动命令", text: $store.draft.calendarCommand, placeholder: "node", mono: true)
        SettingPath(
          label: "引擎目录",
          text: $store.draft.calendarWorkdir,
          placeholder: "../calendar-planning-os"
        ) {
          store.pickFolder(into: \.calendarWorkdir, message: "选择 calendar-planning-os 目录")
        }
        SettingText(
          label: "CLI 相对路径",
          text: $store.draft.calendarCLIPath,
          placeholder: "bin/calendar-planning-os.mjs",
          mono: true
        )
        SettingText(label: "策略文件", text: $store.draft.calendarPolicyFile, placeholder: "可选，本地 markdown", mono: true)
        SettingText(label: "例行文件", text: $store.draft.calendarRoutinesFile, placeholder: "可选，本地 yaml", mono: true)
        SettingNumber(label: "一周排几天", value: $store.draft.calendarWeekDays)
        SettingNumber(label: "最多几件事", value: $store.draft.calendarMaxTasks)
        PanelDivider()
        KeyValueRow("试一下") {
          VStack(alignment: .leading, spacing: Metrics.xxs) {
            HStack(spacing: Metrics.xxs) {
              ActionButton(title: "测试引擎", action: "calendar_test", store: store)
              ActionButton(title: "排本周", action: "calendar_week", store: store)
              ActionButton(title: "排今天", action: "calendar_today", store: store)
            }
            HintText("测试用样例输入检查路径和 CLI，不读真实数据。排本周 / 排今天读真实数据，结果在「概览」的输出块。")
          }
        }
        HintText("保存后无需重启，下一条飞书指令即生效。")
      }
    } actions: {
      SaveAction(isDirty: store.isWorkflowsDirty, isBusy: store.isBusy) {
        Task { await store.saveWorkflows() }
      }
    }
  }
}

/// The loop that watches your chats and proposes things without being asked.
private struct BackgroundSuggestionsPanel: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    @Bindable var store = store
    Panel("后台建议") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        KeyValueRow("上次运行") {
          HStack(spacing: Metrics.xs) {
            StatusDot(snapshot.background.line, tone: snapshot.background.statusTone)
          }
        }
        if !snapshot.background.lastError.isEmpty {
          HintText(snapshot.background.lastError)
        }
        PanelDivider()
        SettingToggle(label: "启用", isOn: $store.draft.backgroundEnabled)
        SettingPicker(
          label: "模式",
          selection: $store.draft.backgroundMode,
          options: [("manual", "手动"), ("todo", "找 todo"), ("review", "找进展")]
        )
        SettingNumber(
          label: "间隔（分钟）",
          value: $store.draft.backgroundInterval,
          hint: "每次扫描调用一次模型，间隔越短花费越多。"
        )
        SettingPicker(
          label: "最低置信度",
          selection: $store.draft.backgroundConfidence,
          options: [("low", "低"), ("medium", "中"), ("high", "高")],
          hint: "低于这一档的建议会被丢弃。"
        )
        SettingToggle(label: "发到飞书", isOn: $store.draft.backgroundSendFeishu)
        SettingToggle(
          label: "只在有变化时发",
          isOn: $store.draft.backgroundChangeOnly,
          hint: "关闭后，结果和上一轮相同也会再发。"
        )
      }
    } actions: {
      SaveAction(isDirty: store.isWorkflowsDirty, isBusy: store.isBusy) {
        Task { await store.saveWorkflows() }
      }
    }
  }
}
