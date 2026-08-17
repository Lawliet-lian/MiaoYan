# 编辑区原生目录栏执行手册

## 1. 文档目的

本文档用于指导 MiaoYan 落地“编辑区原生目录栏”能力，作为后续开发的单一执行依据。

目标不是重写现有预览 TOC，而是在不破坏现有预览逻辑的前提下，为编辑区增加一套独立、原生、可维护的目录能力。

相关文档：

- 项目踩坑记录：`docs/project-pitfalls-log.md`

## 2. 最终结论

最推荐的实现路线：

- 不改 `EditorContentSplitView` 的职责边界
- 在中层 `EditorSplitView` 增加一个新的原生 TOC 栏
- 保持内层 `EditorContentSplitView` 继续只管理“编辑器 / 预览”

最终结构应为：

1. 项目栏
2. 笔记列表
3. 编辑区原生目录
4. 编辑器
5. 预览

对应分层结论：

- 外层 `sidebarSplitView`：不动
- 中层 `EditorSplitView`：扩成三栏
- 内层 `EditorContentSplitView`：保持现状，仅负责编辑器和预览

这是当前风险最低、边界最清晰、最利于后续维护的方案。

## 3. 当前代码事实

当前主界面结构分三层：

1. 外层 `sidebarSplitView`
   - `Resources/Localization/Base.lproj/Main.storyboard`
   - `Controllers/ViewController.swift`
   - 职责：项目栏 + 主内容区

2. 中层 `EditorSplitView`
   - `Resources/Localization/Base.lproj/Main.storyboard`
   - `Views/EditorSplitView.swift`
   - 当前子视图：
     - 左：笔记列表 `SidebarNotesView`
     - 右：编辑区容器 `EditorView`

3. 内层 `EditorContentSplitView`
   - `Controllers/ViewController.swift`
   - `Views/EditorScrollView.swift`
   - 运行时创建，仅负责：
     - 左：编辑器 `editAreaScroll`
     - 右：预览 `previewScrollView`

当前 `Cmd+5` 的 `toggleTOC:` 仍直接调用预览侧的 `editArea.markdownView?.toggleTOC()`，且菜单可用性规则也默认认为 TOC 依附于 preview WebView。

因此，本次新增的原生目录栏必须是“新增一层编辑器能力”，而不是改造现有 preview TOC。

## 4. 范围定义

### 4.1 本次要做

- 在 `EditorSplitView` 中新增第三栏目录容器
- 目录数据来源于编辑器文本，而非预览 DOM
- 支持点击目录项后定位编辑器标题
- 支持编辑器滚动时目录高亮当前标题
- 支持目录显示状态与宽度持久化
- 兼容编辑模式与分屏模式

### 4.2 本次不要做

- 不把目录做成 WebView
- 不从 preview DOM 反推编辑器位置
- 不重写 `EditorContentSplitView`
- 不把目录刷新逻辑并入语法高亮主热路径
- 不新增与 `Cmd+0` ~ `Cmd+5` 冲突的快捷键
- 不在 MVP 阶段直接上树形折叠和复杂交互

> 更新（2026-08-15）：树形折叠/展开已由 Phase 5 承接并落地，不再属于“不做”范围。

## 5. 推荐落地结构

将 `EditorSplitView` 扩成 3 个 arranged subviews：

1. `notesListCustomView`
2. `editorTOCContainerView`，新增
3. `EditorView`，原编辑区容器

`EditorView` 内部结构保持不变：

- 编辑模式：`editorTOC + editor`
- 分屏模式：`editorTOC + editor + preview`
- 纯预览模式：默认隐藏原生目录
- PPT 模式：禁用原生目录

这意味着：

- 编辑区目录属于中层容器能力
- 预览 TOC 仍属于预览层能力
- 两者可以共存，但不互相依赖

## 6. 文件改动清单

### 6.1 必改文件

1. `Resources/Localization/Base.lproj/Main.storyboard`
   - 给 `EditorSplitView` 增加目录栏容器

2. `Controllers/ViewController.swift`
   - 新增目录栏相关 `IBOutlet`
   - 初始化目录视图
   - 在模式切换时统一处理目录显示/隐藏

3. `Views/EditorSplitView.swift`
   - 从两栏逻辑扩成三栏逻辑
   - 处理新增 divider 的约束、隐藏、拖拽与持久化

4. 新增视图文件
   - `Views/EditorTOCView.swift`
   - 如有需要，再补 `Views/EditorTOCRowView.swift`

5. 新增模型与解析文件
   - `Business/EditorTOCItem.swift`
   - `Helpers/EditorTOCParser.swift`

6. `Controllers/ViewController+Editor.swift`
   - 接入文本变化刷新
   - 接入滚动高亮
   - 改造 `toggleTOC:`

7. `Helpers/UserDefaultsManagement.swift`
   - 新增目录栏显示状态与宽度持久化

### 6.2 可能要改

- `Views/EditTextView.swift`
  - 如需补“跳转到字符位置并尽量居中显示”的 helper

- `Controllers/ViewController.swift`
  - 调整 `validateMenuItem(_:)` 中 `toggleTOC:` 的可用性规则

- 各语言 `Main.strings`
  - 新增菜单标题、提示文案或 tooltip 时同步补齐本地化

### 6.3 工程注册要求

新增 Swift 文件后，必须手工更新 `MiaoYan.xcodeproj/project.pbxproj` 的 4 处：

