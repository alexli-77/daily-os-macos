# Daily OS · macOS

Daily OS 的 macOS 客户端：设计系统 + 八屏 + 菜单栏项，读你本机 daily-os 服务的真实数据。

**这个仓库不包含后端。** 服务在 daily-os 服务仓库里，跑在你自己的机器上；这里是它的客户端。

- 设计决策与 token：[DESIGN.md](DESIGN.md)
- iOS 端：[daily-os-ios](https://github.com/alexli-77/daily-os-ios)
- 服务端与 Web 控制台：daily-os 服务仓库

---

## 三个 library

| Target | 平台 | 内容 |
| --- | --- | --- |
| `DailyOSCore` | macOS + iOS | 色板、字体、间距、全部组件、领域模型、fixture、`AppState` |
| `DailyOSMac` | macOS | 分栏外壳、八个屏幕、菜单栏项 |
| `DailyOSClient` | macOS + iOS | 本地服务的传输层、各端点解码器、`LiveAppState` |

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

### 逐屏看

不用跑 App。在 Xcode 里打开任意一个屏幕文件，⌥⌘↩ 打开 canvas，每个屏幕都带 preview：

| 文件 | preview |
| --- | --- |
| `DesignGallery.swift` | 全部 token 与组件，浅色 / 深色各一版 |
| `Screens/*.swift` | 八个屏幕，各带空状态 |
| `TodayScreen.swift` | 额外一版「没有估时」——真实服务给的计划长这样 |
| `CyclesScreen.swift` | 额外一版「队友只读」——这个状态出过 bug |
| `SettingsScreen.swift` | 额外一版 member 视角 |
| `MacRootView.swift` | 整个窗口 |
| `CompanionMenu.swift` | 菜单栏项，含服务降级 |

Fixture 在 `AppState+Preview.swift`：`previewOwner` / `previewTeammate` / `previewMember` /
`previewEmpty` / `previewDegraded`。这个 App 有意思的状态不是「有数据 / 没数据」，
是**谁的数据**和**你被允许对它做什么**——所以这几个是分开的 preview，不是靠脑补的变体。

### 不用 XcodeGen

`project.yml` 只是省事，手工建也就三步：

1. Xcode → File → New → Project → macOS → App，命名 `DailyOS`，放在仓库根目录
2. 删掉模板的 `ContentView.swift` 和 `DailyOSApp.swift`，把本仓库的 `App/DailyOSApp.swift` 加入 target
3. File → Add Package Dependencies → Add Local → 选仓库根目录 → 勾上 `DailyOSCore` 和 `DailyOSMac`

### 装的是不是最新的

```bash
./scripts/check-installed.sh
```

一行答案。它比对 `/Applications` 里那份的版本戳和仓库 HEAD，并且会单独点出三种
「看起来对、其实不能信」的情况：**打包时工作区是脏的**（commit 号和包里的代码对不上，
这比没有 commit 号更误导人）、**没有版本戳**（不是用 `package.sh` 打的）、
**本地领先远端**。

App 里也能看：设置 → 服务 → 「App 版本」。

### 装到自己机器上日常用

```bash
xcodegen generate
xcodebuild build -project DailyOS.xcodeproj -scheme DailyOS -configuration Release \
  -destination 'platform=macOS' -derivedDataPath .build/release CODE_SIGNING_ALLOWED=NO
rm -rf "/Applications/Daily OS.app"
cp -R .build/release/Build/Products/Release/DailyOS.app "/Applications/Daily OS.app"
open "/Applications/Daily OS.app"
```

用 Release 而不是 Debug：日常用的东西不该带调试开销。**先跑一次 Release 构建再改代码**——
`#Preview` 块在 Release 下照样编译，所以只在 Debug 存在的符号会让 Release 构建挂掉，而 Debug 永远发现不了。

**注意开发构建和打包构建装的不是同一个服务。** 上面这种 `xcodebuild` 直接拷过去的 App 里
没有服务负载（`Resources/service` 是 `package.sh` 放进去的），所以它不会去装什么，
只会去找机器上已有的服务——也就是你自己的 checkout。要验证安装那条路径，
得跑 `./scripts/package.sh`。

服务在 launchd 下（`com.daily-os-feishu.agent`）开机自启，`launchctl list | grep daily-os` 查它。

**改了服务端之后，光重启没用。** launchd 跑的是 `dist/index.js`，不是源码：

```bash
npm run build && launchctl kickstart -k gui/$(id -u)/com.daily-os-feishu.agent
```

漏掉 `npm run build` 的失败方式最难查——服务正常在跑、日志干净、`git log` 显示改动就在
当前分支上，只是**跑的不是它**。切分支同理。

### 装到另一台 Mac 上（不需要 Apple 开发者账号）

**没有安装包，也不会有。** macOS 的 App 就是一个目录：整个产品就是 `Daily OS.app`，
「安装」＝拖进 `/Applications`。

```bash
./scripts/package.sh
```

产出在 `dist/`：`Daily OS.app` 和 `DailyOS-<版本>.zip`（约 290 MB）。

**服务打包在里面了，对方不需要再装任何东西。** 拖进「应用程序」、双击，第一次启动会自己
建 `~/Library/Application Support/DailyOS`、写 launchd 配置、把服务拉起来。不用 clone 仓库，
不用 npm，不用跑安装脚本，也不用选任何文件夹。

290 MB 里 104 MB 是 Node 运行时、81 MB 是生产依赖。这是「一步部署」的价目：
要么 App 大 290 MB，要么对方的部署分两步——而两步里失败的永远是第二步。

必须是 **nodejs.org 的官方二进制**，不能是 Homebrew 的 `node`：后者是个 68 KB 的壳，
动态链接 `/opt/homebrew/opt/...` 下一堆 dylib，拷进 bundle 做出来的东西只能在
「已经装了 Homebrew Node」的机器上跑——正好是这次要消灭的那个前置条件。
`bundle-service.sh` 里用 `otool -L` 卡住了这一点。

**代码和数据分开放**：代码只读地待在 `Daily OS.app/Contents/Resources/service`，
数据全在 `~/Library/Application Support/DailyOS`。App 更新时 bundle 是整个被替换的，
写进 bundle 里的东西会在第一次更新时消失。

**进程还是 launchd 的，不是 App 的。** 服务要跑早晨的 `daily_plan` 和晚上的复盘；
把它做成 App 的子进程，这些就只在你记得开 App 的那天发生。变的只是：现在由 App
写 launch agent 并指向自己带的那份服务，而不是让人去终端里跑安装脚本。

**升级会真的生效。** App 更新后 bundle 路径没变、内容变了，launchd 没有理由重启它——
所以安装记录里存的是构建标识（版本＋commit＋构建时间），对不上就重新登记并重启。
只比路径的话，发了一个服务端修复、机器上跑的还是昨天那份，而一切看起来都正常。

**老用户的数据会自动搬过去。** 第一次装的时候如果机器上已经有一个跑过的 checkout，
它的 `.env`、`config/`、`data/` 会被**复制**（不是移动）到托管目录，原目录原样留着当快照。
唯一搬不过去的是写成 `../xxx` 的配置项（比如 `skills.calendar.workdir`）——
它现在会相对 `~/Library/Application Support` 解析，得手改成绝对路径。

装不上的时候看 `~/Library/Application Support/DailyOS/logs/install.log`，
每一步都在里面。

脚本里有两处不是随手写的：

- **通用二进制**（arm64 + x86_64）。Xcode 默认只构建你正在用的这台机器的架构，
  一个 arm64-only 的包给到 Intel Mac 上会报「应用程序不能打开」——这句话完全没提架构，
  对方只会去查权限。
- **显式 ad-hoc 签名**。单架构构建时链接器会自动打一个，**通用构建不会**，
  而 **arm64 可执行文件没有签名就根本跑不起来**。少这一行，「为了兼容 Intel 而改成通用」
  的结果是在 Apple Silicon 上直接挂掉——正好砸了它本来要服务的那批机器。

能这样跑，是因为 **Gatekeeper 拦的是 `com.apple.quarantine` 这个扩展属性，而它是下载器打上去的，不是 app 自带的。** 本地构建的产物没有这个标记，所以不经过 Gatekeeper。

（`CODE_SIGNING_ALLOWED=NO` 不等于完全没签名：Apple Silicon 上 arm64 可执行文件必须有签名才能运行，链接器会自动打一个 ad-hoc 签名。够本机跑，不够分发。）

**拷给别人时，用什么方式传决定了对方要不要跟 Gatekeeper 搏斗：**

| 传输方式 | 带 quarantine | 对方双击 |
| --- | --- | --- |
| `scp` / `rsync` / U 盘 | 否 | 直接开 |
| AirDrop / 浏览器下载 / Messages | 是 | 被拦 |

万一被拦了，对方要走：双击 → 被拦 → 系统设置 → 隐私与安全性 → 往下滚 → 「仍要打开」→ 认证 → 再双击。macOS 15 起 Apple 取消了「右键 → 打开」这个捷径，只剩系统设置这条路。

`xattr -dr com.apple.quarantine` 一行也能解决，但**别把这行写进给别人的安装说明**——让用户在终端里手动关掉一个安全检查，是个很糟的信号，何况他们照做一次之后就会对下一个来路不明的 app 也照做。

**那什么时候才真的需要 $99？** 当你希望一个还不认识你的人，从网页下载完直接双击就能用的时候。在那之前它是纯支出，而这个决定完全可逆——`project.yml` 里 `ENABLE_HARDENED_RUNTIME: YES` 已经预留好了公证的前提。发布链路本身记在 Linear 的 LEO-296 里。

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

## 数据是怎么进来的

整个外壳只跟 `AppState` 一个类型说话。没有任何屏幕直接读 fixture，也没有任何 view 做 I/O。
所以接真实数据是**替换一个类型**，不是改二十个文件——`LiveAppState`
（`Sources/DailyOSClient/LiveAppState.swift`）继承 `AppState` 并覆写那几个 mutation，
**八个屏幕一行都没改**。

写入是乐观的：先改本地再发请求，失败时 toast 说明并 `reload()` 把真相放回去。
本地服务的往返是几毫秒，转圈等待会让勾一个复选框像在提交表单。

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

## 接后端

服务把地址和令牌写在自己 checkout 的 `data/runtime/ui.json` 里，那个令牌直接认证为 admin
（服务源码的注释点名了 mac-companion 是预期调用方）。所以：

- **App 自己不存密码。** 它读那个文件，走 `Authorization: Bearer`；登录界面登的是控制台账号
  （和网页控制台同一套），换的是身份显示，不是这条连接
- 令牌每次服务重启重新生成，client 在 401 时**重读文件重试一次**——那是正常路径不是错误
- 不发 `Origin` 头。服务把无 Origin 的请求当作非浏览器客户端并跳过 CSRF 检查

正常情况下这个文件夹**根本不需要谁来告诉它**：App 自己装的服务，工作目录就是它自己建的
`~/Library/Application Support/DailyOS`。剩下的两条是给「服务不是 App 装的」那些机器留的：

1. `~/Library/LaunchAgents/com.daily-os-feishu.agent.plist` 里的 `WorkingDirectory`——
   这是安装时写进去的路径，**不是猜的**
2. 找不到 plist（服务是手动跑的）才退化成扫描 `~/code`、`~/Developer`、`~/Documents` 这几个常见位置，
   深度 4 层、有访问上限，优先挑已经跑过的那个（有 `data/runtime/ui.json`）

判断一个目录能不能用，看的是 `isUsable` 而不是 `looksValid`：托管目录里只有数据、没有一行源码，
拿「有没有 `src/ui`」去问它，答案会是「不能用」——然后扫描会自信地找到一个**别的**服务。

三条都没结果，才会出现「选择服务文件夹」那一屏。**这一屏是给别人看的**——
装在队友机器上时，站在电脑前的那个人多半不是搭服务的人，所以那里不能出现「仓库」这种词。

```bash
swift run daily-os-live            # 不带参数＝App 现在连的那个
swift run daily-os-live <目录>
```

拿真实服务验证解码器，只打印数量和长度、不打印你的内容。`daily-os-checks` 证明解析器符合格式；
这个证明它们**扛得住你磁盘上的文件**——两回事：fixture 是整齐的，被手工编辑了八个月的周期文件不是。
目前发现的每一个解码 bug（小数秒、空 `updatedAt`、`team.self` 为 null、第四个 `source` 值）
编译器和 fixture 都看不见。

### 已接 / 未接

| 已接真实数据 | 仍是示例数据 |
| --- | --- |
| 今天、周期、OKR、设置 | 对话、运行、产物、排程 |

未接的屏幕在侧栏标了「演示」。半接的界面比未接的更让人困惑——示例数据足够像真的，
而这个误会只有在你按它行动之后才会发现。

## 现状与边界

- `swift build` 通过，零 warning；`daily-os-checks` 通过。
- `xcodebuild` 通过，App 能启动，scene 层（`MenuBarExtra` / `Window` / `CommandGroup`）不崩。
- **写入路径没有端到端验证过。** 读取全部对着真实服务跑通了（12 个周期 / 24 段 / 3 个 OKR 文件 /
  59 个 KR）。但保存段落、点三色圈、快捷捕获这些**会写你的文件**，没有你的明确许可不会去试。
  改估时也一样：编辑器能打开、预设按钮在、删除确认弹得出来并且能取消，
  但**「点一下 30m 之后服务端账本里真的多了一行」这件事没有验证过**。
- **但没有人逐屏看过 macOS 版。** 已验证的是「能编、能起、不崩」，不是「布局对」。
  iOS 版是逐屏在模拟器里看过的（并因此改掉了一个日期 locale 的 bug，见 0.1.1），
  macOS 版还没享受同等待遇。上面那节的 preview 是为了让这件事变成十分钟的活，
  但**它们只是让你能看，不代表已经有人看过**。
- Mock 数据是通用 demo 内容，不含任何真实的 OKR、issue id、团队名或文件路径。
  这个仓库是公开的，上游项目有 privacy-scan 门禁，别把真东西写进 `MockData.swift`。
- 还没做的：App Icon、签名与公证、Sparkle 或 DMG 分发、动效规范。见 [DESIGN.md §10](DESIGN.md#10-还没做的)。

## License

MIT。见 [LICENSE](LICENSE)。
