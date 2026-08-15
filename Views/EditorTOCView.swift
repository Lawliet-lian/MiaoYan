import Cocoa

@MainActor
final class EditorTOCView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private final class CellView: NSTableCellView {
        /// Invoked when the disclosure chevron is clicked. The row's flat
        /// item index is captured by the table view when the cell is
        /// configured, so this closure carries no payload.
        var onToggleDisclosure: (() -> Void)?

        private let disclosureButton = NSButton()
        private let label = NSTextField(labelWithString: "")
        private var indentConstraint: NSLayoutConstraint?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)

            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.textColor = Theme.textColor
            label.font = .systemFont(ofSize: 12)

            disclosureButton.translatesAutoresizingMaskIntoConstraints = false
            disclosureButton.isBordered = false
            disclosureButton.setButtonType(.momentaryChange)
            disclosureButton.imagePosition = .imageOnly
            disclosureButton.focusRingType = .none
            disclosureButton.contentTintColor = Theme.textColor
            disclosureButton.target = self
            disclosureButton.action = #selector(handleDisclosureClick)

            addSubview(disclosureButton)
            addSubview(label)
            textField = label

            let indentConstraint = disclosureButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4)
            self.indentConstraint = indentConstraint
            NSLayoutConstraint.activate([
                indentConstraint,
                disclosureButton.widthAnchor.constraint(equalToConstant: 12),
                disclosureButton.centerYAnchor.constraint(equalTo: centerYAnchor),
                label.leadingAnchor.constraint(equalTo: disclosureButton.trailingAnchor, constant: 2),
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        @objc private func handleDisclosureClick() {
            onToggleDisclosure?()
        }

        func configure(title: String, hasChildren: Bool, isExpanded: Bool, indent: CGFloat) {
            label.stringValue = title
            toolTip = title
            indentConstraint?.constant = indent
            disclosureButton.isHidden = !hasChildren
            disclosureButton.image = hasChildren ? Self.disclosureImage(isExpanded: isExpanded) : nil
        }

        private static func disclosureImage(isExpanded: Bool) -> NSImage? {
            let symbolName = isExpanded ? "chevron.down" : "chevron.right"
            let configuration = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
            image?.isTemplate = true
            return image
        }
    }

    var onSelectItem: ((EditorTOCItem) -> Void)?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let trailingSeparator = NSView()
    /// Shown when the current note has no headings at all, so the panel never
    /// reads as a broken/empty pane. Hidden as soon as the first heading
    /// exists; the table itself renders zero rows in the meantime.
    private let emptyStateLabel = NSTextField(labelWithString: I18n.str("No headings"))
    /// All parsed headings in document order (including descendants hidden
    /// behind collapsed sections). The controller reads this to compute the
    /// current-heading highlight; the table only shows `visibleItems`.
    private(set) var items: [EditorTOCItem] = []
    /// For each flat item index, the indices of its direct child headings.
    /// Built from heading levels: a heading owns every following heading at a
    /// deeper level until the next heading at the same or shallower level.
    private var children: [[Int]] = []
    /// Flat item index -> parent flat item index (roots are absent).
    private var parent: [Int: Int] = [:]
    /// Collapse-state keys ("level:title") for headings that have children.
    /// Keys are pruned on refresh so deleted headings don't leak state, while
    /// surviving keys keep the user's collapsed sections collapsed while they
    /// edit elsewhere in the note.
    private var collapsedKeys: Set<String> = []
    /// Rows actually rendered in the table: the flat list with descendants of
    /// collapsed headings removed.
    private var visibleItems: [EditorTOCItem] = []
    /// Flat item index -> visible table row, for rows that are visible.
    private var visibleRowByFlat: [Int: Int] = [:]
    /// Visible table row -> flat item index.
    private var flatIndexByRow: [Int] = []
    /// Currently highlighted "current heading" flat index, or nil when
    /// nothing is highlighted. Programmatic selection must never be treated
    /// as a user click (see `setHighlightedIndex`).
    private var highlightedIndex: Int?
    private var isProgrammaticSelection = false
    /// Set while a disclosure click is being processed so any selection
    /// change caused by reloading the table is not routed to `onSelectItem`
    /// (which would yank the editor cursor to the row being toggled).
    private var isTogglingDisclosure = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func updateItems(_ items: [EditorTOCItem]) {
        rebuildTree(from: items)
        emptyStateLabel.isHidden = !items.isEmpty
        // The item set changed (typing or note switch); drop the stale
        // selection so a previous heading index does not linger on a row that
        // now belongs to different content. The caller re-evaluates the
        // highlight right after the update.
        highlightedIndex = nil
        if tableView.selectedRow >= 0 {
            tableView.deselectAll(nil)
        }
        tableView.reloadData()
    }

    /// Marks the given flat item as the "current heading" (or clears the
    /// highlight when `index` is nil) and keeps the highlighted row visible
    /// in the outline. Selection is flagged as programmatic so it never
    /// routes through `onSelectItem` — otherwise scrolling the editor would
    /// yank the cursor back to the highlighted heading.
    func setHighlightedIndex(_ index: Int?) {
        let clamped = index.flatMap { items.indices.contains($0) ? $0 : nil }
        guard clamped != highlightedIndex else { return }
        highlightedIndex = clamped

        isProgrammaticSelection = true
        defer { isProgrammaticSelection = false }

        if let flat = clamped, let row = row(forHighlightingFlatIndex: flat) {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
        } else {
            tableView.deselectAll(nil)
        }
    }

    override func layout() {
        super.layout()

        // NSTableView 作为 NSScrollView 的 documentView 时，不会自动通过约束撑开。
        // 这里在布局阶段主动让表格跟随可视区域尺寸，避免出现“容器有了，但列表本体仍是零尺寸”的空白栏。
        tableView.frame = scrollView.contentView.bounds

        // TOC 只有一列，列宽需要跟随表格宽度一起更新，否则首次布局时可能仍保留为 0 宽。
        tableView.tableColumns.first?.width = tableView.bounds.width
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateSeparatorColor()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSeparatorColor()
    }

    private func setup() {
        wantsLayer = true

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .overlay

        tableView.translatesAutoresizingMaskIntoConstraints = false
        tableView.headerView = nil
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = false
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.rowHeight = 22
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.focusRingType = .none
        tableView.dataSource = self
        tableView.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("toc"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

        scrollView.documentView = tableView
        addSubview(scrollView)

        emptyStateLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateLabel.font = .systemFont(ofSize: 12)
        emptyStateLabel.textColor = Theme.secondaryTextColor
        emptyStateLabel.alignment = .center
        emptyStateLabel.lineBreakMode = .byWordWrapping
        emptyStateLabel.maximumNumberOfLines = 2
        emptyStateLabel.isHidden = true
        addSubview(emptyStateLabel)

        trailingSeparator.translatesAutoresizingMaskIntoConstraints = false
        trailingSeparator.wantsLayer = true
        addSubview(trailingSeparator)
        updateSeparatorColor()

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            emptyStateLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            emptyStateLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            emptyStateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            emptyStateLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            trailingSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            trailingSeparator.topAnchor.constraint(equalTo: topAnchor),
            trailingSeparator.bottomAnchor.constraint(equalTo: bottomAnchor),
            trailingSeparator.widthAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func updateSeparatorColor() {
        trailingSeparator.layer?.backgroundColor =
            Theme.splitDividerColor
            .resolvedColor(for: effectiveAppearance)
            .cgColor
    }

    /// Rebuilds the heading tree, prunes stale collapse keys, and recomputes
    /// the visible row set. Collapse state intentionally survives this call
    /// (typing elsewhere must not silently re-expand user-collapsed sections).
    private func rebuildTree(from newItems: [EditorTOCItem]) {
        items = newItems

        var newChildren = Array(repeating: [Int](), count: newItems.count)
        var newParent: [Int: Int] = [:]
        var stack: [(level: Int, index: Int)] = []

        for (index, item) in newItems.enumerated() {
            while let top = stack.last, top.level >= item.level {
                stack.removeLast()
            }
            if let parentIndex = stack.last?.index {
                newChildren[parentIndex].append(index)
                newParent[index] = parentIndex
            }
            stack.append((item.level, index))
        }

        children = newChildren
        parent = newParent

        let currentKeys = Set(newItems.map { Self.key(for: $0) })
        collapsedKeys = collapsedKeys.intersection(currentKeys)

        recomputeVisibleRows()
    }

    /// Flattens the tree into the row set, skipping the whole subtree of any
    /// collapsed heading. A collapsed heading itself stays visible so it can
    /// be expanded again.
    private func recomputeVisibleRows() {
        var visible: [EditorTOCItem] = []
        var rowByFlat: [Int: Int] = [:]
        var flatByRow: [Int] = []

        func flatten(_ index: Int) {
            let item = items[index]
            rowByFlat[index] = visible.count
            flatByRow.append(index)
            visible.append(item)

            if collapsedKeys.contains(Self.key(for: item)) {
                return
            }
            for child in children[index] {
                flatten(child)
            }
        }

        for root in 0..<items.count where parent[root] == nil {
            flatten(root)
        }

        visibleItems = visible
        visibleRowByFlat = rowByFlat
        flatIndexByRow = flatByRow
    }

    /// Maps a flat item index to the table row that should carry the
    /// "current heading" highlight. Hidden descendants (inside a collapsed
    /// section) highlight their nearest visible ancestor, matching standard
    /// outline behavior: collapsing a section keeps the highlight on the
    /// parent row.
    private func row(forHighlightingFlatIndex flatIndex: Int) -> Int? {
        var index = flatIndex
        while visibleRowByFlat[index] == nil {
            guard let parentIndex = parent[index] else { return nil }
            index = parentIndex
        }
        return visibleRowByFlat[index]
    }

    private func toggleDisclosure(at flatIndex: Int) {
        guard items.indices.contains(flatIndex) else { return }

        let key = Self.key(for: items[flatIndex])
        if collapsedKeys.contains(key) {
            collapsedKeys.remove(key)
        } else {
            collapsedKeys.insert(key)
        }

        isTogglingDisclosure = true
        recomputeVisibleRows()
        tableView.reloadData()

        // The highlighted row may have moved (rows above it collapsed or
        // expanded); re-apply the highlight without the no-change guard.
        let highlight = highlightedIndex
        highlightedIndex = nil
        setHighlightedIndex(highlight)

        DispatchQueue.main.async { [weak self] in
            self?.isTogglingDisclosure = false
        }
    }

    /// Collapse-state key for an item. Keyed by level + title (rather than
    /// line number) so inserting text above a heading — the common edit — does
    /// not silently re-expand every section below it. Renaming a heading or
    /// having two same-level headings with identical titles are accepted
    /// limitations for the current outline.
    private static func key(for item: EditorTOCItem) -> String {
        "\(item.level):\(item.title)"
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleItems.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ThemedTableRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("EditorTOCCellView")
        guard flatIndexByRow.indices.contains(row) else { return nil }
        let flatIndex = flatIndexByRow[row]
        let item = items[flatIndex]

        let cell =
            (tableView.makeView(withIdentifier: identifier, owner: self) as? CellView)
            ?? {
                let view = CellView()
                view.identifier = identifier
                return view
            }()

        cell.configure(
            title: item.title,
            hasChildren: !children[flatIndex].isEmpty,
            isExpanded: !collapsedKeys.contains(Self.key(for: item)),
            indent: 4 + CGFloat(max(item.level - 1, 0)) * 12
        )
        cell.onToggleDisclosure = { [weak self] in
            self?.toggleDisclosure(at: flatIndex)
        }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isProgrammaticSelection, !isTogglingDisclosure else { return }
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, flatIndexByRow.indices.contains(selectedRow) else { return }
        onSelectItem?(items[flatIndexByRow[selectedRow]])
    }
}
