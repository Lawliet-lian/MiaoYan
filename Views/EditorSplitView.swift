import Cocoa

@MainActor
class EditorSplitView: ThemedSplitView {
    private enum TOCConstraints {
        // 目录栏宽度策略：
        // - 最小宽度保持 180，避免短标题也挤得过窄，与项目长期使用的默认启动宽度对齐
        // - 新增“自适应基准宽度”`sizeToFitWidth`，在打开文件/重建目录时按最长可见标题估算宽度
        // - 最大宽度改为 320（原先 260 偏紧，会把中文 12~15 字以上的长标题截断）
        // - 增加“预览区最小舒适宽度”`minPreviewWidth`，用于和 `minEditorWidth` 同时钳制，
        //   避免 Single Mode 的“TOC + Preview”两栏布局下，目录过宽把预览压得过窄
        static let minWidth: CGFloat = 180
        static let preferredWidth: CGFloat = 180
        static let sizeToFitMaxWidth: CGFloat = 320
        static let maxWidth: CGFloat = 320
        static let minEditorWidth: CGFloat = 320
        static let minPreviewWidth: CGFloat = 480
    }

    public var shouldHideDivider = false
    private var isAdjustingTOCColumn = false
    private var isUserDraggingDivider = false
    var preferredTOCWidth: CGFloat = TOCConstraints.preferredWidth

    override func currentDividerColor() -> NSColor {
        isDividerHidden ? .clear : Theme.splitDividerColor
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        applyDragFriendlyHoldingPriorities()
        configureTOCColumnIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyDragFriendlyHoldingPriorities()
        configureTOCColumnIfNeeded()
    }

