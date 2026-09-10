import Foundation

public enum RepoRoot {
  /// Where the service checkout is.
  ///
  /// Stored rather than guessed. The old companion prototype searched
  /// `DAILY_OS_REPO_ROOT`, a `--repo` flag and its own bundle location, which
  /// works for something launched from a build directory and not for an app in
  /// `/Applications`. A path the user picked once and the app remembers is both
  /// simpler and correct in more places.
  public static let defaultsKey = "com.dailyos.mac.repoRoot"

  public static func stored(in defaults: UserDefaults = .standard) -> URL? {
    guard let path = defaults.string(forKey: defaultsKey), !path.isEmpty else { return nil }
    return URL(filePath: path)
  }

  public static func store(_ url: URL?, in defaults: UserDefaults = .standard) {
    if let url {
      defaults.set(url.path(percentEncoded: false), forKey: defaultsKey)
    } else {
      defaults.removeObject(forKey: defaultsKey)
    }
  }

  /// Does this look like a daily-os checkout? Used to reject a wrong folder at
  /// pick time rather than as a confusing failure on the first request.
  public static func looksValid(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.appending(path: "package.json").path())
      && FileManager.default.fileExists(atPath: url.appending(path: "src/ui").path())
  }

  /// Find the service folder without asking.
  ///
  /// The comment above used to justify not doing this, and it was arguing
  /// against the wrong thing: the old prototype *guessed* from an env var and
  /// its own bundle path, which is indeed useless for an app in `/Applications`.
  /// Reading the launch agent's own `WorkingDirectory` is not a guess — it is
  /// the path the service was installed with, written by the service itself.
  ///
  /// This matters most for the person who did not set any of it up. "选择服务仓库
  /// 目录" asks someone to know a word they have no reason to know, about a
  /// folder they may never have opened.
  public static func discover() -> URL? {
    if let url = fromLaunchAgent(), looksValid(url) { return tidy(url) }
    if let url = fromCommonLocations() { return tidy(url) }
    return fromSpotlight().map(tidy)
  }

  /// Ask Spotlight, which has already indexed the disk.
  ///
  /// The last resort, and the one that actually covers "the checkout is
  /// somewhere I did not think of". Walking the disk to find it would be
  /// unacceptable on a cold launch; asking the index that already exists costs
  /// a few hundred milliseconds.
  ///
  /// Matches on the runtime file rather than on a folder name, because that
  /// file is the thing this app needs and its presence also proves the service
  /// has run there. A folder called `daily-os-feishu` that was cloned and never
  /// started is not an answer.
  private static func fromSpotlight() -> URL? {
    let process = Process()
    process.executableURL = URL(filePath: "/usr/bin/mdfind")
    process.arguments = ["-name", "ui.json", "-onlyin", URL.homeDirectory.path()]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    guard (try? process.run()) != nil else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    let paths = (String(data: data, encoding: .utf8) ?? "")
      .split(separator: "\n")
      .map(String.init)
      .filter { $0.hasSuffix("/data/runtime/ui.json") }

    for path in paths {
      // Two components up from data/runtime/ui.json is the checkout.
      let root = URL(filePath: path).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
      if looksValid(root) { return root }
    }
    return nil
  }

  /// Directory URLs from `contentsOfDirectory` carry a trailing slash, which is
  /// harmless to every path operation and looks like a typo on the setup screen
  /// — the one place the path is shown to somebody.
  private static func tidy(_ url: URL) -> URL {
    URL(filePath: (url.path(percentEncoded: false) as NSString).standardizingPath)
  }

  /// `~/Library/LaunchAgents/com.daily-os-feishu.agent.plist` → `WorkingDirectory`.
  ///
  /// Authoritative when it exists: `npm run service:install` writes that key
  /// with the checkout it was run from, and launchd starts the service there.
  /// Exposed so a diagnostic can report *which* of the two sources answered.
  /// "Found it" and "found it by guessing at folder names" are different levels
  /// of confidence and the difference is worth being able to see.
  public static func discoverViaLaunchAgent() -> URL? {
    fromLaunchAgent().map(tidy)
  }

  private static func fromLaunchAgent() -> URL? {
    let plist = URL.homeDirectory
      .appending(path: "Library/LaunchAgents/com.daily-os-feishu.agent.plist")
    guard let data = try? Data(contentsOf: plist),
          let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
          let root = object as? [String: Any],
          let directory = root["WorkingDirectory"] as? String,
          !directory.isEmpty
    else { return nil }
    return URL(filePath: directory)
  }

  /// A bounded look in the handful of places people keep code.
  ///
  /// Only for the case where the service is run by hand rather than under
  /// launchd; the agent's plist covers everyone else and covers them exactly.
  ///
  /// Four levels, not two. Two was chosen to keep this cheap and would have
  /// missed `~/code/github/<workspace>/daily-os-feishu` — the layout on the
  /// machine this was written on, which is a strong hint about the layout on
  /// any machine set up the same way. Bounded by a visit budget instead of by
  /// depth alone, so an unusually wide folder cannot turn a cold launch into a
  /// disk crawl.
  ///
  /// Prefers a folder that has actually been run: `data/runtime/ui.json` exists
  /// only after the service has started there at least once, which distinguishes
  /// a live checkout from an abandoned clone.
  private static func fromCommonLocations() -> URL? {
    let home = URL.homeDirectory
    var queue: [(url: URL, depth: Int)] = ["code", "Code", "Developer", "Projects", "src", "Documents", "Desktop", ""]
      .map { ($0.isEmpty ? home : home.appending(path: $0), 0) }

    var candidates: [URL] = []
    var budget = 400

    while !queue.isEmpty, budget > 0 {
      let (directory, depth) = queue.removeFirst()
      budget -= 1
      guard let entries = try? FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      ) else { continue }

      for entry in entries {
        guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
        if entry.lastPathComponent.hasPrefix("daily-os"), looksValid(entry) {
          // A folder that has run wins outright; nothing further to look at.
          if hasRun(entry) { return entry }
          candidates.append(entry)
        } else if depth < 3 {
          queue.append((entry, depth + 1))
        }
      }
    }

    return candidates.first
  }

  /// The service has started here at least once, so its address and token file
  /// is present — which is the only thing the app actually reads.
  public static func hasRun(_ url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.appending(path: "data/runtime/ui.json").path())
  }
}

public extension Notification.Name {
  /// The service folder was changed from Settings.
  ///
  /// A notification rather than a shared object because the two sides live in
  /// modules that cannot import each other: the screens are in `DailyOSMac`,
  /// the connection is in `DailyOSClient`, and the dependency edge deliberately
  /// runs only one way. One broadcast is a smaller price than either widening
  /// that edge or letting the window keep saying "未连接" after the folder was
  /// fixed.
  static let dailyOSRepoRootChanged = Notification.Name("com.dailyos.mac.repoRootChanged")
}
