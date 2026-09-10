import SwiftUI
import DailyOSCore

/// One thing you can do to a task row.
///
/// `symbol` is not decoration: these render icon-only most of the time, so the
/// glyph *is* the button. `label` still travels with it — it becomes the
/// tooltip, the context-menu wording and the VoiceOver name, which is the whole
/// reason an icon-only control is allowed to exist here.
struct TaskAction: Identifiable {
  enum Role {
    /// The one that resolves the row. Gets the check choreography.
    case complete
    case normal
    case destructive
  }

  let id: String
  let label: String
  let symbol: String
  var tone: Tone = .neutral
  /// Pressed when the row has keyboard focus. `nil` means mouse-only.
  var key: KeyEquivalent?
  var role: Role = .normal
  let perform: () -> Void
}

/// A task row you select, then act on.
///
/// Replaces three worded buttons per row. Those were defended on the grounds
/// that a control you have to go looking for does not get used — which is true
/// of *hover-only* controls, and is the reason this is not that. The actions are
/// reachable four ways: click the row and they appear, hover and they appear,
/// right-click for the same list in words, or press a key while the row has
/// focus. What went away is a permanent wall of buttons on rows you are only
/// reading past.
///
/// Every action animates, and the animation is the receipt. Completion is the
/// one that earns a delay: the check fills, then the row leaves. Removing it on
/// the same frame as the click reads as "the row disappeared", not as "I
/// finished that" — and on a list where things also get deleted, those two need
/// to feel different.
struct TaskRow<Accessory: View>: View {
  let item: TodoItem
  let actions: [TaskAction]
  /// The circle on the left. `nil` draws no circle — a row that cannot be
  /// ticked should not carry the affordance for ticking.
  var onToggleCheck: (() -> Void)?
  @Binding var selectedID: TodoItem.ID?
  @ViewBuilder var accessory: () -> Accessory

  @State private var isHovering = false
  /// Set the instant 完成 is pressed, cleared by the row going away. Lets the
  /// check draw itself before the list re-sorts underneath it.
  @State private var isCompleting = false
  @State private var pendingDestructive: TaskAction?
  @FocusState private var isFocused: Bool

  private var isSelected: Bool { selectedID == item.id }
  private var showsActions: Bool { isHovering || isSelected }
  private var isChecked: Bool { isCompleting || item.state == .done }

