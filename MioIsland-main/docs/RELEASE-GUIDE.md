# MioIsland 发版指南

> 面向项目管理员与有发版权限的合作者。包含完整的发版流程、密钥信息和故障排除。
>
> 这是仓库里的权威文档。聊天记录里的旧版可能过时，以这一份为准。

## 1. 分支架构

| 分支 | 用途 | 自动化 |
|------|------|--------|
| `main` | 开发主干，合并 PR，发版代码 | — |
| `landing-page` | 介绍页 + `appcast.xml`（Sparkle 更新源） | push 后自动部署到 GitHub Pages |
| `feature/*` | 功能分支 | PR 合并到 main |

## 2. 关键文件

| 文件 | 说明 |
|------|------|
| `scripts/release.sh` | 一键发版脚本（build + 签名 + DMG + appcast + 部署） |
| `scripts/generate-keys.sh` | 生成 Sparkle EdDSA 密钥对（只需跑一次） |
| `.sparkle-keys/eddsa_private_key` | EdDSA 私钥，**不入 git**，发版必需 |
| `ClaudeIsland/Info.plist` | 包含 `SUFeedURL` 和 `SUPublicEDKey` |
| `landing/public/appcast.xml` | landing-page 分支，Sparkle 检查更新的数据源 |
| `releases/appcast.xml` | 本地生成的 appcast（由脚本自动同步到 landing-page） |

## 3. 密钥信息

### EdDSA 私钥

**不在本文档中记录。** 私钥存在项目管理员的安全保险箱里，通过加密通信（面对面、1Password 共享、Signal 等）传递给新发版人。

存放路径：项目根目录 `.sparkle-keys/eddsa_private_key`（已在 `.gitignore`）

```bash
# 新机器设置私钥（向项目管理员索取 base64 字符串）
mkdir -p .sparkle-keys
pbpaste > .sparkle-keys/eddsa_private_key   # 粘贴管理员给的密钥
chmod 600 .sparkle-keys/eddsa_private_key
```

### EdDSA 公钥（已写入 Info.plist）

```
2099yGC8J95uPjXVnchyCOXCmRwyOhszsElVw/4ih2Q=
```

### 安全警告

- 私钥 **绝对不能** 提交到 git（已在 `.gitignore` 中）
- 私钥丢失 = 必须生成新密钥对，旧版本用户无法平滑升级
- 私钥泄露 = 攻击者可以伪造更新包，必须立即换密钥
- 通过安全渠道（面对面、加密通信）传递私钥，**不要** 发到聊天群或邮件

## 4. 发版流程

### 前置条件

```bash
# 1. 安装 create-dmg
brew install create-dmg

# 2. 确认私钥存在（不要 cat 内容，只验证文件非空）
test -s .sparkle-keys/eddsa_private_key && echo "key present" || echo "MISSING — ask admin"

# 3. 确认 gh CLI 已登录
gh auth status

# 4. 确认在 main 分支且代码是最新的
git checkout main && git pull
```

### 一键发版

```bash
./scripts/release.sh v2.2.0
```

脚本自动完成：

1. 更新 `MARKETING_VERSION`（如 2.2.0）
2. 递增 `CURRENT_PROJECT_VERSION`（build number，如 17 → 18）
3. Build unsigned universal 二进制（arm64 + x86_64）
4. 打包内置插件（stats.bundle 等）
5. Ad-hoc 签名
6. 创建 ZIP 包
7. 创建 DMG（带 Applications 拖拽链接）
8. 用 EdDSA 私钥签名 DMG
9. **检查签名是否为空**——为空则 `exit 1`，绝不发版未签名 appcast
10. 生成 `releases/appcast.xml`
11. 自动切到 landing-page 部署 appcast.xml 并 push
12. 切回 main，commit 版本号变更，打 git tag

### 脚本跑完后手动执行

```bash
# 推送代码和 tag
git push origin main --tags

# 创建 GitHub Release（上传 DMG 和 ZIP）
gh release create v2.2.0 MioIsland-v2.2.0.dmg MioIsland-v2.2.0.zip \
  --title "v2.2.0 — Mio Island"
```

### 验证

```bash
# 1. 确认 appcast 已更新
curl -s "https://miomioos.github.io/MioIsland/appcast.xml?nocache=$(date +%s)" \
  | grep -E "shortVersion|edSignature"
# 应看到新版本号 + 非空签名

# 2. 确认 DMG 可下载
curl -sI https://github.com/MioMioOS/MioIsland/releases/download/v2.2.0/MioIsland-v2.2.0.dmg | head -3

# 3. 本地测一下自动更新（可选但强烈推荐）
#   - 从 DerivedData 跑一个老 build 的 Mio Island
#   - 点 Check for Updates
#   - 确认走完"下载 → 验证签名 → 安装"全流程
```

## 5. 应用内升级原理

```
用户运行 v2.1.0 (build 16)
    │
    ▼ 启动时自动 / 手动点击「检查更新」
    │
    ▼ 请求 https://miomioos.github.io/MioIsland/appcast.xml
    │
    ▼ appcast 内容: v2.1.1, build 17, DMG 地址, EdDSA 签名
    │
    ▼ Sparkle 比较: 本地 build 16 < appcast build 17 → 弹出更新提示
    │
    ▼ 用户点击「安装更新」
    │
    ▼ 下载 DMG → 用 app 内置的公钥验证 EdDSA 签名
    │
    ▼ 签名匹配 → 替换 /Applications 下的旧版本 → 自动重启
```

