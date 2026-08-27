# 项目架构地图

## 当前 Git 基线

| 名称 | 当前值 | 用途 |
|---|---|---|
| 官方基线 | `upstream/main` = `ae20b10e9d77c9f040a423d79081b5ad3c7b5023` | 官方 Aidoku 最新源码 |
| 本地稳定分支 | `main`，当前与 `upstream/main` 相同 | 后续只接收已验证的个人整合版本 |
| 当前工作分支 | `integration/project-baseline-20260828` | 建立项目文档和迁移基线 |
| 旧个人稳定点 | `legacy/main` = `df9964421aa92f5bdcff5b5583c11d575b46791d` | 旧项目主分支参考 |
| 旧最终功能点 | `legacy/feature/txt-local-reader-20260825` = `b0baed469ccd405cf950d99b3ff0a521ad803142` | 功能迁移的主要历史证据 |
| 共同祖先 | `45fe8231a8da58f70f5f2e152a039fcb49eab4cb` | 分析上游变化和旧个人差异的起点 |

`upstream` 和 `legacy` 的 push URL 已设为 `DISABLED`。新的公开个人仓库尚未创建，因此当前没有 `origin`。

## 技术栈

| 范围 | 当前选择 | 证据来源 |
|---|---|---|
| 运行环境 | iOS/iPadOS 15.0+；Xcode 26.6 云端 archive | `Aidoku.xcodeproj/project.pbxproj`、`.github/workflows/nightly.yml` |
| 语言和界面 | Swift 5，UIKit 与 SwiftUI 混合 | Xcode 工程、`Aidoku/App`、`Aidoku/Features` |
| 依赖管理 | Swift Package Manager | `Aidoku.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` |
| 持久化 | Core Data、应用设置和本地文件 | `Aidoku/Core/Database`、`Aidoku/Core/Settings`、`Aidoku/Core/Sources/BuiltIn/Local` |
| 来源扩展 | Aidoku 内置来源与来源/插件管理 | `Aidoku/Core/Sources`、`Aidoku/Features/Source` |
| 测试 | XCTest，`AidokuTests` target | `AidokuTests/`、共享 `Aidoku` scheme |
| 静态检查 | SwiftLint | `.swiftlint.yml`、`.github/workflows/lint.yml` |

## 模块地图

| 路径或模块 | 负责什么 | 不应该负责什么 |
|---|---|---|
| `Aidoku/App` | App 生命周期、导航根节点、公共 UI 和资源 | 阅读格式解析或来源业务规则 |
| `Aidoku/Core/Sources` | 内置来源、来源管理、本地文件来源 | 具体阅读器 UI 状态 |
| `Aidoku/Core/Library` | 漫画/书目模型和书库服务 | 文件渲染和页面控件 |
| `Aidoku/Core/Database` | Core Data 存储与对象映射 | 用户界面和网络展示逻辑 |
| `Aidoku/Core/Downloads` | 下载队列、缓存和下载状态 | 阅读器排版 |
| `Aidoku/Features/Reader` | 漫画、条漫和文字阅读器，阅读位置与交互 | 来源搜索和账户逻辑 |
| `Aidoku/Features/Source` | 来源浏览、搜索和来源界面 | 持久化实现细节 |
| `Aidoku/Features/Library` | 书库展示和管理 | 来源协议实现 |
| `AidokuTests` | 可重复的单元与回归测试 | 真机专属验收替代品 |

## 重要流程

### 来源插件到阅读器

```text
用户添加/选择来源 -> Core/Sources 获取内容 -> Library/Database 保存书目和章节
-> Features/Manga 或 Features/Reader 展示 -> 保存历史与阅读进度
```

### 本地 EPUB/TXT 迁移目标

```text
文件选择器 -> BuiltIn/Local 识别与解析 -> 本地书目/章节模型
-> 文字或图片阅读器 -> 排版/朗读/自动阅读 -> 保存阅读位置
```

官方当前基线只提供其现有本地格式行为；TXT、个人 TTS、自动阅读和跨章节定位仍位于 `legacy/feature/txt-local-reader-20260825`，尚未迁移。

### 上游同步

```text
fetch upstream -> 对比上次同步点 -> 按主题解释变化和重叠
-> sync/upstream-YYYYMMDD -> 自动检查/必要编译 -> 集中真机回归 -> main
```

## 项目命令

| 用途 | 实际命令或入口 | 当前验证状态 |
|---|---|---|
| 获取官方更新 | `git fetch upstream main` | 本机已成功执行；因本轮沙箱所有权差异需临时 safe.directory |
| 获取旧迁移参考 | `git fetch legacy` | 本机已成功执行，只配置了两个旧分支 |
| 安装依赖 | 使用 Xcode 打开工程并解析 `Package.resolved` | Windows 无法执行，待首次 macOS CI 验证 |
| 启动项目 | Xcode 打开 `Aidoku.xcodeproj`，共享 scheme 为 `Aidoku` | 从工程文件确认，Windows 未运行 |
| 运行测试 | `xcodebuild -project Aidoku.xcodeproj -scheme Aidoku -destination '<可用 iOS Simulator>' test` | scheme 包含 `AidokuTests`；具体 destination 待 CI 验证 |
| SwiftLint | `swiftlint lint --reporter github-actions-logging` | 官方 PR 工作流使用；本机未安装 SwiftLint |
| 无签名 archive | `xcodebuild -scheme "Aidoku" -configuration Release archive -archivePath build/Aidoku.xcarchive -skipPackagePluginValidation CODE_SIGN_IDENTITY= CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` | 官方工作流命令；Windows 未执行 |
| IPA 打包 | GitHub Actions `Build and upload nightly ipa` 手动触发 | 本地已改为仅 `workflow_dispatch`，尚未运行 |

## 数据和外部服务

- 持久化数据：Core Data、应用设置、下载缓存和本地导入文件。迁移功能时不得改变现有数据库含义或静默丢失进度。
- 登录和权限：不同来源、追踪服务和侧载签名可能有独立凭据；真实值不得进入 Git。
- 外部服务：GitHub 用于公开源码、代码检查和 macOS 构建；内容来源由 Aidoku 来源机制提供。
- GitHub 认证：当前 `gh` 登录令牌无效；创建新公开仓库或首次推送前需要重新认证。

## 已知架构限制

- Windows 无 Xcode，Swift 编译、Simulator 和 IPA archive 必须在 macOS/CI 完成。
- 官方上游在共同祖先后已有 41 个提交并重组目录；旧代码不能假设原 `Shared/`、`iOS/` 路径仍存在。
- 旧最终功能分支相对共同祖先包含 77 个提交，其中有撤销实验和 CI 噪声；迁移必须按最终行为切片。
- 当前基线尚未包含旧项目的 TXT、字体解析、个人 TTS、自动阅读和跨章节朗读修复。
- iPadOS 精确版本和新基线真机兼容性尚未验证。

## 相关技术决定

- 以当前官方 `upstream/main` 建立新基线，再按有效用户行为迁移旧功能。
- 旧仓库只读保留；新 GitHub 仓库创建前不设置 `origin`。
- `main` 用于个人稳定版本，上游同步在独立分支完成。
- 打包工作流仅手动触发，自动检查优先，真机验收集中在高风险集成节点。
