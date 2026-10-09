// swift-tools-version: 6.0
import PackageDescription

// Two libraries, deliberately.
//
// `DailyOSCore` is everything that is not macOS-specific: the palette, the type
// ramp, the components, the domain model, the fixture, and `AppState`. It
// declares iOS support and contains no macOS-only API, so the iOS app
// (github.com/alexli-77/daily-os-ios) can depend on this package and get the
// same design system rather than a copy of it that drifts.
//
// `DailyOSMac` is the Mac app's own surface: the split-view shell, the eight
// screens, the menu bar item. It is never built for iOS — an iOS consumer
// depends on the `DailyOSCore` product only, and SwiftPM builds just that.
let package = Package(
  name: "DailyOS",
  platforms: [.macOS(.v14), .iOS(.v17)],
  products: [
    .library(name: "DailyOSCore", targets: ["DailyOSCore"]),
    .library(name: "DailyOSMac", targets: ["DailyOSMac"]),
    .library(name: "DailyOSClient", targets: ["DailyOSClient"]),
    .executable(name: "daily-os-checks", targets: ["daily-os-checks"]),
    .executable(name: "daily-os-live", targets: ["daily-os-live"]),
  ],
  targets: [
    .target(name: "DailyOSCore"),
    .target(name: "DailyOSMac", dependencies: ["DailyOSCore"]),
    // Talks to the local daily-os service. Split from DailyOSCore so the design
    // system stays free of networking, and so the iOS app can take one without
    // the other while its transport question (Bonjour vs typed-in address) is
    // still open.
    .target(name: "DailyOSClient", dependencies: ["DailyOSCore"]),
    // Checks live in an executable rather than an XCTest bundle so that
    // `swift run daily-os-checks` works with only the Command Line Tools
    // installed. A test target would need a full Xcode on every machine and in
    // CI, which is a lot of setup to assert a hash function.
    .executableTarget(name: "daily-os-checks", dependencies: ["DailyOSCore"]),
    // Manual, local-only: points the real client at a real service and reports
    // whether the decoders survive real files. Never runs in CI — it needs a
    // service and a person's own data, which is exactly what CI does not have.
    .executableTarget(name: "daily-os-icon", dependencies: ["DailyOSCore"]),
    .executableTarget(name: "daily-os-live", dependencies: ["DailyOSCore", "DailyOSClient"]),
  ]
)
