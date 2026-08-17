# MiaoYan Project Pitfalls Log

## 1. 文档目的

本文档专门记录 MiaoYan 项目开发过程中已经踩过、验证过、或者已经明确废弃的坑。

目标不是写泛泛的经验总结，而是给后续继续接手的人一份可以直接检索的排障记录，避免在同一个问题上重复绕路。

## 2. 使用规则

后续每次遇到新的坑，统一按下面格式追加：

```text
## [日期] 标题

- 现象：
- 初始误判 / 错误尝试：
- 真正根因：
- 最终修复：
- 受影响文件：
- 回归验证：
- 备注：
```

约束：

- 只记录已经有明确证据的结论，不写纯猜测
- 如果某条尝试最后被回退，也要记录“为什么回退”
- 同一个问题允许补充后续结论，但不要覆盖之前的错误路径

## 3. 已记录坑点

## [2026-07-29] Storyboard 增加 TOC 第三栏后 `ibtool` 直接崩溃

- 现象：
  - `Command CompileStoryboard failed with a nonzero exit code`
  - 新增第三栏之前 storyboard 是正常的，新增之后 `ibtool` 本身崩了
- 初始误判 / 错误尝试：
  - 一开始容易怀疑是 outlet、class、constraint 写错
- 真正根因：
  - `Resources/Localization/Base.lproj/Main.storyboard` 里 `EditorSplitView` 已从 2 个 subviews 扩成 3 个，但 `holdingPriorities` 仍然只有 2 个值，导致 storyboard 结构不一致
- 最终修复：
  - 给 `holdingPriorities` 补齐第三个值，和 3 个子视图数量保持一致
- 受影响文件：
  - `Resources/Localization/Base.lproj/Main.storyboard`
- 回归验证：
  - storyboard 可重新编译，`ibtool` 不再崩溃
- 备注：
  - 这类问题优先检查 split view 的 subviews 数量、holding priorities、constraints 数量是否同步

## [2026-07-29] TOC 第三栏出现了，但目录列表是空白

- 现象：
  - 第三栏能显示出来，但列表内容不显示，看起来像“目录没数据”
- 初始误判 / 错误尝试：
  - 容易先怀疑 parser 没解析到标题
- 真正根因：
  - `EditorTOCView` 里的 `NSTableView` 作为 `NSScrollView.documentView` 后，没有在布局阶段主动把 frame 同步到 `scrollView.contentView.bounds`，导致表格尺寸不对，内容实际没正常渲染出来
- 最终修复：
  - 在 `EditorTOCView.layout()` 中显式同步 `tableView.frame`
  - 同时刷新列宽，确保内容能占满目录栏
- 受影响文件：
  - `Views/EditorTOCView.swift`
- 回归验证：
  - 第三栏不再是空白，目录项可以正常显示
- 备注：
  - 以后如果再遇到 AppKit 下“数据有但列表空白”，先查 `documentView` 的尺寸链路

## [2026-07-29] 目录标题看起来“解析错了”，其实是切换文件后没刷新

- 现象：
  - 切换笔记后目录标题不更新
  - 手动按一次 `Command+3` 或触发某些模式切换后，目录才突然变对
- 初始误判 / 错误尝试：
  - 一开始把问题归因到 `EditorTOCParser` 的标题解析规则，尤其怀疑 Setext 识别过宽
- 真正根因：
  - 主切换路径并不统一走 `refillEditArea(...)`
  - 有多条路径会直接执行 `editArea.fill(note:options:)`，但这些路径后面没有补 `refreshEditorTOC()`
  - 所以问题本质不是 parser 错，而是 TOC 吃到了旧 note 的内容
- 最终修复：
  - 在所有直接 `fill(note:)` 的主路径后补 `refreshEditorTOC()`
  - 重点补在 `Views/NotesTableView.swift` 和 `Controllers/ViewController+Data.swift`
- 受影响文件：
  - `Views/NotesTableView.swift`
  - `Controllers/ViewController+Data.swift`
  - `Controllers/ViewController+Editor.swift`
- 回归验证：
  - 切换笔记后目录立即刷新，不再依赖额外快捷键
- 备注：
  - 后续任何新增“整篇 note 重载”路径，都要同步检查是否漏掉 TOC 刷新

## [2026-07-29] 第 2 / 第 3 条 divider 死活拖不动

- 现象：
  - 笔记列表和目录之间、目录和编辑器之间的 divider 看得见，但左右拖拽没有效果
- 初始误判 / 错误尝试：
  - 误以为是 divider 命中区域太窄
  - 尝试过改 `effectiveRect`、`dividerThickness`、手动放大命中区域
  - 这些尝试不仅没解决问题，还让交互更怪
