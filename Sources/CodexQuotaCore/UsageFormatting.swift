import Foundation

public enum UsageFormatting {
    private static let locale = Locale(identifier: "en_GB")

    /// Decimal units; promote values that round up at a unit boundary.
    public static func compact(_ value: Int64?) -> String {
        guard let value else { return "—" }
        let units = ["", "K", "M", "B", "T", "Q"]
        var scaled = Decimal(value)
        var unit = 0
        while abs(scaled) >= 1000, unit < units.count - 1 {
            scaled /= 1000
            unit += 1
        }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 1, .plain)
        if abs(rounded) >= 1000, unit < units.count - 1 {
            rounded /= 1000
            unit += 1
        }
        return rounded.formatted(.number.precision(.fractionLength(0...1)).locale(locale)) + units[unit]
    }

    public static func exact(_ value: Int64?) -> String {
        guard let value else { return "Not available" }
        return value.formatted(.number.locale(locale))
    }

    public static func duration(_ seconds: Int64?) -> String {
        guard let seconds, seconds >= 0 else { return "—" }
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m \(seconds % 60)s" }
        if seconds < 86_400 { return "\(seconds / 3600)h \((seconds % 3600) / 60)m" }
        return "\(compact(seconds / 86_400))d \((seconds % 86_400) / 3600)h"
    }
}
