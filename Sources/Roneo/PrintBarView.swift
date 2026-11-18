import AppKit

/// The print bar: a grid of the job's settings — the printer and its paper on the first row, the
/// pages and how they print on the second — then Copies above Print at the trailing edge. It holds
/// no state of its own: `PrintController` fills every control and receives every action.
final class PrintBarView: NSView {
    let printer = NSPopUpButton()
    let sides = NSSegmentedControl(labels: ["Single", "Double"], trackingMode: .selectOne, target: nil, action: nil)
    let scale = NSSegmentedControl(labels: ["100%", "Fit"], trackingMode: .selectOne, target: nil, action: nil)
    let pages = NSSegmentedControl(labels: ["All", "Current", "Range"], trackingMode: .selectOne, target: nil, action: nil)
    let range = NSTextField(string: "")
    let copies = NSTextField(string: "1")
    let copiesStepper = NSStepper()
    let paper = NSPopUpButton()
    let mediaType = NSPopUpButton()
    let tray = NSPopUpButton()
    let colour = NSSegmentedControl(labels: ["Colour", "Grey"], trackingMode: .selectOne, target: nil, action: nil)
    let printButton = NSButton(title: "Print", target: nil, action: nil)
    let status = NSTextField(labelWithString: "")

    /// Every control but Print, in bar order.
    var settingControls: [NSControl] {
        [printer, paper, mediaType, tray, pages, range, sides, scale, colour, copies, copiesStepper]
    }

    /// The page-number digits the Current segment is sized for.
    private var currentDigits = 0

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        for control in settingControls + [printButton] {
            control.controlSize = .regular
            control.font = font
        }
        pages.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        // The printer name gives up width first, then the media choices; then the grid clips.
        (printer.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingMiddle
        printer.setContentCompressionResistancePriority(.init(200), for: .horizontal)
        for popup in [paper, mediaType, tray] {
            popup.setContentCompressionResistancePriority(.init(210), for: .horizontal)
            let cap = popup.widthAnchor.constraint(lessThanOrEqualToConstant: 200)
            cap.priority = .init(300)
            cap.isActive = true
        }
        range.placeholderString = "1-3, 5"
        range.widthAnchor.constraint(equalToConstant: 76).isActive = true
        copies.alignment = .right
        copies.widthAnchor.constraint(equalToConstant: 48).isActive = true
        copiesStepper.minValue = 1
        copiesStepper.maxValue = 999
        copiesStepper.increment = 1
        copiesStepper.valueWraps = false
        copiesStepper.integerValue = 1
        printButton.bezelStyle = .push
        printButton.bezelColor = .controlAccentColor
        printButton.keyEquivalent = ""
        status.font = font
        status.textColor = .secondaryLabelColor
        status.alignment = .right
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.init(100), for: .horizontal)
        status.setContentHuggingPriority(.init(1), for: .horizontal)
        setCurrentPage(1, of: 1)

        let pagesAndRange = NSStackView(views: [pages, range])
        pagesAndRange.spacing = 6
        let named: [(String, NSView)] = [
            ("Printer", printer), ("Paper", paper), ("Type", mediaType), ("Tray", tray),
            ("Pages", pagesAndRange), ("Sides", sides), ("Scale", scale), ("Colour", colour),
        ]
        fields = named.map { (label: label($0.0), control: $0.1) }
        settings.rowSpacing = 10
        settings.columnSpacing = 6
        settings.yPlacement = .center
        settings.translatesAutoresizingMaskIntoConstraints = false

        let copiesRow = NSStackView(views: [label("Copies"), copies, copiesStepper])
        copiesRow.spacing = 6
        let send = NSGridView(views: [[copiesRow], [printButton]])
        send.rowSpacing = 10
        send.yPlacement = .center
        send.column(at: 0).xPlacement = .fill
        send.cell(for: copiesRow)?.xPlacement = .trailing
        send.translatesAutoresizingMaskIntoConstraints = false

        // Clips the settings grid, never the Copies and Print column, once the popups have shrunk.
        let clip = NSView()
        clip.clipsToBounds = true
        clip.translatesAutoresizingMaskIntoConstraints = false
        clip.addSubview(settings)
        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        let rule = NSBox()
        rule.boxType = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        for view in [clip, status, divider, send, rule] { addSubview(view) }

        let fullGrid = clip.trailingAnchor.constraint(equalTo: settings.trailingAnchor)
        fullGrid.priority = .init(250)
        NSLayoutConstraint.activate([
            settings.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            settings.topAnchor.constraint(equalTo: clip.topAnchor),
            settings.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            fullGrid,
            clip.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            clip.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            clip.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -11),
            status.leadingAnchor.constraint(equalTo: clip.trailingAnchor, constant: 14),
            status.centerYAnchor.constraint(equalTo: printButton.centerYAnchor),
            divider.leadingAnchor.constraint(equalTo: status.trailingAnchor, constant: 14),
            divider.topAnchor.constraint(equalTo: clip.topAnchor),
            divider.bottomAnchor.constraint(equalTo: clip.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            send.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 14),
            send.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            send.centerYAnchor.constraint(equalTo: clip.centerYAnchor),
            printButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        arrange(columns: 2)
        minimumWidth = fittingSize.width
        arrange(columns: 4)
    }

    /// The settings grid: every label and control, in reading order.
    private let settings = NSGridView()
    private var fields: [(label: NSTextField, control: NSView)] = []
    /// Label-and-control pairs per grid row: 4 (two rows) when they fit, else 2 (four rows).
    private var columns = 0
    /// The bar's width with every control showing, which is four rows of the grid.
    private(set) var minimumWidth: CGFloat = 0
    /// The width the two-row grid needed when it last showed.
    private var wideWidth: CGFloat = .greatestFiniteMagnitude

    override func layout() {
        super.layout()
        if columns == 4, fittingSize.width > bounds.width {
            wideWidth = fittingSize.width
            arrange(columns: 2)
        } else if columns == 2, bounds.width >= wideWidth {
            arrange(columns: 4)
        }
    }

    /// Lays the fields out `columns` pairs to a row, labels trailing-aligned in their own columns.
    private func arrange(columns: Int) {
        guard columns != self.columns else { return }
        self.columns = columns
        while settings.numberOfRows > 0 { settings.removeRow(at: 0) }
        while settings.numberOfColumns > 0 { settings.removeColumn(at: 0) }
        for start in stride(from: 0, to: fields.count, by: columns) {
            settings.addRow(with: fields[start..<start + columns].flatMap { [$0.label, $0.control] })
        }
        for index in 0..<settings.numberOfColumns {
            let column = settings.column(at: index)
            column.xPlacement = index.isMultiple(of: 2) ? .trailing : .leading
            column.leadingPadding = index > 0 && index.isMultiple(of: 2) ? 14 : 0
        }
        for popup in [printer, paper, mediaType, tray] { settings.cell(for: popup)?.xPlacement = .fill }
        needsLayout = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Names `page` in the Current segment, which keeps one width for every page of a
    /// `count`-page document so the bar never moves while the view scrolls.
    func setCurrentPage(_ page: Int, of count: Int) {
        let digits = String(max(count, 1)).count
        if digits != currentDigits {
            currentDigits = digits
            let widest = "Current (\(String(repeating: "8", count: digits)))" as NSString
            let width = widest.size(withAttributes: [.font: pages.font as Any]).width
            pages.setWidth(ceil(width) + 16, forSegment: 1)
        }
        let label = "Current (\(page))"
        if pages.label(forSegment: 1) != label { pages.setLabel(label, forSegment: 1) }
    }

    private func label(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .secondaryLabelColor
        return label
    }
}