- 真正根因：
  - `EditorSplitView` 里给前两栏设置了 `.defaultHigh`（750）的 holding priority
  - 这个优先级高于 AppKit divider 拖拽时可打破的布局优先级区间，Auto Layout 会判定宽度不能通过拖拽被修改
- 最终修复：
  - 将 holding priority 调整为 `260 / 260 / 250`
  - 同时让 TOC 最大宽度限制和 divider 最大位置口径保持一致，避免拖宽后松手回弹
- 受影响文件：
  - `Views/EditorSplitView.swift`
- 回归验证：
  - 第 2 / 第 3 条 divider 可拖拽
  - 拖到边界会稳定停住，不会反弹
- 备注：
  - 这是这轮分栏问题里最关键的一个真根因，以后再碰到“split view 看得见但拖不动”，先查 holding priority

## [2026-07-29] `setPosition` 递归重入导致崩溃

- 现象：
  - 调整 TOC 宽度时崩在 `-[NSSplitView setPosition:ofDividerAtIndex:]`
  - 栈里能看到 `___chkstk_darwin`
- 初始误判 / 错误尝试：
  - 容易以为是坐标越界或者 divider index 写错
- 真正根因：
  - `configureTOCColumnIfNeeded()` 在 resize / layout 回调链里再次调用 `setPosition(...)`
  - 又会触发新的 split view resize 回调，形成重入递归
- 最终修复：
  - 增加 `isAdjustingTOCColumn` 保护，避免重复进入
  - 去掉不必要的 `adjustSubviews()` 触发链
- 受影响文件：
  - `Views/EditorSplitView.swift`
- 回归验证：
  - 拖拽和窗口缩放不再崩溃
- 备注：
  - 以后只要在 AppKit layout 回调里再调 `setPosition`，都要先考虑重入

## [2026-08-10] TOC 宽度能记住，但显示状态重启恢复不稳定

- 现象：
  - TOC 宽度重启后能恢复
  - 但用户隐藏 TOC 后重启，TOC 仍可能自己显示出来
- 初始误判 / 错误尝试：
  - 直觉上容易认为是 `UserDefaults` 没存进去
- 真正根因：
  - 宽度和显隐虽然都做了持久化，但启动阶段还有其他 layout / mode 切换链路会覆盖显隐状态
- 最终修复：
  - 本问题在当时没有彻底收掉，属于已知问题并被用户明确要求先暂缓
- 受影响文件：
  - `Controllers/ViewController.swift`
  - `Controllers/ViewController+Layout.swift`
  - `Helpers/UserDefaultsManagement.swift`
- 回归验证：
  - 当时仅验证“宽度持久化可用”，显隐恢复问题延后处理
- 备注：
  - 这个坑后来和“安装版启动布局错乱”排查链路交织在一起，不能孤立看

## [2026-08-10] 退出时停留在预览模式，重启后原生 TOC 又冒出来

- 现象：
  - 关闭 App 前停在预览模式，重启后原生 TOC 仍然显示
  - 且点击后没有真正跳转效果
- 初始误判 / 错误尝试：
  - 容易怀疑是 TOC 可用性判断或者点击跳转逻辑坏了
- 真正根因：
  - `editorMode` 被持久化为了 preview
  - 但启动时原生 TOC 的恢复逻辑还是按编辑态偏好恢复，导致“预览模式 + 原生 TOC 显示”这个错位状态
- 最终修复：
  - `applySavedEditorTOCState()` 按当前模式决定显隐
  - 预览 / 演示 / PPT 模式下，一律不显示原生 TOC
  - `setEditorTOCVisible(true)` 也增加模式守卫
- 受影响文件：
  - `Controllers/ViewController+Layout.swift`
- 回归验证：
  - 预览模式重启后，原生 TOC 不再错误显示
- 备注：
  - 面板显隐恢复必须服从“当前模式约束”，不能只看用户偏好

## [2026-08-15] 打开一个内容较大的 md 文件后，原生 TOC 要过一会才出现

- 现象：
  - 文件已经打开了，但 TOC 要延迟一小段时间才显示出来
- 初始误判 / 错误尝试：
  - 容易怀疑是 debounce 时间太长
- 真正根因：
  - `fill(note:)` 的异步加载分支在真正把文本写入编辑器后，没有自动触发 `textDidChange`
  - 调用方又在 `fill` 返回后立刻 `refreshEditorTOC()`，这时解析到的还是旧缓冲或空缓冲
- 最终修复：
  - 在异步内容真正写入编辑器后，立即重建一次 TOC
- 受影响文件：
  - `Views/EditTextView.swift`
- 回归验证：
  - 打开未缓存的大文件时，TOC 会跟随内容加载及时出现
- 备注：
  - 以后所有异步写入编辑器缓冲的路径，都不要默认依赖 `textDidChange`

## [2026-08-15] 分栏拖拽吸附 / 贴边折叠功能整条回退

