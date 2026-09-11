import AppKit
import SwiftUI
import DailyOSCore

/// Where the evidence comes from.
///
/// Status first, then the fields. That order is the point: the status panel is
/// derived from config plus the doctor checks and answers "is this working",
/// which is the question people come here with — the fields below are what you
/// touch once the answer is no.
struct SourcesSection: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    SourceStatusPanel(store: store, snapshot: snapshot)
    VaultPanel(store: store)
    MemoryPanel(store: store)
    GitHubPanel(store: store)
    LinearPanel(store: store)
    OtherSourcesPanel(store: store)
  }
}

/// Derived from `config` and `doctor`, never invented.
///
/// The old screen listed five sources with fixed 已连接 / 未配置 pills that came
/// from the fixture. This one asks the service, and keeps a fourth answer for the
/// case the service genuinely cannot report on: `runDoctor` has no calendar check
/// at all, so an enabled calendar reads 未知 — the config says it is switched on,
/// and nothing anywhere says it works.
private struct SourceStatusPanel: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  /// Which row has its inline form open. One at a time — two open forms in a
  /// six-row list is two places to type and no indication which one is live.
  @State private var openFormID: String?
  @State private var repositoryDraft = ""

  var body: some View {
    Panel("状态", subtitle: "证据从这些地方来，结论回到你的文件里") {
      VStack(spacing: 0) {
        ForEach(Array(snapshot.sources.enumerated()), id: \.element.id) { index, source in
          if index > 0 { PanelDivider() }
          VStack(alignment: .leading, spacing: Metrics.xxs) {
            HStack(alignment: .top, spacing: Metrics.sm) {
              Image(systemName: source.icon)
                .foregroundStyle(Palette.foreground(for: source.status.tone))
                .frame(width: 20)
              VStack(alignment: .leading, spacing: 2) {
                Text(source.name).inkStyle()
                Text(source.detail)
                  .mutedStyle()
                  .fixedSize(horizontal: false, vertical: true)
              }
              Spacer(minLength: Metrics.xs)
              if let fix = source.fix {
                Button(fix.label) { activate(fix, on: source) }
                  .buttonStyle(QuietButtonStyle())
                  .disabled(store.isBusy)
              }
              Pill(source.status.label, tone: source.status.tone)
            }
            .frame(minHeight: Metrics.hitTarget)

            if openFormID == source.id, source.fix == .addGitHubRepository {
              repositoryForm
            }
          }
          .padding(.vertical, Metrics.xxs)
        }
      }
    } actions: {
      Button("打开配置文件") { store.revealInFinder(snapshot.configPath) }
        .buttonStyle(QuietButtonStyle(tone: .neutral))
      Button("重新检查") { Task { await store.load() } }
        .buttonStyle(QuietButtonStyle())
        .disabled(store.isBusy)
    }
  }

  private var repositoryForm: some View {
    HStack(spacing: Metrics.xs) {
      TextField("owner/repo", text: $repositoryDraft)
        .textFieldStyle(.plain)
        .font(Typo.mono)
        .padding(Metrics.xxs)
        .background(Palette.surfaceSunken)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
        .onSubmit(submitRepository)
      Button("添加", action: submitRepository)
        .buttonStyle(QuietButtonStyle())
        .disabled(store.isBusy || repositoryDraft.trimmingCharacters(in: .whitespaces).isEmpty)
      Button("取消") { openFormID = nil; repositoryDraft = "" }
        .buttonStyle(QuietButtonStyle(tone: .neutral))
    }
    .padding(.leading, 20 + Metrics.sm)
  }

  private func activate(_ fix: SourceFix, on source: SourceRow) {
    if fix.isInline {
      withAnimation(.snappy(duration: 0.2)) {
        openFormID = openFormID == source.id ? nil : source.id
      }
      repositoryDraft = ""
    } else {
      store.apply(fix)
    }
  }

  private func submitRepository() {
    let slug = repositoryDraft
    openFormID = nil
    repositoryDraft = ""
    Task { await store.addGitHubRepository(slug) }
  }
}

/// The user's own knowledge base. Separate from the memory repository below, and
/// the console said so in a hint because people kept pointing both at the same
/// folder and then wondering why Daily OS was writing into their notes.
private struct VaultPanel: View {
  let store: SettingsStore

  var body: some View {
    @Bindable var store = store
    Panel("知识库 Vault", subtitle: "你自己那份笔记库，只读取，不写入") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        SettingToggle(label: "启用", isOn: $store.draft.vaultEnabled)
        SettingPicker(
          label: "来源",
          selection: $store.draft.vaultProvider,
          options: [("local", "本地文件夹"), ("remote", "远程网关")]
        )
        if store.draft.vaultProvider == "local" {
          SettingPath(label: "本地路径", text: $store.draft.vaultLocalPath) {
            store.pickFolder(into: \.vaultLocalPath, message: "选择 vault 知识库文件夹")
          }
        } else {
          SettingText(label: "网关地址", text: $store.draft.vaultGateURL, placeholder: "https://…", mono: true)
          SourceSecretRow(
            label: "网关令牌",
            key: "VAULT_GATE_TOKEN",
            store: store,
            hint: "远程 vault 才需要。本地文件夹模式下这一项不会被读。"
          )
        }
      }
    } actions: {
      SaveAction(isDirty: store.isSourcesDirty, isBusy: store.isBusy) {
        Task { await store.saveSources() }
      }
    }
  }
}

/// Daily OS's own working memory — the folder it writes into.
private struct MemoryPanel: View {
  let store: SettingsStore

