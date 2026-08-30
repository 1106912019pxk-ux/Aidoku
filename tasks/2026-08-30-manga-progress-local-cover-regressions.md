# 任务卡：漫画阅读进度与本地 EPUB 封面回归

- 任务 ID：manga-progress-local-cover-20260830
- 类型：BUG 修复 / 回归验证
- 状态：代码修复、聚焦测试和无编译静态检查已完成；用户已授权当前候选版本进入云端编译、IPA 和真机验收
- 当前分支：`integration/legacy-capability-migration`

## 本轮范围

1. 修复连续阅读插件来源漫画多个章节后，继续阅读位置偶尔落后于实际最新章节的问题。
2. 修复本地导入 EPUB 在软件更新或 App 容器路径变化后丢失封面的问题。

## 本轮不做

- Komiic v3/v1 不做宿主迁移；用户先手动统一到 Aidoku Community v1。
- v1 已提供登录，因此本轮不再增加 Komiic Cookie 配置。
- v1 已提供并默认开启“优先显示单行本”，宿主级章节/单行本模式需求降低优先级，留待其他来源也证明存在缺口后再处理。
- 不创建/合并 PR，不合入 `main`；本轮已授权为当前候选版本提交、推送集成分支并触发云端编译和无签名 IPA。

## 已确认根因

### 漫画阅读进度

- 换章、完成章节、退出阅读器和进入后台会分别启动异步历史保存。
- `HistoryManager` 原先为可并发类，每次写入使用新的 Core Data 后台上下文；同一章节可能并发创建多个 `HistoryObject`。
- `getReadingHistory` 清理重复对象时按未排序抓取结果任意保留第一条，因此可能留下旧页码或未完成状态。
- 非结构化保存任务内部才生成阅读时间，也会让延迟执行的旧事件获得更晚时间，影响“继续阅读”对最新章节的判断。

### 本地 EPUB 封面

- 本地封面使用 `aidoku-image:///Local/...` 保存相对 Documents 的稳定地址。
- 启动扫描原先直接对该自定义 URL 的 `path` 做文件存在检查，没有先还原到当前 Documents 路径，因此会把有效封面误判为损坏。
- 修复扫描找到 `cover.*` 后写回绝对 `file://` 地址，且没有保存背景上下文；App 更新改变容器路径后仍会再次失效。

## 采用的修复

- `HistoryManager` 改用与本地数据管理一致的 Core Data 串行 actor executor，所有历史写入共享一个后台上下文。
- 阅读器在派发异步保存前捕获真实事件时间，避免任务调度顺序改变“最新阅读”语义。
- 重复 History 按“已完成优先、阅读时间较新优先、同时间页码较高优先”选择保留项，并把阅读会话转移到保留项。
- 本地封面检查先把 `aidoku-image` 转回当前 Documents 文件 URL；修复时仍写回稳定 URL，并立即保存 Core Data。

## 验收标准

- [ ] 选择至少两个插件来源，各连续阅读至少 5 个章节，中途包含正常翻页、自动进入下一章和主动退出；重新打开后继续阅读均进入实际最新位置。
- [ ] 杀掉 App 再启动后，最新章节、已读标记和未完成章节页码保持一致。
- [ ] 已经存在重复历史数据的书目首次读取后不回退到较旧未完成状态，阅读统计会话不丢失。
- [ ] 至少一本已有本地 EPUB 和一本新导入 EPUB 在升级安装、冷启动和本地扫描后封面仍显示。
- [ ] 封面恢复不再需要取消书架和重新收藏。

## 修改范围

- `Aidoku/Core/Library/Services/HistoryManager.swift`
- `Aidoku/Core/Database/CoreDataManager+History.swift`
- `Aidoku/Features/Reader/ReaderViewController.swift`
- `Aidoku/Core/Sources/BuiltIn/Local/LocalFileDataManager.swift`
- `AidokuTests/ReadingProgressRegressionTests.swift`
- `AidokuTests/LocalCoverRecoveryTests.swift`
- `docs/PERSONAL_REQUIREMENTS.md`

## 验证状态

- 新增 3 项重复历史选择测试和 3 项本地封面稳定地址测试；测试文件位于 Xcode 文件系统同步组，会自动进入 `AidokuTests` target。
- 12 项源代码契约检查、冲突标记扫描、`git diff --check` 和 Git 所有权检查均通过。
- 当前 Windows 环境没有 Swift/SwiftLint/Xcode，因此未执行 Swift Testing、SwiftLint 或编译；云端 archive、IPA 和真机验收同下一轮需求集中执行。
