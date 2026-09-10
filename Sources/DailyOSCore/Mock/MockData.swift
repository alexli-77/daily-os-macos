import Foundation

/// The fixture the shell runs on.
///
/// Deliberately generic. This repository is public and the upstream project has
/// a `privacy-scan` gate for exactly this reason — no real OKRs, issue ids,
/// team names, file paths or people go in here. The shape is real; the content
/// is a demo account.
public enum MockData {
  private static let now = Date()

  static func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
  static func minutesAgo(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

  // MARK: Service & account

  public static let service = ServiceStatus(
    state: .running,
    endpoint: "127.0.0.1:14573",
    uptime: .seconds(4 * 3600 + 12 * 60),
    note: nil
  )

  public static let account = Account(
    id: "u_demo",
    displayName: "demo",
    email: "demo@example.com",
    role: .owner,
    avatarSeed: "kq7d2f1m"
  )

  public static let teamSync = TeamSyncState(
    status: "ready",
    reason: "",
    syncedAt: minutesAgo(1),
    lastError: ""
  )

  public static let members: [TeamMember] = [
    TeamMember(id: "u_demo", displayName: "demo", avatarSeed: "kq7d2f1m", isSelf: true, lastSyncedAt: minutesAgo(1)),
    TeamMember(id: "u_partner", displayName: "partner", avatarSeed: "z4h8bn02", isSelf: false, lastSyncedAt: minutesAgo(23)),
  ]

  // MARK: Cycles

  public static let cycles: [Cycle] = [
    Cycle(
      id: "c_0824",
      label: "8.24-9.6",
      mode: .biweekly,
      start: daysAgo(16),
      end: daysAgo(2),
      ownerId: "u_demo",
      runId: "run_9f2c41",
      sections: [
        CycleSection(
          kind: .priorities,
          body: """
          ### 工作 · 技术专家
          - **MIT** 把周期数据落成本地 markdown，作为唯一真相源 ✅
          - 团队同步走 upsert + 轮询，本地优先 ✅
          - 把配置台面收敛到 owner-only DEMO-12 🚧
          - 回归测试覆盖周期读写往返 DEMO-15 ❌

          ### 金钱 · 家庭理财
          - 季度财富快照后校准三个数：runway / 月支出上限 / 现金储备线 ✅
          - 决定二次换汇金额并执行 🚧

          ### 自我 · 表达者
          - 每周完成 2 次思考沉淀，其中至少 1 次可转化为公开输出
          """,
          source: .user,
          updatedAt: daysAgo(3),
          pendingDraft: """
          ### 工作 · 技术专家
          - **MIT** 把周期数据落成本地 markdown，作为唯一真相源 ✅
          - 团队同步走 upsert + 轮询，本地优先 ✅
          - 把配置台面收敛到 owner-only DEMO-12 🚧
          - 回归测试覆盖周期读写往返 DEMO-15 ❌
          - 新增：给运行页加 token / 成本列

          ### 金钱 · 家庭理财
          - 季度财富快照后校准三个数：runway / 月支出上限 / 现金储备线 ✅
          - 决定二次换汇金额并执行 🚧

          ### 自我 · 表达者
          - 每周完成 2 次思考沉淀，其中至少 1 次可转化为公开输出
          """
        ),
        CycleSection(
          kind: .retro,
          body: """
          实际做完了前两项。第三项低估了工作量：真正的拦路虎不是权限判断，
          是硬编码的数据目录和一张共享的 SQLite。拆成两个 scope 之后才推动起来。

          节奏上，双周中途插了一件紧急的事，手工改了要务列表 —— 这也是为什么
          planner 重跑不能整段覆盖。
          """,
          source: .user,
          updatedAt: daysAgo(2)
        ),
        CycleSection(
          kind: .review,
          body: """
          计划 4 项，完成 2 项，1 项拆分后推进，1 项顺延。

          结论：双周的容量大约是 2 件"需要连续注意力"的事，不是 4 件。
          下一期按 2 + 若干碎片来排。
          """,
          source: .ai,
          updatedAt: daysAgo(2)
        ),
      ],
      updatedAt: daysAgo(2)
    ),
    Cycle(
      id: "c_0810",
      label: "8.10-8.23",
      mode: .biweekly,
      start: daysAgo(30),
      end: daysAgo(16),
      ownerId: "u_demo",
      runId: "run_71ab03",
      sections: [
        CycleSection(
          kind: .priorities,
          body: """
          - [x] 日历写回幂等：按天覆盖，可撤销
          - [x] 写回前做 free/busy 冲突检测
          - [x] 打通 adjust 回灌闭环
          """,
          source: .planner,
          updatedAt: daysAgo(30)
        ),
        CycleSection(
          kind: .retro,
          body: "三项都做完了。冲突检测这块的卡片提示做得比预期好用，原本以为是可选项。",
          source: .user,
          updatedAt: daysAgo(16)
        ),
        CycleSection(
          kind: .review,
          body: "计划 3 项，完成 3 项。这一期的估算是准的，因为三件事在同一个模块里。",
          source: .ai,
          updatedAt: daysAgo(16)
        ),
      ],
      updatedAt: daysAgo(16)
    ),
    Cycle(
      id: "c_0727",
      label: "7.27-8.9",
      mode: .biweekly,
      start: daysAgo(44),
      end: daysAgo(30),
      ownerId: "u_demo",
      runId: "run_2c99de",
      sections: [
        CycleSection(
          kind: .priorities,
          body: "- [x] 自助注册 / 登录 / 会话持久化\n- [ ] 团队邀请码链路",
          source: .planner,
          updatedAt: daysAgo(44)
        ),
        CycleSection(kind: .retro, body: "登录做完了，邀请码顺延。", source: .user, updatedAt: daysAgo(30)),
        CycleSection(kind: .review, body: "计划 2 项，完成 1 项。", source: .ai, updatedAt: daysAgo(30)),
      ],
      updatedAt: daysAgo(30)
    ),
  ]

  /// The teammate's cycle — read-only, and rendered from the sync cache rather
  /// than from local files.
  public static let partnerCycles: [Cycle] = [
    Cycle(
      id: "p_0824",
      label: "8.24-9.6",
      mode: .biweekly,
      start: daysAgo(16),
      end: daysAgo(2),
      ownerId: "u_partner",
      runId: nil,
      sections: [
        CycleSection(
          kind: .priorities,
          body: "- [x] 期末论文提纲\n- [x] 两场面试\n- [ ] 健身回到每周三次",
          source: .user,
          updatedAt: daysAgo(4)
        ),
        CycleSection(kind: .retro, body: "面试占掉了大部分时间，健身只做到一次。", source: .user, updatedAt: daysAgo(2)),
        CycleSection(kind: .review, body: "计划 3 项，完成 2 项。", source: .ai, updatedAt: daysAgo(2)),
      ],
      updatedAt: daysAgo(2)
    )
  ]

  // MARK: Today

  public static let plan: [TodoItem] = [
    TodoItem(id: "p1", text: "把配置台面收敛为 owner-only", kind: .priority, due: now.addingTimeInterval(3600 * 5), state: .done, sourceRef: "DEMO-12", estimatedMinutes: 90),
    TodoItem(id: "p2", text: "周会 · 同步这一期的进展", kind: .schedule, due: now.addingTimeInterval(3600 * 2), estimatedMinutes: 45),
    TodoItem(id: "p3", text: "回归测试跑一遍", kind: .priority, sourceRef: "DEMO-15", estimatedMinutes: 60),
    TodoItem(id: "p4", text: "读半小时论文", kind: .habit, estimatedMinutes: 30),
  ]

  public static let todos: [TodoItem] = [
    TodoItem(id: "t1", text: "回复上周期的 review 评论", kind: .priority, state: .open),
    TodoItem(id: "t2", text: "把 vault 里的散记归档", kind: .habit, state: .open),
    TodoItem(id: "t3", text: "确认下一期用单周还是双周", kind: .priority, state: .done),
    TodoItem(id: "t4", text: "重新看一遍日历冲突规则", kind: .priority, state: .deferred),
  ]

  // MARK: OKR

  public static let okrFiles: [OkrFile] = [
    OkrFile(
      id: "okr_q",
      label: "本季度",
      fileName: "10_OKR/2026-Q3.md",
      objectives: [
        Objective(
          id: "O1",
          title: "把 daily-os 做成自己每天真的会开的东西",
          keyResults: [
            KeyResult(id: "KR1", title: "连续 8 周完成双周复盘且不缺期", priority: "P0", progress: 0.75, detail: "6 / 8 期", health: .onTrack),
            KeyResult(id: "KR2", title: "周期数据完全本地化，不依赖任何在线文档", priority: "P0", progress: 1.0, detail: "已完成", health: .onTrack),
            KeyResult(id: "KR3", title: "macOS / iOS 客户端跑通第一个可用版本", priority: "P1", progress: 0.2, detail: "UI 骨架中", health: .atRisk),
          ]
        ),
        Objective(
          id: "O2",
          title: "把计划的准确度提上来",
          keyResults: [
            KeyResult(id: "KR1", title: "每期计划完成率稳定在 70% 以上", priority: "P0", progress: 0.5, detail: "近三期 50%", health: .off),
            KeyResult(id: "KR2", title: "每期至少一条可执行的 retro 结论", priority: "P1", progress: 0.9, health: .onTrack),
          ]
        ),
      ]
    ),
    OkrFile(
      id: "okr_y",
      label: "年度",
      fileName: "10_OKR/2026.md",
      objectives: [
        Objective(
          id: "Y1",
          title: "只工作，不上班",
          keyResults: [
            KeyResult(id: "KR1", title: "工资外收入覆盖固定支出的 30%", priority: "P0", progress: 0.35, health: .atRisk),
            KeyResult(id: "KR2", title: "一个能自己跑的产品上线", priority: "P0", progress: 0.45, health: .onTrack),
          ]
        )
      ]
    ),
  ]

  // MARK: Runs

  public static let runs: [WorkflowRun] = [
    WorkflowRun(
      id: "run_a71f39",
      workflow: "cycle-plan",
      startedAt: minutesAgo(1),
      duration: .seconds(38),
      state: .running,
      promptTokens: 8_420,
      completionTokens: 1_180,
      costUSD: 0.0312,
      steps: [
        RunStep(id: "s1", title: "读取上一期 retro 与 OKR", kind: .plan, duration: .milliseconds(240)),
        RunStep(id: "s2", title: "linear.list_issues", kind: .tool, duration: .milliseconds(910), detail: "state=Backlog limit=50 → 23 条"),
        RunStep(id: "s3", title: "vault.search", kind: .tool, duration: .milliseconds(430), detail: "近两期散记 → 11 条"),
        RunStep(id: "s4", title: "生成下一期要务草稿", kind: .plan, duration: .seconds(12)),
      ],
      progress: 0.68
    ),
    WorkflowRun(
      id: "run_9f2c41",
      workflow: "cycle-review",
      startedAt: minutesAgo(95),
      duration: .seconds(74),
      state: .succeeded,
      promptTokens: 14_900,
      completionTokens: 2_640,
      costUSD: 0.0581,
      steps: [
        RunStep(id: "s1", title: "对比计划与执行", kind: .plan, duration: .seconds(3)),
        RunStep(id: "s2", title: "cycle.read", kind: .tool, duration: .milliseconds(120), detail: "20_CYCLES/… 三段"),
        RunStep(id: "s3", title: "等待确认后写回 review 段", kind: .confirm, duration: .seconds(46), detail: "用户确认"),
        RunStep(id: "s4", title: "cycle.write --section review", kind: .write, duration: .milliseconds(180)),
      ]
    ),
    WorkflowRun(
      id: "run_71ab03",
      workflow: "calendar-writeback",
      startedAt: minutesAgo(310),
      duration: .seconds(19),
      state: .failed,
      promptTokens: 3_100,
      completionTokens: 410,
      costUSD: 0.0094,
      steps: [
        RunStep(id: "s1", title: "读取本周排程", kind: .plan, duration: .milliseconds(210)),
        RunStep(id: "s2", title: "calendar.freebusy", kind: .tool, duration: .seconds(15), detail: "超时：日历服务无响应"),
      ]
    ),
    WorkflowRun(
      id: "run_2c99de",
      workflow: "daily-brief",
      startedAt: minutesAgo(600),
      duration: .seconds(11),
      state: .succeeded,
      promptTokens: 2_240,
      completionTokens: 630,
      costUSD: 0.0071,
      steps: [
        RunStep(id: "s1", title: "汇总今日计划", kind: .plan, duration: .seconds(2)),
        RunStep(id: "s2", title: "todo.write", kind: .write, duration: .milliseconds(90)),
      ]
    ),
  ]

  // MARK: Artifacts

  public static let artifacts: [Artifact] = [
    Artifact(
      id: "a1",
      name: "cycle-review-8.24-9.6.md",
      type: .markdown,
      byteSize: 4_812,
      createdAt: minutesAgo(95),
      runId: "run_9f2c41",
      preview: """
      # Review · 8.24-9.6

      计划 4 项，完成 2 项，1 项拆分后推进，1 项顺延。

      ## 计划 vs 执行
      | 要务 | 状态 |
      | --- | --- |
      | 周期数据本地化 | 完成 |
      | 团队同步 | 完成 |
      | 配置收敛 | 拆分后推进 |
      | 回归测试 | 顺延 |
      """
    ),
    Artifact(
      id: "a2",
      name: "plan-draft.json",
      type: .json,
      byteSize: 1_930,
      createdAt: minutesAgo(1),
      runId: "run_a71f39",
      preview: """
      {
        "cycle": "9.7-9.20",
        "mode": "biweekly",
        "items": [
          { "text": "回归测试覆盖周期读写往返", "kind": "priority" },
          { "text": "Runs 页加 token / 成本列", "kind": "priority" }
        ]
      }
      """
    ),
    Artifact(
      id: "a3",
      name: "token-usage-30d.csv",
      type: .csv,
      byteSize: 8_204,
      createdAt: minutesAgo(600),
      runId: nil,
      preview: "date,workflow,prompt,completion,cost\n2026-09-08,daily-brief,2240,630,0.0071"
    ),
    Artifact(
      id: "a4",
      name: "capacity-trend.png",
      type: .image,
      byteSize: 62_140,
      createdAt: daysAgo(2),
      runId: "run_9f2c41",
      preview: nil
    ),
  ]

  // MARK: Schedules

  public static let schedules: [ScheduleEntry] = [
    ScheduleEntry(
      id: "sch1",
      label: "每日简报",
      workflow: "daily-brief",
      cadence: "每天 08:30",
      cron: "30 8 * * *",
      enabled: true,
      lastRun: minutesAgo(600),
      nextRun: now.addingTimeInterval(3600 * 14)
    ),
    ScheduleEntry(
      id: "sch2",
      label: "周期规划",
      workflow: "cycle-plan",
      cadence: "每两周日 20:00",
      cron: "0 20 * * 0",
      enabled: true,
      lastRun: minutesAgo(1),
      nextRun: now.addingTimeInterval(86_400 * 12)
    ),
    ScheduleEntry(
      id: "sch3",
      label: "周期复盘",
      workflow: "cycle-review",
      cadence: "每两周六 21:00",
      cron: "0 21 * * 6",
      enabled: true,
      lastRun: minutesAgo(95),
      nextRun: now.addingTimeInterval(86_400 * 11)
    ),
    ScheduleEntry(
      id: "sch4",
      label: "日历写回",
      workflow: "calendar-writeback",
      cadence: "每天 07:00",
      cron: "0 7 * * *",
      enabled: false,
      lastRun: minutesAgo(310),
      nextRun: nil
    ),
  ]

  // MARK: Chat

  public static let threads: [ChatThread] = [
    ChatThread(
      id: "th1",
      title: "这一期为什么只完成了一半",
      updatedAt: minutesAgo(12),
      messages: [
        ChatMessage(
          id: "m1",
          role: .user,
          text: "这一期为什么只完成了一半？帮我看看是估算问题还是别的。",
          sentAt: minutesAgo(14)
        ),
        ChatMessage(
          id: "m2",
          role: .assistant,
          text: """
          看下来不是估算偏差，是任务粒度问题。

          这一期的 4 项里，"配置收敛"这一项在开工后才发现依赖两件没写进计划的事
          （数据目录硬编码、共享的账号库）。它不是被高估了，是它本来就不是一个任务。

          另外三项完成率正常。近三期的数据是：完成率 50% / 100% / 50%，而两个 50%
          的那两期，都恰好各有一项是"名字听起来是一件事、实际是三件事"。

          建议：下一期规划时，任何一项如果说不出"做完之后哪个文件会变"，就先拆。
          """,
          sentAt: minutesAgo(12),
          toolCalls: [
            ToolCall(id: "tc1", name: "cycle.list", summary: "近 6 期 → 6 条", duration: .milliseconds(80)),
            ToolCall(id: "tc2", name: "cycle.read", summary: "三期 priorities + retro", duration: .milliseconds(210)),
            ToolCall(id: "tc3", name: "okr.read", summary: "2026-Q3.md", duration: .milliseconds(40)),
          ]
        ),
      ]
    ),
    ChatThread(
      id: "th2",
      title: "下一期排什么",
      updatedAt: minutesAgo(240),
      messages: [
        ChatMessage(id: "m1", role: .user, text: "下一期排什么？", sentAt: minutesAgo(242)),
        ChatMessage(
          id: "m2",
          role: .assistant,
          text: "先把上期顺延的回归测试放进来。剩下的容量建议只排一件需要连续注意力的事。",
          sentAt: minutesAgo(240),
          toolCalls: [ToolCall(id: "tc1", name: "linear.list_issues", summary: "Backlog → 23 条", duration: .milliseconds(910))]
        ),
      ]
    ),
    ChatThread(id: "th3", title: "帮我改一下 retro 的措辞", updatedAt: daysAgo(2), messages: []),
  ]

  // MARK: Sources

  public static let sources: [SourceConnection] = [
    SourceConnection(id: "linear", name: "Linear", icon: "checklist", connected: true, detail: "1 个团队 · 4 个项目"),
    SourceConnection(id: "calendar", name: "日历", icon: "calendar", connected: true, detail: "读 free/busy · 写回已关闭"),
    SourceConnection(id: "vault", name: "本地 Vault", icon: "folder", connected: true, detail: "~/Notes · 1,204 个文件"),
    SourceConnection(id: "sync", name: "团队同步", icon: "arrow.triangle.2.circlepath", connected: true, detail: "轮询 60s · 1 分钟前"),
    SourceConnection(id: "im", name: "IM 机器人", icon: "bubble.left.and.bubble.right", connected: false, detail: "未配置"),
  ]

  // MARK: Providers

  /// Off, because that is the service's default and therefore the state the UI
  /// has to handle well. Flip it to `.enabled` in a preview to see the other one.
  public static let agentMode: AgentMode = .disabled

  public static let providers = ["claude", "codex", "openai"]
  public static let models = ["claude-opus-5", "claude-sonnet-5", "claude-haiku-4-5"]
}
