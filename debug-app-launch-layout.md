# Debug Session: app-launch-layout
- **Status**: [OPEN]
- **Issue**: Xcode `Run` 启动后默认三栏布局稳定，但安装到 `Applications` 后冷启动会被改成错误布局；预期是每次启动都固定 `TOC + 编辑 + 预览`。
- **Debug Server**: http://127.0.0.1:7777/event
- **Log File**: .dbg/trae-debug-log-app-launch-layout.ndjson

## Reproduction Steps
1. 构建并安装 `MiaoYan.app` 到 `Applications`
2. 完全退出 App
3. 从 `Applications` 重新打开
4. 观察启动后第一栏、第二栏是否被重新展开，以及编辑/预览是否仍为默认三栏

## Hypotheses & Verification
| ID | Hypothesis | Likelihood | Effort | Evidence |
|----|------------|------------|--------|----------|
| A | 启动后某条业务恢复链再次调用 `showSidebar` / `showNoteList` 或对应 setter，把默认三栏覆盖掉 | High | Low | Pending |
| B | `ensureInitialProjectSelection -> outlineViewSelectionDidChange -> updateTable` 的异步链路在安装版更晚完成，并在完成后改写布局 | High | Medium | Pending |
| C | AppKit / NSWindow 的恢复链仍在安装版生效，导致外层布局被旧窗口状态回放 | Medium | Low | Pending |
| D | 默认三栏本身已正确执行，但后续模式切换逻辑（split/preview/presentation）又把左右栏状态改掉 | Medium | Medium | Pending |
| E | 启动时存在安装版专属的冷启动时序差异，导致同一调用链在 Xcode 与 Applications 的执行顺序不同 | Medium | High | Pending |

## Log Evidence
- `L1` `ViewController.viewDidAppear`: 启动序列开始，`isSingleMode = false`
- `L4` `applyDefaultStartupThreeColumnLayout`: 默认三栏已正确执行，状态为：
  - `sidebarWidth = 0`
  - `isSidebarVisible = false`
  - `isNotelistVisible = false`
  - `isEditorTOCVisible = true`
- `L5-L7` `outlineViewSelectionDidChange -> updateTable completion -> late safeguard`：
  初始项目恢复链执行完成后，布局仍保持默认三栏，没有把第一栏/第二栏重新打开
- `L9-L10` 启动守卫释放前再次重打默认三栏，状态仍正确
- `L11` 更晚出现第二次 `ViewController+Data.updateTable.asyncAfter`：
  - `isSingleMode = true`
  - `isSidebarVisible = true`
  - `isNotelistVisible = true`
  - `sidebarWidth = 211.5`
  - `notelistWidth = 227`
  说明错误布局不是默认三栏失败，而是**启动后更晚的一条 single mode / open file 链路把布局覆盖掉了**
- 第二轮新增证据：
  - `L11` `AppDelegate+URLRoutes.applicationOpenURLs`：`application(_:open:)` 确实收到了一个 `file://...智能履约需求分析.md`
  - `L12` `ViewController.viewDidAppear.consumePendingURLs`：`viewDidAppear` 确实消费了 `appDelegate.urls`
  - `L13` `AppDelegate+URLRoutes.openNotes`：`openNotes(urls:)` 进入了 single mode，且进入时布局已经是错误布局
  - `L14` `ViewController+Data.updateTable.asyncAfter`：此时 `isSingleMode = true`，第一栏/第二栏都已显示

附加状态证据：
- 当前 `defaults read com.tw93.miaoyan isSingleMode` = `1`
- 当前 `singleModePath` 指向：
  `/Users/lawliet/Documents/ObsidianNote/StudyNote/Sleemon/业务/ec/智能履约/智能履约需求分析.md`
- `AppDelegate+URLRoutes.swift` 中 `openNotes(urls:)` 会直接调用 `UserDefaultsManagement.beginSingleMode(for:)`

## Instrumentation Points
- `Controllers/ViewController.swift`
  - `viewDidAppear` 启动序列开始
  - `0.35s` 延迟重打默认三栏后释放启动守卫
- `Controllers/ViewController+Layout.swift`
  - `applyDefaultStartupThreeColumnLayout()`
  - `setSidebarVisible(_:)`
  - `setNotelistVisible(_:)`
- `Views/SidebarProjectView.swift`
  - `outlineViewSelectionDidChange`
  - `updateTable(...)` completion
- `Controllers/ViewController+Data.swift`
  - `updateTable` 后 `0.2s` 的 late safeguard

## Verification Conclusion
| ID | Hypothesis | Status | Evidence Summary |
|----|------------|--------|------------------|
| A | 启动后某条业务恢复链再次调用布局变更，覆盖默认三栏 | ✅ Confirmed | `L11` 显示更晚的一次链路把布局改成 `sidebar + notelist + TOC + ...` |
| B | `ensureInitialProjectSelection -> outlineViewSelectionDidChange -> updateTable` 初始异步链路覆盖布局 | ❌ Rejected | `L5-L7` 执行后布局仍是默认三栏 |
| C | AppKit / NSWindow 恢复链单独导致错误布局 | ⏳ Inconclusive | 不是首个主因信号，日志里真正发生覆盖的是后续业务链 |
| D | split/preview/presentation 模式切换逻辑覆盖布局 | ❌ Rejected | 当前日志没有模式切换信号，且错误发生时关键字段是 `isSingleMode = true` |
| E | 安装版冷启动时序不同，导致更晚链路覆盖布局 | ✅ Confirmed | 安装版里 `L11` 发生在默认三栏和启动守卫释放之后，Xcode run 未观察到该后置覆盖 |

当前最可能根因：
- 安装到 `Applications` 后的冷启动过程中，App 进入了 `single mode`
- 入口大概率是 `AppDelegate.application(_:open:) -> openNotes(urls:) -> UserDefaultsManagement.beginSingleMode(for:)`
- 这条链在默认三栏应用完成之后才落地，最终把布局改坏
- 现已确认不是“推测”，而是运行时证据：第二轮日志直接记录了 `application(_:open:)` 和 `openNotes(urls:)`
