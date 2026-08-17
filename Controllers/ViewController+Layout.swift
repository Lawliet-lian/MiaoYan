import Cocoa

// MARK: - Layout Management
extension ViewController {

    // MARK: - Layout Constants
    private enum LayoutConstants {
        static let minSidebarWidth: CGFloat = 138
        static let maxSidebarWidth: CGFloat = 280
        static let defaultNotelistWidth: CGFloat = 280
        static let defaultStartupTOCWidth: CGFloat = 180
        static let narrowThreshold: CGFloat = 50
        static let searchTopSidebarCollapsed: CGFloat = 30.0
        static let searchTopNormal: CGFloat = 13.0
        static let titlebarHeightNormal: CGFloat = 52.0
        static let titleTopNormal: CGFloat = 16.0
        static let titleLeadingNormal: CGFloat = 25.0
        static let titleBarActionsTopNormal: CGFloat = 18.0
        /// Title bar top inset applied in every layout (matching the 2-column
        /// layout) so the top-right buttons sit at a consistent height. In
        /// editor-only layouts it also lets the title clear the macOS traffic
        /// lights, since the editor reaches the far left there.
        static let titleBarTopInset: CGFloat = 10.0
    }

    // MARK: - Properties
    var sidebarWidth: CGFloat {
        guard let splitView = sidebarSplitView,
            !splitView.subviews.isEmpty
        else { return 0 }
        return splitView.subviews[0].frame.width
    }

    var notelistWidth: CGFloat {
        guard !splitView.subviews.isEmpty else { return 0 }
        return splitView.subviews[0].frame.width
    }

    var isSidebarVisible: Bool {
        guard let sidebarView = sidebarSplitView?.subviews.first else { return false }
        return !sidebarView.isHidden && sidebarWidth > Theme.Metrics.collapsedSplitWidthEpsilon
    }

    var isNotelistVisible: Bool {
        guard let noteListView = splitView?.subviews.first else { return false }
        return !noteListView.isHidden && notelistWidth > Theme.Metrics.collapsedSplitWidthEpsilon
    }

    // Internal (not private): `toggleTOC:` in ViewController+Editor.swift
    // needs it to decide between native TOC and preview TOC.
    var isEditorTOCVisible: Bool {
        guard splitView?.subviews.count ?? 0 >= 3 else { return false }
        let tocView = splitView.subviews[1]
        let tocWidth = tocView.frame.width
        return !tocView.isHidden && tocWidth > Theme.Metrics.collapsedSplitWidthEpsilon
    }

    // MARK: - Layout Management Methods
    func checkSidebarConstraint() {
        let isSidebarCollapsed = !isSidebarVisible && !UserDefaultsManagement.isWillFullScreen
        searchTopConstraint.constant = isSidebarCollapsed ? LayoutConstants.searchTopSidebarCollapsed : LayoutConstants.searchTopNormal
    }

    func checkTitlebarTopConstraint() {
        // Title bar metrics are identical across layouts (52pt), per user
        // request: editor-only/narrow layouts previously used taller bars with
        // lower button offsets, which made the top-right buttons shift
        // vertically between layouts.
        titiebarHeight.constant = LayoutConstants.titlebarHeightNormal
        titleTopConstraint.constant = LayoutConstants.titleTopNormal

        updateTitleLeadingInset(LayoutConstants.titleLeadingNormal)
        updateTitleBarActionsTop(LayoutConstants.titleBarActionsTopNormal)
        updateTitleBarTopInset(LayoutConstants.titleBarTopInset)
    }

    private func updateTitleLeadingInset(_ inset: CGFloat) {
        guard let titleLabel, let container = titleLabel.superview else { return }
        for constraint in container.constraints where constraint.firstItem === titleLabel && constraint.firstAttribute == .leading {
            constraint.constant = inset
        }
    }

