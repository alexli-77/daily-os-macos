import SwiftUI
import DailyOSCore

/// The Feishu channel, in the order a message travels it.
///
/// The console had these four fieldsets scattered down its Setup and Sources
/// pages, which hid the thing that actually matters: **outbound and inbound are
/// two independent switches over one set of credentials.** Turning on the bot
/// without turning on output gives you a bot that answers commands and never
/// speaks first, and nothing on the old page said so.
///
/// One 保存 for the whole section: the credentials go to `.env` and the rest to
/// `config.yaml`, and splitting that into two buttons means an App ID saved
/// without the switch that uses it.
struct FeishuSection: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    CredentialsPanel(store: store, snapshot: snapshot)
    OutputPanel(store: store)
    InteractionPanel(store: store)
    DecisionOnboardingPanel(store: store)
    ProfilesPanel(snapshot: snapshot)
  }
}

/// Ids and secrets. `discover_feishu_setup` reads them out of an existing
/// `lark-cli` login, which is how most people should fill this in — typing an
/// App Secret by hand is the fallback, not the path.
private struct CredentialsPanel: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    @Bindable var store = store
    Panel("凭据", subtitle: "官方 SDK 用这一组；填不全时服务退回 lark-cli") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        KeyValueRow("自动配置") {
          VStack(alignment: .leading, spacing: Metrics.xxs) {
            ActionButton(title: "从 lark-cli 读取", action: "discover_feishu_setup", store: store)
            HintText("先点这个，只补它报出来还缺的字段。它直接写 .env 并刷新这一屏。")
          }
        }
        PanelDivider()
        SettingText(label: "App ID", text: $store.draft.larkAppID, placeholder: "cli_xxx", mono: true)
        SourceSecretRow(
          label: "App Secret",
          key: "LARK_APP_SECRET",
          store: store,
          hint: "SDK 发消息和 websocket 监听用的都是它。写进 \(snapshot.envPath)，这个 App 不会读回来。"
        )
        SettingText(
          label: "会话 ID",
          text: $store.draft.feishuChatID,
          placeholder: "oc_xxx",
          hint: "发消息、拉反馈、读群聊历史都发到这里。留空就等于没有出口。",
          mono: true
        )
        SettingText(
          label: "所有者 open_id",
          text: $store.draft.ownerOpenID,
          placeholder: "ou_xxx",
          hint: "交互层用它判断谁是你。不填的话，下面的安全默认值会把所有指令都拒掉。",
          mono: true
        )
      }
    } actions: {
      SaveAction(isDirty: store.isFeishuDirty, isBusy: store.isBusy) {
        Task { await store.saveFeishu() }
      }
    }
  }
}

/// Outbound: the briefing, the review, the cards.
private struct OutputPanel: View {
  let store: SettingsStore

  var body: some View {
    @Bindable var store = store
    Panel("发送", subtitle: "工作流的结果怎么发出去") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        SettingToggle(
          label: "飞书输出",
          isOn: $store.draft.outputEnabled,
          hint: "关掉之后计划和复盘照常生成、照常写盘，只是不再发到飞书。"
        )
        SettingPicker(
          label: "发送方式",
          selection: $store.draft.outputProvider,
          options: [("auto", "自动"), ("sdk", "官方 SDK"), ("lark_cli", "lark-cli")],
          hint: "自动 = App ID 和 App Secret 都填了就用 SDK，否则退回 lark-cli。"
        )
        SettingPicker(
          label: "消息格式",
          selection: $store.draft.outputSendMode,
          options: [("markdown", "Markdown"), ("text", "纯文本")]
        )
        PanelDivider()
        SettingToggle(
          label: "飞书反馈",
          isOn: $store.draft.feedbackEnabled,
          hint: "轮询会话里以指令前缀开头的消息，把它们当成对 Daily OS 的指令。"
        )
        SettingText(
          label: "指令前缀",
          text: $store.draft.feedbackPrefix,
          placeholder: "daily-os",
          mono: true
        )
        SettingNumber(
          label: "每次拉取条数",
          value: $store.draft.feedbackPollLimit,
          hint: "一次往回读多少条消息找指令。服务端接受 1–100。"
        )
      }
    } actions: {
      SaveAction(isDirty: store.isFeishuDirty, isBusy: store.isBusy) {
        Task { await store.saveFeishu() }
      }
    }
  }
}

/// Inbound: the websocket listener that lets you drive this Mac from a phone.
///
/// The security block is not optional detail. The service's default is to deny
/// every message until the owner id or one of these lists names someone — which
/// is the right default and also the reason a correctly configured bot can look
/// completely dead. Putting the allow-lists next to the switch is what makes
/// that one screen instead of a support thread.
private struct InteractionPanel: View {
  let store: SettingsStore