- 现象：
  - 试图让第 2 / 3 / 4 条线支持拖到边缘后自动吸附折叠
  - 期间出现了窄条无法拉回、拖拽手势串到下一条 divider、交互不符合预期等连锁问题
- 初始误判 / 错误尝试：
  - 为了修局部问题，连续叠加了多轮吸附阈值、最小坐标、mouseUp 落态、窄手柄等修补
- 真正根因：
  - 这条交互本身和现有多层 split view 结构耦合太深
  - 即使局部修通，也不符合用户对“主流编辑器交互”的预期
- 最终修复：
  - 用户决定整体回退这条功能线
  - 相关实现全部撤销，只保留与此无关的稳定修复
- 受影响文件：
  - `Views/EditorSplitView.swift`
  - `Views/EditorScrollView.swift`
  - `Controllers/ViewController+Layout.swift`
  - `Theme` 常量及调试日志
- 回归验证：
  - 分栏行为恢复到原先稳定版本
- 备注：
  - 这类“功能层面方向不对”的问题，不该继续在细节里硬补

## [2026-08-17] 安装到 `Applications` 后启动布局异常，不能简单归因到 `UserDefaults`

- 现象：
  - Xcode 里停止再运行，看起来能记住布局
  - 安装到 `Applications` 后，关闭再打开布局表现不一致
- 初始误判 / 错误尝试：
  - 先后怀疑过 `UserDefaults` 域不同、`autosaveName`、窗口恢复、bundle 差异
  - 这些都不是完整答案
- 真正根因：
  - 安装版启动链路更完整，后置的恢复 / 打开文件事件会覆盖前面已经应用过的默认布局
  - 问题不能只盯着“启动时有没有把布局设对”，还要看后面谁又改回去了
- 最终修复：
  - 先通过运行时日志确认普通启动和“打开文件”两条链路
  - 最终把问题收敛到 single mode 的打开文件路径，而不是继续泛化排查所有启动恢复项
- 受影响文件：
  - `Controllers/AppDelegate.swift`
  - `Controllers/AppDelegate+URLRoutes.swift`
  - `Controllers/ViewController.swift`
  - `Controllers/ViewController+Layout.swift`
- 回归验证：
  - 普通启动和打开文件两条链路分开定位后，问题边界变清晰
- 备注：
  - 以后再查“安装版才复现”的问题，优先区分冷启动、reopen、手动 open file 三种入口

## [2026-08-17] 手动双击单个 md 文件时，布局会被拉成默认 5 栏

- 现象：
  - 直接启动安装版 App 时默认 3 栏是稳定的
  - 但双击某个 `.md` 文件，或者“打开方式 -> MiaoYan”后，会变成 5 栏
- 初始误判 / 错误尝试：
  - 前面有一段时间一直在修“普通启动默认布局”
  - 但那并不是这次用户真正要修的路径
- 真正根因：
  - `application(_:open:)` -> `openNotes(urls:)` -> `reloadForSingleMode()` -> `configureNotesList()`
  - 在 single mode 的“单文件”分支中，代码会显式调用 `showSidebar("")`
  - `showSidebar("")` 会联动展开 notelist，再叠加 TOC、editor、preview，就自然变成 5 栏
- 最终修复：
  - 不再对“单文件 single mode”调用 `showSidebar("")`
  - 改为单独应用 `TOC + 编辑 + 预览` 的 3 栏默认布局
  - 同时把 editor / preview 的 split 比例重置回 50/50，避免继承上一次会话的比例
- 受影响文件：
  - `Controllers/ViewController.swift`
  - `Controllers/ViewController+Layout.swift`
- 回归验证：
  - 双击单个 `.md` 文件后，界面稳定保持 3 栏，不再跳成 5 栏
- 备注：
  - 这个问题是最近这轮安装版布局排查里最关键的最终结论

## 4. 当前高价值结论

如果后面再有人继续改这一块，优先记住下面几条：

- `EditorSplitView` 的 divider 拖不动，先查 holding priority，不要先去改命中区域
- TOC 标题“不对”时，先排查是不是切 note 后没刷新，而不是先怀疑 parser
- App 启动布局问题要先区分“普通启动”和“打开文件进入 single mode”两条链
- single mode 打开单文件时，不能直接复用项目浏览态的 `showSidebar("")`
- 异步 `fill(note:)` 写入编辑器内容后，不要假设 `textDidChange` 一定会触发

## 5. 后续维护建议

- 以后凡是涉及布局恢复、single mode、打开文件链路的改动，提交前都至少手动验证两条路径：
  - 普通启动 App
  - 双击单个 `.md` 文件打开 App
- 如果是安装版才复现的问题，优先保留运行时现场和日志，再做静态修补
- 文档优先写在 `docs/` 里，不把关键排障信息只留在聊天记录里
