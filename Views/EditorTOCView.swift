import Cocoa

@MainActor
final class EditorTOCView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private final class CellView: NSTableCellView {
        var leadingConstraint: NSLayoutConstraint?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)

            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            label.textColor = Theme.textColor
            label.font = .systemFont(ofSize: 12)

            addSubview(label)
            textField = label

            leadingConstraint = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8)
            NSLayoutConstraint.activate([
                leadingConstraint!,
                label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
                label.centerYAnchor.constraint(equalTo: centerYAnchor),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }
    }

    var onSelectItem: ((EditorTOCItem) -> Void)?

    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let trailingSeparator = NSView()
    private(set) var items: [EditorTOCItem] = []
    /// Currently highlighted "current heading" row, or nil when nothing is
    /// highlighted. Programmatic selection must never be treated as a user
    /// click (see `setHighlightedIndex`).
    private var highlightedIndex: Int?
    private var isProgrammaticSelection = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func updateItems(_ items: [EditorTOCItem]) {
        self.items = items
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

    /// Marks the given row as the "current heading" (or clears the highlight
    /// when `index` is nil) and keeps the highlighted row visible in the
    /// outline. Selection is flagged as programmatic so it never routes
    /// through `onSelectItem` — otherwise scrolling the editor would yank the
    /// cursor back to the highlighted heading.
    func setHighlightedIndex(_ index: Int?) {
        let clamped = index.flatMap { items.indices.contains($0) ? $0 : nil }
        guard clamped != highlightedIndex else { return }
        highlightedIndex = clamped

        isProgrammaticSelection = true
        defer { isProgrammaticSelection = false }

        if let row = clamped {
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

        trailingSeparator.translatesAutoresizingMaskIntoConstraints = false
        trailingSeparator.wantsLayer = true
        addSubview(trailingSeparator)
        updateSeparatorColor()

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            trailingSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            trailingSeparator.topAnchor.constraint(equalTo: topAnchor),
            trailingSeparator.bottomAnchor.constraint(equalTo: bottomAnchor),
            trailingSeparator.widthAnchor.constraint(equalToConstant: 1),
        ])
    }

    private func updateSeparatorColor() {
        trailingSeparator.layer?.backgroundColor = Theme.splitDividerColor
            .resolvedColor(for: effectiveAppearance)
            .cgColor
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        items.count
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ThemedTableRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("EditorTOCCellView")
        let item = items[row]

        let cell = (tableView.makeView(withIdentifier: identifier, owner: self) as? CellView) ?? {
            let view = CellView()
            view.identifier = identifier
            return view
        }()

        cell.textField?.stringValue = item.title
        cell.leadingConstraint?.constant = 8 + CGFloat(max(item.level - 1, 0)) * 12
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isProgrammaticSelection else { return }
        let selectedRow = tableView.selectedRow
        guard selectedRow >= 0, items.indices.contains(selectedRow) else { return }
        onSelectItem?(items[selectedRow])
    }
}
