# 任务卡：第一里程碑后的文字阅读器修复与体验优化

- 任务 ID：post-migration-reader-20260830
- 类型：BUG 修复 / 需求讨论 / 功能实现 / 审查交接
- 状态：四项代码和源代码契约检查已完成；用户已授权与漫画进度、EPUB 封面修复合并进行云端编译和真机验收
- 当前分支：`integration/legacy-capability-migration`；新任务尚未创建独立分支

## 用户最终得到的结果

在不重新迁移旧项目、不破坏第一里程碑稳定基线的前提下，修复分页文字首次点击和 TXT 分页字体问题，并为文字阅读器增加可控的左右独立边距与正文粗度。

## 当前行为或问题

1. 分页文字首次点击补丁已保留，并补齐“只允许单指单击”的严格约束和双击拒绝测试；长按、双击及分页滑动不在共存范围内。
2. TXT 分页会根据本地 `.txt/...` 章节键走纯文本 attributed-string 路径，保留行首空格并使用所选正文 face；本地 EPUB 继续走 CommonMark 路径。
3. 原有水平填充和 iPad 双页最外侧安全区逻辑保持不变；新增默认均为 `0` 的左、右独立边距，作为每页文字排版的额外增量，分页和滚动共用。
4. 正文新增“细、正常、中等、半粗、粗”五档；系统字体使用对应系统 weight，自定义字体在已安装 family 的实际 face 中选择最接近者，不合成不存在的中间字重。

## 验收标准

- [ ] 分页文字连续翻过至少 10 个新页面时，每页第一次点击左/右 tap zone 都立即执行一次对应翻页；不需要先激活文字视图。
- [ ] 长按、拖动选择和系统文字菜单仍可用；长按不误翻页，正常单击不产生两次翻页。
- [ ] `LXGWWenKaiGBScreen` 在同一个 TXT 章节的分页和滚动模式显示一致，并与同字体的 EPUB 正文效果一致；加入包含中文正文和行首空格/缩进的聚焦回归样本。
- [ ] 文字设置提供独立左、右边距，分页和滚动共用；从旧水平边距升级时初始视觉不变，修改任一侧只改变对应侧且触发正确重排。
- [ ] 正文字重设置在分页和滚动模式一致；不支持某一字重的字体明确回退到最接近的实际 face，不伪造不存在的连续变化。
- [ ] 先运行相关自动测试和一次云端编译；只有上述变更集中完成后再安排一轮最小真机验收和必要打包。

## 本次明确不做

- 不重新执行旧项目的完整迁移，不改写已经接受的第一里程碑基线。
- 不在本任务中同步新上游提交；上游差异仍先说明、后审批。
- 不开发 PDF、书库重构、新插件协议或与上述四项无关的阅读器重构。
- 不为了连续字重而引入新的字体渲染依赖。

## 限制与需要决定的事项

- 必须保持不变：书库、阅读历史、章节索引和进度含义；分页与滚动模式切换位置；长按系统文字选择。
- 用户已确认：保留现有水平填充和 iPad 安全区/双页外侧逻辑；左、右边距是额外的每页文字边距，分页和滚动共用，默认 `0`，范围 `0–80 pt`、步进 `2 pt`。不迁移或改写旧水平填充值。
- 用户已确认：正文字重提供“细、正常、中等、半粗、粗”五档；标题在正文基础上保留更强层级，代码块保持等宽字体语义。
- 本轮授权边界：允许为当前候选版本提交、推送集成分支、触发云端编译和生成无签名 IPA；不创建/合并 PR，不合入 `main`。

## 相关上下文

- 第一里程碑交接：`tasks/2026-08-28-legacy-capability-migration.md`
- 长期需求台账：`docs/PERSONAL_REQUIREMENTS.md` 中 `RDR-005` 至 `RDR-009`
- 分页文字排版：`Aidoku/Features/Reader/Readers/Text/Paged/TextPaginator.swift`
- 分页文字页面：`Aidoku/Features/Reader/Readers/Text/Paged/TextSinglePageViewController.swift`、`TextDoublePageViewController.swift`
- 滚动文字排版：`Aidoku/Features/Reader/Page/MarkdownView.swift`、`Readers/Text/Scroll/ReaderTextView.swift`
- 字体解析与导入：`Aidoku/Features/Reader/Readers/Text/TextReaderPreferences.swift`、`Aidoku/Features/Reader/TextReaderFontStore.swift`
- 设置入口：`Aidoku/Features/Reader/ReaderSettingsView.swift`
- 当前首次点击补丁：`Aidoku/Features/Reader/ReaderViewController.swift`、`AidokuTests/ReaderTapGesturePolicyTests.swift`

