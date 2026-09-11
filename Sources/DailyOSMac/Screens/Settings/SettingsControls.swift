import SwiftUI
import DailyOSCore

/// The handful of form controls this screen repeats a hundred times.
///
/// They exist so that no panel has to decide how wide a text field is or where
/// the hint goes. Fourteen sections each choosing for themselves is how a
/// settings screen ends up with six field widths and four kinds of help text —
/// and the Apple-native feel here comes almost entirely from the opposite.
///
/// All of them sit in a `KeyValueRow`, so the labels line up down the whole
/// panel whatever the control is.

/// One line of text.
struct SettingText: View {
  let label: String
  @Binding var text: String
  var placeholder = ""
  var hint = ""
  var mono = false
  var width: CGFloat = 320

  var body: some View {
    KeyValueRow(label) {
      VStack(alignment: .leading, spacing: Metrics.xxs) {
        TextField(placeholder, text: $text)
          .textFieldStyle(.roundedBorder)
          .font(mono ? Typo.monoBody : Typo.body)
          .frame(maxWidth: width)
        if !hint.isEmpty { HintText(hint) }
      }
    }
  }
}

/// A whole number. `TextField(value:format:)` rather than a `Stepper`: every one
/// of these is a value you type (a poll limit, a debounce in milliseconds), not
/// one you nudge.
struct SettingNumber: View {
  let label: String
  @Binding var value: Int
  var hint = ""

  var body: some View {
    KeyValueRow(label) {
      VStack(alignment: .leading, spacing: Metrics.xxs) {
        TextField("", value: $value, format: .number)
          .textFieldStyle(.roundedBorder)
          .font(Typo.tabularBody)
          .frame(maxWidth: 120)
        if !hint.isEmpty { HintText(hint) }
      }
    }
  }
}

/// On or off. A switch rather than `CheckCircle`, which is the todo affordance
/// and would read as "this setting is a task".
struct SettingToggle: View {
  let label: String
  @Binding var isOn: Bool
  var hint = ""

  var body: some View {
    KeyValueRow(label) {
      VStack(alignment: .leading, spacing: Metrics.xxs) {
        Toggle("", isOn: $isOn)
          .labelsHidden()
          .toggleStyle(.switch)
        if !hint.isEmpty { HintText(hint) }
      }
    }
  }
}

/// A closed set of values. Menu rather than segmented past three options, because
/// a five-segment control at this width truncates its own labels.
struct SettingPicker: View {
  let label: String
  @Binding var selection: String
  let options: [(value: String, title: String)]
  var hint = ""

  var body: some View {
    KeyValueRow(label) {
      VStack(alignment: .leading, spacing: Metrics.xxs) {
        if options.count <= 3 {
          picker.pickerStyle(.segmented).frame(maxWidth: 300, alignment: .leading)
        } else {
          picker.pickerStyle(.menu).frame(maxWidth: 240, alignment: .leading)
        }
        if !hint.isEmpty { HintText(hint) }
      }
    }
  }

  private var picker: some View {
    Picker("", selection: $selection) {
      ForEach(options, id: \.value) { option in
        Text(option.title).tag(option.value)
      }
    }
    .labelsHidden()
  }
}

/// A list, one entry per line.
///
/// Every list in this config is a set of short opaque strings — open ids, chat
/// ids, `owner/repo`. A row editor with add and remove buttons would be six
/// controls for something you paste ten of at once, so it is a text box and the
/// save path does the de-duplicating.
struct SettingLines: View {
  let label: String
  @Binding var text: String
  var placeholder = ""
  var hint = ""
  var height: CGFloat = 84

  var body: some View {
    KeyValueRow(label) {
      VStack(alignment: .leading, spacing: Metrics.xxs) {
        PlainTextEditor(text: $text, height: height, mono: true)
          .frame(maxWidth: 420)
        if !placeholder.isEmpty, text.isEmpty { HintText(placeholder) }
        if !hint.isEmpty { HintText(hint) }
      }
    }
  }
}

/// A path, with the picker beside it.
///
/// Typing a path is still allowed — a lot of these live behind symlinks or on
/// volumes the panel opens slowly — but the button is what makes a mistyped
/// path an uncommon way to configure this app rather than the normal one.
struct SettingPath: View {
  let label: String
  @Binding var text: String
  var placeholder = ""
  var hint = ""
  let choose: () -> Void

  var body: some View {
    KeyValueRow(label) {
      VStack(alignment: .leading, spacing: Metrics.xxs) {
        HStack(spacing: Metrics.xs) {
          TextField(placeholder, text: $text)
            .textFieldStyle(.roundedBorder)
            .font(Typo.monoBody)
            .frame(maxWidth: 360)
          Button("选择…", action: choose)
            .buttonStyle(QuietButtonStyle())
        }
        if !hint.isEmpty { HintText(hint) }
      }
    }
  }
}