    private func updateTitleBarActionsTop(_ top: CGFloat) {
        guard let titleBarAdditionalView, let formatButton else { return }

        for constraint in titleBarAdditionalView.constraints {
            let first = constraint.firstItem as? NSView
            let second = constraint.secondItem as? NSView
            guard constraint.firstAttribute == .top,
                constraint.secondAttribute == .top
            else { continue }

            if first === formatButton && second === titleBarAdditionalView {
                constraint.constant = top
            } else if first === titleBarAdditionalView && second === formatButton {
                constraint.constant = -top
            }
        }
    }

    /// Offsets the whole title bar vertically so the top-right buttons stay at
    /// the same height in every layout (and the title clears the traffic
    /// lights when the editor reaches the far left).
    private func updateTitleBarTopInset(_ inset: CGFloat) {
        guard let superview = titleBarView.superview else { return }
        for constraint in superview.constraints
        where constraint.firstItem === titleBarView && constraint.firstAttribute == .top {
            constraint.constant = inset
        }
    }

    // MARK: - Core Panel Operations

    private var isPresentationMode: Bool {
        sessionPresentationMode || sessionMagicPPTMode
    }

    func setSidebarVisible(_ visible: Bool, saveState: Bool = true) {
        if visible, isEnforcingDefaultStartupLayout, !UserDefaultsManagement.isSingleMode {
            return
        }
        let sidebarView = sidebarSplitView.subviews.first
        if visible {
            sidebarView?.isHidden = false
            let savedWidth = UserDefaultsManagement.realSidebarSize
            let targetWidth = max(savedWidth, Int(LayoutConstants.minSidebarWidth))

            if savedWidth < Int(LayoutConstants.minSidebarWidth) {
                UserDefaultsManagement.realSidebarSize = Int(LayoutConstants.minSidebarWidth)
            }

            sidebarSplitView.setPosition(CGFloat(targetWidth), ofDividerAt: 0)
        } else {
            if saveState && !isPresentationMode && sidebarWidth > Theme.Metrics.sidebarCollapseSnapWidth {
                UserDefaultsManagement.realSidebarSize = Int(sidebarWidth)
            }
            sidebarSplitView.setPosition(0, ofDividerAt: 0)
            sidebarView?.isHidden = true
        }
        if saveState {
            UserDefaultsManagement.sidebarVisible = visible
        }
        editArea.updateTextContainerInset()
        sidebarSplitView?.layoutSubtreeIfNeeded()
        (sidebarSplitView as? ThemedSplitView)?.applyDividerColor()
        updateSidebarColumnWidth()
        checkSidebarConstraint()
        updateToolbarButtonTints()
    }

    func ensurePanelsVisibleAtStartup() {
        guard !UserDefaultsManagement.isSingleMode else { return }
        let shouldShowSidebar = isSidebarVisible
        let shouldShowNotelist = isNotelistVisible

        if shouldShowSidebar && !shouldShowNotelist {
            setNotelistVisible(true, saveState: false)
        }

        normalizeNotelistWidth(saveState: false)
    }

    /// Startup is intentionally deterministic now: each launch resets to a
    /// stable default layout instead of replaying the previous session's panel
    /// combination. The default is:
    /// - hide sidebar and note list
    /// - show native TOC with a reasonable fixed width
    /// - force split mode so editor and preview share the remaining width 50/50
    func applyDefaultStartupThreeColumnLayout() {
        guard !UserDefaultsManagement.isSingleMode else { return }

        collapseNotelist(saveState: false)
        UserDefaultsManagement.sidebarVisible = false
        UserDefaultsManagement.notelistVisible = false
        UserDefaultsManagement.editorTOCVisible = true
        splitView.preferredTOCWidth = LayoutConstants.defaultStartupTOCWidth
        setEditorTOCVisible(true, saveState: false)

        UserDefaultsManagement.editorContentSplitPosition = 0
        sessionSplitMode = true
        applyEditorModePreferenceChange()

        view.layoutSubtreeIfNeeded()
        splitView.layoutSubtreeIfNeeded()
        editorContentSplitView?.layoutSubtreeIfNeeded()
    }