  var body: some View {
    HStack(spacing: Metrics.xxs) {
      if let onToggleCheck {
        CheckCircle(isOn: isChecked) {
          if item.state == .done { onToggleCheck() } else { complete(onToggleCheck) }
        }
        // Springs on the fill so ticking has weight. `.snappy` here would be
        // indistinguishable from no animation at this size.
        .animation(.spring(response: 0.3, dampingFraction: 0.62), value: isChecked)
      } else {
        // Holds the slot open. A row with nothing left to tick still belongs to
        // the same list, and letting its text slide left breaks the one vertical
        // line the eye follows down a column of tasks.
        Color.clear.frame(width: Metrics.hitTarget, height: Metrics.hitTarget)
      }

      // No line limit. These are sentences the planner wrote for you to act on,
      // and half of one with an ellipsis is not something you can act on.
      Text(item.text)
        .inkStyle()
        .strikethrough(isChecked, color: Palette.inkMuted)
        .foregroundStyle(item.state == .open && !isCompleting ? Palette.ink : Palette.inkMuted)
        .fixedSize(horizontal: false, vertical: true)
        .animation(.easeOut(duration: 0.2), value: isChecked)

      Spacer(minLength: Metrics.xs)
      accessory()
      actionCluster
    }
    .padding(.horizontal, Metrics.xs)
    .padding(.vertical, 2)
    .frame(minHeight: Metrics.hitTarget)
    .background(rowBackground)
    // A real Button behind the content rather than `.onTapGesture` on it.
    // The gesture version did not fire at all: this row already carries a check
    // circle and up to three icon buttons, and stacking a tap recogniser under
    // `.focusable()` and those buttons produced a row that simply ignored
    // clicks. A background button takes whatever the controls on top of it do
    // not want, which is exactly the rule wanted here.
    .background {
      Button(action: select) { Rectangle().fill(.clear).contentShape(Rectangle()) }
        .buttonStyle(.plain)
        // The row's own accessibility label already says everything this would.
        .accessibilityHidden(true)
    }
    .overlay(alignment: .leading) { selectionBar }
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.14)) { isHovering = hovering }
    }
    // Focus is what makes the keys work, and selection is what makes focus
    // visible. Kept in sync both directions so clicking and tabbing land in the
    // same state rather than in two competing highlights.
    .focusable()
    .focusEffectDisabled()
    .focused($isFocused)
    .onChange(of: isFocused) { _, focused in if focused { selectedID = item.id } }
    .onChange(of: isSelected) { _, selected in if selected { isFocused = true } }
    // ⏎ belongs to the circle, not to an action, which is why no action is
    // allowed to claim it: in a list of things to finish, the default key has
    // exactly one meaning.
    .onKeyPress(.return) {
      guard isSelected, item.state != .done, let onToggleCheck else { return .ignored }
      complete(onToggleCheck)
      return .handled
    }
    .modifier(TaskRowKeys(actions: actions, isEnabled: isSelected, run: run))
    .contextMenu { contextMenu }
    .confirmationDialog(
      pendingDestructive.map { "\($0.label)这一条？" } ?? "",
      isPresented: Binding(get: { pendingDestructive != nil }, set: { if !$0 { pendingDestructive = nil } }),
      titleVisibility: .visible
    ) {
      if let action = pendingDestructive {
        Button(action.label, role: .destructive) {
          pendingDestructive = nil
          withAnimation(.snappy(duration: 0.25)) { action.perform() }
        }
      }
      Button("取消", role: .cancel) { pendingDestructive = nil }
    } message: {
      Text(item.text)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(Text(item.text))
  }

  // MARK: Chrome

  private var rowBackground: some View {
    RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous)
      .fill(isSelected ? Palette.surfaceSunken : (isHovering ? Palette.surfaceSunken.opacity(0.5) : .clear))
  }

  /// Two points of moss down the left edge of the selected row. The app carries
  /// depth in hairlines, so selection is marked the same way rather than with a
  /// filled blue bar borrowed from a list style this screen does not use.
  @ViewBuilder private var selectionBar: some View {
    if isSelected {
      RoundedRectangle(cornerRadius: 1, style: .continuous)
        .fill(Palette.moss)
        .frame(width: 2, height: 16)
        .transition(.opacity.combined(with: .scale(scale: 0.4, anchor: .center)))
    }
  }

  /// Reserves its width whether or not the icons are showing, so a row does not
  /// reflow under the pointer. Text that shifts sideways on hover is the reason
  /// people mis-click.
  private var actionCluster: some View {
    HStack(spacing: 2) {
      ForEach(actions) { action in
        Button { run(action) } label: {
          Image(systemName: action.symbol)
            .font(.system(size: 12, weight: .medium))
            .frame(width: 24, height: 24)
            .contentShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .buttonStyle(TaskIconButtonStyle(tone: action.tone))
        .help(action.key.map { "\(action.label)（\(keyHint($0))）" } ?? action.label)
        .accessibilityLabel(Text(action.label))
      }
    }
    .opacity(showsActions ? 1 : 0)
    // Slides in from the right rather than fading in place: the eye catches
    // movement toward it, and the row is where the pointer already is.
    .offset(x: showsActions ? 0 : 8)
    .animation(.snappy(duration: 0.18), value: showsActions)
    .frame(width: CGFloat(actions.count) * 26, alignment: .trailing)
    // Hidden icons must not be clickable, or the row has invisible hit targets.
    .allowsHitTesting(showsActions)
  }

  @ViewBuilder private var contextMenu: some View {
    ForEach(actions) { action in
      Button(role: action.role == .destructive ? .destructive : nil) {
        run(action)
      } label: {
        Label(action.label, systemImage: action.symbol)
      }
    }
  }

  // MARK: Behaviour

  private func select() {
    withAnimation(.snappy(duration: 0.16)) { selectedID = item.id }
    isFocused = true
  }

  private func run(_ action: TaskAction) {
    switch action.role {
    case .complete:
      complete(action.perform)
    case .destructive:
      // The only action on this row with nothing behind it. Everything else is
      // one click from being undone.
      pendingDestructive = action
    case .normal:
      withAnimation(.snappy(duration: 0.22)) { action.perform() }
    }
  }

  /// Fill the check, hold, then let the row go.
  private func complete(_ perform: @escaping () -> Void) {
    guard !isCompleting else { return }
    withAnimation(.spring(response: 0.3, dampingFraction: 0.62)) { isCompleting = true }
    Task {
      try? await Task.sleep(for: .milliseconds(320))
      withAnimation(.snappy(duration: 0.26)) { perform() }
      // Not reset: by now this row either carries `state == .done` or has left
      // the list. Clearing it would flash the row back to unticked in the frame
      // before the store catches up.
    }
  }

  /// Switches on the character rather than on the `KeyEquivalent`, which is not
  /// `Equatable`. `.delete` is DEL, not backspace, on this platform.
  private func keyHint(_ key: KeyEquivalent) -> String {
    switch key.character {
    case "\r", "\n": "⏎"
    case "\u{7F}", "\u{8}": "⌫"
    case " ": "空格"
    default: String(key.character).uppercased()
    }
  }
}

