import AppKit

/// The print bar's controls in two rows, as the architecture sketch lays them out. It holds no
/// state of its own: `PrintController` fills every control and receives every action.
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
        [printer, sides, scale, pages, range, copies, copiesStepper, paper, mediaType, tray, colour]
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        for control in settingControls + [printButton] {
            control.controlSize = .small
            control.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        }
        // The popups give up width first, the printer name before the media choices.
        (printer.cell as? NSPopUpButtonCell)?.lineBreakMode = .byTruncatingMiddle
        printer.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true
        printer.setContentCompressionResistancePriority(.init(200), for: .horizontal)
        for popup in [printer, paper, mediaType, tray] {
            popup.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        }
        for popup in [paper, mediaType, tray] {
            popup.widthAnchor.constraint(lessThanOrEqualToConstant: 160).isActive = true
            popup.setContentCompressionResistancePriority(.init(210), for: .horizontal)
        }
        range.placeholderString = "1-3, 5"
        range.widthAnchor.constraint(equalToConstant: 56).isActive = true
        copies.alignment = .right
        copies.widthAnchor.constraint(equalToConstant: 36).isActive = true
        copiesStepper.minValue = 1
        copiesStepper.maxValue = 999
        copiesStepper.increment = 1
        copiesStepper.valueWraps = false
        copiesStepper.integerValue = 1
        printButton.bezelStyle = .push
        printButton.keyEquivalent = ""
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.textColor = .secondaryLabelColor
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.init(100), for: .horizontal)

        let top = row([labelled("Printer", printer), labelled("Sides", sides), labelled("Scale", scale),
                       labelled("Pages", pages, range), labelled("Copies", copies, copiesStepper)])
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let bottom = row([labelled("Paper", paper), labelled("Type", mediaType), labelled("Tray", tray),
                          labelled("Colour", colour), spacer, status, printButton])
        let rows = NSStackView(views: [top, bottom])
        rows.orientation = .vertical
        rows.alignment = .width
        rows.spacing = 6
        rows.edgeInsets = NSEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)
        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        let rule = NSBox()
        rule.boxType = .separator
        rule.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rule)
        NSLayoutConstraint.activate([
            rule.leadingAnchor.constraint(equalTo: leadingAnchor),
            rule.trailingAnchor.constraint(equalTo: trailingAnchor),
            rule.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// A horizontal row that clips at narrow widths rather than holding the window open.
    private func row(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        stack.setClippingResistancePriority(.defaultLow, for: .horizontal)
        return stack
    }

    private func labelled(_ title: String, _ controls: NSView...) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [label] + controls)
        stack.orientation = .horizontal
        stack.spacing = 4
        stack.alignment = .centerY
        return stack
    }
}