/// The multi-line editor behind `SettingLines` and the markdown panels.
///
/// `.scrollContentBackground(.hidden)` is load-bearing: a plain `TextEditor`
/// paints the system's own control background, which on the paper palette is a
/// grey rectangle that belongs to a different app.
struct PlainTextEditor: View {
  @Binding var text: String
  var height: CGFloat = 240
  var mono = false

  var body: some View {
    TextEditor(text: $text)
      .font(mono ? Typo.monoBody : Typo.body)
      .foregroundStyle(Palette.ink)
      .scrollContentBackground(.hidden)
      .padding(Metrics.xs)
      .frame(height: height)
      .background(Palette.surfaceSunken)
      .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous)
          .strokeBorder(Palette.line, lineWidth: Metrics.hairline)
      )
  }
}

/// The one way explanatory prose appears on this screen.
struct HintText: View {
  private let text: String
  init(_ text: String) { self.text = text }

  var body: some View {
    Text(text)
      .mutedStyle()
      .fixedSize(horizontal: false, vertical: true)
  }
}

/// A read-only block of whatever the service just said.
///
/// Monospaced and selectable because the contents are machine output — a JSON
/// dump from `collect`, a doctor report, an engine stack trace — and the next
/// thing someone does with it is paste it somewhere.
struct OutputBlock: View {
  let text: String
  var height: CGFloat = 220

  var body: some View {
    ScrollView {
      Text(text)
        .font(Typo.mono)
        .foregroundStyle(Palette.ink)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.xs)
    }
    .frame(height: height)
    .background(Palette.surfaceSunken)
    .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Metrics.radiusSmall, style: .continuous)
        .strokeBorder(Palette.line, lineWidth: Metrics.hairline)
    )
  }
}

/// A secret that belongs to a data source.
///
/// Presence and a replace field, never the value: unlike the model key row there
/// is no 显示 button here, because nothing on a sources panel is improved by
/// having a GitHub token sitting in a screenshot. Replacing goes through
/// `/api/env`, which skips an empty secret — so an untouched field cannot blank
/// a working key.
struct SourceSecretRow: View {
  let label: String
  let key: String
  let store: SettingsStore
  var hint = ""

  var body: some View {
    @Bindable var store = store
    let present = store.sourceSecrets[key] ?? false
    KeyValueRow(label) {
      VStack(alignment: .leading, spacing: Metrics.xs) {
        HStack(spacing: Metrics.xs) {
          Pill(present ? "已配置" : "未配置", tone: present ? .ok : .neutral)
          Text(key).font(Typo.mono).foregroundStyle(Palette.inkMuted)
          Button(store.editingSourceSecret == key ? "取消" : (present ? "更换" : "填写")) {
            store.toggleSourceSecretEditor(key: key)
          }
          .buttonStyle(QuietButtonStyle())
        }
        if store.editingSourceSecret == key {
          HStack(spacing: Metrics.xs) {
            SecureField(key, text: $store.sourceSecretDraft)
              .textFieldStyle(.roundedBorder)
              .frame(maxWidth: 320)
            Button("写入") { store.confirmSaveSourceSecret(key: key) }
              .buttonStyle(MossButtonStyle(prominent: false))
              .disabled(store.sourceSecretDraft.isEmpty || store.isBusy)
          }
        }
        if !hint.isEmpty { HintText(hint) }
      }
    }
  }
}

/// The 保存 action every editable section puts in its panel header.
///
/// Present only when there is something to save. A permanently lit Save button
/// is a button you press to find out whether anything changed, and on this
/// screen pressing it rewrites the user's whole config file.
struct SaveAction: View {
  let isDirty: Bool
  let isBusy: Bool
  var title = "保存"
  let action: () -> Void

  var body: some View {
    if isDirty {
      Button(title, action: action)
        .buttonStyle(MossButtonStyle(prominent: false))
        .disabled(isBusy)
    }
  }
}

/// A run-this-now button for one of the service's named actions.
///
/// Shows which one is in flight rather than disabling the whole panel: several
/// of these take a minute, and a screen that goes uniformly grey does not say
/// which of the eight buttons it is waiting on.
struct ActionButton: View {
  let title: String
  let action: String
  let store: SettingsStore
  var tone: Tone = .accent
  var run: (() -> Void)?

  var body: some View {
    Button(store.runningAction == action ? "\(title)…" : title) {
      if let run {
        run()
      } else {
        Task { await store.runAction(action, label: title) }
      }
    }
    .buttonStyle(QuietButtonStyle(tone: tone))
    .disabled(store.isBusy)
  }
}