extension TaskRow where Accessory == EmptyView {
  init(
    item: TodoItem,
    actions: [TaskAction],
    onToggleCheck: (() -> Void)? = nil,
    selectedID: Binding<TodoItem.ID?>
  ) {
    self.init(item: item, actions: actions, onToggleCheck: onToggleCheck, selectedID: selectedID) {
      EmptyView()
    }
  }
}

/// Dispatches a keystroke to whichever action claims it, while the row is
/// selected.
///
/// Two fixed handlers that look the character up, rather than one `.onKeyPress`
/// per action. A per-action chain would change *shape* whenever the action list
/// does — an open row and a deferred row do not offer the same things — and a
/// row whose modifier stack is rebuilt mid-animation loses the `@State` driving
/// that animation.
///
/// Every row installs them and the unselected ones return `.ignored`. Letting
/// only the selected row install handlers sounds tidier but makes the
/// installation itself conditional, which is the same shape problem again.
private struct TaskRowKeys: ViewModifier {
  let actions: [TaskAction]
  let isEnabled: Bool
  let run: (TaskAction) -> Void

  func body(content: Content) -> some View {
    content
      .onKeyPress(characters: .letters) { press in fire(press.characters.first) }
      // Compared against `KeyEquivalent.delete.character` rather than a literal
      // code point, so this keeps matching whatever SwiftUI defines it as.
      .onKeyPress(.delete) { fire(KeyEquivalent.delete.character) }
  }

  private func fire(_ character: Character?) -> KeyPress.Result {
    guard isEnabled, let character else { return .ignored }
    let typed = Character(String(character).lowercased())
    guard let action = actions.first(where: { $0.key?.character == typed }) else { return .ignored }
    run(action)
    return .handled
  }
}

/// Quiet square, tinted on hover. Borderless at rest so a row with four of
/// these still reads as a line of text rather than as a toolbar.
private struct TaskIconButtonStyle: ButtonStyle {
  let tone: Tone
  @State private var isHovering = false

  func makeBody(configuration: Configuration) -> some View {
    let accent = Palette.foreground(for: tone)
    return configuration.label
      .foregroundStyle(isHovering || configuration.isPressed ? accent : Palette.inkMuted)
      .background {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(Palette.softBackground(for: tone))
          .opacity(isHovering ? 1 : 0)
      }
      .scaleEffect(configuration.isPressed ? 0.88 : 1)
      .animation(.snappy(duration: 0.14), value: isHovering)
      .animation(.snappy(duration: 0.12), value: configuration.isPressed)
      .onHover { isHovering = $0 }
  }
}

/// The transition a task row leaves by.
///
/// Collapsing height rather than a plain fade, so the rows below move up into
/// the gap and the list visibly closes over what you finished. A fade leaves a
/// hole for one frame and then snaps, which reads as a glitch.
extension AnyTransition {
  static var taskRow: AnyTransition {
    .asymmetric(
      insertion: .opacity.combined(with: .move(edge: .top)),
      removal: .opacity.combined(with: .scale(scale: 0.97, anchor: .top))
    )
  }
}
