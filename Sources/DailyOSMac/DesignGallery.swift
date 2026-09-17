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
        Text("Paper & Mint").inkStyle(Typo.display)

        Panel("纸与墨", subtitle: "三层纸、三级墨") {
          HStack(spacing: Metrics.xs) {
            swatch("paper", Palette.paper)
            swatch("page", Palette.page)
            swatch("rule", Palette.rule)
            swatch("ink", Palette.ink)
            swatch("ink2", Palette.ink2)
            swatch("ink3", Palette.ink3)
            Spacer()
          }
        }

        Panel("薄荷色阶", subtitle: "mint400 是唯一的实心强调色；mint200 上的字一律 mint800") {
          VStack(alignment: .leading, spacing: Metrics.sm) {
            HStack(spacing: Metrics.xs) {
              swatch("mint50", Palette.mint50)
              swatch("mint100", Palette.mint100)
              swatch("mint200", Palette.mint200)
              swatch("mint400", Palette.mint400)
              swatch("mint600", Palette.mint600)
              swatch("mint800", Palette.mint800)
              swatch("q1", Palette.q1)
              Spacer()
            }
            PanelDivider()
            HStack(spacing: Metrics.sm) {
              Text("薄荷底上的字")
                .font(Typo.label)
                .foregroundStyle(Palette.mint800)
                .padding(.horizontal, Metrics.sm)
                .padding(.vertical, Metrics.xxs)
                .background(Palette.mint200, in: Capsule())
              Text("超时 · mint600").font(Typo.caption).foregroundStyle(Palette.mint600)
              Text("MIT").font(Typo.caption).bold().kerning(0.96).foregroundStyle(Palette.q1)
              Spacer()
            }
          }
        }

        Panel("系统状态层", subtitle: "明确的例外：整条信息就是一个状态时才用，计划行永远不是") {
          VStack(alignment: .leading, spacing: Metrics.sm) {
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

        Panel("字体", subtitle: "精确字号 + relativeTo，系统字号照样跟随") {
          VStack(alignment: .leading, spacing: Metrics.xs) {
            Text("display · 9月14日").inkStyle(Typo.display)
            Text("heading · 区块标题").inkStyle(Typo.heading)
            Text("body · 把编导 Skill 的用户价值写清楚").inkStyle()
            Text("label · 10:30–12:30").font(Typo.label).foregroundStyle(Palette.ink2)
            Text("caption · 2h · CUTTO-1022").mutedStyle()
            Text("mono · run_9f2c41 · 20_CYCLES/2026-08-24.md").font(Typo.mono).foregroundStyle(Palette.ink2)
            Text("tabular · 12.4k · $0.0312 · 2m 08s").font(Typo.tabularBody).foregroundStyle(Palette.ink)
            Text("今天清完了").font(Typo.hand).foregroundStyle(Palette.mint600)
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
                Text(seed).font(Typo.mono).foregroundStyle(Palette.ink2)
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
      RoundedRectangle(cornerRadius: Metrics.radiusPaper, style: .continuous)
        .fill(color)
        .frame(width: 52, height: 40)
        .overlay(
          RoundedRectangle(cornerRadius: Metrics.radiusPaper, style: .continuous)
            .strokeBorder(Palette.rule, lineWidth: Metrics.hairline)
        )
      Text(name).font(Typo.mono).foregroundStyle(Palette.ink2)
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
