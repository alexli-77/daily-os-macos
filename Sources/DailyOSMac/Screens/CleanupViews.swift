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

/// What the window asks before today, in order.
enum RootPrompt: Identifiable {
  case cleanup(WrapupDay)
  case newCycle(NewCycleNotice)
  case impact(AdhocImpact)

  @MainActor init?(_ state: AppState) {
    // The answer to what was just added comes first.
    if let impact = state.adhocImpact { self = .impact(impact) }
    else if let day = state.cleanupPrompt { self = .cleanup(day) }
    else if let notice = state.newCyclePrompt { self = .newCycle(notice) }
    else { return nil }
  }

  var id: String {
    switch self {
    case .cleanup(let day): "cleanup:\(day.id)"
    case .newCycle(let notice): "cycle:\(notice.id)"
    case .impact(let impact): "impact:\(impact.id)"
    }
  }
}

/// 挤占提醒 (2026-11-02, the user: "新增任务……会影响到本期 weekly 任务的完成，应该
/// 给一个提醒机制，或者重新帮我去编排"). After an add that took work time and left
/// today's 要务 without room: which ones, and three answers.
struct AdhocImpactPrompt: View {
  @Environment(AppState.self) private var state
  let impact: AdhocImpact

  @State private var isWorking = false

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.md) {
      VStack(alignment: .leading, spacing: Metrics.xxs) {
        Text("这条会挤掉今天的要务").font(Typo.heading).foregroundStyle(Palette.ink)
        Text(impact.text).font(Typo.body).foregroundStyle(Palette.ink2)
          .fixedSize(horizontal: false, vertical: true)
      }
      VStack(alignment: .leading, spacing: 4) {
        ForEach(impact.squeezed, id: \.itemKey) { entry in
          HStack(alignment: .firstTextBaseline, spacing: 6) {
            Circle().strokeBorder(Palette.warn, lineWidth: 1).frame(width: 8, height: 8)
            Text(entry.label).font(Typo.body).foregroundStyle(Palette.ink).lineLimit(1)
            Spacer(minLength: Metrics.sm)
            Text(DaySchedule.duration(entry.minutes)).font(Typo.caption).foregroundStyle(Palette.ink3)
          }
        }
      }
      HStack {
        Button("我自己安排") { state.adhocImpact = nil }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
          .keyboardShortcut(.cancelAction)
          .disabled(isWorking)
        if impact.cycleID != nil {
          Button("重新编排本期", action: replan)
            .buttonStyle(QuietButtonStyle(tone: .neutral))
            .disabled(isWorking)
            .help("从现在起把这一期剩下的要务重新排进剩下的日子，一两分钟。")
        }
        Spacer()
        Button(isWorking ? "处理中…" : "顺到明天", action: defer_)
          .buttonStyle(MossButtonStyle(prominent: true))
          .keyboardShortcut(.defaultAction)
          .disabled(isWorking)
      }
    }
    .padding(Metrics.lg)
    .frame(width: 460)
    .background(Palette.paper)
    .interactiveDismissDisabled(true)
  }

  private func defer_() {
    isWorking = true
    Task {
      let outcome = await state.deferSqueezed(impact)
      isWorking = false
      state.adhocImpact = nil
      switch outcome {
      case .ok(let message): state.toast = message ?? "挪到明天了"
      case .failed(let why), .unsupported(let why): state.toast = why
      }
    }
  }

  private func replan() {
    guard let cycleID = impact.cycleID else { return }
    isWorking = true
    Task {
      let outcome = await state.generateCycleSchedule(cycleID: cycleID)
      isWorking = false
      state.adhocImpact = nil
      switch outcome {
      case .ok(let message): state.toast = message ?? "开始重新编排，一两分钟后出来"
      case .failed(let why), .unsupported(let why): state.toast = why
      }
    }
  }
}

/// 新的双周开始了 (2026-11-02). The 8:00 plan waits for it: a plan made before
/// the 双周 is set has no 要务 and fills the day from Linear and the 作息.
/// Suggests the review first (去复盘 → that 双周's 复盘 → 结束本期 → today's
/// plan); generating today's plan anyway is one click.
struct NewCyclePrompt: View {
  @Environment(AppState.self) private var state
  let notice: NewCycleNotice

  @State private var isStarting = false

  var body: some View {
    VStack(alignment: .leading, spacing: Metrics.md) {
      VStack(alignment: .leading, spacing: Metrics.xxs) {
        Text("新的双周开始了").font(Typo.heading).foregroundStyle(Palette.ink)
        Text("上一期 \(notice.previous) 已经结束，这一期的要务还没定。建议先复盘上一期，再生成新双周的要务，最后生成今天的计划——不然今天的计划只能从 Linear 和作息里凑。")
          .font(Typo.body).foregroundStyle(Palette.ink2)
          .fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        Button("稍后") { state.answerNewCycle(notice) }
          .buttonStyle(QuietButtonStyle(tone: .neutral))
          .keyboardShortcut(.cancelAction)
        Button(isStarting ? "生成中…" : "直接生成今天的计划", action: generate)
          .buttonStyle(QuietButtonStyle(tone: .neutral))
          .disabled(isStarting)
          .help(state.hasPlan ? "今天已经有一份计划，这会重新生成。" : "用模型额度，飞书也会收到一条。")
        Spacer()
        Button("去复盘") { state.goSetNewCycle(notice) }
          .buttonStyle(MossButtonStyle(prominent: true))
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(Metrics.lg)
    .frame(width: 460)
    .background(Palette.paper)
    .interactiveDismissDisabled(true)
  }

  private func generate() {
    isStarting = true
    Task {
      let outcome = await state.generatePlan()
      isStarting = false
      state.answerNewCycle(notice)
      switch outcome {
      case .ok(let message): state.toast = message ?? "已让 daily_plan 跑起来了"
      case .failed(let why), .unsupported(let why): state.toast = why
      }
    }
  }
}