### 版本比较规则

Sparkle 用 `sparkle:version`（对应 `CFBundleVersion`，即 build number）做比较，**不是** marketing version。

- appcast 中 `sparkle:version` = build number（如 17）
- appcast 中 `sparkle:shortVersionString` = 显示给用户的版本号（如 2.1.1）
- app 中 `CFBundleVersion` = 当前 build number（如 16）

**build number 必须严格递增**，`release.sh` 会自动处理。

## 6. 多人开发协作

### 权限分级

| 角色 | 能做什么 | 需要什么 |
|------|---------|---------|
| 开发者 | 提交代码、创建 PR | GitHub 仓库写权限 |
| 管理员/发版人 | 以上 + 发版 | GitHub 写权限 + EdDSA 私钥 + `gh` CLI |

### 新管理员配置

```bash
# 1. 克隆项目
git clone https://github.com/MioMioOS/MioIsland.git
cd MioIsland

# 2. 设置私钥（向项目管理员索取 base64 字符串，复制到剪贴板后粘贴）
mkdir -p .sparkle-keys
pbpaste > .sparkle-keys/eddsa_private_key
chmod 600 .sparkle-keys/eddsa_private_key

# 3. 安装工具
brew install create-dmg
gh auth login

# 4. 首次 build（下载 Sparkle SPM 包，生成 sign_update 工具）
xcodebuild -scheme ClaudeIsland -configuration Release build \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=""

# 5. 验证 sign_update 工具可用
find ~/Library/Developer/Xcode/DerivedData/ClaudeIsland-*/SourcePackages/artifacts -name "sign_update"
# 应输出一个路径

# 6. dry-run 验证签名链路
./scripts/release.sh v0.0.0-dryrun || true  # 应该能跑到签名那一步，不要真推
```

**没有私钥就不要跑 release.sh。** 脚本会在签名失败时硬停，见下面的故障排除。

## 7. 故障排除

### 「此更新未正确签名」（v2.1.6 事故实录）

**症状：** Sparkle 提示"此更新未正确签名，无法验证其真实性"。

**根因：** 线上 appcast.xml 的 `sparkle:edSignature=""` 为空。

**历史：** 2026-04-17 另一位协作者在没有 `.sparkle-keys/eddsa_private_key` 的机器上跑了 `release.sh v2.1.6`。老版 `release.sh` 在缺私钥时只打印 "SKIP Sparkle signing" 然后继续生成无签名 appcast 并推到 landing-page，导致全量用户升级失败。

**修复：** 当时的紧急修复

```bash
# 下载已经在 GitHub 上的 DMG（不要重做包，SHA256 已经广播给了用户）
curl -LO https://github.com/MioMioOS/MioIsland/releases/download/v2.1.6/MioIsland-v2.1.6.dmg

# 用正确的私钥签名
SIGN_UPDATE=$(find ~/Library/Developer/Xcode/DerivedData/ClaudeIsland-*/SourcePackages/artifacts -name sign_update | head -1)
"$SIGN_UPDATE" MioIsland-v2.1.6.dmg --ed-key-file .sparkle-keys/eddsa_private_key

# 把输出的 sparkle:edSignature="..." 填到 landing-page 分支的 landing/public/appcast.xml
git checkout landing-page
# 手动编辑 landing/public/appcast.xml，把空的 edSignature 替换进去
git commit -am "fix: sign v2.1.Z appcast"
git push origin landing-page
```

**预防：** 现在的 `release.sh` 如果签名为空会直接 `exit 1`，不会再把没签名的 appcast 推出去。

### 「You're up to date」但版本不对

Sparkle 比较的是 build number，不是 marketing version。检查 appcast 的 `sparkle:version` 是否大于当前 app 的 `CFBundleVersion`。

```bash
# 查看 app 的 build number
defaults read /Applications/"Mio Island.app"/Contents/Info CFBundleVersion

# 查看 appcast 的 build number
curl -s https://miomioos.github.io/MioIsland/appcast.xml | grep "sparkle:version"
```

### 「An error occurred in retrieving update information」

appcast URL 不可达。确认 `Info.plist` 中的 `SUFeedURL` 是：

```
https://miomioos.github.io/MioIsland/appcast.xml
```

确认 landing-page 分支的 appcast 已部署：

```bash
curl -s "https://miomioos.github.io/MioIsland/appcast.xml?nocache=$(date +%s)" | head -5
```

### 更新后 app 没有自动重启

用户需要在 macOS 系统设置 → 隐私与安全 → App 管理 中开启 Mio Island 的权限。首次更新时会提示。

### 私钥丢失怎么办

必须生成新密钥对，发一个特殊版本让旧用户手动下载：

```bash
./scripts/generate-keys.sh
# 更新 Info.plist 中的 SUPublicEDKey 为新公钥
# 在 GitHub release 页面和网站上提示用户手动下载新版本
```

## 8. 技术细节

| 配置 | 值 |
|------|-----|
| Sparkle 版本 | 2.6+ (SPM) |
| 签名算法 | Ed25519 (EdDSA) |
| 签名永久有效 | 是，不会过期 |
| appcast 地址 | `https://miomioos.github.io/MioIsland/appcast.xml` |
| GitHub Pages 来源 | `landing-page` 分支 → `landing/public/` |
| Build 方式 | unsigned + ad-hoc sign（无需 Developer ID） |
| 架构 | Universal (arm64 + x86_64) |
| 最低系统版本 | macOS 15.0 |