1. `PBXBuildFile`
2. `PBXFileReference`
3. 所属 group 的 `children`
4. 对应 target 的 `PBXSourcesBuildPhase`

## 7. 数据模型设计

MVP 先使用扁平数组模型，降低复杂度：

```swift
struct EditorTOCItem {
    let level: Int
    let title: String
    let line: Int
    let characterRange: NSRange
}
```

说明：

- `level`：标题级别，1...6
- `title`：目录展示文案
- `line`：标题所在行，便于后续调试与扩展
- `characterRange`：用于点击跳转和滚动高亮匹配

树形结构不是 MVP 必需项。先用扁平数组 + 缩进展示层级即可。

## 8. 解析规则

不要直接复用预览 TOC。

应新增 `EditorTOCParser`，从编辑器文本本身做一次轻量扫描。可以参考以下正则来源，但不要直接把高亮逻辑当目录数据源：

- `Helpers/NotesTextProcessor.swift`
  - `headersAtxRegex`
  - `headersSetextRegex`

必须满足以下规则：

1. fenced code block 里的 `#` 不算标题
2. frontmatter 区块不算标题
3. 支持 ATX 标题：`#` ~ `######`
4. 支持 Setext 标题
5. 空标题过滤
6. 去除标题前后空白
7. 去除 closing `#`

建议解析顺序：

1. 先按行扫描文本
2. 维护 `isInFrontmatter` 状态
3. 维护 `isInFencedCodeBlock` 状态
4. 在有效内容区识别 ATX / Setext 标题
5. 生成 `EditorTOCItem`

实现建议：

- 不直接复用高亮用的整套 `NotesTextProcessor` 处理链
- 解析器尽量无 UI 依赖，方便后续补单测
- 长文档下避免重复创建过多中间对象

## 9. 交互规则

### 9.1 显示规则

- 编辑模式：可显示
- 分屏模式：可显示
- 纯预览模式：默认隐藏原生目录
- PPT 模式：禁用原生目录

### 9.2 点击规则

点击目录项后：

1. `editArea.setSelectedRange(...)`
2. `editArea.scrollRangeToVisible(...)`
3. `window?.makeFirstResponder(editArea)`

如果默认滚动不够理想，可以在 `EditTextView` 增加一个“跳转并尽量居中显示”的 helper，但这属于增强项，不阻塞 MVP。

### 9.3 高亮规则

- 监听编辑器滚动
- 取当前可视区域顶部附近的标题作为“当前标题”
- 高亮最近的一个 heading
- 目录自动滚动到当前高亮项可见

性能要求：

- 不要在每次 `boundsDidChange` 时全量重算
- 对高亮计算做 `50ms ~ 100ms` 节流

### 9.4 刷新规则

- 文本变化后不要立即全量重建目录
- 对目录刷新做 `120ms ~ 250ms` debounce
- 刷新前确认当前 note 仍是同一篇，避免串 note

## 10. 布局与持久化规则

目录栏建议约束：

- 默认宽度：`180 ~ 220`
- 最小宽度：`140`
- 最大宽度：`320`

新增持久化项建议：

- `editorTOCVisible`
- `editorTOCWidth` 或 `editorTOCSplitPosition`

持久化风格参考：

- `sidebarSize`
- `realSidebarSize`
- `editorContentSplitPosition`

关键约束：

- 目录必须挂在 `EditorSplitView`
- 不允许塞进 `EditorContentSplitView`

否则在分屏模式下，目录会和预览职责混杂，后续切模式会明显更难维护。

## 11. 菜单与快捷键规则

> 更新（2026-08-16）：用户决定拆分快捷键——`Cmd+5` 还原为预览 WebView 的目录切换（`toggleTOC:`，原始行为），新增 `Cmd+6` 作为原生编辑区目录切换（`toggleNativeTOC:`）。仓库规则允许 `Cmd+6`（`Cmd+0`~`Cmd+5` 已占满，6 空闲）。

当前行为：

- `Cmd+5`（Toggle TOC）：仅切换预览 WebView 的 TOC，可用条件为 preview 存在且非 PPT
- `Cmd+6`（Toggle Native TOC）：切换原生编辑区目录（编辑/分屏/纯预览可用；演示与 PPT 禁用，演示/PPT 继续用 `Cmd+5` 的预览 TOC）

同时需要改造：

- `toggleTOC:` 还原为 `editArea.markdownView?.toggleTOC()`
- 新增 `toggleNativeTOC:`（`setEditorTOCVisible(!isEditorTOCVisible)`）及 EditTextView / EditorMenuManager 转发链
- `validateMenuItem(_:)` 分别判断两个动作的可用性
- 新增菜单项 `Toggle Native TOC`（`Cmd+6`），并补齐四种语言 `Main.strings` 文案

## 12. 单阶段执行协议

从本次开始，目录栏开发改为“单阶段执行”模式。

执行规则：

1. 一次只做一个阶段，不跨阶段连做
2. 每完成一个阶段，必须先由人工手动验证
3. 人工验证通过后，才进入下一个阶段
4. 每次结束时，都要回写本文档中的阶段状态
5. 下次继续时，默认从“下一个未完成阶段”开始，而不是重新全量扫描

这样做的目的不是改变设计，而是缩短单次执行时间，降低回合成本，并避免一次改动过大导致回滚困难。

## 13. 阶段状态看板

### 当前执行基线