    /// Single-file open should start from the same visual baseline as a clean
    /// app launch instead of inheriting the project browser layout. This path
    /// is intentionally transient:
    /// - keep sidebar + note list collapsed
    /// - keep native TOC visible with the default width
    /// - force editor + preview back to a balanced side-by-side split
    ///
    /// We avoid persisting sidebar / note list visibility here because opening
    /// one file from Finder should not rewrite the user's normal library
    /// layout preferences.
    func applySingleFileOpenThreeColumnLayout() {
        collapseNotelist(saveState: false)
        splitView.preferredTOCWidth = LayoutConstants.defaultStartupTOCWidth
        setEditorTOCVisible(true, saveState: false)

        // Reset the content split ratio for this entry path so a previously
        // saved editor-only / uneven split cannot leak into single-file open.
        UserDefaultsManagement.editorContentSplitPosition = 0
        sessionSplitMode = true
        applyEditorModePreferenceChange()

        view.layoutSubtreeIfNeeded()
        splitView.layoutSubtreeIfNeeded()
        editorContentSplitView?.layoutSubtreeIfNeeded()
    }

    /// Restores the user-selected sidebar / note list visibility after the
    /// initial AppKit layout pass has completed. Doing this in `viewDidLoad`
    /// is too early: later split-view sizing and mode setup can overwrite the
    /// restored state and make relaunch look "random".
    func applySavedPanelVisibilityState() {
        guard !UserDefaultsManagement.isSingleMode else { return }

        let shouldShowNotelist = UserDefaultsManagement.notelistVisible
        let shouldShowSidebar = shouldShowNotelist && UserDefaultsManagement.sidebarVisible

        setNotelistVisible(shouldShowNotelist, saveState: false)
        setSidebarVisible(shouldShowSidebar, saveState: false)
    }

    /// Shows or hides the native editor TOC column.
    ///
    /// - Parameter saveState: `true` for user-initiated toggles (Cmd+5,
    ///   layout cycle) so the choice survives relaunch. Transient
    ///   mode-driven changes (entering preview / presentation / PPT and the
    ///   restore on exit) pass `false` so they never clobber the preference.
    func setEditorTOCVisible(_ visible: Bool, saveState: Bool = true) {
        // The native outline is a mode-aware panel: it is fully usable in
        // edit / split / pure preview (preview clicks navigate the preview),
        // but never in presentation or PPT, which are fullscreen slide
        // surfaces with no editor column. This guard covers a relaunch that
        // restores presentation/PPT (EditorStateManager keeps `editorMode`
        // across launches) and any layout-cycle call inside those modes.
        if visible && (sessionPresentationMode || sessionMagicPPTMode) {
            return
        }
        guard splitView.subviews.count >= 3 else { return }

        if visible {
            splitView.subviews[1].isHidden = false
        }

        splitView.setTOCVisible(visible)
        splitView.layoutSubtreeIfNeeded()
        splitView.applyDividerColor()

        // Phase 2: once the panel becomes visible, immediately mark the heading
        // under the editor's current viewport so the outline is in sync from
        // the first frame instead of waiting for the next scroll event.
        if visible {
            updateEditorTOCHighlight()
        }

        // Phase 3: persist only user-initiated visibility changes.
        if saveState {
            UserDefaultsManagement.editorTOCVisible = visible
        }
    }

    /// Phase 3: restores the persisted TOC width and visibility once at
    /// startup, after the default panels have been laid out. Width `0` means
    /// no stored value yet, so the layout's default stays in place.
    func applySavedEditorTOCState() {
        guard splitView.subviews.count >= 3 else { return }

        let savedWidth = UserDefaultsManagement.editorTOCWidth
        if savedWidth > 0 {
            splitView.preferredTOCWidth = savedWidth
        }

        // Mode rule wins over the saved preference only for fullscreen slide
        // surfaces: if the app relaunched into presentation / PPT, the native
        // outline starts hidden. Pure preview restores the user's preference
        // like edit / split, so the outline keeps working across relaunches.
        let restoredInHiddenMode = sessionPresentationMode || sessionMagicPPTMode
        let visible = !restoredInHiddenMode && UserDefaultsManagement.editorTOCVisible
        setEditorTOCVisible(visible, saveState: false)
    }

