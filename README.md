# Daily OS · macOS

Daily OS 的 macOS 前端外壳：设计系统 + 八屏 UI 骨架 + 菜单栏项，跑在 mock 数据上。

**这个仓库不包含后端，也不发起任何网络请求。** 它是形态和样式的真相源。
真实产品（前端 + 后端 + 发布物）在私有仓库里，通过依赖这个包来复用整套 UI。

- 设计决策与 token：[DESIGN.md](DESIGN.md)
- iOS 端：[daily-os-ios](https://github.com/alexli-77/daily-os-ios)
- 服务端与 Web 控制台：daily-os 服务仓库

---

## 两个 library

| Target | 平台 | 内容 |
| --- | --- | --- |
| `DailyOSCore` | macOS + iOS | 色板、字体、间距、全部组件、领域模型、mock fixture、`AppState` |
| `DailyOSMac` | macOS | 分栏外壳、八个屏幕、菜单栏项 |

`DailyOSCore` 声明支持 iOS 且不含任何 macOS 专属 API，所以
[daily-os-ios](https://github.com/alexli-77/daily-os-ios) 直接 SPM 依赖它，
两端共用**同一份**设计系统而不是各存一份副本。

> 这个安排的代价：一个名字叫 `daily-os-macos` 的仓库同时是 iOS 端的依赖来源，读起来别扭。
> 真正干净的做法是把 `DailyOSCore` 抽成第三个仓库 `daily-os-kit`。
> 那是个 20 分钟的活，等到第一次因为这件事绊倒时再做就行——现在不值得为它多开一个仓库。

---

## 跑起来

只需要 Command Line Tools，不需要完整 Xcode：

```bash
swift build && swift run daily-os-checks
```

跑 App：

```bash
brew install xcodegen && xcodegen generate && open DailyOS.xcodeproj
```

### 不用 XcodeGen

`project.yml` 只是省事，手工建也就三步：

1. Xcode → File → New → Project → macOS → App，命名 `DailyOS`，放在仓库根目录
2. 删掉模板的 `ContentView.swift` 和 `DailyOSApp.swift`，把本仓库的 `App/DailyOSApp.swift` 加入 target
3. File → Add Package Dependencies → Add Local → 选仓库根目录 → 勾上 `DailyOSCore` 和 `DailyOSMac`

---

## 目录

```
Sources/DailyOSCore/
  DesignSystem/     色板、字体、间距
    Components/     Panel / Pill / PixelAvatar / Buttons / Layout / Chrome
  Model/            领域类型与显示格式化
  Mock/             MockData —— 唯一的 fixture
  State/            AppState —— UI 唯一的数据入口
  Navigation/       AppSection（八个 section 的定义，两端共用）
Sources/DailyOSMac/
  Navigation/       RootView、MacRootView（两栏 split view）
  Screens/          八个屏幕
  Companion/        MenuBarExtra
  Components/       ListColumn（Mac 专属 chrome）
Sources/daily-os-checks/   跨端一致性校验
App/                Xcode app target 的 scene 定义（刻意很薄）
```

八个屏幕：**今天 / 周期 / OKR / 对话 / 运行 / 产物 / 排程 / 设置**。
为什么是这八个、以及 Web 版的 dashboard 和 profile 去哪了，见 [DESIGN.md §1](DESIGN.md#1-产品形态)。

---

## 私有仓库怎么消费这个包

整个外壳只跟 `AppState` 一个类型说话。没有任何屏幕直接读 `MockData`，
也没有任何 view 做 I/O。所以接真实数据是**替换一个类型**，不是改二十个文件：

```swift
import DailyOSCore

@MainActor
final class LiveAppState: AppState {
  private let client: DailyOSClient   // 私有仓库自己的 HTTP/SSE 客户端

  override func updateSection(cycleID: Cycle.ID, kind: CycleSectionKind, body: String) {
    Task {
      try await client.writeCycleSection(cycleID, kind, body)
      await reload()
    }
  }
  // send() / capture() / toggleSchedule() 同理
}
```

`AppState` 上的每个 mutation 都很小，并且**按用户意图命名**而不是按它改的字段命名
（`capture` / `acceptDraft` / `toggleTodo`），因为那正是需要接后端的接缝。

两点契约值得先知道：

- **只读不能只靠 UI。** 队友的周期在这里是「不渲染编辑控件」，真正的保证在服务端断言
  和数据库 RLS 上。不要把 UI 这层当成安全边界。
- **配置是 owner-only。** 非 owner 看到的是解释而不是禁用的控件。同样，服务端才是执法者。

---

## 校验

```bash
swift run daily-os-checks
```

跑的是跨端一致性，不是 UI 快照：

- `PixelAvatar` 是服务端 `src/ui/avatar.ts` 的逐位移植。校验用的期望值**读自真实 JS 实现的输出**，
  不是从算法重新推导——否则就是拿一个实现跟它自己比。同一个账号必须在 Mac、手机和浏览器上
  画出完全一样的头像。
- 400 个生成种子不会产生全空或全满的格子（Web 版为此有重画循环，丢掉这个循环仍能通过前面的固定用例）。
- 格式化函数：时长、token 计数、成本。这些被每个屏幕共用，坏了不会有任何地方报错。

用可执行 target 而不是 XCTest bundle，是为了只装 Command Line Tools 的机器和 CI 也能跑。

---

## 现状与边界

- `swift build` 通过，零 warning；`daily-os-checks` 通过。
- `xcodebuild` 通过，App 能启动，scene 层（`MenuBarExtra` / `Window` / `CommandGroup`）不崩。
- **但没有人逐屏看过 macOS 版。** 已验证的是「能编、能起、不崩」，不是「布局对」。
  iOS 版是逐屏在模拟器里看过的（并因此改掉了一个日期 locale 的 bug，见 0.1.1），
  macOS 版还没享受同等待遇。
- Mock 数据是通用 demo 内容，不含任何真实的 OKR、issue id、团队名或文件路径。
  这个仓库是公开的，上游项目有 privacy-scan 门禁，别把真东西写进 `MockData.swift`。
- 还没做的：App Icon、签名与公证、Sparkle 或 DMG 分发、动效规范。见 [DESIGN.md §10](DESIGN.md#10-还没做的)。

## License

MIT。见 [LICENSE](LICENSE)。