- 执行模式：单阶段执行
- 当前状态：`Phase 5` 目录折叠/展开已人工验证通过（`done`）
- 当前起点：全部阶段完成；`Phase 4` 验证仍在排队（用户指示暂缓）
- 规则：未经过人工验证的源码改动，不视为阶段完成

### 阶段状态定义

- `pending`：未开始
- `in_progress`：当前正在执行
- `waiting_validation`：代码已完成，等待人工验证
- `done`：人工验证通过
- `discarded`：废弃，不再继续沿用

### 阶段清单

| 阶段 | 名称 | 状态 | 说明 |
| --- | --- | --- | --- |
| Phase 0 | 方案冻结与执行编排 | `done` | 结构方案已确定，执行手册已建立 |
| Phase 1 | MVP 骨架 | `done` | 基础目录能力与 divider 拖拽修复已落地，人工验证通过 |
| Phase 2 | 编辑器联动 | `done` | 文本变化 debounce 刷新、滚动高亮、高亮项自动滚入可视区已落地，人工验证通过 |
| Phase 3 | 布局与持久化 | `done` | TOC 宽度持久化、split 行为、Cmd+5 路由与菜单可用性已落地；显隐重启恢复存在已知问题，用户指示暂缓处理 |
| Phase 4 | 打磨与收尾 | `waiting_validation` | 空状态、长标题 tooltip、多模式行为统一已落地，等待人工验证 |
| Phase 5 | 目录折叠/展开 | `done` | 目录项按标题层级支持折叠/展开，折叠状态在文本刷新间保留（不跨重启持久化），人工验证通过 |

### 状态记录日志

后续每完成一个阶段，都按下面格式追加一条：

```text
- [日期] Phase N -> waiting_validation
  - 本轮完成：...
  - 待人工验证：...
  - 验证结论：pending / pass / fail
  - 下一阶段：Phase N+1 / 原阶段返工
```

当前日志：

- [2026-07-28] Phase 0 -> done
  - 本轮完成：确认目录落点在 `EditorSplitView`，并将执行方式改为单阶段执行
  - 待人工验证：无
  - 验证结论：pass
  - 下一阶段：Phase 1

- [2026-07-29] Phase 0 -> done
  - 本轮完成：采用方案 A，废弃并清理所有未验证的目录栏源码改动，恢复到干净工作区
  - 待人工验证：无
  - 验证结论：pass
  - 下一阶段：Phase 1

- [2026-07-29] Phase 1 -> waiting_validation
  - 本轮完成：新增编辑区原生目录 MVP 骨架（解析标题、展示目录、点击跳转），并完成 storyboard 第三栏与工程注册
  - 待人工验证：手动运行 App，确认第三栏目录出现且点击可跳转
  - 验证结论：pending
  - 下一阶段：Phase 2

- [2026-07-29] Phase 1 -> in_progress
  - 本轮完成：人工验证开始
  - 待人工验证：修复 build 失败（CompileStoryboard nonzero exit code）
  - 验证结论：fail
  - 下一阶段：Phase 1（修复后重新验证）

- [2026-07-29] Phase 1 -> in_progress
  - 本轮完成：目录第三栏、标题解析、点击跳转、切换文件刷新等基础能力已基本跑通；后续尝试修复 divider 拖拽问题时效果退化，用户已手动回退到上一稳定版本
  - 待人工验证：优先修复第 2 / 第 3 条 divider 无法左右拖拽的问题；修复后重新验证栏位拖拽、栏位切换与目录展示
  - 验证结论：fail
  - 下一阶段：Phase 1（先修遗留问题，再决定是否进入 Phase 2）

- [2026-07-29] Phase 1 -> waiting_validation
  - 本轮完成：以 `Views/EditorSplitView.swift` 作为正确修复版本，定位并修复第 2 / 第 3 条 divider 无法拖拽的根因——`configureTOCColumnIfNeeded()` 曾把第 1 / 第 2 栏 holding priority 设为 `.defaultHigh`(750)，超过 AppKit divider 拖拽优先级(490/510)，Auto Layout 驱动的 split view 因此判定两栏不可因拖拽改宽；现已改为 260/260/250 并补充注释。同时把 `maxTOCDividerPosition` 与 TOC 最大宽度(260)口径对齐，消除拖宽后松手回弹；`preferredTOCWidth` 记录时同步夹取到合法区间
  - 待人工验证：拖拽第 2 条(笔记列表↔目录)与第 3 条(目录↔编辑器) divider 可自由改宽；拖到边界处正常停住不回弹；Cmd+1/2 栏位显隐切换后拖拽仍正常；窗口缩放时仍由编辑器栏吸收宽度
  - 验证结论：pending
  - 下一阶段：Phase 2（验证通过后）

- [2026-08-10] Phase 1 -> done
  - 本轮完成：用户确认 Phase 1 开发验收完成，骨架、点击跳转与 divider 拖拽修复全部通过
  - 待人工验证：无
  - 验证结论：pass
  - 下一阶段：Phase 2