    /// 三栏 holding priority 必须低于 AppKit 的 divider 拖拽优先级
    /// (dragThatCannotResizeWindow = 490 / dragThatCanResizeWindow = 510)。
    /// 本 split view 是 Auto Layout 驱动的（EditorView 关闭了 autoresizing 转换），
    /// 一旦某栏 holding priority 高于拖拽优先级，布局引擎会判定该栏"不可因拖拽改宽"，
    /// 相邻 divider 就完全拖不动（此前 .defaultHigh = 750 正是第 2 / 第 3 条 divider 卡死的根因）。
    /// 编辑器栏保持最低优先级，窗口缩放时由它吸收宽度变化。
    private func applyDragFriendlyHoldingPriorities() {
        guard subviews.count >= 3 else { return }
        setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 0)
        setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 1)
        setHoldingPriority(NSLayoutConstraint.Priority(250), forSubviewAt: 2)
    }

    private var isDividerHidden: Bool {
        if subviews.count >= 3 {
            let tocWidth = subviews[1].frame.width
            let isTOCHidden = subviews[1].isHidden || tocWidth <= Theme.Metrics.collapsedSplitWidthEpsilon
            if !isTOCHidden {
                return false
            }
        }

        let notelistWidth = subviews.first?.frame.width ?? 0
        let isNotelistHidden = subviews.first?.isHidden == true
        return shouldHideDivider || isNotelistHidden || notelistWidth <= Theme.Metrics.collapsedSplitWidthEpsilon
    }

    override func minPossiblePositionOfDivider(at dividerIndex: Int) -> CGFloat {
        return 0
    }

    override func maxPossiblePositionOfDivider(at dividerIndex: Int) -> CGFloat {
        if dividerIndex == 0 {
            return 600
        }
        return super.maxPossiblePositionOfDivider(at: dividerIndex)
    }

    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if dividerIndex == 1 {
            if isAdjustingTOCColumn || subviews[1].isHidden {
                return proposedPosition
            }
            return max(minTOCDividerPosition, min(proposedPosition, maxTOCDividerPosition))
        }

        return proposedPosition
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        if !isUserDraggingDivider {
            configureTOCColumnIfNeeded()
        }
        applyDividerColor()
        AppContext.shared.viewController?.viewDidResize()
    }

    func splitViewWillResizeSubviews(_ notification: Notification) {
        if notification.userInfo?["NSSplitViewDividerIndex"] as? NSNumber != nil {
            isUserDraggingDivider = true
        }
        if let vc = AppContext.shared.viewController {
            vc.editArea.updateTextContainerInset()
        }
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        finishDividerDragIfNeeded()
    }

    private func finishDividerDragIfNeeded() {
        guard isUserDraggingDivider else { return }
        isUserDraggingDivider = false

        if let vc = AppContext.shared.viewController {
            let notelistWidth = vc.splitView.subviews[0].frame.width
            if notelistWidth >= Theme.Metrics.noteListMinimumWidth {
                UserDefaultsManagement.sidebarSize = Int(notelistWidth)
            }
        }

        if subviews.count >= 3, subviews[1].isHidden == false {
            let tocWidth = subviews[1].frame.width
            if tocWidth > Theme.Metrics.collapsedSplitWidthEpsilon {
                preferredTOCWidth = min(max(tocWidth, TOCConstraints.minWidth), TOCConstraints.maxWidth)
                // Phase 3: persist the dragged TOC width so it survives relaunch.
                UserDefaultsManagement.editorTOCWidth = preferredTOCWidth
            }
        }

        configureTOCColumnIfNeeded()
        applyDividerColor()
    }

    func splitView(
        _ splitView: NSSplitView,
        effectiveRect proposedEffectiveRect: NSRect,
        forDrawnRect drawnRect: NSRect,
        ofDividerAt dividerIndex: Int
    ) -> NSRect {
        if isVertical {
            return proposedEffectiveRect.insetBy(dx: -6, dy: 0)
        }

        return proposedEffectiveRect.insetBy(dx: 0, dy: -6)
    }

    /// 按当前可用宽度（剩余空间）计算 TOC 合理上限：
    /// - 硬上限 `TOCConstraints.maxWidth`
    /// - 编辑器保留 `TOCConstraints.minEditorWidth`
    /// - 预览保留 `TOCConstraints.minPreviewWidth`
    /// 三条里取最紧的一条，保证“TOC + 预览 / TOC + 编辑 / TOC + 分屏”都不会把右栏压得太窄。
    private func availableTOCMaxWidth() -> CGFloat {
        guard subviews.count >= 3 else { return TOCConstraints.maxWidth }
        let noteListWidth = subviews[0].isHidden ? 0 : subviews[0].frame.width
        let base = noteListWidth + dividerThickness
        let remaining = bounds.width - base - (dividerThickness * 2)
        // 右侧最少要同时容纳编辑器和预览的最小值中的较大者：
        // 在 split / previewOnly / editorOnly 三种布局里，只要比两者最小宽度都能满足，不会出现两栏之一被压崩。
        let rightMinimumReserve = max(TOCConstraints.minEditorWidth, TOCConstraints.minPreviewWidth)
        let clamped = remaining - rightMinimumReserve
        return min(TOCConstraints.maxWidth, max(TOCConstraints.minWidth, clamped))
    }

    private var minTOCDividerPosition: CGFloat {
        guard subviews.count >= 3 else { return 0 }
        return subviews[0].frame.width + dividerThickness + TOCConstraints.minWidth
    }

    private var maxTOCDividerPosition: CGFloat {
        guard subviews.count >= 3 else { return bounds.width }
        let base = subviews[0].frame.width + dividerThickness
        let maxTOCWidth = availableTOCMaxWidth()
        return max(minTOCDividerPosition, base + maxTOCWidth)
    }

    /// 给定“自适应推荐宽度”（来自 TOC 最长可见标题测算），返回夹取后的合法 TOC 宽度。
    /// 这个宽度会在 `EditorSplitView` 允许的上下限内，并且不侵占预览/编辑器的最小宽度。
    func clampedAdaptiveTOCWidth(proposed: CGFloat) -> CGFloat {
        let clampedMax = availableTOCMaxWidth()
        return max(TOCConstraints.minWidth, min(proposed, clampedMax))
    }

    private func configureTOCColumnIfNeeded() {
        guard subviews.count >= 3, !isAdjustingTOCColumn else { return }
        guard subviews[1].isHidden == false else { return }

        let currentTOCWidth = subviews[1].frame.width
        let maxWidth = availableTOCMaxWidth()

        let targetTOCWidth: CGFloat
        if currentTOCWidth <= Theme.Metrics.collapsedSplitWidthEpsilon || currentTOCWidth > maxWidth {
            targetTOCWidth = min(preferredTOCWidth, maxWidth)
        } else {
            targetTOCWidth = max(TOCConstraints.minWidth, min(currentTOCWidth, maxWidth))
        }

        let currentPosition = subviews[0].frame.width + dividerThickness + currentTOCWidth
        let targetPosition = subviews[0].frame.width + dividerThickness + targetTOCWidth
        guard abs(targetPosition - currentPosition) > 0.5 else { return }

        isAdjustingTOCColumn = true
        defer { isAdjustingTOCColumn = false }
        setPosition(targetPosition, ofDividerAt: 1)
    }

    func setTOCVisible(_ visible: Bool) {
        guard subviews.count >= 3, !isAdjustingTOCColumn else { return }

        let noteListWidth = subviews[0].isHidden ? 0 : subviews[0].frame.width
        let tocView = subviews[1]
        let collapsePosition = noteListWidth + dividerThickness

        isAdjustingTOCColumn = true
        defer { isAdjustingTOCColumn = false }

        if visible {
            tocView.isHidden = false

            let maxWidth = availableTOCMaxWidth()
            let targetWidth = min(max(TOCConstraints.minWidth, preferredTOCWidth), maxWidth)
            setPosition(collapsePosition + targetWidth, ofDividerAt: 1)
        } else {
            tocView.isHidden = true
            setPosition(collapsePosition, ofDividerAt: 1)
        }

        applyDividerColor()
    }
}
