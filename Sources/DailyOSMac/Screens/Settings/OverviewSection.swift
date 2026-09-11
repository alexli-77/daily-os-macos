import SwiftUI
import DailyOSCore

/// The console's Overview: what the service thinks of itself, and the things you
/// can make it do right now.
///
/// The web version was a row of ten identical grey buttons. Here they are
/// grouped by what they touch, because "Collect" and "Test Feishu" are not the
/// same kind of act — one reads your sources, the other posts a message into a
/// chat your colleagues can see. The one that leaves this Mac asks first.
struct OverviewSection: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  private var failures: [DoctorRow] { snapshot.doctor.filter { !$0.ok } }
  private var warnings: [DoctorRow] { snapshot.doctor.filter { $0.ok && $0.level == "warning" } }

  var body: some View {
    DoctorPanel(store: store, snapshot: snapshot, failures: failures, warnings: warnings)
    ActionsPanel(store: store)
    if !store.actionOutput.isEmpty {
      Panel("输出", subtitle: "上一次动作的完整返回，服务原样给的") {
        OutputBlock(text: store.actionOutput, height: 280)
      } actions: {
        Button("复制") { store.copy(store.actionOutput, what: "输出") }
          .buttonStyle(QuietButtonStyle())
        Button("清除") { store.clearActionOutput() }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
      }
    }
  }
}

/// `runDoctor`'s checks, worst first.
///
/// Sorted rather than listed in the service's order because the service's order
/// is the order the checks were written in, and with twenty rows the one that is
/// broken is the only one anybody came here to read.
private struct DoctorPanel: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot
  let failures: [DoctorRow]
  let warnings: [DoctorRow]

  var body: some View {
    Panel("自检", subtitle: summary) {
      if snapshot.doctor.isEmpty {
        HintText("服务没有返回任何检查项。它可能是个更老的版本。")
      } else {
        VStack(spacing: 0) {
          ForEach(Array(ordered.enumerated()), id: \.element.id) { index, check in
            if index > 0 { PanelDivider() }
            HStack(alignment: .top, spacing: Metrics.sm) {
              Pill(check.label, tone: check.tone)
                .frame(width: 56, alignment: .leading)
              VStack(alignment: .leading, spacing: 2) {
                Text(check.name).font(Typo.monoBody).foregroundStyle(Palette.ink)
                if !check.detail.isEmpty {
                  HintText(check.detail)
                }
              }
              Spacer(minLength: 0)
            }
            .frame(minHeight: Metrics.hitTarget)
            .padding(.vertical, Metrics.xxs)
          }
        }
      }
    } actions: {
      ActionButton(title: "重新自检", action: "doctor", store: store)
    }
  }

  private var ordered: [DoctorRow] {
    failures + warnings + snapshot.doctor.filter { $0.ok && $0.level != "warning" }
  }

  private var summary: String {
    guard !snapshot.doctor.isEmpty else { return "还没有结果" }
    if failures.isEmpty && warnings.isEmpty { return "\(snapshot.doctor.count) 项全部通过" }
    let parts = [
      failures.isEmpty ? nil : "\(failures.count) 项失败",
      warnings.isEmpty ? nil : "\(warnings.count) 项有警告",
    ].compactMap { $0 }
    return parts.joined(separator: "，") + "，共 \(snapshot.doctor.count) 项"
  }
}

/// Everything `/api/action` dispatches that is worth a button.
///
/// `todo_capture` is missing on purpose: 今天 already has the capture field, and
/// a second one buried in Settings is a second place for a thought to end up.
private struct ActionsPanel: View {
  let store: SettingsStore

  var body: some View {
    @Bindable var store = store
    Panel("手动运行", subtitle: "平时由排程触发，这里是想现在就跑一次的时候") {
      VStack(alignment: .leading, spacing: 0) {
        KeyValueRow("工作流") {
          HStack(spacing: Metrics.xxs) {
            ActionButton(title: "生成今日安排", action: "plan", store: store)
            ActionButton(title: "生成今日复盘", action: "review", store: store)
            ActionButton(title: "生成周复盘", action: "weekly", store: store)
          }
        }
        PanelDivider()
        KeyValueRow("证据") {
          HStack(spacing: Metrics.xxs) {
            ActionButton(title: "采集证据", action: "collect", store: store)
            ActionButton(title: "今日进展", action: "progress", store: store)
          }
        }
        PanelDivider()
        KeyValueRow("聊天线索") {
          HStack(spacing: Metrics.xxs) {
            ActionButton(title: "全部", action: "chat_analysis", store: store)
            ActionButton(title: "只找 todo", action: "chat_analysis_todo", store: store)
            ActionButton(title: "只找进展", action: "chat_analysis_review", store: store)
          }
        }
        PanelDivider()
        KeyValueRow("日历草稿") {
          HStack(spacing: Metrics.xxs) {
            ActionButton(title: "本周", action: "calendar_week", store: store)
            ActionButton(title: "今天", action: "calendar_today", store: store)
            ActionButton(title: "测试引擎", action: "calendar_test", store: store)
          }
        }
        PanelDivider()
        KeyValueRow("飞书") {
          HStack(spacing: Metrics.xxs) {
            // The only button here that writes to something other than this Mac,
            // so it is the only one that goes through a confirmation.
            ActionButton(title: "发测试消息", action: "feishu_test", store: store) {
              store.confirmFeishuTest()
            }
            ActionButton(title: "拉取反馈", action: "feedback_poll", store: store)
          }
        }
        PanelDivider()
        KeyValueRow("结果回发飞书") {
          VStack(alignment: .leading, spacing: Metrics.xxs) {
            Toggle("", isOn: $store.sendActionOutput)
              .labelsHidden()
              .toggleStyle(.switch)
            HintText("关掉就只在这一屏看结果。生成类的动作默认会把结果也发到飞书，和排程跑出来的那份走同一条路。")
          }
        }
      }
    }
  }
}
