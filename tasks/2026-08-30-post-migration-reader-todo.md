# 任务卡：第一里程碑后的文字阅读器修复与体验优化

- 任务 ID：post-migration-reader-20260830
- 类型：BUG 修复 / 功能实现 / 回归收敛
- 状态：TXT 分页字体和左右独立边距已真机验收；分页正文保持上游非交互方案，并仅对分页文字取消无意义的双击等待，等待真机复验
- 当前分支：`integration/legacy-capability-migration`

## 用户最终得到的结果

在不重新迁移旧项目、不破坏第一里程碑稳定基线的前提下：

1. TXT 分页使用所选字体，并正确保留普通正文中的行首空格和缩进。
2. 既有水平填充与 iPad 双页安全区逻辑保持不变，左、右独立边距作为默认 `0` 的额外每页文字边距。
3. 分页文字完全采用上游 Aidoku 的交互边界：正文视图不接收触摸、不支持文本选择，所有点击交给外层 tap zone，以翻页正确性为最高优先级。
4. 不提供阅读器内五档字重。需要不同粗细时，分别导入并选择实际字体文件。

## 已确认行为与问题

- 用户已在真机验收 TXT 分页字体和左右独立边距，结果通过。
- 两轮分页选择补丁均未通过真机验收：第一版让父级单击和 `UITextView` 手势并行，出现明显延迟且长按不可用；第二版过滤显式 tap recognizer，仍被系统文字交互吞掉新页面第一次点击，并保留了双击选词。
- 当前分页正文保持上游 Aidoku 的 `UITextView.isUserInteractionEnabled = false`，不再参与任何触摸或选择；父级手势只增加一项明确差异：分页文字不创建 dummy double-tap recognizer，因此单击无需等待双击失败。
- 分页选择只有在未来引入独立、明确的“阅读/选择”状态后才可能重新评估，已降为低优先级 TODO；当前不再尝试让文字选择与翻页手势竞争。
- 滚动文字原有选择行为不变；漫画及其他阅读器继续使用上游既有单击/双击手势配置。
- `LXGWWenKaiGBScreen` 是单一 Regular face。五档设置无法从该字体文件得到真实粗细变化；用户决定回退该功能，改为手动导入其他实际 face。

## 验收标准

- [x] TXT 分页与滚动模式均使用所选字体；TXT 中中文正文和行首空格/缩进不再因 CommonMark code block 规则切换为系统等宽字体。
- [x] 左、右独立边距与既有水平填充相加，默认 `0`；分页和滚动共用，iPad 双页外侧安全区不变。
- [ ] 分页文字连续翻过至少 10 个新页面，每页第一次单击左/右 tap zone 都立即且只执行一次对应翻页。
- [ ] 分页文字不响应长按或双击选文，双击不会出现文字选区或系统选择菜单。
- [ ] 滚动文字原有选择行为不变；漫画原有单击/双击翻页行为不变。
- [ ] 用户在本轮提交推送后手动触发云端编译，并执行双设备真机复验。

## 本次明确不做

- 不提供分页文字选择，不再通过自定义手势过滤、应用层双击选词或额外等待阈值协调选择与翻页。
- 不提供正文字重设置，不合成不存在的字重，不为连续字重引入字体渲染依赖。
- 不重新执行旧项目完整迁移，不同步新上游提交，不修改书库、章节索引或进度含义。
- 不开发 PDF、书库重构、新插件协议或无关阅读器重构。

## 相关代码

- 分页 tap zone：`Aidoku/Features/Reader/ReaderViewController.swift`
- 点击延迟策略测试：`AidokuTests/ReaderTapDelayPolicyTests.swift`
- 分页文字页面：`Aidoku/Features/Reader/Readers/Text/Paged/TextSinglePageViewController.swift`、`TextDoublePageViewController.swift`
- 分页排版：`Aidoku/Features/Reader/Readers/Text/Paged/TextPaginator.swift`
- 滚动排版：`Aidoku/Features/Reader/Page/MarkdownView.swift`
- 字体解析与导入：`Aidoku/Features/Reader/Readers/Text/TextReaderPreferences.swift`、`Aidoku/Features/Reader/TextReaderFontStore.swift`

## 采用的方案

