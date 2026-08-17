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
    private var draggingDividerIndex: Int?
    private var dividerDragMonitor: Any?
    var preferredTOCWidth: CGFloat = TOCConstraints.preferredWidth

    override func currentDividerColor() -> NSColor {
        isDividerHidden ? .clear : Theme.splitDividerColor
    }

    override func awakeFromNib() {
        super.awakeFromNib()
        applyPersistedTOCWidthIfNeeded()
        applyDragFriendlyHoldingPriorities()
        configureTOCColumnIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            if let monitor = dividerDragMonitor {
                NSEvent.removeMonitor(monitor)
                dividerDragMonitor = nil
            }
            isUserDraggingDivider = false
            draggingDividerIndex = nil
            return
        }
        applyPersistedTOCWidthIfNeeded()
        applyDragFriendlyHoldingPriorities()
        configureTOCColumnIfNeeded()
    }

    /// `preferredTOCWidth` 默认是 140，storyboard 里 TOC 却是 200。
    /// 必须在第一次 `configureTOCColumnIfNeeded` 之前读出持久化宽度，
    /// 否则启动布局会把用户拖过的宽度弹回默认值。
    private func applyPersistedTOCWidthIfNeeded() {
        let savedWidth = UserDefaultsManagement.editorTOCWidth
        guard savedWidth > 0 else { return }
        preferredTOCWidth = min(max(savedWidth, TOCConstraints.minWidth), TOCConstraints.maxWidth)
    }

    /// 三栏 holding priority 必须低于 AppKit 的 divider 拖拽优先级
    /// (dragThatCannotResizeWindow = 490 / dragThatCanResizeWindow = 510)。
    /// 本 split view 是 Auto Layout 驱动的（EditorView 关闭了 autoresizing 转换），
    /// 一旦某栏 holding priority 高于拖拽优先级，布局引擎会判定该栏"不可因拖拽改宽"，
    /// 相邻 divider 就完全拖不动（此前 .defaultHigh = 750 正是第 2 / 第 3 条 divider 卡死的根因）。
    /// 目录栏略高于笔记列表，避免启动布局在上限附近把 TOC 和笔记列表各挤掉几像素。
    /// 编辑器栏保持最低优先级，窗口缩放时由它吸收宽度变化。
    private func applyDragFriendlyHoldingPriorities() {
        guard subviews.count >= 3 else { return }
        setHoldingPriority(NSLayoutConstraint.Priority(260), forSubviewAt: 0)
        setHoldingPriority(NSLayoutConstraint.Priority(400), forSubviewAt: 1)
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

    func splitView(_ splitView: NSSplitView, shouldAdjustSizeOfSubview view: NSView) -> Bool {
        guard subviews.count >= 3, view === subviews[1] else { return true }
        if isAdjustingTOCColumn || view.isHidden {
            return true
        }
        if isUserDraggingDivider && draggingDividerIndex == 1 {
            return true
        }
        // Keep the persisted TOC width when the window / note list resizes.
        // Equal holding priorities used to let the note list steal a couple of
        // points from a max-width TOC on every launch layout pass.
        return preferredTOCWidth > availableTOCMaxWidth + 1
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        // Persist widths only while the user is actively dragging a divider.
        // Programmatic layout (startup, window resize, `setPosition`) also
        // posts this notification, and saving then would overwrite the stored
        // widths with pre-restore values.
        if isUserDraggingDivider {
            saveDividerWidths()
        } else {
            configureTOCColumnIfNeeded()
        }
        applyDividerColor()
        AppContext.shared.viewController?.viewDidResize()
    }

    func splitViewWillResizeSubviews(_ notification: Notification) {
        if isCurrentEventUserDividerDrag {
            beginDividerDragIfNeeded(
                dividerIndex: (notification.userInfo?["NSSplitViewDividerIndex"] as? NSNumber)?.intValue
            )
        }
        if let vc = AppContext.shared.viewController {
            vc.editArea.updateTextContainerInset()
        }
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        finishDividerDragIfNeeded()
    }

    private var isCurrentEventUserDividerDrag: Bool {
        guard let event = NSApp.currentEvent else { return false }
        switch event.type {
        case .leftMouseDown, .leftMouseDragged:
            return true
        default:
            return false
        }
    }

    private func beginDividerDragIfNeeded(dividerIndex: Int?) {
        if let dividerIndex {
            draggingDividerIndex = dividerIndex
        }
        guard !isUserDraggingDivider else { return }
        isUserDraggingDivider = true
        guard dividerDragMonitor == nil else { return }
        dividerDragMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            DispatchQueue.main.async {
                self?.finishDividerDragIfNeeded()
            }
            return event
        }
    }

    private func finishDividerDragIfNeeded() {
        guard isUserDraggingDivider else { return }
        isUserDraggingDivider = false
        if let monitor = dividerDragMonitor {
            NSEvent.removeMonitor(monitor)
            dividerDragMonitor = nil
        }
        saveDividerWidths()
        draggingDividerIndex = nil
        configureTOCColumnIfNeeded()
        applyDividerColor()
    }

    /// Persists the current note-list and TOC widths to UserDefaults. Called
    /// on every live divider-drag resize (and once more on mouse-up), so the
    /// layout survives relaunch even if the drag never reaches this view's
    /// `mouseUp` handler.
    private func saveDividerWidths() {
        let draggedDivider = draggingDividerIndex

        if draggedDivider != 1, let vc = AppContext.shared.viewController {
            let notelistWidth = vc.splitView.subviews[0].frame.width
            if notelistWidth >= Theme.Metrics.noteListMinimumWidth {
                UserDefaultsManagement.sidebarSize = Int(notelistWidth)
            }
        }

        guard draggedDivider != 0 else { return }
        guard subviews.count >= 3, subviews[1].isHidden == false else { return }
        let tocWidth = subviews[1].frame.width
        guard tocWidth > Theme.Metrics.collapsedSplitWidthEpsilon else { return }
        preferredTOCWidth = min(max(tocWidth.rounded(), TOCConstraints.minWidth), TOCConstraints.maxWidth)
        UserDefaultsManagement.editorTOCWidth = preferredTOCWidth
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

    private var availableTOCMaxWidth: CGFloat {
        guard subviews.count >= 3 else { return TOCConstraints.maxWidth }
        let noteListWidth = subviews[0].isHidden ? 0 : subviews[0].frame.width
        return max(
            TOCConstraints.minWidth,
            bounds.width - noteListWidth - TOCConstraints.minEditorWidth - (dividerThickness * 2)
        )
    }

    private var maxTOCDividerPosition: CGFloat {
        guard subviews.count >= 3 else { return bounds.width }
        // 与 configureTOCColumnIfNeeded 的上限口径保持一致：
        // 拖拽时直接停在 TOC 最大宽度处，避免松手后被回弹截断。
        let base = subviews[0].frame.width + dividerThickness
        let maxTOCWidth = min(TOCConstraints.maxWidth, availableTOCMaxWidth)
        return max(minTOCDividerPosition, base + maxTOCWidth)
    }

    private func clampedTOCWidth(_ width: CGFloat) -> CGFloat {
        let preferred = min(max(width, TOCConstraints.minWidth), TOCConstraints.maxWidth)
        let available = min(TOCConstraints.maxWidth, availableTOCMaxWidth)
        // 1pt slack absorbs divider / backing-scale rounding so a max-width
        // TOC is not ratcheted down a couple of points on every launch pass.
        if preferred <= available + 1 {
            return preferred
        }
        return available
    }

    private func configureTOCColumnIfNeeded() {
        guard subviews.count >= 3, !isAdjustingTOCColumn else { return }
        guard subviews[1].isHidden == false else { return }
        guard bounds.width > TOCConstraints.minEditorWidth + TOCConstraints.minWidth else { return }

        let currentTOCWidth = subviews[1].frame.width
        let targetTOCWidth = clampedTOCWidth(preferredTOCWidth)

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
            setPosition(collapsePosition + clampedTOCWidth(preferredTOCWidth), ofDividerAt: 1)
        } else {
            tocView.isHidden = true
            setPosition(collapsePosition, ofDividerAt: 1)
        }

        applyDividerColor()
    }
}
