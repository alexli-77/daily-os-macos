import SwiftUI
import DailyOSCore

/// 查看日志 is real; 重启 is not an endpoint, and says so.
///
/// `/api/logs` is `readUiLogs()` — the service's own network-and-action log, with
/// secrets already redacted on the way in. Restarting has no endpoint at all:
/// `runActionInner` dispatches `service_install` and `service_uninstall` and
/// nothing else, and `installLaunchAgent` is not a restart in disguise — it boots
/// the agent out and back in, which kills the process answering the request and
/// mints a new token, so a "重启" button wired to it would hang up on itself.
/// launchd, on the other hand, can be asked directly, and this app can talk to
/// launchd — which is what the buttons below do.
///
/// Deliberately absent: the scheduler driver picker. Which scheduler runs the
/// timed workflows is a property of the schedules, and 排程 is where this app
/// talks about those.
struct ServiceSection: View {
  @Environment(AppState.self) private var state
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    @Bindable var store = store
    Panel("服务") {
      VStack(alignment: .leading, spacing: 0) {
        KeyValueRow("状态") {
          StatusDot(
            state.service.state.label,
            tone: state.service.state.tone,
            pulsing: state.service.state == .running
          )
        }
        PanelDivider()
        KeyValueRow("地址", state.service.endpoint, mono: true)
        PanelDivider()
        KeyValueRow("launchd") {
          HStack(spacing: Metrics.xs) {
            Pill(snapshot.service.installed ? "已安装 plist" : "没有 plist", tone: snapshot.service.installed ? .ok : .neutral)
            Pill(snapshot.service.registered ? "已注册" : "未注册", tone: snapshot.service.registered ? .ok : .warn)
            Text(snapshot.service.label).font(Typo.mono).foregroundStyle(Palette.inkMuted)
          }
        }
        PanelDivider()
        KeyValueRow("plist", snapshot.service.plistPath, mono: true)
        PanelDivider()
        // No "已运行" row: the service reports no start time anywhere, and the
        // old screen filled that gap with a zero that read as "刚刚启动".
        VStack(alignment: .leading, spacing: Metrics.xs) {
          Text("开机自启").mutedStyle(Typo.body)
          Text(snapshot.service.installed
            ? "已经装成后台任务：开机自启，崩了自动拉起，早报和复盘这些定时任务才会按时跑。Daily OS 启动时会检查它，没在跑就顺手启动。"
            // No markdown here: this is a `Text(String)`, not a `Text(verbatim:)`
            // of a `LocalizedStringKey`, so `**…**` renders as four asterisks.
            : "还没装成后台任务。现在服务只在你手动开着的时候活着——定时任务不会跑，早报不会自己来。")
            .mutedStyle()
            .fixedSize(horizontal: false, vertical: true)

          HStack(spacing: Metrics.xs) {
            if snapshot.service.installed {
              Button("重启服务") { Task { await store.restartService() } }
                .buttonStyle(QuietButtonStyle())
              Button("停止服务") { store.confirmStopService() }
                .buttonStyle(QuietButtonStyle(tone: .neutral))
              Button("取消开机自启") { store.confirmUninstallAgent() }
                .buttonStyle(QuietButtonStyle(tone: .danger))
            } else {
              Button("装成后台任务") { Task { await store.installAgent() } }
                .buttonStyle(MossButtonStyle())
            }
            Spacer(minLength: 0)
          }

          if snapshot.service.installed {
            // Rebuilding the service is the step people forget, and the symptom
            // — a restart that changes nothing — looks like the restart failing.
            Text("改过服务端代码的话，先在服务目录跑 npm run build 再重启：launchd 跑的是 dist/，不是源码。")
              .mutedStyle()
              .fixedSize(horizontal: false, vertical: true)
          }

          PanelDivider()

          SettingToggle(
            label: "防止待机休眠",
            isOn: Binding(
              get: { snapshot.preventSleep },
              // One leaf, written on the flip. A 保存 button for a single switch
              // is a switch that appears not to work until you find the button.
              set: { value in Task { await store.savePreventSleep(value) } }
            ),
            hint: "用 macOS 的 caffeinate 拦住闲置休眠。合上 MacBook 盖子——尤其是用电池时——仍然会强制睡着，这个开关拦不住。"
          )
        }
        .padding(.top, Metrics.xs)
      }
    } actions: {
      Button("打开 Web 控制台") { store.openWebConsole() }
        .buttonStyle(QuietButtonStyle(tone: .neutral))
        .disabled(store.isBusy)
      Button("查看日志") { store.section = .logs }
        .buttonStyle(QuietButtonStyle())
    }
  }
}

/// `/api/logs`, newest first, as the service returns it.
struct LogsSection: View {
  let store: SettingsStore

  var body: some View {
    Panel("服务日志", subtitle: "只保留最近 7 天；密钥和响应体不进日志") {
      if store.logs.isEmpty {
        EmptyState(
          icon: "doc.plaintext",
          title: "还没有日志",
          message: "data/logs/ui-network.jsonl 现在是空的。点右上角刷新，或者先做点会留下记录的事。",
          actionTitle: "刷新",
          action: { Task { await store.loadLogs() } }
        )
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(store.logs) { entry in
            VStack(alignment: .leading, spacing: 2) {
              HStack(spacing: Metrics.xs) {
                Circle()
                  .fill(Palette.foreground(for: entry.tone))
                  .frame(width: 6, height: 6)
                Text(entry.time).font(Typo.mono).foregroundStyle(Palette.inkMuted)
                Text(entry.summary).font(Typo.monoBody).foregroundStyle(Palette.ink)
                Spacer(minLength: 0)
                if !entry.status.isEmpty {
                  Text(entry.status).mutedStyle()
                }
              }
              if !entry.detail.isEmpty {
                Text(entry.detail)
                  .mutedStyle()
                  .fixedSize(horizontal: false, vertical: true)
                  .padding(.leading, 14)
              }
            }
            .padding(.vertical, Metrics.xxs)
          }
        }
      }
    } actions: {
      Button("刷新") { Task { await store.loadLogs() } }
        .buttonStyle(QuietButtonStyle())
        .disabled(store.isBusy)
      Button("清空") { store.confirmClearLogs() }
        .buttonStyle(QuietButtonStyle(tone: .danger))
        .disabled(store.isBusy || store.logs.isEmpty)
    }
  }
}
