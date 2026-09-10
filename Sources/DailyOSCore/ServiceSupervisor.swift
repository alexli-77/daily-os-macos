import Foundation

#if os(macOS)

/// Starts and stops the daily-os service's launch agent.
///
/// **The app does not own the service process, and should not.** Making the
/// service a child of this app would be the obvious reading of "let the Mac app
/// start it", and it would quietly break the product: the service is what runs
/// the morning `daily_plan`, the evening review and every other scheduled
/// workflow. Tie its lifetime to a window and those only happen on days you
/// remembered to open the app — and the whole point of a daily briefing is that
/// it arrives without being asked.
///
/// So the app supervises rather than hosts. launchd keeps owning the process:
/// it starts at login, survives the app quitting, and restarts on crash. What
/// changes is that the app now *checks and fixes* that on launch instead of
/// showing a wall and leaving you to run `launchctl` yourself.
///
/// Lives in `DailyOSCore` rather than in `DailyOSClient` because both the
/// screens and the transport need it and only one of them can import the other.
/// It is process control, not transport — there is no HTTP here — so the
/// module boundary the split protects is not the one being crossed.
public enum ServiceSupervisor {
  public static let label = "com.daily-os-feishu.agent"

  public static var plistURL: URL {
    URL.homeDirectory.appending(path: "Library/LaunchAgents/\(label).plist")
  }

  /// The agent has been registered by `npm run service:install`.
  public static var isInstalled: Bool {
    FileManager.default.fileExists(atPath: plistURL.path())
  }

  private static var domain: String { "gui/\(getuid())" }

  /// Whether launchd currently has the job loaded. Not the same as "the HTTP
  /// server is answering" — a job can be loaded and still starting up, which is
  /// exactly the window that made the app report "服务没在跑" about a service
  /// that was two seconds from being ready.
  public static func isLoaded() async -> Bool {
    await run(["print", "\(domain)/\(label)"]).status == 0
  }

  /// Bring the service up, whatever state it is in.
  ///
  /// `kickstart` starts a loaded job and does nothing useful for one that was
  /// never bootstrapped, so an unloaded job is bootstrapped first. Both are
  /// idempotent enough to call on every launch.
  public static func start() async throws {
    if await !isLoaded() {
      let bootstrap = await run(["bootstrap", domain, plistURL.path()])
      // 5 is "already bootstrapped", which is a success for our purposes and an
      // error for launchctl's.
      if bootstrap.status != 0 && bootstrap.status != 5 {
        throw Failure("launchctl bootstrap 失败：\(bootstrap.output)")
      }
    }
    let kickstart = await run(["kickstart", "\(domain)/\(label)"])
    if kickstart.status != 0 {
      throw Failure("launchctl kickstart 失败：\(kickstart.output)")
    }
  }

  /// Restart, for picking up a rebuilt `dist/`.
  public static func restart() async throws {
    let result = await run(["kickstart", "-k", "\(domain)/\(label)"])
    if result.status != 0 {
      throw Failure("重启失败：\(result.output)")
    }
  }

  /// Stop until the next login. Deliberately not `bootout` — that unregisters
  /// the job, and someone stopping the service for an hour does not mean they
  /// want it gone after a reboot.
  public static func stop() async throws {
    let result = await run(["kill", "SIGTERM", "\(domain)/\(label)"])
    if result.status != 0 {
      throw Failure("停止失败：\(result.output)")
    }
  }

  public struct Failure: LocalizedError {
    public let errorDescription: String?
    init(_ message: String) { errorDescription = message }
  }

  /// `launchctl` only. Never a shell, and never a string the caller composed:
  /// arguments go to `Process` as an array, so a path with a space in it is a
  /// path with a space in it rather than two arguments.
  private static func run(_ arguments: [String]) async -> (status: Int32, output: String) {
    await withCheckedContinuation { continuation in
      let process = Process()
      process.executableURL = URL(filePath: "/bin/launchctl")
      process.arguments = arguments
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = pipe
      do {
        try process.run()
      } catch {
        continuation.resume(returning: (-1, error.localizedDescription))
        return
      }
      let data = pipe.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      let output = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      continuation.resume(returning: (process.terminationStatus, output))
    }
  }
}

#endif