    private func setNotelistVisible(_ visible: Bool, saveState: Bool = true) {
        if visible, isEnforcingDefaultStartupLayout, !UserDefaultsManagement.isSingleMode {
            return
        }
        let noteListView = splitView.subviews.first
        if visible {
            isRestoringNotelistVisibility = true
            // Phase 3: re-showing the note list restores the user's persisted
            // TOC preference instead of force-showing the outline (a Cmd+5
            // hide would otherwise be undone by a note-list toggle).
            setEditorTOCVisible(UserDefaultsManagement.editorTOCVisible, saveState: false)
            noteListView?.isHidden = false
            let savedWidth = UserDefaultsManagement.sidebarSize
            let fallbackWidth = Int(LayoutConstants.defaultNotelistWidth)
            let targetWidth = max(savedWidth > 0 ? savedWidth : fallbackWidth, Int(Theme.Metrics.noteListMinimumWidth))
            splitView.shouldHideDivider = false
            splitView.setPosition(CGFloat(targetWidth), ofDividerAt: 0)

            // Sync selection: If editor has a note, select it in the list (suppressing side effects like reloading)
            if let currentNote = EditTextView.note {
                if let index = notesTableView.getIndex(currentNote) {
                    notesTableView.selectRow(index, ensureVisible: true, suppressSideEffects: true)
                }
            }
        } else {
            if saveState && !isPresentationMode && notelistWidth >= Theme.Metrics.noteListMinimumWidth {
                UserDefaultsManagement.sidebarSize = Int(notelistWidth)
            }
            splitView.shouldHideDivider = true
            splitView.setPosition(0, ofDividerAt: 0)
            noteListView?.isHidden = true
        }
        if saveState {
            UserDefaultsManagement.notelistVisible = visible
            if !visible {
                // Sidebar cannot be visible without the note list column.
                UserDefaultsManagement.sidebarVisible = false
            }
        }
        editArea.updateTextContainerInset()
        splitView.layoutSubtreeIfNeeded()
        if visible {
            isRestoringNotelistVisibility = false
        }
        splitView.applyDividerColor()
        checkTitlebarTopConstraint()
        updateToolbarButtonTints()
    }

    private func normalizeNotelistWidth(saveState: Bool) {
        let width = notelistWidth
        guard !isNormalizingNotelistWidth,
            !isRestoringNotelistVisibility,
            isNotelistVisible,
            width <= Theme.Metrics.collapsedSplitWidthEpsilon
        else { return }

        isNormalizingNotelistWidth = true
        defer { isNormalizingNotelistWidth = false }
        collapseNotelist(saveState: saveState)
    }

    func collapseNotelist(saveState: Bool = true) {
        setNotelistVisible(false, saveState: saveState)
        if isSidebarVisible {
            setSidebarVisible(false, saveState: saveState)
        }
    }

    // MARK: - Sidebar Management

    func hideSidebar(_ sender: Any) {
        guard isSidebarVisible else { return }

        // 隐藏 sidebar → 不影响 notelist（允许两栏模式）
        setSidebarVisible(false)
    }

    func showSidebar(_ sender: Any) {
        guard !isSidebarVisible else { return }

        // 显示 sidebar → 自动显示 notelist
        if !isNotelistVisible {
            setNotelistVisible(true)
        }
        setSidebarVisible(true)
    }

    // MARK: - Note List Management

    func showNoteList(_ sender: Any) {
        guard !isNotelistVisible else { return }

        // 显示 notelist → 不强制显示 sidebar（允许两栏模式）
        setNotelistVisible(true)
    }

    func hideNoteList(_ sender: Any) {
        guard isNotelistVisible else { return }

        // 隐藏 notelist → 自动隐藏 sidebar
        collapseNotelist()
    }

    // MARK: - Toggle Actions
    @IBAction func toggleNoteList(_ sender: Any) {
        guard splitView != nil else { return }
        isNotelistVisible ? hideNoteList(sender) : showNoteList(sender)
    }

