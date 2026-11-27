public enum MenuBarHealth: Equatable, Sendable {
    case current
    case stale
    case refreshFailed
}

public struct MenuBarPresentation: Equatable, Sendable {
    public let title: String
    public let toolTip: String
    public let accessibilityLabel: String

    public init(
        selectedAccountLabel: String?,
        accountCount: Int,
        stateTitle: String,
        health: MenuBarHealth = .current
    ) {
        guard let selectedAccountLabel else {
            title = stateTitle
            toolTip = "Codex Quota — click to view usage"
            accessibilityLabel = "Codex Quota, \(stateTitle). Show usage."
            return
        }

        let visibleState = health == .current ? stateTitle : "\(stateTitle) ⚠︎"
        if accountCount > 1 {
            title = "\(Self.boundedIdentifier(selectedAccountLabel)) · \(visibleState)"
        } else {
            title = visibleState
        }
        switch health {
        case .current:
            toolTip = "\(selectedAccountLabel) — \(stateTitle). Click to view usage."
            accessibilityLabel = "Codex Quota, \(selectedAccountLabel), \(stateTitle). Show usage."
        case .stale:
            toolTip = "\(selectedAccountLabel) — \(stateTitle). This reading is older than 15 minutes. Click to view usage."
            accessibilityLabel = "Codex Quota, \(selectedAccountLabel), \(stateTitle). This reading is older than 15 minutes. Show usage."
        case .refreshFailed:
            toolTip = "\(selectedAccountLabel) — \(stateTitle). Refresh failed; showing the retained reading. Click to view usage."
            accessibilityLabel = "Codex Quota, \(selectedAccountLabel), \(stateTitle). Refresh failed; showing the retained reading. Show usage."
        }
    }

    private static func boundedIdentifier(_ label: String) -> String {
        let maximumCharacters = 12
        guard label.count > maximumCharacters else { return label }
        return "\(label.prefix(maximumCharacters - 1))…"
    }
}
