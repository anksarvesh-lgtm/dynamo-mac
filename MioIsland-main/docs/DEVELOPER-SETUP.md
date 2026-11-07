# 开发者环境配置

> 这是给协作开发者的入门文档。你想本地跑起来、改代码、提 PR —— 看这一份就够了。
>
> 发版相关的权限和密钥，请看 [`RELEASE-GUIDE.md`](./RELEASE-GUIDE.md)（仅管理员需要）。

## 前置条件

- macOS 15.0+（Sequoia 或更新）
- Xcode 16+（装完 Command Line Tools）
- Swift 5.10+（跟 Xcode 捆绑）
- `git`、`gh`（GitHub CLI）

可选：

- `brew install create-dmg`（要自己打 DMG 时才需要）
- 一台带刘海的 Mac（测刘海显示最直观）；非刘海 Mac 也能跑，看顶部居中悬浮块

## 拉代码

```bash
git clone https://github.com/MioMioOS/MioIsland.git
cd MioIsland
```

SPM 依赖（Sparkle、Starscream 等）Xcode 第一次 build 时会自动拉。

## 本地跑起来

```bash
open ClaudeIsland.xcodeproj
```

在 Xcode 里选 `ClaudeIsland` scheme → Product → Run（⌘R）。

Xcode 会用 debug 配置 build，ad-hoc 签名，跑在你自己机器上。**不需要** Apple Developer 证书、也不需要 Sparkle 私钥。

### 命令行 build（不想开 Xcode）

```bash
xcodebuild -scheme ClaudeIsland -configuration Debug build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""

# 产物路径
DD=$(find ~/Library/Developer/Xcode/DerivedData -maxdepth 1 -name "ClaudeIsland-*" | head -1)
open "$DD/Build/Products/Debug/Mio Island.app"
```

## 开发约定

- 分支：`main` 受保护，**不能直接 push**。所有改动走 PR → 合并到 main
- 分支命名：`feat/<short-name>`、`fix/<short-name>`、`docs/<short-name>`
- Commit 信息：用简短的命令式动词开头（`fix:` / `feat:` / `docs:` / `chore:`）
- 代码风格：SwiftUI 为主，SwiftLint 暂未强制，但尽量对齐已有代码的缩进和命名
- PR 要求：自测通过、描述"改了什么"和"为什么改"，reviewer 同意后合并

## 目录导览

| 目录/文件 | 作用 |
|---|---|
| `ClaudeIsland/` | 主 app 源码 |
| `ClaudeIsland/UI/Views/NotchView.swift` | 刘海主视图 |
| `ClaudeIsland/Core/NotchViewModel.swift` | 状态 + 展开尺寸计算 |
| `ClaudeIsland/Services/` | 核心服务（会话监控、插件、配对等） |
| `ClaudeIsland/Resources/Plugins/` | 内置插件 `.bundle`（stats 等） |
| `ClaudeIsland/Info.plist` | `SUPublicEDKey`（Sparkle 验证公钥）、`SUFeedURL` 等 |
| `scripts/release.sh` | 发版脚本（仅管理员跑） |
| `scripts/generate-keys.sh` | 生成 Sparkle 密钥对（只跑一次） |
| `.sparkle-keys/` | **在 `.gitignore` 里，永不提交**。发版私钥存放处 |
| `docs/RELEASE-GUIDE.md` | 发版流程（管理员） |
| `landing/` | 介绍页源码 + appcast.xml（`landing-page` 分支托管） |

## 写插件？

MioIsland 插件是独立 `.bundle`，一条 `swiftc` 命令就能编。不碰 host app 主仓库。

- 模板：https://github.com/MioMioOS/mio-plugin-template
- 市场：https://miomio.chat/developer
- 官方清单：https://github.com/MioMioOS/mio-plugin-registry

模板自带 `CLAUDE.md`，是给 AI 读的"合同"，也可以当人读的上手指南。

## 绝对不要做的事（安全红线）

1. **不要提交 `.sparkle-keys/` 里的任何东西。** 这是发版私钥。`.gitignore` 已经挡了它，你自己不要硬 force-add
2. **不要在 commit / PR / docs 里写出任何密钥的字符串值。** 需要贴示例就写 `<ASK_ADMIN>` 之类的占位符
3. **不要改 `Info.plist` 的 `SUPublicEDKey`**，除非你就是要做密钥轮换（那是管理员的活）
4. **不要动 `.entitlements` 加 `com.apple.security.app-sandbox`。** App 依赖非沙盒能力读其他进程状态
5. **不要 commit 本地 build 产物**（`*.dmg`、`*.zip`、`MioIsland-v*.{dmg,zip}`）——根目录的这些文件都是临时的

## 常见问题

### Xcode build 报错找不到 Sparkle

SPM 包没拉下来。Xcode 菜单：File → Packages → Reset Package Caches，再 build。

### 非刘海 Mac 看不到 app

app 是 `LSUIElement=true`（无 Dock 图标）。没刘海的机器，在屏幕顶部中央偏上位置鼠标 hover 就能看到悬浮块。若还看不到，在 System Settings → Displays 确认分辨率，然后到 app 的 Settings → Appearance 调整 offset。

### 调试日志在哪看

Xcode 调试台能看到 `print(...)` 输出。生产环境可以在 Console.app 搜 `Mio Island` 或 subsystem `com.mioisland`。

### 新 PR 合并后本地没 pull

`main` 是权威源。

```bash
git checkout main
git pull --ff-only origin main
```

如果 pull 失败，说明你本地 main 跑偏了。不要 force — 问一下 reviewer。

## 碰到问题

- 搜 Issues：https://github.com/MioMioOS/MioIsland/issues
- 内部沟通：WeChat 群（扫 `docs/wechat-qr.jpg`，微信群 QR 每 7 天失效，过期了问管理员要新的）
- 私聊管理员：扫 `docs/wechat-qr-kris.jpg`