    @IBAction func toggleLayoutCycle(_ sender: Any) {
        guard splitView != nil, sidebarSplitView != nil else { return }

        switch (isSidebarVisible, isNotelistVisible, isEditorTOCVisible) {
        case (false, false, false):
            setEditorTOCVisible(true)
        case (false, false, true):
            setNotelistVisible(true)
        case (false, true, true):
            setSidebarVisible(true)
        default:
            setSidebarVisible(false)
            setNotelistVisible(false)
            setEditorTOCVisible(false)
        }
    }

    @IBAction func toggleSidebarPanel(_ sender: Any) {
        guard sidebarSplitView != nil else { return }
        isSidebarVisible ? hideSidebar(sender) : showSidebar(sender)
    }

    @IBAction func toggleSplitMode(_ sender: Any) {
        saveTitleSafely()
        let newMode = !sessionSplitMode
        sessionSplitMode = newMode

        // Trigger UI update
        // If currently in Preview Mode, exit it.
        // The disablePreview() logic will check splitViewMode and automatically transition to Split Mode.
        if sessionPreviewMode {
            disablePreview()
        } else {
            applyEditorModePreferenceChange()
        }

        // Update Button Icon
        if let button = toggleSplitButton {
            // Prefer split icon; fall back if the single icon asset is missing.
            let iconName = newMode ? "icon_editor_split" : "icon_editor_single"
            let image = NSImage(named: iconName) ?? NSImage(named: "icon_editor_split")
            if let image {
                image.isTemplate = true
                button.image = image
            }
        }
        updateToolbarButtonTints()
    }

    // MARK: - Gesture Handling
    override func wantsScrollEventsForSwipeTracking(on axis: NSEvent.GestureAxis) -> Bool {
        axis == .horizontal
    }

    override func swipe(with event: NSEvent) {
        swipe(deltaX: event.deltaX)
    }

    override func scrollWheel(with event: NSEvent) {
        if !NSEvent.isSwipeTrackingFromScrollEventsEnabled {
            super.scrollWheel(with: event)
            return
        }

        switch event.phase {
        case .began:
            isHandlingScrollEvent = true
            swipeLeftExecuted = false
            swipeRightExecuted = false
            scrollDeltaX = 0
        case .changed:
            guard isHandlingScrollEvent else {
                break
            }

            let directionChanged = scrollDeltaX.sign != event.scrollingDeltaX.sign

            guard !directionChanged else {
                scrollDeltaX = event.scrollingDeltaX
                break
            }

            scrollDeltaX += event.scrollingDeltaX

            // throttle
            guard abs(scrollDeltaX) > 50 else {
                break
            }

            let flippedScrollDelta = scrollDeltaX * -1
            let swipedLeft = flippedScrollDelta > 0

            switch (swipedLeft, swipeLeftExecuted, swipeRightExecuted) {
            case (true, false, _):  // swiped left
                swipeLeftExecuted = true
                swipeRightExecuted = false  // allow swipe back (right)
            case (false, _, false):  // swiped right
                swipeLeftExecuted = false  // allow swipe back (left)
                swipeRightExecuted = true
            default:
                super.scrollWheel(with: event)
                return
            }
            swipe(deltaX: flippedScrollDelta)
            return
        case .cancelled,
            .ended,
            .mayBegin:
            isHandlingScrollEvent = false
        default:
            break
        }

        super.scrollWheel(with: event)
    }

    func swipe(deltaX: CGFloat) {
        guard deltaX != 0 else { return }

        let swipedLeft = deltaX > 0

        if swipedLeft {
            // 向左滑：优先隐藏 sidebar，然后隐藏 notelist
            if isSidebarVisible {
                hideSidebar("")
            } else if isNotelistVisible {
                hideNoteList("")
            }
        } else {
            // 向右滑：优先显示 notelist，然后显示 sidebar
            if !isNotelistVisible {
                showNoteList("")
            } else if !isSidebarVisible {
                showSidebar("")
            }
        }
    }

    // MARK: - Split View Delegate
    func splitViewWillResizeSubviews(_ notification: Notification) {
        editArea.updateTextContainerInset()
    }