- [2026-08-10] Phase 2 -> waiting_validation
  - 本轮完成：实现编辑器联动三件事——`textDidChange` 后 180ms debounce 重建目录（刷新前取消挂起任务，换 note 走立即刷新路径）；监听编辑区 clip view 滚动，60ms 节流后按“可视区顶部最近一个标题”计算当前章节并高亮；高亮项自动 `scrollRowToVisible` 滚入目录可视区。`EditorTOCView` 新增 `setHighlightedIndex`，程序化选中加标记避免滚动高亮误触点击跳转；`updateItems` 清理旧高亮。面板重新显示时立即同步一次高亮。macOS Debug build 通过
  - 待人工验证：输入文字后目录延迟约 0.2s 稳定刷新；滚动编辑器时当前章节高亮跟随且自动滚入可视区；点击目录项跳转正常且不被滚动高亮回拉；长文档滚动无明显卡顿
  - 验证结论：pending
  - 下一阶段：Phase 3

- [2026-08-10] Phase 2 -> done
  - 本轮完成：用户确认 Phase 2 开发验收完成并推送（commit `7a71267 完成Phase 2`），编辑器联动三项全部通过
  - 待人工验证：无
  - 验证结论：pass
  - 下一阶段：Phase 3

- [2026-08-10] Phase 3 -> waiting_validation
  - 本轮完成：布局与持久化落地——新增 `UserDefaultsManagement.editorTOCVisible / editorTOCWidth` 两个持久化项；拖拽 divider 结束后写入 TOC 宽度，启动时 `applySavedEditorTOCState()` 恢复宽度与显隐；`setEditorTOCVisible` 增加 `saveState` 参数，仅用户主动切换（Cmd+5 / 布局轮换）持久化，预览/演示/PPT 的瞬态隐藏不写偏好，退出时按保存值恢复；`toggleTOC:` 改为按模式路由（编辑/分屏切原生目录，纯预览/演示保留 preview TOC，PPT 禁用），`validateMenuItem` 同步调整；进入纯预览模式隐藏原生目录，恢复时回到用户偏好。移除 `editorTOCPreferredWidth` 镜像，避免拖拽后被旧值回写。macOS Debug build 通过
  - 待人工验证：重启后 TOC 宽度与显隐状态可恢复；拖拽第 2/第 3 条 divider 后重启仍保留宽度；Cmd+5 在编辑/分屏切换原生目录、纯预览切换 preview TOC、PPT 下不可用；菜单可用性与上述一致；进入/退出预览与演示模式后 TOC 显隐回到用户偏好
  - 验证结论：pending
  - 下一阶段：Phase 4

- [2026-08-10] Phase 3 -> done（含暂缓问题）
  - 本轮完成：人工验证反馈——目录宽度重启后能保留记忆；目录隐藏后重启仍会显示（已知问题）。用户指示该问题先忽略，继续 Phase 4 开发；宽度持久化与 Cmd+5 菜单路由按可接受处理
  - 待人工验证：无（遗留问题另行处理）
  - 验证结论：pass（遗留：`editorTOCVisible` 重启恢复不生效，暂缓）
  - 下一阶段：Phase 4

- [2026-08-10] Phase 4 -> waiting_validation
  - 本轮完成：打磨与收尾落地——`EditorTOCView` 新增空状态文案（无标题时居中显示“暂无标题”，含 zh-Hans/zh-Hant/ja/es 四种本地化）；长标题单行截断基础上补 tooltip 显示完整标题；多模式行为核对（编辑/分屏可显示并联动、纯预览瞬态隐藏并恢复、PPT 禁用，Cmd+5 路由与 `validateMenuItem` 与 Phase 3 一致）；macOS Debug build 通过
  - 待人工验证：无标题文档目录栏显示空状态文案；长标题悬停显示完整 tooltip；编辑 / 分屏 / 纯预览 / PPT 四种模式行为一致；回归确认目录刷新、点击跳转、滚动高亮、宽度拖拽无退化
  - 验证结论：pending
  - 下一阶段：全部阶段完成（验证通过后将总状态标记为完成）

- [2026-08-10] Phase 4 -> in_progress
  - 本轮完成：修复"预览模式下原生目录可见且点击无跳转"——根因是 `editorMode` 跨启动持久化（`defaults` 中为 `preview`），App 重启直接处于预览模式而 `enablePreview()` 未执行，原生目录按编辑态偏好显示，点击跳转到的是隐藏的编辑器所以无效果。修复：`applySavedEditorTOCState()` 改为按当前会话模式计算显隐（预览/演示/PPT 一律隐藏，忽略保存偏好）；`setEditorTOCVisible(true)` 增加模式守卫，预览族模式下禁止显示原生目录（覆盖布局轮换、笔记列表重显等路径）。macOS Debug build 通过
  - 待人工验证：退出时停留在预览模式，重启后原生目录保持隐藏；预览模式下任何操作（Cmd+1 布局轮换、显示笔记列表）都不会再让原生目录出现；编辑/分屏模式显隐与 Cmd+5 行为无回归
  - 验证结论：pending
  - 下一阶段：Phase 4（验证通过后标记完成）

- [2026-08-15] Phase 5 -> waiting_validation
  - 本轮完成：目录折叠/展开落地——`EditorTOCView` 内部把扁平标题数组按层级建成树，有子标题的行显示 chevron 折叠按钮，点击后隐藏/显示整个子树；折叠中的章节滚动高亮自动落到最近可见父级；折叠状态以 `level:title` 为键在文本刷新间保留，标题删除后自动清理；改动全部收敛在 `EditorTOCView`，不涉及 ViewController / EditorSplitView / 解析器。macOS Debug build 通过
  - 待人工验证：有子标题的行出现折叠箭头；点击可折叠/展开且子标题隐藏/恢复；折叠后滚动编辑器，当前章节高亮仍正确；点击跳转、滚动高亮、debounce 刷新、宽度拖拽无回归
  - 验证结论：pending
  - 下一阶段：Phase 5（验证通过后标记完成）

