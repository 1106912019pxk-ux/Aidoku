# 旧个人版本迁移审计

审计基准：旧最终功能点 `b0baed469ccd405cf950d99b3ff0a521ad803142`；当前官方基线 `ae20b10e`；当前迁移分支 `integration/legacy-capability-migration`。

本文按最终用户行为审计，不把合并提交、构建重试和格式化噪声算作独立功能。状态“已迁入”表示代码已进入当前分支；当前分支已通过 Xcode 26.6 Release archive 和无签名 IPA 生成，但不等于已经通过自动测试或真机验收。

旧范围共 77 个提交；已逐条复核提交主题和关键差异。其中 7 个是合并提交、9 个是 CI 流程提交、6 个是文档提交，其余产品代码按下表的最终用户行为归并。被撤销或未形成稳定交付的 Readium/sherpa 路线单独列在“有意不迁入”，没有把它们静默算作完成。

## 已迁入的个人改动

| 旧改动或行为 | 旧证据 | 当前实现位置 | 与当前上游的冲突及处理 | 当前证据 |
|---|---|---|---|---|
| PICA 分流、启动不阻塞、原域名 TLS、失败回退系统网络 | `f0010a41`、`3ba068a4`、`f1d1ba6c` | `Aidoku/Core/Sources/PicaNetworkRouting.swift`、`Aidoku/Extensions/AidokuRunner/AidokuRunner.swift`、`Aidoku/App/AppDelegate.swift`、`Aidoku/Core/Downloads/DownloadTask.swift` | 旧版把大量逻辑直接放进旧 `AidokuRunner` 扩展；当前上游已把 Runner 变为 Swift Package，并提供 `InterpreterConfiguration.requestHandler`。保留线路解析和本地 CONNECT 隧道，但改从当前 request handler、Nuke data loader 和下载器三个实际网络入口接入；只匹配 Picacomic 域名，频道 1 和故障时走系统网络。 | `PicaNetworkRoutingTests` 覆盖域名/频道边界；未做真实线路请求和真机性能对比。 |
| PICA 详情页远端收藏、结构化元数据、作者逐项搜索/复制、按钮不被固定高度截断 | `52ed940e`、`57b518cb`、`29d00eeb`、`cce906e7`、`c93cc740` | `Aidoku/Features/Manga/MangaDetailsHeaderView.swift` | 当前上游已改用 `MangaIdentifier`、新的 Tracker API 和 `mangaId` 参数。保留上游现有书库、Tracker、Safari 和章节 UI，只增加 `zh.picacomic` 限定的通知协议、元数据解析和作者交互；没有用旧文件覆盖新文件。 | 来源键、通知结果格式和错误分支已静态核对；需要配套的定制 PICA AIX 和真机登录态验收。 |
| E-Hentai 账户收藏状态、添加和移除 | `99c623f4` | `Aidoku/Features/Manga/MangaDetailsHeaderView.swift` | 保留当前通用详情页，只对 `multi.ehentai` 显示账户收藏按钮；优先读取详情状态，不存在时调用定制来源通知。 | 通知结果格式已与只读旧定制来源核对；需要配套的定制 E-Hentai AIX 和真机 Cookie/登录态验收。 |
| PICA 屏蔽分类和过滤后空页仍继续分页 | `1a1f98cb` | `Aidoku/Features/Source/SearchFilterHeaderView.swift`、`SourceHomeContentView.swift`、`HomeGridView.swift`、`HomeComponents/HomeListView.swift` | 当前上游重组了 Home 目录并已经把 `loadMore` 变成可选闭包。屏蔽分类只对 PICA 生效；空中间页跳过逻辑作为通用、最多 20 页的防护；加载标志改为等待异步请求真正结束再复位。 | 静态路径和状态流检查通过；需用存在连续空页的 PICA 分类验收。 |
| 书库筛选菜单避免 Swift 类型检查超时 | `5b0c68a0` | `Aidoku/Features/Library/LibraryViewController.swift` | 上游当前仍保留一个大型 `compactMap + 数组拼接` 表达式。只机械拆成显式 `[UIMenuElement]`，保持现有 actor store、菜单内容和交互不变。 | `git diff --check` 和 Xcode 26.6 Release archive 通过。 |
| 文字排版设置：字号、行距、上下/水平边距、段距、首行缩进、主题 | `4db9134d` 及其最终状态 | `ReaderSettingsView.swift`、`TextReaderPreferences.swift`、`TextPaginator.swift`、`ReaderTextView.swift`、分页/滚动文字控制器、设置默认值和本地化 | 不恢复 Readium 阅读器；把仍适用于上游原生 EPUB/TXT 文字阅读器的设置接入当前分页和滚动渲染链。 | `TextPaginatorTests` 增加设置相关检查；视觉和旋转/双页仍需设备验收。 |
| 已选字体 family 解析到可用 PostScript face | `baca3897` | `TextReaderFontStore.swift`、`MarkdownView.swift`、`TextPaginator.swift`、设置 UI | 当前上游字体入口已变化。建立一个共享解析器供 Markdown、分页器和设置预览使用，不复制旧 Readium 字体存储。 | 静态调用链检查通过；CJK 自定义字体需真机确认。 |
| 独立自动阅读、分页文字临时切连续滚动、速度控制和停止后恢复 | `61b60546`、`9189e359`、`f8296000` | `ReaderReaderDelegate.swift`、`ReaderSettingsView.swift`、`ReaderViewController.swift`、`ReaderToolbarView.swift`、`ReaderWebtoonViewController.swift`、`ReaderTextViewController.swift`、设置默认值/UI | 复用上游 Webtoon 的 display-link 引擎，但恢复旧版独立会话：阅读设置中可选择速度并启动；分页文字启动时临时切滚动，停止后恢复原文字样式和阅读模式；图片模式临时切 Webtoon；速度恢复为 0.5×–8×、1× 约 56 点/秒，并在工具栏提供分级加减和停止。已启动会话不受全局按钮显示开关误停。遇到 EPUB 图片 spine 时退出或跳过，不把图片塞进文字阅读器。 | 会话入口、模式切换、混合 spine 和生命周期状态流已静态检查；速度感受、跨章和位置恢复需真机确认。 |
| Microsoft Edge 在线朗读、Apple 系统降级、后续 3 段音频预取、暂停/继续/停止、后台音频和媒体控制 | `00b49944` 至 `de3e1246` 的稳定在线/系统链路，预取最终状态见 `9189e359` | `ReaderSpeech.swift`、`ReaderViewController.swift`、文字阅读器、本地化、`Info.plist` | 旧实现分散在多个控制器/引擎文件；当前实现收敛为设置存储、WebSocket 服务、分段器和控制器。保留 Microsoft 默认、Apple 降级和最多 3 段预取；预取失败只回到正常逐段合成，不终止朗读。明确不迁入未完成验收的 sherpa 离线模型。 | `ReaderSpeechTests` 覆盖分段、锚点、SSML 和音频帧解析；Xcode 26.6 Release archive 已通过；AVFoundation、MediaPlayer、WebSocket 和后台行为待真机。 |
| 朗读时文本仍可选择，翻页/滚动/滑块导航锁定 | `d2b9a519`、`478b2cb3` | `MarkdownView.swift`、文字页控制器、`ReaderViewController.swift` | 不给正文加覆盖层；只锁定页面容器的导航滚动和工具栏滑块，因此系统文本选择仍可工作。 | 静态交互链检查通过；长按选择与朗读并行需真机。 |
| 正在朗读的内容使用实际渲染页文本和可见页锚点 | `7ffd2c93`、`64be4105` | `ReaderSpeech.swift`、`ReaderPagedTextViewController.swift`、`ReaderTextViewController.swift` | 修正迁移初版把 `[TextPage]` 当作原始 `[Page]` 的错误；分页模式从屏幕正在显示的 `TextPage` 开始，并朗读 `attributedContent.string`。滚动模式继续按实际 section/hosting controller 定位。 | 静态类型和锚点检查通过；真实 Markdown 转换后的页同步需真机。 |
| EPUB/TXT 跨章节朗读及分页未完成时保留待定位目标 | `b0baed46` | `ReaderViewController.swift`、`ReaderPagedTextViewController.swift`、`ReaderTextViewController.swift` | 下一章先按当前安全区、字号、边距和单双页布局生成朗读分页；声音进入新章时由父控制器保存 chapter/page 目标，加载真实章节，等阅读器上报可用页后重试。朗读触发的换章不会误停；用户手动换章会停止。 | pending/retry 状态流已静态核对；跨两章 EPUB/TXT 和前后台恢复需真机。 |
| TXT 独立导入、多编码、自动/关闭/自定义分章、预览、UTF-8 规范化索引、重启扫描和删除 | `fe5b49a2`、`fada8188` | `TxtParser.swift`、`LocalFileImportView.swift`、`LocalFileManager.swift`、`LocalFileDataManager.swift`、`LocalModels.swift`、本地化 | 当前上游本地来源模型和导入界面已重组。保留现有 EPUB/CBZ/ZIP 流程，TXT 单独解析后写规范化 UTF-8 与 JSON 字节范围，失败不登记半成品；扫描旧/损坏索引时重新规范化。 | `TxtParserTests` 覆盖编码、分章开关、正则、前言和范围；大文件与真实导入恢复需设备/编译环境。 |
| 后台音频能力声明 | `a46f1300` | `Aidoku/Info.plist` | 上游 plist 只有 fetch、processing、remote-notification；在保留三项的同时补回 `audio`，没有改变其他后台权限。 | plist XML 解析通过；系统后台策略需真机。 |

