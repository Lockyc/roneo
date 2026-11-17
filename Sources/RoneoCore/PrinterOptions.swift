import Foundation

/// Duplex choice for a print job.
public enum Sides: Equatable, Sendable {
    case single, double
}

/// One CUPS option (one `lpoptions -l` line): its key, display label and selectable values.
public struct PrinterOption: Equatable, Sendable {
    public let key: String
    public let label: String
    public let choices: [String]
    public let defaultChoice: String?

    public init(key: String, label: String, choices: [String], defaultChoice: String?) {
        self.key = key
        self.label = label
        self.choices = choices
        self.defaultChoice = defaultChoice
    }
}

/// Everything a printer's `lpoptions -l` output says it can do.
public struct PrinterCapabilities: Equatable, Sendable {
    public let options: [PrinterOption]

    public init(options: [PrinterOption]) {
        self.options = options
    }

    public func option(_ key: String) -> PrinterOption? {
        options.first { $0.key == key }
    }

    /// True when `Duplex` offers anything besides `None`.
    public var supportsDuplex: Bool {
        option("Duplex")?.choices.contains { $0 != "None" } ?? false
    }

    /// Double-sided when the printer's own `Duplex` default is not `None`.
    public var defaultSides: Sides {
        guard let d = option("Duplex")?.defaultChoice, d != "None" else { return .single }
        return .double
    }
}

public enum PrinterOptionsParser {
    /// Parses `lpoptions -l` lines of the form `Key/Label: a *b c`. `*` marks the default; a line
    /// without one defaults to its first choice. `Custom.*` choices are free-form entries, not
    /// selectable values, so they are dropped.
    public static func parse(_ output: String) -> PrinterCapabilities {
        var options: [PrinterOption] = []
        for line in output.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let head = line[..<colon]
            let key: String
            let label: String
            if let slash = head.firstIndex(of: "/") {
                key = String(head[..<slash])
                label = String(head[head.index(after: slash)...])
            } else {
                key = String(head)
                label = key
            }
            var choices: [String] = []
            var defaultChoice: String?
            for token in line[line.index(after: colon)...].split(separator: " ") {
                var value = String(token)
                let isDefault = value.hasPrefix("*")
                if isDefault { value.removeFirst() }
                if value.isEmpty || value.hasPrefix("Custom.") { continue }
                choices.append(value)
                if isDefault { defaultChoice = value }
            }
            guard !key.isEmpty, !choices.isEmpty else { continue }
            options.append(PrinterOption(key: key, label: label, choices: choices,
                                         defaultChoice: defaultChoice ?? choices.first))
        }
        return PrinterCapabilities(options: options)
    }
}