- [2026-08-15] Phase 5 -> done
  - 本轮完成：用户确认 Phase 5 人工验收通过，折叠/展开功能完成
  - 待人工验证：无
  - 验证结论：pass
  - 下一阶段：全部阶段完成

- [2026-08-15] Phase 5 后记 -> 修复
  - 本轮完成：修复"打开 md 文件后原生目录要过一会才显示"。根因：内容未加载时 `fill(note:)` 走异步加载，调用方在 `fill` 返回后立即调 `refreshEditorTOC()`，解析到的是旧/空缓冲；异步加载完成后 `publishStorage` 直接替换 storage，不经过 `didChangeText`，因此 `textDidChange` 的 debounce 刷新不会触发，目录只能等启动流程 0.2s 的兜底刷新才出现。修复：在 `fill(note:)` 异步分支的 `applyNoteContent` 之后、内容真正写入缓冲时立刻重建目录（面板可见时）。解析耗时基准：5600 行 / 600 标题约 27ms，非瓶颈。macOS Debug build 通过
  - 待人工验证：打开一个内容未缓存的 md 文件，目录应随内容加载完成立即出现，不再滞后
  - 验证结论：pending
  - 下一阶段：待人工确认后收尾

- [2026-08-15] 布局 -> 拖拽折叠吸附
  - 本轮完成：分栏拖拽吸附——笔记列表与目录栏支持拖到最左贴边消失（阈值 20px），与项目栏拖拽行为一致；只折叠当前栏，不联动项目栏。实现：`EditorSplitView.constrainSplitPosition` 对 divider 0（笔记列表）与 divider 1（目录）增加吸附返回折叠位置；`finishDividerDragIfNeeded` 在拖拽结束后落隐藏态（目录隐藏避免 `configureTOCColumnIfNeeded` 复活零宽栏）；新增 `Theme.Metrics.tocCollapseSnapWidth=20`，`noteListCollapseSnapWidth` 改为 20 并接线；`setNotelistVisible` 改为 internal 供 EditorSplitView 调用。macOS Debug build 通过
  - 待人工验证：拖 divider 0 / divider 1 到最左约 20px 内松手，笔记列表/目录应完全贴边消失；项目栏保持不动；Cmd+2 / Cmd+5 可恢复显示；正常拖宽、宽度持久化无回归
  - 验证结论：pending
  - 下一阶段：待人工确认后收尾

- [2026-08-15] 布局 -> 拖拽折叠吸附（修复无效问题）
  - 本轮完成：首版“没有任何效果”的根因——NSSplitView 拖拽最小坐标未放开，拖拽过程中 proposed 位置到不了 20px 吸附区（栏位停在约 60-80px 窄条），且 `constrainSplitPosition` 返回 0 也会被最小坐标钳回。修复：`EditorSplitView` 实现 `splitView(_:constrainMinCoordinate:ofSubviewAt:)`，divider 0 下限放开为 0、divider 1 下限放开为折叠位置（零宽目录位置）；吸附与拖拽结束落隐藏态逻辑保持不变。macOS Debug build 通过
  - 待人工验证：务必使用 DerivedData 的新 Debug 构建（`/Applications` 里的旧版不会包含此改动），拖第 2/3 条 divider 到最左，笔记列表/目录应贴边消失
  - 验证结论：pending
  - 下一阶段：待人工确认后收尾

- [2026-08-15] 布局 -> 第 3 / 4 条线吸附优化
  - 本轮完成：第 3 条线（目录↔编辑器）之前吸附无效的根因是拖拽路径里存在“最小 100px 钳制”，proposed 到不了吸附区；改为拖拽时镜像第 2 条线（无粘滞最小宽度，平滑拖入 20px 吸附区，松手未达吸附区由 `configureTOCColumnIfNeeded` 收回 100px，不会残留细条）。第 4 条线（编辑器↔预览）原来有 200px 最小宽度下限，拖不到边缘；`EditorContentSplitView` 放开拖拽下限（左 0 / 右 bounds-width），`constrainSplitPosition` 增加 20px 双向吸附，`mouseUp` 时落到 `.previewOnly` / `.editorOnly` 干净状态。macOS Debug build 通过
  - 待人工验证：拖第 3 条线到最左目录贴边消失、编辑器贴左；拖第 4 条线到最左编辑器消失（预览全屏）或最右预览消失（编辑器全屏）；恢复显示走 Cmd+2 / Cmd+5 / 分屏切换，无回归
  - 验证结论：pending
  - 下一阶段：待人工确认后收尾

- [2026-08-15] 布局 -> 修复 TOC 折叠拖拽接力误伤笔记列表
  - 本轮完成：运行时日志确认——divider 1 拖到 TOC 归零后，NSSplitView 会把同一拖拽手势“接力”到 divider 0（零宽面板 pass-through），继续拖就把笔记列表也折叠了。修复：TOC 吸附折叠时置位 `didSnapTOCThisDrag`，同一手势内 divider 0 被锁在当前宽度（`constrainSplitPosition` 直接返回笔记列表当前宽度），松手时统一落隐藏态并复位标志；笔记列表不再被误折叠，新的 divider 0 拖拽不受影响。macOS Debug build 通过
  - 待人工验证：拖第 3 条线到最左，目录贴边消失、笔记列表保持不动；再拖第 2 条线，笔记列表仍可正常折叠/恢复；Cmd+5 恢复目录无回归
  - 验证结论：pending
  - 下一阶段：待人工确认后收尾