## 有意不迁入的旧提交

| 旧内容 | 旧证据 | 处理结论 | 原因 |
|---|---|---|---|
| 独立 Readium 书库、Books 页签、Readium 字体/偏好和 Xcode 26 ZIP 临时补丁 | `140a13fe` 至 `4db9134d` 中的 Readium 路线 | 不迁入 Readium 模块、依赖、页签和补丁；只迁入对上游原生文字阅读仍有效的排版偏好 | 该路线曾撤销又恢复，但没有形成稳定真机全链路；当前项目已明确继续使用上游 EPUB 阅读器，避免双书库/双阅读器和额外依赖。 |
| sherpa-onnx 离线朗读模型 | `00b49944` 的未完成部分 | 不迁入 | 模型未入包、完整链路未验收，迁入会增加体积、生产依赖和维护面。 |
| PR 自动 IPA、反复审批、构建重试提交 | `0e3bc332`、`2de9dff4`、`af89d82c`、`35a461f2`、`8a395332`、`052050ff`、`9c988a49` | 不逐提交迁入；流程重新定义为手动打包、代码/云编译/真机验收分离 | 这些提交是旧开发阶段的流程噪声和限制，不是产品能力。 |
| 旧 TASKS、PROJECT_OVERVIEW、handoff 全文和合并提交 | 文档与 merge commits | 只把仍有效决定压缩到当前 `docs/`、`tasks/` 和 `AGENTS.md` | 避免旧路径、旧仓库名和过期限制成为新项目指令。 |