TXT 字体修复只让本地 `.txt/...` 章节走纯文本 attributed-string 路径；EPUB 继续走 CommonMark，以保留标题、列表、图片和代码语义。左右独立边距只作为每页文字排版的额外增量，不改写旧水平填充值或 iPad 双页外侧安全区。

分页正文沿用上游 Aidoku：单页和双页均使用普通 `UITextView`，关闭 `isUserInteractionEnabled`，让触摸直接穿透到父级 tap zone。父控制器仅增加两项配套差异：分页文字不等待双击判定，并在 reader 类型完成切换后重建点击识别器，确保初次进入与分页/滚动切换都使用正确策略；漫画及其他阅读器仍完整保留上游双击等待和“禁用双击缩放”设置语义。分页文字不支持选择，滚动文字不受影响。

正文字重和相关默认值、设置、本地化、解析逻辑与测试全部回退。字体选择仍保存具体 PostScript face，因此分别导入 Light、Regular、Medium 文件后可以手动切换真实字形。

## 工作记录

- 2026-08-30：用户确认 `LXGWWenKaiGBScreen` 在 EPUB 和 TXT 滚动正常，只有 TXT 分页异常。
- 2026-08-30：完成 TXT 纯文本分页、左右独立边距和初版分页点击/选择处理。
- 2026-08-30：候选提交 `d28c69da` 云端 archive 成功；真机验收确认 TXT 分页字体和左右边距通过，但发现分页单击延迟、长按选择丢失、正文字重无可见效果。
- 2026-08-30：用户确认分页改为单击立即翻页且只保留长按选文；正文字重完整回退，以独立字体文件替代。
- 2026-08-31：候选提交 `d1651d2d` 云端 archive 成功，但真机仍出现新页面第一次点击不翻页、双击选词；确认不是打错版本，而是系统文字交互仍参与手势竞争。
- 2026-08-31：用户终止分页选择实验，以翻页绝对正确为最高优先级；分页交互和父级点击手势恢复上游 Aidoku 状态，分页选择降为低优先级 TODO。
- 2026-08-31：真机确认完全恢复上游后分页点击仍有明显延迟；源码对比确认上游通过 `tap.require(toFail: doubleTap)` 延迟 tap zone，而最新回退删除了分页文字豁免。现恢复仅分页文字即时点击，漫画双击缩放不变。

## 验证状态

- 已有真机证据：TXT 分页字体、左右独立边距通过；漫画进度暂未发现问题，仍需继续观察。
- 当前代码检查：Git 所有权检查和 `git diff --check` 通过；将唯一策略块归一化后，bar-toggle 函数其余内容与 `upstream/main` 完全一致；上游/当前 A/B 条件矩阵证明只有“分页文字、默认设置”从等待变为立即，漫画默认、禁用双击和单击查词三种行为均与上游一致；reader 类型确定后的手势重建契约存在，漫画设置和漫画 reader 文件没有改动；单双页正文触摸穿透存在，分页选择实验符号无残留；新增 4 项策略测试但当前 Windows 无法执行 UIKit/Xcode 测试；`LocalFileDataManager.swift` 与稳定锚点 `d5dd3739` 的封面实现静态一致。
- 当前 Windows 环境无法运行 Xcode、Swift Testing 或 iOS Simulator；打包由用户在本轮提交推送后从 GitHub Actions 页面手动触发。
- 当前分页交互回退、封面回退和字重回退均尚未真机验收。

## 交接

- 第一里程碑稳定锚点：`d5dd3739`。
- 已编译但真机未接受的旧候选：`d28c69da`；不得作为交付版本。
- 真机未接受的最新候选：`d1651d2d`；其分页文字专用即时点击/长按选择策略已在当前工作树中回退，不得作为交付版本。
- 当前工作树保留 TXT 分页字体、左右独立边距和漫画进度修复；本地封面恢复与正文字重维持回退；分页交互恢复上游 Aidoku 状态。
- 当前修改尚未提交或推送，也未触发云端编译或打包。
- 新任务继续前必读：本任务卡、`docs/PERSONAL_REQUIREMENTS.md`、`tasks/2026-08-28-legacy-capability-migration.md`、`tasks/2026-08-30-manga-progress-local-cover-regressions.md` 和当前 `git diff`。