  var body: some View {
    @Bindable var store = store
    Panel("接收", subtitle: "在飞书里发指令回来") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        SettingToggle(
          label: "交互层",
          isOn: $store.draft.interactionEnabled,
          hint: "一个 websocket 监听，用的是上面同一组 SDK 凭据。"
        )
        SettingText(label: "指令前缀", text: $store.draft.interactionPrefix, placeholder: "daily-os", mono: true)
        SettingPicker(
          label: "回复格式",
          selection: $store.draft.interactionReplyMode,
          options: [("markdown", "Markdown"), ("text", "纯文本")]
        )
        SettingNumber(
          label: "防抖（毫秒）",
          value: $store.draft.interactionDebounce,
          hint: "连着发好几条时，等这么久再一起处理。"
        )
        SettingToggle(
          label: "群里必须 @",
          isOn: $store.draft.interactionRequireMention,
          hint: "开着的话，群消息只有 @ 了机器人才算指令。"
        )
        PanelDivider()
        SettingPicker(
          label: "权限级别",
          selection: $store.draft.interactionAccessLevel,
          options: [("read_only", "只读"), ("workspace", "可写工作区"), ("full", "完全")],
          hint: "full 会让远端指令能在本机任意执行。只在自己一个人用的部署里开它。"
        )
        SettingLines(
          label: "管理员 open_id",
          text: $store.draft.interactionAdmins,
          placeholder: "每行一个 ou_xxx",
          height: 64
        )
        SettingLines(
          label: "允许的用户",
          text: $store.draft.interactionUsers,
          placeholder: "每行一个 ou_xxx",
          height: 64
        )
        SettingLines(
          label: "允许的会话",
          text: $store.draft.interactionChats,
          placeholder: "每行一个 oc_xxx",
          height: 64
        )
        SettingLines(
          label: "允许的工作区",
          text: $store.draft.interactionWorkspaces,
          placeholder: "每行一个本机路径",
          hint: "安全默认：所有者 open_id、允许的用户、允许的会话三项都空着时，交互层拒绝所有消息——不是坏了，是还没放行任何人。",
          height: 64
        )
      }
    } actions: {
      SaveAction(isDirty: store.isFeishuDirty, isBusy: store.isBusy) {
        Task { await store.saveFeishu() }
      }
    }
  }
}

/// The private group where the user teaches Daily OS how to decide.
private struct DecisionOnboardingPanel: View {
  let store: SettingsStore

  var body: some View {
    @Bindable var store = store
    Panel("决策校准群", subtitle: "Mac 这边只负责配置，磨合发生在飞书里") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        SettingText(label: "群名称", text: $store.draft.decisionChatName, placeholder: "Daily OS · 决策校准")
        SettingText(
          label: "群 ID",
          text: $store.draft.decisionChatID,
          placeholder: "自动创建，或手动粘贴 oc_xxx",
          mono: true
        )
        SettingToggle(
          label: "启动时自动创建",
          isOn: $store.draft.decisionAutoCreate,
          hint: "默认关着，免得客户刚启动工具就被突然拉进一个群。确认飞书应用开通了 im:chat 之后再打开。"
        )
        PanelDivider()
        KeyValueRow("现在就建") {
          VStack(alignment: .leading, spacing: Metrics.xxs) {
            ActionButton(title: "开始决策校准", action: "decision_onboarding_start", store: store) {
              store.confirmDecisionOnboarding()
            }
            HintText("会创建（或复用）那个群并发一张欢迎卡片。已经发过的 24 小时内不会重复发。")
          }
        }
      }
    } actions: {
      SaveAction(isDirty: store.isFeishuDirty, isBusy: store.isBusy) {
        Task { await store.saveFeishu() }
      }
    }
  }
}

/// The `sources.feishu.profiles` array, read-only — see `FeishuProfileRow` for
/// why this app shows profiles instead of editing them.
private struct ProfilesPanel: View {
  let snapshot: SettingsSnapshot

  var body: some View {
    Panel("采集档案", subtitle: "同一个 lark-cli 应用下的几套采集组合") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        if snapshot.feishuProfiles.isEmpty {
          HintText("config.yaml 里没有 profiles，服务会退回 sources.feishu 下的那一组默认设置。")
        } else {
          VStack(spacing: 0) {
            ForEach(Array(snapshot.feishuProfiles.enumerated()), id: \.element.id) { index, profile in
              if index > 0 { PanelDivider() }
              HStack(spacing: Metrics.sm) {
                Pill(profile.enabled ? "启用" : "停用", tone: profile.enabled ? .ok : .neutral)
                Text(profile.label).inkStyle()
                Text(profile.identity).font(Typo.mono).foregroundStyle(Palette.inkMuted)
                Spacer(minLength: Metrics.xs)
                Text(detail(profile)).mutedStyle()
              }
              .frame(minHeight: Metrics.hitTarget)
            }
          }
        }
        HintText("一个档案是四个采集器加一份文档清单，而配置写回是整份文件覆盖——这个 App 只认识它显示出来的字段，改一个档案就会把没显示的那些（比如文档 token 列表）抹掉。所以这里只读；要增删档案，用「服务」页的「打开 Web 控制台」。")
      }
    }
  }

  private func detail(_ profile: FeishuProfileRow) -> String {
    let collectors = profile.collectors.isEmpty ? "没有启用任何采集器" : profile.collectors.joined(separator: " · ")
    guard profile.documentCount > 0 else { return collectors }
    return "\(collectors)；\(profile.documentCount) 个文档"
  }
}