## 配套来源边界

PICA 和 E-Hentai 账户收藏按钮依赖旧项目中分别实现了通知协议的定制 AIX。宿主迁移不会把这些来源打入 IPA，也不会修改或构建旧来源仓库。若只安装当前社区版来源，基础阅读仍可使用，但上述定制收藏按钮会收到“没有结果”错误；最终验收必须使用与通知协议匹配的定制来源版本。

## 冲突处理原则

1. 当前上游的数据模型、actor/并发边界、导航结构和通用 UI 是骨架，不用旧整文件覆盖。
2. 个人功能按来源键、文件类型或阅读器协议限定作用域，避免改变其他来源和漫画阅读行为。
3. 上游已有完整等价能力时复用上游；只有缺失的用户行为才补入。
4. 旧实现与当前持久数据冲突时保留当前数据库语义；TXT 使用新文件旁路索引，不改 Core Data 模型。
5. 旧实验没有稳定验收或会引入新依赖时不迁入，并在本审计中显式列出，不能静默遗漏。

## 构建验证与尚未完成项

- Windows 已完成：Git 所有权检查、diff 空白检查、Swift 文件结构/关键符号扫描、plist XML 解析和本地化键检查。
- GitHub Actions 运行 `33265963550`：macOS 26、Xcode 26.6、Release archive、无签名 IPA 压缩和 artifact 上传全部通过；产物 `Aidoku-iOS_nightly-140cce2.ipa`，artifact ID `9718720054`，GitHub 显示 11.2 MB，SHA-256 `9da1d8918dcf3acbaa19613982223528bfb51d89bf2c9902ee297734d60ee2cc`。
- 构建中依据明确诊断修复了 `ReaderSpeech.swift` 的 SwiftUI 导入、`if` 表达式控制流和错误描述显式返回兼容问题；没有用猜测性改动绕过编译器。
- 尚未完成：Swift Testing/XCTest、SwiftLint，以及成功 artifact 的本地下载解包复核。
- 尚未完成：PICA/E-Hentai 定制来源联调、Microsoft WebSocket、Apple 降级、后台媒体、EPUB/TXT 跨章、字体、旋转/双页、大 TXT 导入。
- 尚未完成：最终一次 iPhone 17（iOS 26）和 iPad Air 4 集中验收。
