import SwiftUI

struct Palette {
    var background: Color
    var sidebar: Color
    var card: Color
    var ink: Color
    var muted: Color
    var hairline: Color
    var accent: Color
    var over: Color
    var onPace: Color

    static func current(_ scheme: ColorScheme) -> Palette {
        switch scheme {
        case .dark:
            Palette(
                background: Color(red: 0.09, green: 0.085, blue: 0.078),
                sidebar: Color(red: 0.12, green: 0.112, blue: 0.102),
                card: Color(red: 0.16, green: 0.15, blue: 0.136),
                ink: Color(red: 0.96, green: 0.94, blue: 0.90),
                muted: Color(red: 0.73, green: 0.69, blue: 0.62),
                hairline: Color.white.opacity(0.10),
                accent: Color(red: 0.49, green: 0.80, blue: 0.64),
                over: Color(red: 0.93, green: 0.56, blue: 0.42),
                onPace: Color(red: 0.93, green: 0.78, blue: 0.46)
            )
        default:
            Palette(
                background: Color(red: 0.965, green: 0.953, blue: 0.925),
                sidebar: Color(red: 0.94, green: 0.922, blue: 0.882),
                card: Color(red: 1, green: 0.995, blue: 0.985),
                ink: Color(red: 0.12, green: 0.10, blue: 0.086),
                muted: Color(red: 0.39, green: 0.35, blue: 0.30),
                hairline: Color.black.opacity(0.08),
                accent: Color(red: 0.07, green: 0.40, blue: 0.32),
                over: Color(red: 0.62, green: 0.24, blue: 0.18),
                onPace: Color(red: 0.45, green: 0.32, blue: 0.08)
            )
        }
    }
}

extension View {
    func quotaCard(_ palette: Palette) -> some View {
        padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 1)
            )
    }
}

func tokenText(_ value: Int64?) -> String {
    guard let value else { return "—" }
    return value.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_GB")))
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