## 采用的方案

按四个可独立验证的小切片推进：先校验现有首次点击补丁；再为 TXT 分页增加能区分纯文本与 EPUB Markdown 的最小排版处理；随后让默认 `0` 的左右独立边距叠加到现有水平填充上；最后增加可落到实际字体 face 的五档正文粗度。每个切片补聚焦测试或源代码契约检查，不把多个未知原因混在一个试错补丁中。

TXT 字体根因已经由数据流和聚焦样本确认：本地 TXT 与 EPUB 都生成 `.text` 页面，分页器此前无条件按 CommonMark 解析；TXT 中四空格缩进正文因此进入 code block，并由 `mergeCodeBlockAttributes` 改成系统等宽字体。当前修复只让本地 `.txt/...` 章节走纯文本路径，EPUB 的 Markdown 标题、列表、图片和代码语义保持不变。

## 工作记录

- 2026-08-30：用户确认 `LXGWWenKaiGBScreen` 在 EPUB 和 TXT 滚动模式正常，只有 TXT 分页异常。
- 2026-08-30：用户完成 iPad Air 4 验收，并接受第一里程碑稳定版本；本任务中的问题均作为后续修复或优化，不重新打开迁移范围。
- 2026-08-30：用户确认本轮完成四项，但不单独进入编译环节，留待下一轮需求一起编译和真机验收。
- 2026-08-30：首次点击策略补齐单指单击限制；TXT 分页增加本地纯文本分流；分页/滚动接入默认 `0` 的左右独立边距和五档正文字重；设置、默认值和简繁中英文案同步。
- 当前下一步：与 `tasks/2026-08-30-manga-progress-local-cover-regressions.md` 的两项修复一起提交，触发一次云端 Release archive/IPA，并执行最小双设备真机验收。

## 验证证据

- 自动检查及结果：`git diff --check` 与 Git 所有权检查通过；14 项源代码契约检查通过；简体中文、繁体中文和英文的 8 个新增本地化键均唯一；未发现冲突标记。新增 Swift Testing 用例尚未在 macOS 执行。
- 人工验收：第一里程碑版本已由用户在 iPhone 17 和 iPad Air 4 接受；`LXGWWenKaiGBScreen` 的 EPUB、TXT 滚动正常和 TXT 分页异常由用户真机确认。
- 尚未验证：四项变更均未执行 Swift 编译、Swift Testing、SwiftLint、云端 archive 或真机验收；这是用户为与下一轮需求合并验证而明确保留的状态。

## 交接

- 已改变的行为：分页首次点击只与可选择文字视图的单指单击共存；本地 TXT 分页不再把缩进正文当代码块；左右边距与既有水平填充相加；分页和滚动正文共用五档字重。
- 修改的文件或模块：`ReaderViewController.swift`、`TextPaginator.swift`、`ReaderPagedTextViewController.swift`、`TextReaderPreferences.swift`、`ReaderTextView.swift`、`ReaderTextViewController.swift`、`MarkdownView.swift`、两个设置入口、默认值、本地化和聚焦测试。
- 已知限制：Windows 无法运行 Xcode；已验收 IPA 对应产品代码 `d5dd3739`，不包含当前首次点击补丁。
- 当前 Git 状态：`integration/legacy-capability-migration` 远端停在 `05a82dfd`；本任务四项代码、测试和交接文档均未提交、未推送；`main` 尚未合入迁移分支。
- 推荐下一步：下一轮继续在本任务状态上开发；完成后统一运行 Swift 编译/测试和真机验收，不重新迁移旧分支。
- 新对话必读文件：本任务卡、`docs/PERSONAL_REQUIREMENTS.md`、`tasks/2026-08-28-legacy-capability-migration.md`、`docs/ARCHITECTURE.md`。