    func splitViewDidResizeSubviews(_ notification: Notification) {
        guard let splitView = notification.object as? NSSplitView,
            splitView == sidebarSplitView
        else { return }
        (sidebarSplitView as? ThemedSplitView)?.applyDividerColor()
        updateSidebarColumnWidth()
        checkSidebarConstraint()
        updateToolbarButtonTints()
    }

    func splitView(_ splitView: NSSplitView, constrainSplitPosition proposedPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView == sidebarSplitView,
            dividerIndex == 0,
            proposedPosition > 0,
            proposedPosition <= Theme.Metrics.sidebarCollapseSnapWidth
        {
            return 0
        }

        return proposedPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView == sidebarSplitView && dividerIndex == 0 {
            return 0
        }

        if dividerIndex == 0 && UserDefaultsManagement.isSingleMode {
            return 0
        }
        return proposedMinimumPosition
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        if splitView == sidebarSplitView && dividerIndex == 0 {
            return LayoutConstants.maxSidebarWidth
        }

        if dividerIndex == 0 && UserDefaultsManagement.isSingleMode {
            return 0
        }
        return proposedMaximumPosition
    }

    // MARK: - View Resize
    func viewDidResize() {
        checkSidebarConstraint()
        checkTitlebarTopConstraint()
        updateSidebarColumnWidth()

        if view.window?.inLiveResize != true {
            normalizeNotelistWidth(saveState: false)
        }

        handleEditorContentResize()
    }

    func handleEditorContentResize() {
        editArea.updateTextContainerInset()
        if view.window?.inLiveResize == true {
            needsPreviewLayoutAfterLiveResize = true
            return
        }
        updatePreviewLayoutDuringResize()
        schedulePreviewLayoutUpdateAfterResize()
    }

    private func updatePreviewLayoutDuringResize() {
        guard let previewView = editArea.markdownView else { return }

        let targetBounds: CGRect
        if let previewScroll = previewScrollView {
            targetBounds = previewScroll.bounds
        } else if let container = previewView.superview {
            targetBounds = container.bounds
        } else {
            return
        }

        let targetFrame = CGRect(origin: .zero, size: targetBounds.size)
        if previewView.frame != targetFrame {
            previewView.frame = targetFrame
        }
    }

    func handleWindowDidEndLiveResize() {
        guard needsPreviewLayoutAfterLiveResize else { return }
        needsPreviewLayoutAfterLiveResize = false
        schedulePreviewLayoutUpdateAfterResize()
    }

    private func schedulePreviewLayoutUpdateAfterResize() {
        guard shouldShowPreview else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.layoutSubtreeIfNeeded()
            self.updatePreviewLayoutDuringResize()
        }
    }

    // MARK: - Table and Sidebar Layout
    func updateSidebarColumnWidth() {
        guard sidebarWidth > 0,
            let column = storageOutlineView?.tableColumns.first
        else { return }

        let clipWidth = sidebarScrollView?.contentView.bounds.width ?? 0
        let fallbackWidth = sidebarSplitView?.subviews.first?.bounds.width ?? storageOutlineView.bounds.width
        let measuredWidth = clipWidth > 1 ? clipWidth : fallbackWidth
        let targetWidth = max(0, floor(measuredWidth))
        if column.width != targetWidth {
            column.width = targetWidth
        }
        if let outline = storageOutlineView, outline.frame.width != targetWidth {
            outline.setFrameSize(NSSize(width: targetWidth, height: outline.frame.height))
        }

        if let scrollView = sidebarScrollView {
            let clipView = scrollView.contentView
            let origin = clipView.bounds.origin
            if origin.x != 0 {
                clipView.scroll(to: NSPoint(x: 0, y: origin.y))
                scrollView.reflectScrolledClipView(clipView)
            }
        }
    }

    func reloadSideBar() {
        guard let outline = storageOutlineView else {
            return
        }

        sidebarTimer.invalidate()
        sidebarTimer = Timer.scheduledTimer(timeInterval: 1.2, target: outline, selector: #selector(outline.reloadSidebar), userInfo: nil, repeats: false)
    }

    func setTableRowHeight() {
        notesTableView.rowHeight = CGFloat(52)
        notesTableView.selectionHighlightStyle = .none
        notesTableView.reloadData()
    }

}