- [2026-08-15] 布局 -> 目录折叠改为可拖拽窄手柄
  - 本轮完成：上一版把 TOC 折叠到 0 并在松手后隐藏，导致折叠态没有任何可拖拽的分隔线，无法向右重新展开（日志与截图确认 divider 0/1 被锁死）。修复：TOC 拖拽折叠不再归零，而是停在 `TOCConstraints.collapsedWidth=14` 的可见窄条——保留可拖拽的 divider，向右拖动即重新展开（新增 `isTOCCollapsedByDrag` 防止 `configureTOCColumnIfNeeded` 在窗口缩放时把窄条撑回 100px；宽度持久化跳过折叠宽度；吸附仅向左触发，向右直接展开）。笔记列表仍受同一手势保护。macOS Debug build 通过
  - 待人工验证：拖第 3 条线到最左，目录停在约 14px 窄条且笔记列表不动；向右拖窄条右侧的线，目录能重新展开；Cmd+5 仍可完全隐藏/显示目录；窗口缩放不会把折叠窄条撑开
  - 验证结论：pending
  - 下一阶段：待人工确认后收尾

- [2026-08-15] 布局 -> 拖拽吸附功能整体回退
  - 本轮完成：用户评估后决定撤回整条“分栏拖拽吸附/贴边折叠”功能（第 2/3/4 条线），理由是多条线吸附交互不符合主流编辑器习惯；相关改动（`EditorSplitView` / `EditorScrollView` / `ViewController+Layout` / `Theme` 常量与调试日志）已全部回退，工作区干净。分栏行为恢复为原始状态：TOC 拖拽宽度 100~260 钳制、编辑器/预览最小 200px、笔记列表吸附常量未接线。仅保留“打开 md 文件后原生目录显示延迟”修复（commit `4e0a7c9`，`EditTextView.swift`）
  - 结论：discarded
  - 下一阶段：无（功能不再沿用）

- [2026-08-16] 快捷键 -> Cmd+6 拆分
  - 本轮完成：用户要求原生目录不与预览 TOC 冲突——`Cmd+5`（Toggle TOC）还原为预览 WebView 目录（`toggleTOC:` 直接调用 `editArea.markdownView?.toggleTOC()`）；新增 `Cmd+6`（Toggle Native TOC，`toggleNativeTOC:`）切换原生编辑区目录。同步改动：storyboard 新增菜单项、EditTextView / EditorMenuManager 转发链、`validateMenuItem` 可用性（Cmd+5：preview 存在且非 PPT；Cmd+6：非演示/PPT 且三栏结构）、四种语言 `Main.strings` 文案。macOS Debug build 通过
  - 待人工验证：编辑/分屏下 Cmd+6 切换原生目录、Cmd+5 切换预览目录；预览模式下 Cmd+5 生效、Cmd+6 可用性符合预期；PPT 下两者禁用；菜单标题本地化正常
  - 验证结论：pending
  - 下一阶段：待人工确认后收尾

- [2026-08-17] 布局 -> 全部栏位布局持久化
  - 本轮完成：重启后只记住第 2/3 栏（笔记列表宽度、目录宽度与显隐），现补齐全部栏位——第 1 栏（项目栏）与第 2 栏（笔记列表）的显隐新增 `sidebarVisible` / `notelistVisible` 持久化，并在启动时由新增 `restorePanelLayout()` 统一恢复宽度与显隐；演示/PPT 进入时的瞬态隐藏改为 `collapseNotelist(saveState: false)`，不再覆盖用户偏好；第 4/5 栏（编辑/预览）分屏比例与显隐沿用既有 `editorContentSplitPosition` + `splitViewMode` 恢复。macOS Debug build 通过
  - 待人工验证：调整各栏宽度/显隐（含第 1、4、5 栏）后重启，全部布局应恢复；演示/PPT 进出不影响用户显隐偏好
  - 验证结论：pending
  - 下一阶段：待人工确认后收尾

- [2026-08-17] 布局 -> 单文件 single mode 打开 md 默认 5 栏
  - 本轮完成：用户最终确认真正问题不是“普通启动默认布局”，而是双击单个 `.md` 文件进入 single mode 时界面被拉成 5 栏。根因定位到 `application(_:open:) -> openNotes(urls:) -> reloadForSingleMode() -> configureNotesList()` 链路中，单文件分支显式调用了 `showSidebar("")`，联动展开 sidebar + notelist，再叠加 TOC、editor、preview 形成 5 栏。修复：单文件 single mode 不再调用 `showSidebar("")`，改为应用单独的 `TOC + 编辑 + 预览` 三栏布局，并把 editor / preview split 比例重置为 50/50。用户已人工确认“双击 md 文件后布局稳定”
  - 待人工验证：无
  - 验证结论：pass
  - 下一阶段：收尾记录，相关排障结论已同步到 `docs/project-pitfalls-log.md`

## 14. 分阶段实施计划

### Phase 1: MVP 骨架

目标：做出最小可运行版本，但只覆盖最核心路径。

本阶段范围：

