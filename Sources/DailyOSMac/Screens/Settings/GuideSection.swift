import SwiftUI
import DailyOSCore

/// The console's Guide, which is documentation and has no endpoint behind it.
///
/// Kept because of what it documents: the Feishu command set exists nowhere in
/// this app's UI — you type those strings into a chat on your phone — so a
/// screen that omits them leaves the remote half of the product undiscoverable.
/// The parts of the web guide that describe the browser console's own pages are
/// dropped instead of translated: this app has those pages, and a table telling
/// you where to click in a different UI is worse than no table.
struct GuideSection: View {
  var body: some View {
    Panel("先做什么", subtitle: "第一次配置的顺序") {
      GuideTable(
        headers: ["步骤", "去哪里", "做什么"],
        rows: [
          ["1", "模型", "选服务商，填密钥或确认 CLI 已登录。"],
          ["2", "飞书", "填凭据，决定发送和接收各开哪一半。"],
          ["3", "数据源", "指好 vault 和记忆仓库，接上 Linear / GitHub。"],
          ["4", "决策规则", "写你的偏好：优先看什么、哪些事不要做。"],
          ["5", "排程", "确认早报和复盘的时间。"],
        ]
      )
    }

    Panel("飞书指令", subtitle: "在飞书里发给机器人，必须带前缀") {
      GuideTable(
        headers: ["指令", "用途", "什么时候用"],
        rows: [
          ["daily-os status", "发一张操作卡片。", "想点按钮时。"],
          ["daily-os plan", "生成今日安排。", "每天开始工作前。"],
          ["daily-os review", "生成今日复盘。", "晚上收尾时。"],
          ["daily-os weekly", "生成普通周复盘。", "只想快速看本周总结时。"],
          ["daily-os weekly deep", "运行 weekly-review 技能。", "要生成可写回飞书 Weekly 的草稿时。"],
          ["daily-os calendar week", "生成本周日历草稿。", "周计划之后，想把任务落到时间块时。"],
          ["daily-os calendar today", "生成今日日历草稿。", "今天临时事项变化后。"],
          ["daily-os details", "展开最近一次完整输出。", "卡片内容太短时。"],
          ["daily-os progress", "找今日进展候选。", "复盘前想补进展时。"],
          ["daily-os chat", "分析最近聊天里的线索。", "想从聊天里找任务、日程、文档更新时。"],
          ["daily-os chat todo", "只找 todo 线索。", "聊天里有人安排事情后。"],
          ["daily-os chat review", "只找进展和复盘线索。", "晚上复盘前。"],
          ["daily-os remember 今天进展：…", "手动记录进展。", "系统没识别到你做了什么时。"],
          ["daily-os 修改今日安排：…", "调整今日安排。", "计划不对时。"],
        ],
        monoColumn: 0
      )
    }

    Panel("写回飞书 Weekly", subtitle: "会改外部文档，所以多一道确认") {
      GuideTable(
        headers: ["动作", "说明"],
        rows: [
          ["先发 daily-os weekly deep", "先生成草稿。不要直接写文档。"],
          ["看飞书卡片", "确认目标文档、周列、要务 / retro 列和要写入的行。"],
          ["点确认写回", "确认之后才改飞书文档。"],
        ]
      )
    }

    Panel("双周复盘 · OKR 写回", subtitle: "跑的是 life-review-os 技能的 biweekly 模式") {
      GuideTable(
        headers: ["步骤", "指令 / 位置", "说明"],
        rows: [
          ["前置", "记忆仓库 10_OKR/", "三层 OKR 需填真值；仍是占位 TODO 时写不回 KR。在「OKR」那一页改。"],
          ["触发", "daily-os skills run weekly-review biweekly", "在对话或飞书里发。必须带 daily-os 前缀，否则会被当成自由对话。"],
          ["看草稿", "对话 / 飞书卡片", "草稿含「计划 vs 执行」复盘、下期安排，以及结构化的 KR 进度块。"],
          ["确认写回", "点卡片「确认写回 OKR」", "确认之后才更新对应 KR；未确认不改任何文件。"],
        ],
        monoColumn: 1
      )
    }

    Panel("安装边界", subtitle: "现在能做到哪一步") {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        HintText("后台服务可以在「服务」那一页一键安装。还没有签名的 Mac App，也没有 DMG 安装包——服务本身仍然是一个需要自己拉下来的 Node 仓库。")
        OutputBlock(
          text: """
            npm ci
            npm run setup
            npm run ui
            npm run build
            """,
          height: 96
        )
      }
    }
  }
}

/// A table that stays a table.
///
/// `Grid` rather than a stack of `HStack`s so the columns actually line up when
/// one cell wraps to three lines — which most of the 说明 column does at this
/// width, and which is exactly where hand-laid rows stop looking like a table.
private struct GuideTable: View {
  let headers: [String]
  let rows: [[String]]
  /// Which column holds machine text (a command, a path). `nil` for none.
  var monoColumn: Int?

  var body: some View {
    Grid(alignment: .topLeading, horizontalSpacing: Metrics.sm, verticalSpacing: Metrics.xs) {
      GridRow {
        ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
          Text(header).mutedStyle(Typo.label)
        }
      }
      Divider().overlay(Palette.line)
      ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
        GridRow {
          ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
            Text(cell)
              .font(index == monoColumn ? Typo.mono : Typo.body)
              .foregroundStyle(index == 0 ? Palette.ink : Palette.inkMuted)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
  }
}
