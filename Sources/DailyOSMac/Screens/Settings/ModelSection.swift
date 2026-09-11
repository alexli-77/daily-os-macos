import SwiftUI
import DailyOSCore

/// Which model runs the work, and how it proves who it is.
///
/// Provider → model → credential, in that order, because each choice narrows the
/// next: two of the four providers have no key at all and authenticate through a
/// CLI that has to be on `PATH`, which is why the CLI panels live here rather
/// than under 服务.
struct ModelSection: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    ProviderPanel(store: store, snapshot: snapshot)
    CLIPanel(store: store)
  }
}

private struct ProviderPanel: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    @Bindable var store = store
    Panel("模型", subtitle: "决定工作流和对话用什么跑") {
      VStack(spacing: Metrics.sm) {
        KeyValueRow("服务商") {
          // Bound through the store's setters rather than through `$store` plus
          // `onChange`. Switching provider has to re-pick the model, and an
          // `onChange` cannot tell that apart from a reload repopulating the
          // picker — which would reset the model on every refresh and then offer
          // to save the reset. The setter runs only when the user picks.
          Picker("", selection: Binding(get: { store.draft.provider }, set: { store.selectProvider($0) })) {
            ForEach(store.providerOptions, id: \.self) { Text($0).tag($0) }
          }
          .labelsHidden()
          .pickerStyle(.menu)
          .frame(maxWidth: 220, alignment: .leading)
        }
        PanelDivider()
        KeyValueRow("模型") {
          VStack(alignment: .leading, spacing: Metrics.xs) {
            Picker("", selection: Binding(get: { store.draft.modelSelection }, set: { store.selectModel($0) })) {
              ForEach(store.modelOptions) { option in
                Text(option.title).tag(option.id)
              }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 320, alignment: .leading)
            if store.isCustomModel {
              TextField("模型 id", text: $store.draft.model)
                .textFieldStyle(.roundedBorder)
                .font(Typo.monoBody)
                .frame(maxWidth: 320)
            }
            HintText("下拉里的都是建议值，不是白名单。服务把 llm.model 原样发给 CLI，所以列表里没有的 id 也能用——当前设置永远留在列表里，打开这一屏不会把它悄悄改掉。")
          }
        }
        PanelDivider()
        APIKeyRow(store: store, snapshot: snapshot)
      }
    } actions: {
      SaveAction(isDirty: store.hasLLMChanges, isBusy: store.isBusy) {
        store.confirmSaveLLM()
      }
    }
  }
}

/// The 密钥 row, which is three different rows depending on the provider.
///
/// The old screen drew a hardcoded `••••••••••••` for every provider, which was
/// wrong three ways at once: it implied a key existed, it implied this app could
/// see it, and it implied every provider needs one. Codex and Claude authenticate
/// through their own CLI's subscription login and have no key at all;
/// `ANTHROPIC_API_KEY` is needed by the `anthropic` provider but is missing from
/// the service's `SECRET_ENV_KEYS` allow-list, so `/api/env-secret` refuses to
/// read it and `/api/env` refuses to write it.
private struct APIKeyRow: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    @Bindable var store = store
    KeyValueRow("API 密钥") {
      switch store.apiKeyRequirement {
      case .none(let checkName):
        VStack(alignment: .leading, spacing: Metrics.xxs) {
          Pill("不需要", tone: .neutral)
          Text("\(store.draft.provider) 用它自己 CLI 的订阅登录，不存 API key。")
            .mutedStyle()
          if let check = snapshot.doctor.first(where: { $0.name == checkName }) {
            HStack(spacing: Metrics.xs) {
              StatusDot(check.ok ? "已登录" : "未登录", tone: check.ok ? .ok : .danger)
              Text(check.detail.isEmpty ? check.name : check.detail).mutedStyle()
            }
          } else {
            Text("服务的自检里没有 \(checkName) 这一项，登录状态未知。").mutedStyle()
          }
        }

      case .managed(let key):
        VStack(alignment: .leading, spacing: Metrics.xs) {
          HStack(spacing: Metrics.xs) {
            Pill(store.secretPresent ? "已配置" : "未配置", tone: store.secretPresent ? .ok : .neutral)
            Text(store.secretDisplay)
              .font(Typo.monoBody)
              .foregroundStyle(Palette.inkMuted)
              .textSelection(.enabled)
            if store.secretPresent {
              Button(store.isSecretRevealed ? "隐藏" : "显示") {
                Task { await store.toggleReveal(key: key) }
              }
              .buttonStyle(QuietButtonStyle())
              .disabled(store.isBusy)
            }
            Button(store.isEditingSecret ? "取消" : "更换") { store.toggleSecretEditor() }
              .buttonStyle(QuietButtonStyle())
          }
          if store.isEditingSecret {
            HStack(spacing: Metrics.xs) {
              SecureField(key, text: $store.secretDraft)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 320)
              Button("保存") { store.confirmSaveSecret(key: key) }
                .buttonStyle(MossButtonStyle(prominent: false))
                .disabled(store.secretDraft.isEmpty || store.isBusy)
            }
            Text("写进 \(snapshot.envPath)。这个 App 不会把密钥记进日志，也不会存到别的地方。")
              .mutedStyle()
              .fixedSize(horizontal: false, vertical: true)
          }
        }

      case .unmanaged(let key):
        VStack(alignment: .leading, spacing: Metrics.xxs) {
          Pill("服务读不到", tone: .warn)
          Text(unmanagedExplanation(key: key))
            .mutedStyle()
            .fixedSize(horizontal: false, vertical: true)
        }
      }
    }
  }

  private func unmanagedExplanation(key: String) -> String {
    guard !key.isEmpty else {
      return "这个服务商不在服务已知的四个里（codex / openai / claude / anthropic），需不需要密钥无从判断。"
    }
    return """
      \(store.draft.provider) 需要 \(key)，但服务的 /api/env-secret 只放行 \
      OPENAI_API_KEY、GITHUB_TOKEN、LINEAR_API_KEY、VAULT_GATE_TOKEN、LARK_APP_SECRET。\
      \(key) 不在这个名单里，读写都会被拒绝，只能直接改 \(snapshot.envPath) 再重启服务。
      """
  }
}

