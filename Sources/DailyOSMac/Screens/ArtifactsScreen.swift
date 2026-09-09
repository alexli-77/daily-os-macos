import SwiftUI
import DailyOSCore

/// Files the workflows produced.
///
/// A list, not a grid. Artifacts here are overwhelmingly text — markdown
/// reviews, JSON drafts, CSV exports — and a grid of thumbnails for text files
/// is decoration that costs you the metadata you actually scan by: which run
/// made it, and when.
struct ArtifactsScreen: View {
  @Environment(AppState.self) private var state

  var body: some View {
    HStack(spacing: 0) {
      ListColumn { ArtifactList() }
      Group {
        if let artifact = state.selectedArtifact {
          ArtifactDetail(artifact: artifact)
        } else {
          emptyState
        }
      }
      .frame(maxWidth: .infinity)
    }
    .background(Palette.paper)
  }

  private var emptyState: some View {
    EmptyState(
      icon: "shippingbox",
      title: "还没有产物",
      message: "工作流生成的文件会出现在这里，并且指回生成它的那次运行。"
    )
  }
}

private struct ArtifactList: View {
  @Environment(AppState.self) private var state

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 2) {
        ForEach(state.artifacts) { artifact in
          SelectableRow(isSelected: artifact.id == state.selectedArtifact?.id) {
            state.selectedArtifactID = artifact.id
          } content: {
            ArtifactRow(artifact: artifact)
          }
        }
      }
      .padding(Metrics.xs)
    }
  }
}

private struct ArtifactRow: View {
  let artifact: Artifact

  var body: some View {
    HStack(alignment: .top, spacing: Metrics.xs) {
      Image(systemName: artifact.type.icon)
        .foregroundStyle(Palette.inkMuted)
        .frame(width: 18)
      VStack(alignment: .leading, spacing: Metrics.xxs) {
        Text(artifact.name).inkStyle().lineLimit(1).truncationMode(.middle)
        HStack(spacing: Metrics.xs) {
          Text(Fmt.bytes(artifact.byteSize)).font(Typo.tabularCaption).foregroundStyle(Palette.inkMuted)
          Text(Fmt.stamp(artifact.createdAt)).mutedStyle()
        }
      }
    }
  }
}

private struct ArtifactDetail: View {
  let artifact: Artifact

  var body: some View {
    ScreenScaffold(artifact.name, subtitle: subtitle) {
      Panel("预览") {
        if let preview = artifact.preview, artifact.type.isPreviewable {
          ScrollView(.horizontal, showsIndicators: true) {
            Text(preview)
              .font(Typo.mono)
              .foregroundStyle(Palette.ink)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .frame(maxHeight: 360)
          .padding(Metrics.xs)
          .background(Palette.surfaceSunken)
          .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
        } else {
          EmptyState(
            icon: artifact.type.icon,
            title: "无法预览",
            message: "\(artifact.type.label) 不在可预览类型里。用系统默认程序打开。",
            actionTitle: "打开",
            action: {}
          )
        }
      } actions: {
        Button("打开") {}.buttonStyle(QuietButtonStyle())
      }

      Panel("信息") {
        VStack(spacing: 0) {
          KeyValueRow("类型", artifact.type.label, mono: true)
          PanelDivider()
          KeyValueRow("大小", Fmt.bytes(artifact.byteSize))
          PanelDivider()
          KeyValueRow("生成于", Fmt.stamp(artifact.createdAt))
          if let runId = artifact.runId {
            PanelDivider()
            KeyValueRow("来自运行") {
              HStack(spacing: Metrics.xs) {
                Text(runId).font(Typo.monoBody).foregroundStyle(Palette.ink)
                Button("查看") {}.buttonStyle(QuietButtonStyle())
              }
            }
          }
        }
      }
    }
  }

  private var subtitle: String {
    "\(artifact.type.label) · \(Fmt.bytes(artifact.byteSize))"
  }
}

// MARK: - Previews

#Preview("产物") {
  ArtifactsScreen()
    .environment(AppState.previewOwner())
    .frame(width: 1_040, height: 720)
}

#Preview("产物 · 空状态") {
  ArtifactsScreen()
    .environment(AppState.previewEmpty())
    .frame(width: 1_040, height: 720)
}