1. 新增 `EditorTOCItem`
2. 新增 `EditorTOCParser`
3. 新增 `EditorTOCView`
4. Storyboard 给 `EditorSplitView` 增加第三栏容器
5. `ViewController` 绑定目录 UI
6. 读取当前 note 文本并生成目录
7. 点击目录项跳转到编辑器标题

本阶段不做：

- 不做滚动高亮
- 不做 debounce 刷新
- 不做宽度持久化
- 不做复杂空状态

本阶段完成标准：

- 编辑模式下能看到第三栏目录
- 能正确列出标题
- 点击能准确跳转

本阶段当前状态（2026-07-29）：

- 正确修复基线文件：`Views/EditorSplitView.swift`
- divider 拖拽根因已定位并修复：`setHoldingPriority(.defaultHigh)`(750) 高于 AppKit divider 拖拽优先级(490/510)，导致 Auto Layout split view 拒绝通过拖拽改变第 1 / 第 2 栏宽度
- 附带修复：TOC 拖拽上限与 `maxWidth`(260) 口径对齐，避免拖宽后松手回弹
- 等待人工验证通过后方可进入 Phase 2

本阶段结束动作：

- 停止继续开发
- 通知人工手动验证
- 将本阶段状态改为 `waiting_validation`

### Phase 2: 编辑器联动

目标：让目录与编辑器状态联动，但不引入布局持久化改造。

本阶段范围：

1. 文本变化后 debounce 刷新目录
2. 编辑器滚动时高亮当前标题
3. 高亮项自动滚入可视区

本阶段不做：

- 不做 split 宽度持久化
- 不做菜单路由重构
- 不做空状态与 tooltip 打磨

本阶段完成标准：

- 文本变更后目录能稳定刷新
- 滚动编辑器时高亮准确
- 长文档下无明显卡顿

本阶段当前状态（2026-08-10）：

- 文本变化 debounce 刷新已接入 `textDidChange`（180ms），换 note 走 `refreshEditorTOC()` 立即刷新并取消挂起任务
- 编辑区 clip view 滚动观察已接入，60ms 节流后按“可视区顶部最近一个标题”更新高亮
- `EditorTOCView.setHighlightedIndex` 负责高亮与自动滚入可视区，程序化选中不会触发点击跳转
- macOS Debug build 通过，等待人工验证

本阶段结束动作：

- 停止继续开发
- 通知人工手动验证
- 将本阶段状态改为 `waiting_validation`

### Phase 3: 布局与持久化

目标：补齐第三栏作为正式面板所需的布局能力。

本阶段范围：

1. 宽度持久化
2. 显示状态持久化
3. `EditorSplitView` 第二个 divider 行为
4. `toggleTOC:` 在编辑/分屏模式下切换原生目录
5. `validateMenuItem(_:)` 可用性规则调整

本阶段不做：

- 不做空状态 polish
- 不做长标题 tooltip
- 不做全量回归收尾

本阶段完成标准：

- 重启应用后目录宽度和显隐状态可恢复
- 编辑 / 分屏 / 纯预览 / PPT 下的菜单行为符合预期

本阶段当前状态（2026-08-10）：

- 宽度持久化：`UserDefaultsManagement.editorTOCWidth`，divider 拖拽结束时写入，启动时恢复
- 显隐持久化：`UserDefaultsManagement.editorTOCVisible`，仅用户主动切换写入；预览/演示/PPT 的瞬态隐藏与恢复不写偏好
- `EditorSplitView` 第二个 divider：拖拽宽度夹取到 100~260 后持久化，`preferredTOCWidth` 为唯一宽度源（移除 `editorTOCPreferredWidth` 镜像）
- `toggleTOC:` 按模式路由：编辑/分屏切原生目录，纯预览/演示保留 preview TOC，PPT 禁用；`validateMenuItem` 同步调整
- 纯预览模式进入时隐藏原生目录，退出时按持久化偏好恢复
- macOS Debug build 通过，等待人工验证

本阶段结束动作：

- 停止继续开发
- 通知人工手动验证
- 将本阶段状态改为 `waiting_validation`

### Phase 4: 打磨与收尾

目标：做最终体验收尾，并完成统一回归。

本阶段范围：

1. 空状态 UI
2. 长标题截断与 tooltip
3. 统一编辑 / 分屏 / 纯预览 / PPT 行为
4. 回归验证与文档收尾

本阶段完成标准：

- 无明显视觉毛刺和错位
- 多模式行为一致
- 文档与实现状态同步

本阶段当前状态（2026-08-10）：

- 空状态 UI：`EditorTOCView` 无标题时居中显示空状态文案，四种语言已本地化
- 长标题 tooltip：单元格单行截断基础上设置 `toolTip` 为完整标题
- 多模式行为：编辑/分屏可显示并联动，纯预览瞬态隐藏、退出恢复，PPT 禁用；Cmd+5 路由与菜单可用性与 Phase 3 一致
- 修复：重启后恢复预览/演示/PPT 模式时，原生目录按模式规则隐藏（`applySavedEditorTOCState` 模式感知 + `setEditorTOCVisible` 模式守卫），不再出现"预览模式下原生目录可见但点击无跳转"
- macOS Debug build 通过，等待人工验证

本阶段结束动作：

- 通知人工手动验证
- 验证通过后将总状态标记为完成

### Phase 5: 目录折叠/展开

目标：让原生目录支持按层级折叠/展开。

本阶段范围：

