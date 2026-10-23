import SwiftUI
import DailyOSCore

/// 回收 — a past day that ended without its evening review, asked about
/// before today.
///
/// The review runs on this Mac at its set time. A Mac that is asleep or off
/// then never runs it, and nothing used to say so: on 2026-10-19 three rows
/// were left unticked and nothing looked at them again. So a day like that is
/// not let through quietly. The window opens on this sheet and cannot be
/// dismissed until the day is either closed out (回收: every unticked row gets
/// 完成 / 未做 / 挪到今天, then that evening's review runs late) or skipped on
/// purpose (跳过: the rows stay as they were, and the day is not asked about
/// again). Several days come one after another, oldest first.
struct WrapupSheet: View {
  @Environment(AppState.self) private var state
  let day: WrapupDay

  private enum Step { case ask, settle }

  @State private var step: Step = .ask
  @State private var choices: [String: WrapupChoice] = [:]
  @State private var isSaving = false
  @State private var error: String?

  private var unsettled: [WrapupDay.Row] { day.unsettled }
  private var title: String {
    DayLabel.title(for: day.date, today: day.today).replacingOccurrences(of: " · ", with: "（") + (DayLabel.title(for: day.date, today: day.today).contains(" · ") ? "）" : "")
  }
  private var remainingDays: Int { max(0, state.pendingWrapups.count - 1) }

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.md) {
      switch step {
      case .ask: ask
      case .settle: settle
      }
      if let error {
        Text(error).font(Typo.caption).foregroundStyle(Palette.warn)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(Metrics.lg)
    .frame(width: 520)
    .background(Palette.paper)
    // Not dismissable: the day is closed out or skipped, by a choice.
    .interactiveDismissDisabled(true)
  }

  // MARK: Ask

  private var ask: some View {
    VStack(alignment: .leading, spacing: Metrics.md) {
      VStack(alignment: .leading, spacing: Metrics.xxs) {
        Text("\(title) 还没回收").font(Typo.heading).foregroundStyle(Palette.ink)
        Text("那天晚上的复盘没有跑（电脑可能没开）。回收完，再进今天。")
          .font(Typo.body).foregroundStyle(Palette.ink2)
          .fixedSize(horizontal: false, vertical: true)
      }
      if unsettled.isEmpty {
        Text("那天的条目都处理过了，回收就是补跑那天的复盘。")
          .font(Typo.body).foregroundStyle(Palette.ink2)
      } else {
        VStack(alignment: .leading, spacing: 4) {
          Text("还有 \(unsettled.count) 条没勾：").font(Typo.caption).foregroundStyle(Palette.ink3)
          ForEach(unsettled.prefix(5)) { row in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Circle().strokeBorder(Palette.ink3, lineWidth: 1).frame(width: 8, height: 8)
              Text(row.text).font(Typo.body).foregroundStyle(Palette.ink).lineLimit(1)
              if row.state == .partial { Text("做了一部分").font(Typo.caption).foregroundStyle(Palette.ink3) }
            }
          }
          if unsettled.count > 5 {
            Text("…还有 \(unsettled.count - 5) 条").font(Typo.caption).foregroundStyle(Palette.ink3)
          }
        }
      }
      HStack(alignment: .center) {
        VStack(alignment: .leading, spacing: 2) {
          Text("跳过：没勾的原样留在那天，以后不再问。").font(Typo.caption).foregroundStyle(Palette.ink3)
          if remainingDays > 0 {
            Text("之后还有 \(remainingDays) 天没回收。").font(Typo.caption).foregroundStyle(Palette.ink3)
          }
        }
        Spacer()
        Button("跳过", action: skip)
          .buttonStyle(QuietButtonStyle(tone: .neutral))
          .disabled(isSaving)
        Button("回收") {
          if unsettled.isEmpty { finish() } else { step = .settle }
        }
        .buttonStyle(MossButtonStyle(prominent: true))
        .keyboardShortcut(.defaultAction)
        .disabled(isSaving)
      }
    }
  }

  // MARK: Settle

  private var settle: some View {
    VStack(alignment: .leading, spacing: Metrics.md) {
      VStack(alignment: .leading, spacing: Metrics.xxs) {
        Text("回收 \(title)").font(Typo.heading).foregroundStyle(Palette.ink)
        Text("每条选一个。挪到今天的，会直接加进今天的计划。")
          .font(Typo.caption).foregroundStyle(Palette.ink3)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(unsettled.enumerated()), id: \.element.id) { index, row in
            if index > 0 { Divider() }
            settleRow(row)
          }
        }
      }
      .frame(maxHeight: 360)
      HStack {
        Button("全部挪到今天") {
          for row in unsettled where WrapupChoice.options(for: row).contains(.moveToToday) { choices[row.id] = .moveToToday }
        }
        .buttonStyle(QuietButtonStyle(tone: .neutral))
        .disabled(isSaving)
        Spacer()
        Button("返回") { step = .ask }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
          .disabled(isSaving)
        Button(isSaving ? "回收中…" : "回收完成", action: finish)
          .buttonStyle(MossButtonStyle(prominent: true))
          .keyboardShortcut(.defaultAction)
          .disabled(isSaving || unsettled.contains { choices[$0.id] == nil })
          .help("每条都选好才能完成。完成后会补跑那天的复盘，用一次模型额度。")
      }
    }
  }

  private func settleRow(_ row: WrapupDay.Row) -> some View {
    VStack(alignment: .leading, spacing: Metrics.xs) {
      HStack(alignment: .firstTextBaseline, spacing: Metrics.xs) {
        Text(row.text).font(Typo.body).foregroundStyle(Palette.ink)
          .fixedSize(horizontal: false, vertical: true)
        if row.state == .partial { Text("做了一部分").font(Typo.caption).foregroundStyle(Palette.ink3) }
      }
      HStack(spacing: Metrics.xxs) {
        ForEach(WrapupChoice.options(for: row), id: \.self) { option in
          let isPicked = choices[row.id] == option
          Button(option.label) { choices[row.id] = option }
            .buttonStyle(QuietButtonStyle(tone: isPicked ? .accent : .neutral))
            .overlay {
              if isPicked {
                RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Palette.mint400, lineWidth: 1)
              }
            }
            .accessibilityAddTraits(isPicked ? .isSelected : [])
        }
      }
    }
    .padding(.vertical, Metrics.sm)
  }

  // MARK: Actions

  private func skip() {
    isSaving = true
    error = nil
    let date = day.date
    Task {
      let outcome = await state.resolveWrapup(date: date, action: "skip")
      isSaving = false
      switch outcome {
      case .ok(let text): state.toast = text ?? "跳过了"
      case .failed(let why), .unsupported(let why): error = why
      }
    }
  }

  /// Every decision, then the close. A decision that fails stops here with the
  /// sheet still up, so nothing is half-closed without saying so.
  private func finish() {
    isSaving = true
    error = nil
    let date = day.date
    let decisions = unsettled.compactMap { row in choices[row.id].map { (row, $0) } }
    Task {
      var moved = 0
      for (row, choice) in decisions {
        let outcome: AppState.ActionOutcome
        if choice == .moveToToday {
          outcome = await state.moveRowToToday(date: date, candidateID: row.id, rank: row.rank)
          if case .ok = outcome { moved += 1 }
        } else if let event = choice.event {
          outcome = await state.editPastRow(date: date, candidateID: row.id, rank: row.rank, event: event)
        } else {
          continue
        }
        if case .failed(let why) = outcome { error = "「\(row.text)」没记上：\(why)"; isSaving = false; return }
        if case .unsupported(let why) = outcome { error = why; isSaving = false; return }
      }
      let outcome = await state.resolveWrapup(date: date, action: "done")
      isSaving = false
      switch outcome {
      case .ok(let text):
        state.toast = [text ?? "回收完了", moved > 0 ? "\(moved) 条挪到了今天" : nil].compactMap { $0 }.joined(separator: "；")
      case .failed(let why), .unsupported(let why):
        error = why
      }
    }
  }
}
