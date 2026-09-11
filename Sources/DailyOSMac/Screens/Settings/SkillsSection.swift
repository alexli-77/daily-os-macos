import SwiftUI
import DailyOSCore

/// Real installed state for the weekly-review skill.
///
/// The old screen said "已安装 · weekly-review v1.4" for everyone, including
/// people who had never installed it, and there is no version number anywhere in
/// the service — the skill is a git checkout the CLI symlinks to, so its identity
/// is a branch and a commit. `readSkillRepoState` reports all of it from local
/// git without touching the network, including which CLI actually resolves to
/// this directory: without that line an update can report success while the CLI
/// keeps loading an unrelated copy.
struct SkillsSection: View {
  let store: SettingsStore
  let snapshot: SettingsSnapshot

  var body: some View {
    @Bindable var store = store
    Panel("技能", subtitle: "工作流真正执行的那份 checkout") {
      VStack(alignment: .leading, spacing: Metrics.sm) {
        SettingToggle(
          label: "加载技能",
          isOn: Binding(
            get: { snapshot.skillsEnabled },
            // Written straight through rather than into the draft: it is one
            // leaf with no neighbours to save alongside, and a 保存 button for a
            // single switch is a switch that does nothing until you find it.
            set: { value in Task { await store.saveSkillsEnabled(value) } }
          ),
          hint: "关掉之后注册表里的技能一个都不会加载，双周复盘会退回到内置的简易版本。"
        )
        PanelDivider()
        HStack(spacing: Metrics.xs) {
          Pill(snapshot.skillRepo.available ? "已安装" : "未安装", tone: snapshot.skillRepo.available ? .ok : .neutral)
          Text(snapshot.skillRepo.skillId).font(Typo.mono).foregroundStyle(Palette.inkMuted)
        }
        if snapshot.skillRepo.available {
          VStack(alignment: .leading, spacing: Metrics.xxs) {
            KeyValueRow("目录", snapshot.skillRepo.workdir, mono: true)
            if snapshot.skillRepo.isGitRepo {
              KeyValueRow("版本", "\(snapshot.skillRepo.branch) @ \(snapshot.skillRepo.commit)", mono: true)
              if !snapshot.skillRepo.subject.isEmpty {
                KeyValueRow("最新提交", snapshot.skillRepo.subject)
              }
              KeyValueRow("与远端", snapshot.skillRepo.behindText)
            }
            KeyValueRow("CLI 链接", snapshot.skillRepo.linkText)
          }
        } else {
          SettingText(
            label: "安装到",
            text: $store.skillInstallDir,
            placeholder: "留空用默认 ~/.daily-os/skills/life-review-os",
            mono: true,
            width: 420
          )
        }
        if !snapshot.skillRepo.blocked.isEmpty {
          Text(snapshot.skillRepo.blocked)
            .foregroundStyle(Palette.foreground(for: .warn))
            .font(Typo.caption)
            .fixedSize(horizontal: false, vertical: true)
        }
        if !snapshot.skills.isEmpty {
          PanelDivider()
          ForEach(snapshot.skills) { skill in
            HStack(spacing: Metrics.xs) {
              Text(skill.id).inkStyle()
              Pill(skill.provider, tone: .neutral)
              if !skill.defaultMode.isEmpty { Pill(skill.defaultMode, tone: .accent) }
              Spacer(minLength: Metrics.xs)
              Text(skill.path).font(Typo.mono).foregroundStyle(Palette.inkMuted).lineLimit(1).truncationMode(.head)
            }
            .frame(minHeight: Metrics.hitTarget)
          }
        }
      }
    } actions: {
      if snapshot.skillRepo.available {
        Button("更新") { store.confirmUpdateSkill() }
          .buttonStyle(QuietButtonStyle())
          .disabled(store.isBusy || !snapshot.skillRepo.canUpdate)
          .help(snapshot.skillRepo.canUpdate ? "git fetch + git pull --ff-only" : snapshot.skillRepo.blocked)
      } else {
        Button("安装") { store.confirmInstallSkill() }
          .buttonStyle(QuietButtonStyle())
          .disabled(store.isBusy)
      }
    }
  }
}
