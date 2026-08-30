# 任务卡：第一里程碑后的文字阅读器修复与体验优化

- 任务 ID：post-migration-reader-20260830
- 类型：BUG 修复 / 功能实现 / 回归收敛
- 状态：TXT 分页字体和左右独立边距已真机验收；分页手势已按真机反馈调整，正文字重已回退，等待当前候选云端编译与真机复验
- 当前分支：`integration/legacy-capability-migration`

## 用户最终得到的结果

在不重新迁移旧项目、不破坏第一里程碑稳定基线的前提下：

1. TXT 分页使用所选字体，并正确保留普通正文中的行首空格和缩进。
2. 既有水平填充与 iPad 双页安全区逻辑保持不变，左、右独立边距作为默认 `0` 的额外每页文字边距。
3. 分页文字单击立即执行 tap zone 翻页；只保留系统长按选文，不增加双击选词或应用层等待判定。
4. 不提供阅读器内五档字重。需要不同粗细时，分别导入并选择实际字体文件。

## 已确认行为与问题

- 用户已在真机验收 TXT 分页字体和左右独立边距，结果通过。
- 第一版分页选择补丁让父级单击和 `UITextView` 的单击识别器并行，并保留了等待双击失败的关系；真机表现为单击翻页明显延迟，且长按选择不可用。
- 当前处理仅针对分页文字：分页文字视图拒绝内部 tap recognizer，保留系统 long-press 等非点击手势；父级 tap zone 不再等待双击判定，因此单击直接翻页。
- 漫画及其他阅读器继续使用原有单击/双击手势配置，不受分页文字专用策略影响。
- `LXGWWenKaiGBScreen` 是单一 Regular face。五档设置无法从该字体文件得到真实粗细变化；用户决定回退该功能，改为手动导入其他实际 face。

## 验收标准

- [x] TXT 分页与滚动模式均使用所选字体；TXT 中中文正文和行首空格/缩进不再因 CommonMark code block 规则切换为系统等宽字体。
- [x] 左、右独立边距与既有水平填充相加，默认 `0`；分页和滚动共用，iPad 双页外侧安全区不变。
- [ ] 分页文字连续翻过至少 10 个新页面，每页第一次单击左/右 tap zone 都立即且只执行一次对应翻页。
- [ ] 分页文字长按、拖动选区和系统菜单可用；长按不误翻页。
- [ ] 滚动文字原有选择行为不变；漫画原有单击/双击翻页行为不变。
- [ ] 用户在本轮提交推送后手动触发云端编译，并执行双设备真机复验。

## 本次明确不做

- 不提供应用层双击选词，不为区分单击和双击增加输出间隔或等待阈值。
- 不提供正文字重设置，不合成不存在的字重，不为连续字重引入字体渲染依赖。
- 不重新执行旧项目完整迁移，不同步新上游提交，不修改书库、章节索引或进度含义。
- 不开发 PDF、书库重构、新插件协议或无关阅读器重构。

## 相关代码

- 分页 tap zone：`Aidoku/Features/Reader/ReaderViewController.swift`
- 分页文字页面：`Aidoku/Features/Reader/Readers/Text/Paged/TextSinglePageViewController.swift`、`TextDoublePageViewController.swift`
- 分页排版：`Aidoku/Features/Reader/Readers/Text/Paged/TextPaginator.swift`
- 滚动排版：`Aidoku/Features/Reader/Page/MarkdownView.swift`
- 字体解析与导入：`Aidoku/Features/Reader/Readers/Text/TextReaderPreferences.swift`、`Aidoku/Features/Reader/TextReaderFontStore.swift`
- 聚焦手势测试：`AidokuTests/PagedTextGestureTests.swift`

## 采用的方案

TXT 字体修复只让本地 `.txt/...` 章节走纯文本 attributed-string 路径；EPUB 继续走 CommonMark，以保留标题、列表、图片和代码语义。左右独立边距只作为每页文字排版的额外增量，不改写旧水平填充值或 iPad 双页外侧安全区。

分页手势使用专用 `PagedSelectableTextView`：其内部点击识别器不参与竞争，系统长按选择识别器仍可开始；分页父控制器的单击 tap zone 在 reader 装载后重建，并仅对分页文字移除双击失败等待。该边界避免改变漫画和滚动阅读器的既有交互。

正文字重和相关默认值、设置、本地化、解析逻辑与测试全部回退。字体选择仍保存具体 PostScript face，因此分别导入 Light、Regular、Medium 文件后可以手动切换真实字形。

## 工作记录

- 2026-08-30：用户确认 `LXGWWenKaiGBScreen` 在 EPUB 和 TXT 滚动正常，只有 TXT 分页异常。
- 2026-08-30：完成 TXT 纯文本分页、左右独立边距和初版分页点击/选择处理。
- 2026-08-30：候选提交 `d28c69da` 云端 archive 成功；真机验收确认 TXT 分页字体和左右边距通过，但发现分页单击延迟、长按选择丢失、正文字重无可见效果。
- 2026-08-30：用户确认分页改为单击立即翻页且只保留长按选文；正文字重完整回退，以独立字体文件替代。

## 验证状态

- 已有真机证据：TXT 分页字体、左右独立边距通过；漫画进度暂未发现问题，仍需继续观察。
- 当前代码检查：`git diff --check` 与 Git 所有权检查通过；4 个已回退符号无残留，5 项分页手势源代码契约存在，三份本地化无本轮新增重复键；`LocalFileDataManager.swift` 与稳定锚点 `d5dd3739` 的封面实现静态一致。
- 当前 Windows 环境无法运行 Xcode、Swift Testing 或 iOS Simulator；打包由用户在本轮提交推送后从 GitHub Actions 页面手动触发。
- 当前分页手势调整、封面回退和字重回退均尚未真机验收。

## 交接

- 第一里程碑稳定锚点：`d5dd3739`。
- 已编译但真机未接受的旧候选：`d28c69da`；不得作为交付版本。
- 当前修改保留 TXT 分页字体、左右独立边距和漫画进度修复；回退本地封面恢复与正文字重；增加分页文字专用即时点击/长按选择策略。
- 当前修改随本提交推送到集成分支；提交本身不触发手动打包工作流。
- 新任务继续前必读：本任务卡、`docs/PERSONAL_REQUIREMENTS.md`、`tasks/2026-08-28-legacy-capability-migration.md`、`tasks/2026-08-30-manga-progress-local-cover-regressions.md` 和当前 `git diff`。