/// Where the Codex and Claude executables are.
///
/// These exist for one failure only, and it is worth naming: the service runs
/// under launchd, whose `PATH` is not the shell's. A `codex` that works in
/// Terminal is invisible to the daemon, and the symptom is every model call
/// failing with "command not found" while the CLI is demonstrably installed.
///
/// The picker is this app's `NSOpenPanel` rather than the service's
/// `choose_codex_binary` action for the same reason the vault picker is — that
/// action shells out to `osascript`, so the dialog would belong to the node
/// process and can open behind this window.
private struct CLIPanel: View {
  let store: SettingsStore

  var body: some View {
    @Bindable var store = store
    Panel("CLI 路径", subtitle: "launchd 的 PATH 和你终端里的不是同一个") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        SettingPath(
          label: "Codex",
          text: $store.draft.codexBin,
          placeholder: "codex 或 /opt/homebrew/bin/codex",
          hint: "留空就按 PATH 找。provider 是 codex 时才用得上。"
        ) {
          store.pickFile(into: \.codexBin, message: "选择 Codex CLI 可执行文件")
        }
        SettingPath(
          label: "Codex home",
          text: $store.draft.codexHome,
          placeholder: "可选，通常是 ~/.codex",
          hint: "登录状态存在这个目录里。换过它，就要用同一个目录重新跑一次 codex login。"
        ) {
          store.pickFolder(into: \.codexHome, message: "选择 Codex home 目录")
        }
        SettingPath(
          label: "Claude",
          text: $store.draft.claudeBin,
          placeholder: "claude 或 /opt/homebrew/bin/claude",
          hint: "provider 是 claude 时才用得上。"
        ) {
          store.pickFile(into: \.claudeBin, message: "选择 Claude CLI 可执行文件")
        }
        PanelDivider()
        KeyValueRow("查找与测试") {
          VStack(alignment: .leading, spacing: Metrics.xxs) {
            HStack(spacing: Metrics.xxs) {
              ActionButton(title: "找 Codex", action: "discover_codex_binary", store: store)
              ActionButton(title: "测 Codex 登录", action: "codex_test", store: store)
              ActionButton(title: "找 Claude", action: "discover_claude_binary", store: store)
              ActionButton(title: "测 Claude 登录", action: "claude_test", store: store)
            }
            HintText("查找会直接写进 .env 并刷新这一屏；测试只跑一次登录检查。两者的完整输出都落在「概览」的输出块里——这里不重复一份，否则关掉哪一份就成了新问题。提示未登录时，用上面同一个路径在终端跑 codex login 或 claude auth login。")
          }
        }
      }
    } actions: {
      SaveAction(isDirty: store.isCLIDirty, isBusy: store.isBusy) {
        Task { await store.saveCLIPaths() }
      }
    }
  }
}
