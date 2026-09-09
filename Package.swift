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
    .executable(name: "daily-os-checks", targets: ["daily-os-checks"]),
  ],
  targets: [
    .target(name: "DailyOSCore"),
    .target(name: "DailyOSMac", dependencies: ["DailyOSCore"]),
    // Checks live in an executable rather than an XCTest bundle so that
    // `swift run daily-os-checks` works with only the Command Line Tools
    // installed. A test target would need a full Xcode on every machine and in
    // CI, which is a lot of setup to assert a hash function.
    .executableTarget(name: "daily-os-checks", dependencies: ["DailyOSCore"]),
  ]
)
