# 任务卡：漫画阅读进度与本地 EPUB 封面回归

- 任务 ID：manga-progress-local-cover-20260830
- 类型：BUG 修复 / 回归收敛
- 状态：漫画进度修复保留并继续观察；本地 EPUB 封面修复已按真机反馈完整回退
- 当前分支：`integration/legacy-capability-migration`

## 当前范围

修复连续阅读插件来源漫画多个章节后，继续阅读位置偶尔落后于实际最新章节的问题。

本地 EPUB 封面原问题属于升级或容器变化后的边缘问题。候选修复导致正常本地文件封面也消失，用户决定停止进一步不稳定尝试，恢复修复前行为；旧封面丢失仍可通过取消书架后重新收藏恢复。

## 漫画进度根因与保留修复

- 换章、完成章节、退出阅读器和进入后台会分别启动异步历史保存。
- `HistoryManager` 原先可并发写入多个 Core Data 后台上下文；同一章节可能产生重复 `HistoryObject`。
- 重复对象清理此前可能任意保留旧页码或未完成状态，非结构化保存任务内生成的时间也可能颠倒事件先后。
- 当前修复将历史写入串行化，在派发前捕获事件时间，并按“已完成优先、阅读时间较新优先、同时间页码较高优先”合并重复项，同时转移阅读会话。

## 封面回退边界

- 删除本轮新增的稳定 URL 转换、修复后持久化和对应聚焦测试。
- `LocalFileDataManager` 恢复到第一里程碑锚点 `d5dd3739` 的封面扫描与修复逻辑。
- 不继续尝试自动迁移旧封面地址，不扩大到本地文件导入、图片加载器或书架缓存重构。

## 验收标准

- [ ] 选择至少两个插件来源，各连续阅读至少 5 个章节；包含正常翻页、自动进入下一章和主动退出，重新打开后继续阅读均进入实际最新位置。
- [ ] 杀掉 App 再启动后，最新章节、已读标记和未完成章节页码保持一致。
- [ ] 已存在重复历史数据的书目首次读取后不回退到较旧未完成状态，阅读统计会话不丢失。
- [ ] 普通本地文件封面恢复为第一里程碑既有显示行为。

## 修改范围

- `Aidoku/Core/Library/Services/HistoryManager.swift`
- `Aidoku/Core/Database/CoreDataManager+History.swift`
- `Aidoku/Features/Reader/ReaderViewController.swift`
- `AidokuTests/ReadingProgressRegressionTests.swift`
- `Aidoku/Core/Sources/BuiltIn/Local/LocalFileDataManager.swift` 仅用于完整回退封面候选修复
- `docs/PERSONAL_REQUIREMENTS.md`

## 验证状态

- 漫画进度聚焦测试保留；用户目前继续阅读未发现问题，但样本和时间尚不足，继续观察。
- 本地封面实现已静态对比第一里程碑锚点 `d5dd3739`，该文件没有差异；`LocalCoverRecovery` 及对应测试均无残留。
- 当前分页手势和两项回退随本轮候选一起推送；打包由用户从 GitHub Actions 页面手动触发后统一真机验收。
