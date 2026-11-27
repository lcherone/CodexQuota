import SwiftUI

struct Palette {
    var background: Color
    var ink: Color
    var secondary: Color
    var hairline: Color

    static func current(_ scheme: ColorScheme) -> Palette {
        switch scheme {
        case .dark:
            Palette(
                background: .black,
                ink: .white,
                secondary: .white.opacity(0.62),
                hairline: .white.opacity(0.22)
            )
        default:
            Palette(
                background: .white,
                ink: .black,
                secondary: .black.opacity(0.62),
                hairline: .black.opacity(0.18)
            )
        }
    }
}

enum PanelMetrics {
    static let width: CGFloat = 360
    static let horizontalPadding: CGFloat = 14
    static let controlHeight: CGFloat = 28
    static let minimumScrollHeight: CGFloat = 160
    static let footerAllowance: CGFloat = 142
    static let cornerRadius: CGFloat = 6
}

func planLabel(_ value: String?) -> String {
    guard let value, !value.isEmpty else { return "Codex" }
    return value.split(separator: "_").map { word in
        word.prefix(1).uppercased() + word.dropFirst()
    }.joined(separator: " ")
}

func reachedSentence(_ value: String) -> String {
    switch value {
    case "rate_limit_reached":
        return "The short-term rate limit is reached."
    case "workspace_owner_credits_depleted", "workspace_member_credits_depleted":
        return "Workspace credits are depleted."
    case "workspace_owner_usage_limit_reached", "workspace_member_usage_limit_reached":
        return "The workspace usage limit is reached."
    default:
        return "The provider marked this allowance as reached."
    }
}
