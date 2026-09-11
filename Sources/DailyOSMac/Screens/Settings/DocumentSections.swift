import SwiftUI
import DailyOSCore

/// The prose the model reads before it decides anything.
///
/// Three editors that write markdown files rather than config keys, which is why
/// they are grouped away from the switches: nothing here has a schema, and the
/// only validation is that you can read what you wrote. Each one names the file
/// it writes, because "saved" without a path is how people end up editing the
/// bundled template and wondering why nothing changed.

/// `decision-policy.md` — the user's own preferences, in their own words.
struct DecisionSection: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    @Bindable var store = store
    Panel("决策规则", subtitle: "信息源优先级、每日计划规则、不要做什么") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        KeyValueRow("文件", snapshot.decisionPolicy.notesPath, mono: true)
        KeyValueRow("记忆仓库", snapshot.decisionPolicy.repositoryPath, mono: true)
        PlainTextEditor(text: $store.draft.decisionPolicyMd, height: 380)
        HintText("改完下一次计划或复盘立刻生效，不用重启服务。")
      }
    } actions: {
      Button("在访达中显示") { store.revealInFinder(snapshot.decisionPolicy.notesPath) }
        .buttonStyle(QuietButtonStyle(tone: .neutral))
      SaveAction(
        isDirty: store.draft.decisionPolicyMd != store.original.decisionPolicyMd,
        isBusy: store.isBusy
      ) {
        Task { await store.saveDecisionPolicy() }
      }
    }
    ExamplePanel()
  }
}

/// The console's static example, kept because an empty markdown box is the
/// hardest kind of empty state: nothing about it says what a "rule" looks like.
private struct ExamplePanel: View {
  var body: some View {
    Panel("示例", subtitle: "照着改，或者整段拷过去当起点") {
      OutputBlock(text: ExamplePanel.sample, height: 300)
    }
  }

  private static let sample = """
    # 决策规则

    ## 信息源优先级

    - 每周要务优先于 Linear。
    - 用户今天手动记录的 todo 优先级最高。
    - Linear 只用来看任务状态和链接。

    ## 每日计划规则

    - 每天最多给我 3 个重点任务。
    - 先放今天必须完成的事。
    - 不确定的任务放到「暂缓」。

    ## 复盘规则

    - 先检查今天有没有完成重点任务。
    - 没完成时，告诉我原因可能是什么。
    - 不要只总结，要给下一步建议。

    ## AI 分工规则

    - Codex 可以先写草稿和检查清单。
    - 对外发送邮件前必须让我确认。
    - 涉及隐私或付款的事只提醒，不自动执行。

    ## 不要做

    - 不要把过期 Linear 日期当成今天任务。
    - 不要一次给太多任务。
    - 不要在我没确认前改长期规则。

    ## 校准记录

    - 如果今天计划太多，下次减少到 3 项以内。
    - 如果任务说不清楚，下次写成可执行动作。
    """
}

/// The several files that together decide how the next cycle gets planned.
///
/// A picker rather than a stack of editors: they live in two different repos —
/// one is injected into the input pack, the rest are embedded into
/// life-review-os's own prompts — and the list shrinks when that checkout is
/// missing. Showing four empty boxes for files that do not exist on this machine
/// would be four invitations to write into nothing.
struct StrategySection: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    @Bindable var store = store
    Panel("复盘策略", subtitle: "改完下一次 review 立即生效，不用重启") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        if snapshot.strategy.isEmpty {
          HintText("服务没有列出任何策略文件。通常是 life-review-os 还没安装——去「技能」装一次。")
        } else {
          KeyValueRow("文件") {
            Picker("", selection: Binding(
              get: { store.selectedStrategyFile?.id ?? "" },
              set: { store.selectStrategyFile($0) }
            )) {
              ForEach(snapshot.strategy) { file in
                Text(file.label).tag(file.id)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 420, alignment: .leading)
          }
          if let file = store.selectedStrategyFile {
            HintText(file.hint)
            KeyValueRow("路径", file.path, mono: true)
            if !file.exists {
              Pill("文件还不存在", tone: .warn)
            }
          }
          PlainTextEditor(text: $store.draft.strategyMd, height: 360)
        }
      }
    } actions: {
      if let file = store.selectedStrategyFile {
        Button("在访达中显示") { store.revealInFinder(file.path) }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
      }
      SaveAction(
        isDirty: store.draft.strategyMd != store.original.strategyMd,
        isBusy: store.isBusy
      ) {
        Task { await store.saveStrategy() }
      }
    }
    if !snapshot.defaultStrategy.isEmpty {
      Panel("内置默认规则", subtitle: "「计划条目规则」为空或被删掉时，回退到这一份") {
        OutputBlock(text: snapshot.defaultStrategy, height: 280)
      }
    }
  }
}

/// The three OKR files, as raw markdown.
///
/// The OKR screen reads these same three files and this one writes them, which
/// looks like duplication until you count how often each happens: objectives are
/// written a few times a year and consulted every time a review gets drafted.
/// Putting the editor on the reading screen would put a text box in front of
/// that daily glance; leaving it out of the app entirely is what the OKR screen
/// does today, and it ends with "在文件里改" as the only answer.
///
/// 整理格式 rewrites the editor and stops there. The whole value of the button is
/// that you look at what it did before it touches the file — saving for you
/// removes the only moment a mangled objective can still be undone.
struct OKRSection: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    if snapshot.okr.isEmpty {
      Panel("OKR") {
        EmptyState(
          icon: "target",
          title: "服务没有返回 OKR 文件",
          message: "它在记忆仓库的 10_OKR/ 下找这三个文件。先去「数据源」把记忆仓库指到一个真实目录。"
        )
      }
    } else {
      Panel("目录", subtitle: snapshot.okrDir) {
        HintText("这三个文件同时是「今天」页 North Star 的来源。还是占位 TODO 时，那一栏会显示 not found，双周复盘也写不回 KR 进度。")
      } actions: {
        Button("在访达中显示") { store.revealInFinder(snapshot.okrDir) }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
      }
      ForEach(snapshot.okr) { file in
        OKRFilePanel(store: store, file: file)
      }
    }
  }
}

private struct OKRFilePanel: View {
  let store: SettingsStore
  let file: OkrFileRow

  var body: some View {
    @Bindable var store = store
    Panel(file.label, subtitle: file.fileName) {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        KeyValueRow("路径", file.path, mono: true)
        PlainTextEditor(
          text: Binding(
            get: { store.draft.okrMarkdown[file.id] ?? "" },
            set: { store.draft.okrMarkdown[file.id] = $0 }
          ),
          height: 260
        )
        HintText("不用手写表格：每个目标写一行（可带 P0/P1），KR 用 - 或 * 开头列在下面，点「整理格式」转成标准结构，检查过再保存。")
      }
    } actions: {
      Button("整理格式") { Task { await store.formatOKR(level: file.id) } }
        .buttonStyle(QuietButtonStyle(tone: .neutral))
        .disabled(store.isBusy)
      SaveAction(isDirty: isDirty, isBusy: store.isBusy) {
        Task { await store.saveOKR(level: file.id) }
      }
    }
  }

  private var isDirty: Bool {
    store.draft.okrMarkdown[file.id] != store.original.okrMarkdown[file.id]
  }
}
