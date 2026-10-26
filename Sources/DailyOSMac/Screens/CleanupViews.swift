import SwiftUI
import DailyOSCore

/// 每日清理 — the two pieces the user sees.
///
/// 2026-10-26, after the 回收 sheet: the rule is "a day is not over until each
/// of its To-do has a decision", and the place to decide is the day itself —
/// its 日 view, with the same circle and menu as today — not a list of rows in
/// a popup. So the popup only asks, and sends you there:
///
///   1. `CleanupPrompt` — the window opens on it when an earlier day still has
///      open rows, oldest day first. 前往清理 opens that day in 日.
///   2. `CleanupBanner` — on that day's call sheet: how many rows are left,
///      then 清理完成, which closes the day and goes on to the next one, or to
///      today when none is left.
///
/// The 21:00 reminder to clean today is `CleanupReminder`.

/// The question before today. Not dismissable: the day is cleaned or put down,
/// by a choice.
struct CleanupPrompt: View {
  @Environment(AppState.self) private var state
  let day: WrapupDay

  @State private var isSaving = false
  @State private var error: String?

  private var dayText: String { DayLabel.text(for: day.date, today: day.today) }
  private var title: String { dayText == "昨天" ? "昨日 To-do 未清理" : "\(dayText)的 To-do 未清理" }
  private var laterDays: Int { max(0, state.pendingWrapups.count - 1) }

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.md) {
      VStack(alignment: .leading, spacing: Metrics.xxs) {
        Text(title).font(Typo.heading).foregroundStyle(Palette.ink)
        Text(laterDays > 0
             ? "一共 \(laterDays + 1) 天没清理，从最早的一天开始，清完一天接下一天，最后进今天。"
             : "清理完再进今天。")
          .font(Typo.body).foregroundStyle(Palette.ink2)
          .fixedSize(horizontal: false, vertical: true)
      }
      let open = day.open
      VStack(alignment: .leading, spacing: 4) {
        Text("还有 \(open.count) 条没处理：").font(Typo.caption).foregroundStyle(Palette.ink3)
        ForEach(open.prefix(4)) { row in
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().strokeBorder(Palette.ink3, lineWidth: 1).frame(width: 8, height: 8)
            Text(row.text).font(Typo.body).foregroundStyle(Palette.ink).lineLimit(1)
          }
        }
        if open.count > 4 {
          Text("…还有 \(open.count - 4) 条").font(Typo.caption).foregroundStyle(Palette.ink3)
        }
      }
      if let error {
        Text(error).font(Typo.caption).foregroundStyle(Palette.warn)
          .fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Button("这天不清了", action: putDown)
          .buttonStyle(QuietButtonStyle(tone: .neutral))
          .disabled(isSaving)
          .help("没处理的原样留在那天，以后不再问。周报里会写「结果未知」。")
        Spacer()
        Button("前往清理") { Task { await state.startCleanup(day) } }
          .buttonStyle(MossButtonStyle(prominent: true))
          .keyboardShortcut(.defaultAction)
          .disabled(isSaving)
      }
    }
    .padding(Metrics.lg)
    .frame(width: 440)
    .background(Palette.paper)
    .interactiveDismissDisabled(true)
  }

  private func putDown() {
    isSaving = true
    error = nil
    Task {
      let outcome = await state.finishCleanup(day, action: "skip")
      isSaving = false
      switch outcome {
      case .ok(let text): state.toast = text ?? "这天不清了"
      case .failed(let why), .unsupported(let why): error = why
      }
    }
  }
}

/// On a pending day's call sheet, under its progress line.
struct CleanupBanner: View {
  @Environment(AppState.self) private var state
  let day: WrapupDay

  @State private var isSaving = false

  private var open: [TodoItem] { state.cleanupOpenRows }
  private var isLast: Bool { state.pendingWrapups.filter { $0.date != day.date }.isEmpty }

  var body: some View {
    HStack(alignment: .top, spacing: Metrics.sm) {
      Image(systemName: open.isEmpty ? "checkmark.circle" : "checklist")
        .font(.system(size: 15))
        .foregroundStyle(Palette.mint600)
      VStack(alignment: .leading, spacing: 2) {
        if open.isEmpty {
          Text("这天清理完了").font(Typo.label).foregroundStyle(Palette.ink)
          Text(isLast ? "点「清理完成」进入今天。" : "点「清理完成」接着清理下一天。")
            .font(Typo.caption).foregroundStyle(Palette.ink2)
        } else {
          Text("正在清理：还有 \(open.count) 条没处理").font(Typo.label).foregroundStyle(Palette.ink)
          Text("鼠标移到每条左边的圆圈上，选 完成 / 部分 / 未做 / 挪到今天。")
            .font(Typo.caption).foregroundStyle(Palette.ink2)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: Metrics.xs)
      if !open.isEmpty {
        Button("剩下的都挪到今天", action: moveAll)
          .buttonStyle(QuietButtonStyle())
          .disabled(isSaving)
          .help("没处理的每条加进今天的计划，这天记成「挪到今天」。")
      }
      Button(isSaving ? "正在保存…" : (isLast ? "清理完成，进入今天" : "清理完成，下一天"), action: finish)
        .buttonStyle(MossButtonStyle(prominent: open.isEmpty))
        .disabled(isSaving || !open.isEmpty)
        .help(open.isEmpty ? "" : "每条都处理了才能完成")
    }
    .padding(Metrics.sm)
    .background(Palette.mint50, in: RoundedRectangle(cornerRadius: Metrics.radiusPaper, style: .continuous))
  }

  private func finish() {
    isSaving = true
    Task {
      let outcome = await state.finishCleanup(day, action: "done")
      isSaving = false
      switch outcome {
      case .ok(let text): state.toast = text ?? "清理完了"
      case .failed(let why), .unsupported(let why): state.toast = why
      }
    }
  }

  private func moveAll() {
    isSaving = true
    let rows = open
    let date = day.date
    Task {
      var moved = 0
      for item in rows {
        let rank = (state.viewedDay?.items.firstIndex { $0.id == item.id } ?? 0) + 1
        switch await state.moveRowToToday(date: date, candidateID: item.id, rank: rank) {
        case .ok: moved += 1
        case .failed(let why), .unsupported(let why):
          isSaving = false
          state.toast = "「\(item.text)」没挪成：\(why)"
          return
        }
      }
      isSaving = false
      state.toast = "\(moved) 条挪到了今天"
    }
  }
}