1. `EditorTOCView` 内部将扁平标题数组按层级建成树
2. 有子标题的行显示 chevron 折叠按钮，点击折叠/展开整个子树
3. 折叠状态下滚动高亮落到最近可见父级
4. 折叠状态在文本刷新间保留（键：`level:title`），标题删除后自动清理

本阶段不做：

- 不跨重启持久化折叠状态
- 不改 `ViewController` / `EditorSplitView` / `EditorTOCParser`

本阶段完成标准：

- 有子标题的行出现折叠箭头，点击可折叠/展开
- 折叠后子标题隐藏，再次展开恢复
- 滚动高亮、点击跳转、debounce 刷新、宽度拖拽无回归

本阶段当前状态（2026-08-15）：

- 代码已落地，改动仅限 `Views/EditorTOCView.swift`
- macOS Debug build 通过，等待人工验证

## 15. 风险点

1. 不要破坏 `EditorContentSplitView` 既有的 editor / preview 切换逻辑
2. 不要让目录解析与高亮共享同一条高频热路径
3. 不要从 preview DOM 反推编辑器位置
4. 不要遗漏 `project.pbxproj` 的 4 处注册
5. 不要新增冲突快捷键
6. 不要把 frontmatter / fenced code block 里的伪标题收进目录
7. 不要在文本快速切换 note 时发生旧目录回写新页面

## 16. 验收标准

满足以下条件才可认为功能完成：

1. 编辑模式下出现第三栏目录
2. 分屏模式下第三栏仍存在，位于编辑器左侧
3. 点击目录项，编辑器准确跳转到对应标题
4. 滚动编辑器时，目录高亮跟随
5. 长文档下无明显卡顿或主线程阻塞
6. 纯预览 / PPT 模式不出现错误行为
7. 重启后目录宽度和显示状态可恢复

## 17. 开发执行清单

后续正式开发时，不再按“大串任务”一次做完，而是按阶段执行：

### 进入任何阶段前

- [ ] 先看“阶段状态看板”，确认当前应执行的阶段
- [ ] 确认上一个阶段已经人工验证通过
- [ ] 只读取当前阶段所需文件，不跨阶段提前实现

### Phase 1 清单

- [x] 先读 `Controllers/ViewController.swift`
- [x] 再读 `Controllers/ViewController+Editor.swift`
- [x] 再读 `Views/EditorSplitView.swift`
- [x] 确认 `EditorContentSplitView` 的创建与切换边界
- [x] 实现 `EditorTOCItem`
- [x] 实现 `EditorTOCParser`
- [x] 实现 `EditorTOCView`
- [x] 修改 storyboard 增加 TOC 容器
- [x] 在 `ViewController` 中完成 outlet 绑定与初始化
- [x] 打通目录点击跳转
- [x] 修复第 2 / 第 3 条 divider 无法左右拖拽
- [x] 停止，等待人工验证

### Phase 2 清单

- [x] 增加文本变化 debounce 刷新
- [x] 增加滚动高亮
- [x] 增加高亮项自动滚入可视区
- [ ] 停止，等待人工验证

### Phase 3 清单

- [x] 增加宽度与显示状态持久化
- [x] 改造 `toggleTOC:` 与 `validateMenuItem(_:)`
- [x] 更新 `EditorSplitView` divider 行为
- [x] 手工补齐 `project.pbxproj`（本轮无新增文件，无需注册）
- [ ] 停止，等待人工验证

### Phase 4 清单

- [x] 空状态 UI
- [x] 长标题截断与 tooltip
- [x] 统一多模式行为
- [x] 运行 macOS Debug build
- [ ] 手动验证编辑 / 分屏 / 纯预览 / PPT 四种模式

## 18. 给执行型 AI 的提示词

```text
请为 MiaoYan 实现“编辑区原生目录栏”，位置在笔记列表右侧、编辑器左侧。

强约束：
1. 不要改成 WebView 目录；目录必须来源于编辑器文本。
2. 不要把目录塞进 EditorContentSplitView；目录应该加在 EditorSplitView 这一层。
3. 目录在编辑模式和分屏模式都可用；PPT 模式禁用。
4. 先做 MVP：标题解析、目录展示、点击跳转。
5. 标题解析要支持 ATX + Setext，排除 frontmatter 和 fenced code block。
6. 点击目录项后，编辑器光标跳到对应字符位置，并滚动到可见区域。
7. 新增 Swift 文件后，务必手工更新 MiaoYan.xcodeproj/project.pbxproj 的 4 处 target membership。
8. 新增代码请写详细注释。
9. 先做最小可运行版本，再补滚动高亮和 debounce 刷新。

优先阅读文件：
- Controllers/ViewController.swift
- Controllers/ViewController+Editor.swift
- Views/EditorSplitView.swift
- Views/EditorScrollView.swift
- Views/EditTextView.swift
- Helpers/NotesTextProcessor.swift
- Resources/Localization/Base.lproj/Main.storyboard

目标交付：
- 新增 EditorTOCParser / EditorTOCView
- Storyboard 第三栏目录容器
- toggleTOC: 在编辑/分屏模式下切换原生目录
- 文本变化后刷新目录
- 点击目录跳转
```

## 19. 文档维护规则

后续如果实现路径发生变化，应优先更新本文档，再继续开发，保证本文档始终是“目录栏开发”的单一真理来源。

同时新增两条维护规则：

1. 每个阶段结束时，必须更新“阶段状态看板”和“状态记录日志”
2. 未经人工验证通过，不得把下一阶段标记为 `in_progress`
