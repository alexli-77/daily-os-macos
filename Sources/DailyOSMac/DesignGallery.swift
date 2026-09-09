import SwiftUI
import DailyOSCore

/// Every token and component on one canvas.
///
/// Not part of the app — it is never routed to from `AppSection`. It exists so
/// that "did the palette change break anything" is one preview to look at
/// rather than eight screens to click through, and so that light and dark can
/// be compared side by side, which is the check that actually catches a bad
/// dark value.
///
/// Kept in the shipping target rather than behind `#if DEBUG` on purpose: this
/// is a design-system repository, and a gallery you have to reconfigure the
/// build to see is a gallery nobody opens.
public struct DesignGallery: View {
  public init() {}

  public var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Metrics.md) {
        Text("Paper & Moss").inkStyle(Typo.display)

        Panel("色彩", subtitle: "五个 tone，任何带状态的东西都必须是其中之一") {
          VStack(alignment: .leading, spacing: Metrics.sm) {
            HStack(spacing: Metrics.xs) {
              swatch("paper", Palette.paper)
              swatch("surface", Palette.surface)
              swatch("sunken", Palette.surfaceSunken)
              swatch("line", Palette.line)
              swatch("ink", Palette.ink)
              swatch("muted", Palette.inkMuted)
              swatch("moss", Palette.moss)
              swatch("mossSoft", Palette.mossSoft)
            }
            PanelDivider()
            HStack(spacing: Metrics.xs) {
              Pill("neutral")
              Pill("accent", tone: .accent)
              Pill("ok", tone: .ok)
              Pill("warn", tone: .warn)
              Pill("danger", tone: .danger)
              Spacer()
            }
            HStack(spacing: Metrics.md) {
              StatusDot("运行中", tone: .ok, pulsing: true)
              StatusDot("降级", tone: .warn)
              StatusDot("已停止", tone: .danger)
              Spacer()
            }
          }
        }

        Panel("字体", subtitle: "系统字号，跟随辅助功能设置") {
          VStack(alignment: .leading, spacing: Metrics.xs) {
            Text("display · 屏幕标题").inkStyle(Typo.display)
            Text("title · 面板标题").inkStyle(Typo.title)
            Text("heading · 面板内小标题").inkStyle(Typo.heading)
            Text("body · 正文与列表行").inkStyle()
            Text("caption · 时间戳与元信息").mutedStyle()
            Text("mono · run_9f2c41 · 20_CYCLES/2026-08-24.md").font(Typo.mono).foregroundStyle(Palette.inkMuted)
            Text("tabular · 12.4k · $0.0312 · 2m 08s").font(Typo.tabularBody).foregroundStyle(Palette.ink)
          }
        }

        Panel("控件") {
          VStack(alignment: .leading, spacing: Metrics.sm) {
            HStack(spacing: Metrics.xs) {
              Button("主要动作") {}.buttonStyle(MossButtonStyle())
              Button("次要动作") {}.buttonStyle(MossButtonStyle(prominent: false))
              Button("安静动作") {}.buttonStyle(QuietButtonStyle())
              Button("破坏性") {}.buttonStyle(QuietButtonStyle(tone: .danger))
              Spacer()
            }
            PanelDivider()
            HStack(spacing: Metrics.md) {
              CheckCircle(isOn: false) {}
              CheckCircle(isOn: true) {}
              Text("待办勾选").inkStyle()
              Spacer()
            }
            PanelDivider()
            VStack(alignment: .leading, spacing: Metrics.xs) {
              ProgressTrack(fraction: 0.75)
              ProgressTrack(fraction: 0.4, tone: .warn)
              ProgressTrack(fraction: 0.15, tone: .danger)
            }
          }
        }

        Panel("头像", subtitle: "5×5 identicon，与 Web 端逐位一致") {
          HStack(spacing: Metrics.sm) {
            ForEach(["kq7d2f1m", "z4h8bn02", "daily-os", "demo", "partner"], id: \.self) { seed in
              VStack(spacing: Metrics.xxs) {
                PixelAvatar(seed: seed, size: 40)
                Text(seed).font(Typo.mono).foregroundStyle(Palette.inkMuted)
              }
            }
            Spacer()
          }
        }

        Panel("空状态", subtitle: "永远不是空白页：说清原因，给一个动作") {
          EmptyState(
            icon: "calendar.badge.plus",
            title: "还没有周期",
            message: "跑一次「周期规划」，或者直接在 20_CYCLES/ 里建一个 Markdown 文件。",
            actionTitle: "跑一次规划",
            action: {}
          )
        }
      }
      .padding(Metrics.screenPadding)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .background(Palette.paper)
  }

  private func swatch(_ name: String, _ color: Color) -> some View {
    VStack(spacing: Metrics.xxs) {
      RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous)
        .fill(color)
        .frame(width: 52, height: 40)
        .overlay(
          RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous)
            .strokeBorder(Palette.line, lineWidth: Metrics.hairline)
        )
      Text(name).font(Typo.mono).foregroundStyle(Palette.inkMuted)
    }
  }
}

// MARK: - Previews

#Preview("设计系统 · 浅色") {
  DesignGallery()
    .frame(width: 760, height: 900)
    .preferredColorScheme(.light)
}

/// The dark palette is not the light ramp inverted, so it has to be looked at
/// rather than reasoned about.
#Preview("设计系统 · 深色") {
  DesignGallery()
    .frame(width: 760, height: 900)
    .preferredColorScheme(.dark)
}
