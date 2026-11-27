public struct MenuBarPresentation: Equatable, Sendable {
    public let title: String
    public let toolTip: String
    public let accessibilityLabel: String

    public init(selectedAccountLabel: String?, accountCount: Int, stateTitle: String) {
        guard let selectedAccountLabel else {
            title = stateTitle
            toolTip = "Codex Quota — click to view usage"
            accessibilityLabel = "Codex Quota, \(stateTitle). Show usage."
            return
        }

        if accountCount > 1 {
            title = "\(Self.boundedIdentifier(selectedAccountLabel)) · \(stateTitle)"
        } else {
            title = stateTitle
        }
        toolTip = "\(selectedAccountLabel) — \(stateTitle). Click to view usage."
        accessibilityLabel = "Codex Quota, \(selectedAccountLabel), \(stateTitle). Show usage."
    }

    private static func boundedIdentifier(_ label: String) -> String {
        let maximumCharacters = 12
        guard label.count > maximumCharacters else { return label }
        return "\(label.prefix(maximumCharacters - 1))…"
    }
}
