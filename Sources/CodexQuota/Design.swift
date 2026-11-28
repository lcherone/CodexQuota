import SwiftUI

struct Palette {
    var background: Color
    var ink: Color
    var secondary: Color
    var hairline: Color

    var accent: Color { Color(red: 0.06, green: 0.64, blue: 0.40) }
    var warning: Color { Color(red: 0.82, green: 0.46, blue: 0.08) }

    static func current(_ scheme: ColorScheme) -> Palette {
        switch scheme {
        case .dark:
            Palette(
                background: Color(white: 0.105),
                ink: Color(white: 0.96),
                secondary: .white.opacity(0.66),
                hairline: .white.opacity(0.14)
            )
        default:
            Palette(
                background: Color(red: 0.985, green: 0.98, blue: 0.97),
                ink: Color(white: 0.09),
                secondary: .black.opacity(0.62),
                hairline: .black.opacity(0.12)
            )
        }
    }
}

enum PanelMetrics {
    static let width: CGFloat = 400
    static let horizontalPadding: CGFloat = 16
    static let controlHeight: CGFloat = 28
    static let maximumHeight: CGFloat = 640
    static let cornerRadius: CGFloat = 8
}

struct QuotaCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuotaCheckbox(configuration: configuration)
    }
}

private struct QuotaCheckbox: View {
    let configuration: ToggleStyleConfiguration
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var focused: Bool

    var body: some View {
        let palette = Palette.current(scheme)
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(configuration.isOn ? Color.white : .clear)
                    .frame(width: 17, height: 17)
                    .background(configuration.isOn ? palette.accent : palette.ink.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(configuration.isOn ? palette.accent : palette.secondary, lineWidth: 1))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(focused ? Color.accentColor : .clear, lineWidth: 2).padding(-3))
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                configuration.label
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .frame(minHeight: 28)
        }
        .buttonStyle(.plain)
        .focusable(interactions: .activate)
        .focused($focused)
        .foregroundStyle(palette.ink)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

struct QuotaTabs<Value: Hashable>: View {
    var values: [Value]
    @Binding var selection: Value
    var title: (Value) -> String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let palette = Palette.current(scheme)
        HStack(spacing: 0) {
            ForEach(values, id: \.self) { value in
                Button { selection = value } label: {
                    Text(title(value))
                        .font(.system(size: 13, weight: selection == value ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .contentShape(Rectangle())
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(selection == value ? palette.ink : .clear).frame(height: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
        .foregroundStyle(palette.ink)
    }
}

struct QuotaMeter: View {
    var percent: Double
    var color: Color

    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(color.opacity(0.12))
                .overlay(alignment: .leading) {
                    Capsule().fill(color)
                        .frame(width: geometry.size.width * min(1, max(0, percent / 100)))
                }
        }
        .frame(height: 7)
        .accessibilityHidden(true)
    }
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