  var body: some View {
    @Bindable var store = store
    Panel("记忆仓库", subtitle: "Daily OS 自己的工作记忆，周期和 OKR 都住在这里") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        SettingPath(
          label: "仓库路径",
          text: $store.draft.memoryRepositoryPath,
          placeholder: "留空则用内置模板 memory-vault/default",
          hint: "OKR 编辑器写的是这个目录下的 10_OKR/；留空时写的是内置模板，重装服务就没了。"
        ) {
          store.pickFolder(into: \.memoryRepositoryPath, message: "选择 Daily OS 记忆仓库文件夹")
        }
        SettingText(
          label: "长期追加日志",
          text: $store.draft.memoryLongTermPath,
          placeholder: "./data/memory/long-term.md",
          mono: true
        )
        SettingText(
          label: "每日运行目录",
          text: $store.draft.memoryDailyDir,
          placeholder: "./data/memory/daily",
          mono: true
        )
      }
    } actions: {
      SaveAction(isDirty: store.isSourcesDirty, isBusy: store.isBusy) {
        Task { await store.saveSources() }
      }
    }
  }
}

private struct GitHubPanel: View {
  let store: SettingsStore

  var body: some View {
    @Bindable var store = store
    Panel("GitHub") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        SettingToggle(label: "启用", isOn: $store.draft.githubEnabled)
        SourceSecretRow(label: "访问令牌", key: "GITHUB_TOKEN", store: store)
        KeyValueRow("自动查找") {
          ActionButton(title: "从本机读取令牌", action: "discover_github_token", store: store)
        }
        SettingLines(
          label: "仓库",
          text: $store.draft.githubRepositories,
          placeholder: "每行一个 owner/repo",
          hint: "一个都不填时这个数据源什么也采不到，而自检仍然是绿的——它检查的是令牌，不是仓库。",
          height: 96
        )
        SettingNumber(label: "每仓库条数", value: $store.draft.githubPerRepoLimit)
      }
    } actions: {
      SaveAction(isDirty: store.isSourcesDirty, isBusy: store.isBusy) {
        Task { await store.saveSources() }
      }
    }
  }
}

private struct LinearPanel: View {
  let store: SettingsStore

  var body: some View {
    @Bindable var store = store
    Panel("Linear") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        SettingToggle(label: "启用", isOn: $store.draft.linearEnabled)
        SourceSecretRow(
          label: "API key",
          key: "LINEAR_API_KEY",
          store: store,
          hint: "留空时服务会退回到本机 Codex 的 Linear 连接，所以自检里缺它只是警告，不是失败。"
        )
        KeyValueRow("自动查找") {
          ActionButton(title: "从本机读取密钥", action: "discover_linear_token", store: store)
        }
        SettingText(
          label: "任务归属",
          text: $store.draft.linearAssignee,
          placeholder: "me / 邮箱 / 显示名；留空=整个团队",
          hint: "作用于所有过滤，包括下面的白名单。me 指 API key 所属的账号。"
        )
        SettingToggle(label: "只看当前 Cycle", isOn: $store.draft.linearActiveCycleOnly)
        PanelDivider()
        SettingText(
          label: "查询",
          text: $store.draft.linearQuery,
          placeholder: "assignee = me and state.type != 'completed'",
          hint: "留空即可；只有需要自定义 GraphQL 过滤时才填。",
          mono: true,
          width: 420
        )
        SettingLines(label: "只看这些项目", text: $store.draft.linearProjectsAllow, placeholder: "每行一个项目名", height: 64)
        SettingLines(label: "排除这些项目", text: $store.draft.linearProjectsBlock, placeholder: "每行一个项目名", height: 64)
        SettingLines(label: "只看这些团队", text: $store.draft.linearTeamsAllow, placeholder: "每行一个团队名或 key", height: 64)
        SettingLines(
          label: "排除这些团队",
          text: $store.draft.linearTeamsBlock,
          placeholder: "每行一个团队名或 key",
          hint: "匹配忽略大小写、空格、连字符和下划线。",
          height: 64
        )
      }
    } actions: {
      SaveAction(isDirty: store.isSourcesDirty, isBusy: store.isBusy) {
        Task { await store.saveSources() }
      }
    }
  }
}

/// The switches with nothing behind them but a switch, plus the local file list.
private struct OtherSourcesPanel: View {
  let store: SettingsStore

  var body: some View {
    @Bindable var store = store
    Panel("其他来源") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        SettingToggle(
          label: "飞书采集",
          isOn: $store.draft.feishuSourceEnabled,
          hint: "日历、任务、文档、群聊由「飞书」那一页的采集档案决定收哪些。"
        )
        SettingToggle(label: "Chrome 快照", isOn: $store.draft.chromeSnapshotEnabled)
        SettingToggle(
          label: "Apple 日历快照",
          isOn: $store.draft.appleCalendarEnabled,
          hint: "走 osascript 读本机日历，第一次会弹系统授权。"
        )
        PanelDivider()
        SettingToggle(label: "本地文件", isOn: $store.draft.localFilesEnabled)
        SettingLines(
          label: "文件清单",
          text: $store.draft.localFiles,
          placeholder: "每行一条：名称 | 绝对路径",
          hint: "缺了名称或路径的行会被丢掉，不会存成半条——采集器打不开的路径每天失败一次，而屏幕上什么都不会说。",
          height: 112
        )
      }
    } actions: {
      SaveAction(isDirty: store.isSourcesDirty, isBusy: store.isBusy) {
        Task { await store.saveSources() }
      }
    }
  }
}
