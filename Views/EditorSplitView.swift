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
        configureTOCColumnIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureTOCColumnIfNeeded()
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
                preferredTOCWidth = tocWidth
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
        let maxByEditorWidth = bounds.width - TOCConstraints.minEditorWidth - dividerThickness
        return max(minTOCDividerPosition, maxByEditorWidth)
    }

    private func configureTOCColumnIfNeeded() {
        guard subviews.count >= 3, !isAdjustingTOCColumn else { return }
        guard subviews[1].isHidden == false else { return }

        setHoldingPriority(.defaultHigh, forSubviewAt: 0)
        setHoldingPriority(.defaultHigh, forSubviewAt: 1)
        setHoldingPriority(.defaultLow, forSubviewAt: 2)

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
