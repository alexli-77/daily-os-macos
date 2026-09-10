import Foundation
import DailyOSCore
import DailyOSClient

// Point the real client at a real service and report whether the decoders
// survive real files.
//
// `daily-os-checks` proves the parsers agree with the format. This proves they
// agree with *your disk*, which is a different claim: fixtures are tidy, and a
// cycle file that has been hand-edited for eight months is not. Every decoder
// bug found so far — fractional seconds, empty `updatedAt`, a null `team.self`,
// a fourth `source` value — was invisible to a compiler and to a fixture.
//
// Prints counts, lengths and enum tallies only. It never prints the text of a
// cycle, a todo or an objective: this reads a person's private files, and a
// diagnostic that pastes them into a terminal is a diagnostic that ends up in a
// screenshot.
//
//     swift run daily-os-live [path-to-daily-os-feishu]

@MainActor
func run() async -> Int32 {
  let root = CommandLine.arguments.count > 1
    ? URL(filePath: CommandLine.arguments[1])
    : URL(filePath: FileManager.default.currentDirectoryPath)
      .deletingLastPathComponent()
      .appending(path: "daily-os-feishu")

  print("repo: \(root.path())")
  guard RepoRoot.looksValid(root) else {
    print("✗ 这个目录不像 daily-os 服务仓库。用法：swift run daily-os-live <path-to-daily-os-feishu>")
    return 1
  }

  let client = DailyOSClient(repoRoot: root)
  var failures = 0

  func step(_ name: String, _ body: () async throws -> String) async {
    do {
      print("✓ \(name) — \(try await body())")
    } catch {
      failures += 1
      let reason = (error as? ClientError)?.errorDescription ?? error.localizedDescription
      print("✗ \(name) — \(reason)")
    }
  }

  await step("发现服务") {
    let endpoint = try await client.currentEndpoint()
    return "\(endpoint.url.absoluteString)，令牌 \(endpoint.token.count) 字符"
  }

  await step("服务状态") {
    let status = try await client.serviceStatus()
    return "\(status.state.label)（\(status.endpoint)）\(status.note.map { " · \($0)" } ?? "")"
  }

  await step("周期") {
    let result = try await client.cycles()
    var modes: [String: Int] = [:]
    var sources: [String: Int] = [:]
    var sectionCount = 0
    var broken = 0
    var withPriorities = 0

    for cycle in result.mine {
      modes[cycle.mode.rawValue, default: 0] += 1
      if cycle.frontmatterError != nil { broken += 1 }
      for section in cycle.sections {
        sectionCount += 1
        sources[section.source.rawValue, default: 0] += 1
      }
      if let priorities = cycle.section(.priorities), !priorities.priorities.isEmpty {
        withPriorities += 1
      }
    }

    let modeText = modes.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: " ")
    let sourceText = sources.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: " ")
    var line = "\(result.mine.count) 个，队友 \(result.teammates.count) 个，成员 \(result.members.count) 人"
    line += " · \(modeText) · \(sectionCount) 段（\(sourceText)）"
    line += " · \(withPriorities) 个能解析出要务"
    if broken > 0 { line += " · ⚠️ \(broken) 个 frontmatter 损坏，不可写" }
    return line
  }

  await step("要务解析") {
    let result = try await client.cycles()
    guard let newest = result.mine.first, let section = newest.section(.priorities) else {
      return "没有可解析的要务段"
    }
    let doc = section.priorities
    let mit = doc.allItems.filter(\.isMIT).count
    let statuses = Dictionary(grouping: doc.allItems.compactMap(\.status), by: \.rawValue)
      .sorted { $0.key < $1.key }
      .map { "\($0.key)×\($0.value.count)" }
      .joined(separator: " ")
    let refs = doc.allItems.flatMap(\.refs).count
    return "最新周期 \(newest.label)：\(doc.groups.count) 组 / \(doc.trackedCount) 条 · MIT×\(mit)"
      + " · \(statuses.isEmpty ? "无状态标记" : statuses) · \(refs) 个引用"
  }

  await step("待办") {
    let inbox = try await client.todoInbox()
    var kinds: [String: Int] = [:]
    for item in inbox.open + inbox.recent { kinds[item.kind.rawValue, default: 0] += 1 }
    let kindText = kinds.sorted { $0.key < $1.key }.map { "\($0.key)×\($0.value)" }.joined(separator: " ")
    return "未完成 \(inbox.open.count)，最近 \(inbox.recent.count) · \(kindText)"
  }

  await step("OKR") {
    let files = try await client.okrFiles()
    let objectives = files.reduce(0) { $0 + $1.objectives.count }
    let krs = files.reduce(0) { $0 + $1.objectives.reduce(0) { $0 + $1.keyResults.count } }
    let empty = files.filter(\.objectives.isEmpty).count
    var line = "\(files.count) 个文件 · \(objectives) 个 Objective · \(krs) 个 KR"
    if empty > 0 { line += " · ⚠️ \(empty) 个文件没解析出目标" }
    return line
  }

  // Go through the store, not just the client.
  //
  // The first version of this tool called `DailyOSClient` directly and reported
  // everything healthy while the app showed an empty cycles screen: the store
  // was resolving `isViewingSelf` against fixture identity and rendering the
  // (empty) teammate list. A check that skips the layer the UI actually reads
  // cannot see that class of bug at all.
  await step("经由 LiveAppState") {
    let connection = ServiceConnection(repoRoot: root)
    let state = LiveAppState(connection: connection)
    await state.reload()

    guard connection.state.isConnected else {
      throw ClientError.service(message: "store 没能连上：\(connection.state.label)")
    }
    var problems: [String] = []
    if !state.isViewingSelf { problems.append("isViewingSelf 为 false —— 界面会显示空的队友视图") }
    if state.visibleCycles.isEmpty { problems.append("visibleCycles 为空 —— 周期页会是空的") }
    if state.selectedCycle == nil { problems.append("没有选中的周期") }
    if let error = state.lastError { problems.append(error) }
    if !problems.isEmpty { throw ClientError.service(message: problems.joined(separator: "；")) }

    let planned = state.plan.count
    let done = state.plan.filter { $0.state != .open }.count
    let stale = state.planStaleDate.map { "（来自 \($0)，今天还没跑）" } ?? ""
    return "身份 \(state.account.displayName) · 可见周期 \(state.visibleCycles.count)"
      + " · 选中 \(state.selectedCycle?.label ?? "—")"
      + " · 今日计划 \(planned) 条\(stale)，已处理 \(done)"
      + " · 待办 \(state.openTodos.count) · OKR \(state.okrFiles.count) 个文件"
      + " · 产物 \(state.artifacts.count)（\(state.artifacts.filter { $0.path != nil }.count) 个有路径）"
      + " · 团队 \(state.teamSync?.label ?? "未知")"
  }

  print(failures == 0 ? "\n全部通过。" : "\n\(failures) 项失败。")
  return failures == 0 ? 0 : 1
}

exit(await run())
