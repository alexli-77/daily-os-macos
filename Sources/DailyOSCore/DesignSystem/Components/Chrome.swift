import SwiftUI

/// A toast, pinned to the bottom.
///
/// Every mutation in this app writes to a file on disk, and the only way to
/// tell the user *which* file without shouting is a transient line. Matches the
/// web console's `#toast`.
public struct ToastOverlay: ViewModifier {
  @Environment(AppState.self) private var state

  public init() {}

  public func body(content: Content) -> some View {
    content.overlay(alignment: .bottom) {
      if let toast = state.toast {
        HStack(spacing: Metrics.sm) {
          Text(toast)
            .font(Typo.caption)
            .foregroundStyle(Palette.paper)
          // Every change Today makes to the schedule can be taken back here:
          // the agreed rule is write back without asking, but never without
          // a way back.
          if let undo = state.toastUndo {
            Button("撤销") {
              state.toastUndo = nil
              state.toast = nil
              undo()
            }
            .buttonStyle(.plain)
            .font(Typo.caption.bold())
            .foregroundStyle(Palette.mint200)
          }
        }
        .padding(.horizontal, Metrics.sm)
        .padding(.vertical, Metrics.xs)
        .background(Palette.ink.opacity(0.92), in: Capsule())
        .padding(.bottom, Metrics.lg)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .task(id: toast) {
          // Long enough to read a sentence and reach 撤销.
          try? await Task.sleep(for: .seconds(state.toastUndo == nil ? 2.2 : 6))
          withAnimation(.easeOut(duration: 0.2)) {
            state.toast = nil
            state.toastUndo = nil
          }
        }
      }
    }
    .animation(.easeOut(duration: 0.2), value: state.toast)
  }
}

extension View {
  public func toastOverlay() -> some View { modifier(ToastOverlay()) }
}

/// A small group heading inside a list column or a stack of panels.
public struct SectionLabel: View {
  private let text: String
  public init(_ text: String) { self.text = text }
  public var body: some View {
    Text(text)
      .mutedStyle(Typo.label)
      .padding(.horizontal, Metrics.sm)
      .padding(.top, Metrics.xs)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}
