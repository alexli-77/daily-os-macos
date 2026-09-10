import AppKit
import SwiftUI
import DailyOSCore

/// Files the workflows produced.
///
/// A list, not a grid. Artifacts here are overwhelmingly text — markdown
/// reviews, JSON drafts, CSV exports — and a grid of thumbnails for text files
/// is decoration that costs you the metadata you actually scan by: which run
/// made it, and when.
///
/// The rows come from `AppState` like every other screen's do, and they carry
/// their own path, so this screen opens files without talking to the service
/// itself. It used to, because `Artifact` had no path field.
struct ArtifactsScreen: View {
  @Environment(AppState.self) private var state
  @State private var actions = ArtifactFileActions()

  var body: some View {
    HStack(spacing: 0) {
      ListColumn { ArtifactList() }
      Group {
        if let artifact = state.selectedArtifact {
          ArtifactDetail(artifact: artifact, actions: actions)
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
  @Environment(AppState.self) private var state
  let artifact: Artifact
  let actions: ArtifactFileActions

  private var hasFile: Bool { artifact.path != nil }

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
            message: previewMessage,
            // No button when there is no file behind it: an "打开" that shrugs
            // is the defect this screen was rewritten to remove.
            actionTitle: hasFile ? "打开" : nil,
            action: { actions.open(artifact) }
          )
        }
      } actions: {
        if hasFile {
          Button("打开") { actions.open(artifact) }.buttonStyle(QuietButtonStyle())
          Button("在访达中显示") { actions.reveal(artifact) }.buttonStyle(QuietButtonStyle())
        }
      }

      Panel("信息") {
        VStack(spacing: 0) {
          // `ArtifactType` mirrors the service's set one-to-one now, so the
          // domain label is the true one and there is no wire word to fall back
          // to.
          KeyValueRow("类型", artifact.type.label, mono: true)
          PanelDivider()
          KeyValueRow("大小", Fmt.bytes(artifact.byteSize))
          PanelDivider()
          KeyValueRow("生成于", Fmt.stamp(artifact.createdAt))
          if let url = artifact.path {
            PanelDivider()
            KeyValueRow("位置") {
              Text(url.path(percentEncoded: false))
                .font(Typo.monoBody)
                .foregroundStyle(Palette.ink)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
            }
          } else {
            PanelDivider()
            KeyValueRow("文件") { Text("这个产物不在本机服务的索引里，没有对应的文件路径。").mutedStyle() }
          }
          if let runId = artifact.runId {
            PanelDivider()
            KeyValueRow("来自运行") {
              HStack(spacing: Metrics.xs) {
                Text(runId).font(Typo.monoBody).foregroundStyle(Palette.ink)
                // Only offered when that run is actually loaded. Jumping to Runs
                // with an id the list does not contain lands on whatever run is
                // first, which reads as "here is the run that made this file"
                // and is not.
                if state.runs.contains(where: { $0.id == runId }) {
                  Button("查看") {
                    state.selectedRunID = runId
                    state.section = .runs
                  }
                  .buttonStyle(QuietButtonStyle())
                }
              }
            }
          }
          if let message = actions.actionError {
            PanelDivider()
            KeyValueRow("打不开") {
              Text(message)
                .font(Typo.body)
                .foregroundStyle(Palette.foreground(for: .danger))
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }
    }
  }

  private var subtitle: String {
    "\(artifact.type.label) · \(Fmt.bytes(artifact.byteSize))"
  }

  private var previewMessage: String {
    hasFile
      ? "产物索引只返回文件信息，不返回内容。交给系统默认程序打开。"
      : "服务的产物索引里没有这个文件，Mac 端也就无从打开它。"
  }
}

// MARK: - Files on disk

/// The two things you can do with an artifact's file.
///
/// `Artifact.path` carries the location now, so this holds no state about
/// *where* anything is — only why the last click did nothing. It used to read
/// the service's index itself, through a copy of the transport, because the
/// record had no path field; adding one deleted about ninety lines and one
/// place for the two to disagree.
@Observable
@MainActor
final class ArtifactFileActions {
  /// Why the last click did nothing. Cleared by the next successful one.
  private(set) var actionError: String?

  /// Hand the file to whatever the user has set as its default application.
  func open(_ artifact: Artifact) {
    guard let url = resolve(artifact) else { return }
    if NSWorkspace.shared.open(url) {
      actionError = nil
    } else {
      actionError = "系统里没有能打开 \(url.lastPathComponent) 的程序。"
    }
  }

  func reveal(_ artifact: Artifact) {
    guard let url = resolve(artifact) else { return }
    NSWorkspace.shared.activateFileViewerSelecting([url])
    actionError = nil
  }

  /// The index is a snapshot of the last scan, and a workflow output can be
  /// moved or cleaned up after it. Checking first is what turns a click that
  /// does nothing into a sentence that says why.
  private func resolve(_ artifact: Artifact) -> URL? {
    guard let url = artifact.path else {
      actionError = "这个产物没有文件路径——它不在本机服务的索引里。"
      return nil
    }
    guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
      actionError = "文件已经不在磁盘上了：\(url.path(percentEncoded: false))"
      return nil
    }
    return url
  }
}

// MARK: - Previews

/// Both previews run without a service, so every row is fixture data with no
/// file behind it and the detail panel says so where the open buttons would be.
/// That is the intended reading: these artifacts do not exist on this disk.
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
