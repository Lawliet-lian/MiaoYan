import Cocoa

@MainActor
class EditorSplitView: ThemedSplitView {
    private enum TOCConstraints {
        static let minWidth: CGFloat = 100
        static let preferredWidth: CGFloat = 140
        static let maxWidth: CGFloat = 260
        static let minEditorWidth: CGFloat = 320
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

    private var minTOCDividerPosition: CGFloat {
        guard subviews.count >= 3 else { return 0 }
        return subviews[0].frame.width + dividerThickness + TOCConstraints.minWidth
    }

    private var maxTOCDividerPosition: CGFloat {
        guard subviews.count >= 3 else { return bounds.width }
        // 与 configureTOCColumnIfNeeded 的上限口径保持一致：
        // 拖拽时直接停在 TOC 最大宽度处，避免松手后被回弹截断。
        let base = subviews[0].frame.width + dividerThickness
        let availableTOCWidth = bounds.width - base - dividerThickness - TOCConstraints.minEditorWidth
        let maxTOCWidth = min(TOCConstraints.maxWidth, availableTOCWidth)
        return max(minTOCDividerPosition, base + maxTOCWidth)
    }

    private func configureTOCColumnIfNeeded() {
        guard subviews.count >= 3, !isAdjustingTOCColumn else { return }
        guard subviews[1].isHidden == false else { return }

        let currentTOCWidth = subviews[1].frame.width
        let availableMaxWidth = max(
            TOCConstraints.minWidth,
            bounds.width - subviews[0].frame.width - TOCConstraints.minEditorWidth - (dividerThickness * 2)
        )
        let maxWidth = min(TOCConstraints.maxWidth, availableMaxWidth)

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

            let availableMaxWidth = max(
                TOCConstraints.minWidth,
                bounds.width - noteListWidth - TOCConstraints.minEditorWidth - (dividerThickness * 2)
            )
            let targetWidth = min(max(TOCConstraints.minWidth, preferredTOCWidth), min(TOCConstraints.maxWidth, availableMaxWidth))
            setPosition(collapsePosition + targetWidth, ofDividerAt: 1)
        } else {
            tocView.isHidden = true
            setPosition(collapsePosition, ofDividerAt: 1)
        }

        applyDividerColor()
    }
}
