import Foundation

public struct AccountRecord: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var label: String
    public var codexHome: String
    public var createdAt: Date

    public init(id: String, label: String, codexHome: String, createdAt: Date) {
        self.id = id
        self.label = label
        self.codexHome = codexHome
        self.createdAt = createdAt
    }
}

public struct DailyBucket: Codable, Equatable, Sendable {
    public var startDate: String
    public var tokens: Int64

    public init(startDate: String, tokens: Int64) {
        self.startDate = startDate
        self.tokens = tokens
    }
}

public struct UsageSample: Codable, Equatable, Sendable {
    public var accountId: String
    public var sampledAt: Date
    public var email: String?
    public var planType: String?
    public var limitId: String?
    public var limitName: String?
    public var usedPercent: Double?
    public var windowDurationMins: Double?
    public var resetsAt: Date?
    public var reached: String?
    public var lifetimeTokens: Int64?
    public var peakDailyTokens: Int64?
    public var shortUsedPercent: Double?
    public var shortDurationMins: Double?
    public var dailyBuckets: [DailyBucket]

    public init(
        accountId: String,
        sampledAt: Date,
        email: String?,
        planType: String?,
        limitId: String?,
        limitName: String?,
        usedPercent: Double?,
        windowDurationMins: Double?,
        resetsAt: Date?,
        reached: String?,
        lifetimeTokens: Int64?,
        peakDailyTokens: Int64?,
        shortUsedPercent: Double?,
        shortDurationMins: Double?,
        dailyBuckets: [DailyBucket]
    ) {
        self.accountId = accountId
        self.sampledAt = sampledAt
        self.email = email
        self.planType = planType
        self.limitId = limitId
        self.limitName = limitName
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
        self.reached = reached
        self.lifetimeTokens = lifetimeTokens
        self.peakDailyTokens = peakDailyTokens
        self.shortUsedPercent = shortUsedPercent
        self.shortDurationMins = shortDurationMins
        self.dailyBuckets = dailyBuckets
    }

    public static func make(
        accountId: String = "account",
        sampledAt: Date,
        email: String? = nil,
        planType: String? = "plus",
        limitId: String? = "codex",
        limitName: String? = "Codex",
        usedPercent: Double? = nil,
        windowDurationMins: Double? = QuotaTiming.weeklyMinutes,
        resetsAt: Date? = nil,
        reached: String? = nil,
        lifetimeTokens: Int64? = nil,
        peakDailyTokens: Int64? = nil,
        shortUsedPercent: Double? = nil,
        shortDurationMins: Double? = nil,
        dailyBuckets: [DailyBucket] = []
    ) -> UsageSample {
        UsageSample(
            accountId: accountId,
            sampledAt: sampledAt,
            email: email,
            planType: planType,
            limitId: limitId,
            limitName: limitName,
            usedPercent: usedPercent,
            windowDurationMins: windowDurationMins,
            resetsAt: resetsAt,
            reached: reached,
            lifetimeTokens: lifetimeTokens,
            peakDailyTokens: peakDailyTokens,
            shortUsedPercent: shortUsedPercent,
            shortDurationMins: shortDurationMins,
            dailyBuckets: dailyBuckets
        )
    }
}

public struct StoreFile: Codable, Equatable, Sendable {
    public var version: Int
    public var selectedAccountId: String?
    public var accounts: [AccountRecord]
    public var samples: [UsageSample]

    public static let currentVersion = 1

    public static func empty() -> StoreFile {
        StoreFile(version: currentVersion, selectedAccountId: nil, accounts: [], samples: [])
    }
}

public struct AccountIdentity: Equatable, Sendable {
    public var type: String
    public var email: String?
    public var planType: String?
}

public struct WeeklyWindow: Equatable, Sendable {
    public var limitId: String?
    public var limitName: String
    public var planType: String?
    public var usedPercent: Double
    public var windowDurationMins: Double
    public var resetsAt: Date?
    public var reached: String?
}

public struct ShortWindow: Equatable, Sendable {
    public var usedPercent: Double
    public var windowDurationMins: Double
    public var resetsAt: Date?
}

public struct UsageReading: Equatable, Sendable {
    public var identity: AccountIdentity?
    public var weekly: WeeklyWindow?
    public var shortWindow: ShortWindow?
    public var lifetimeTokens: Int64?
    public var peakDailyTokens: Int64?
    public var dailyBuckets: [DailyBucket]
}

public struct WeekStat: Equatable, Identifiable, Sendable {
    public var resetsAt: Date
    public var usedPercent: Double
    public var complete: Bool

    public var id: TimeInterval { resetsAt.timeIntervalSince1970 }
}

public struct UsageTotals: Equatable, Sendable {
    public var lifetimeTokens: Int64?
    public var peakDailyTokens: Int64?
    public var recordedTokens: Int64
    public var weeks: Int
    public var averageWeeklyPercent: Double?
}

public enum LondonClock {
    public static let zone = TimeZone(identifier: "Europe/London")!

    public static func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = Locale(identifier: "en_GB")
        return calendar
    }

    public static func isoDate(_ date: Date) -> String {
        let parts = calendar().dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    public static func resetLine(_ date: Date) -> String {
        let calendar = calendar()
        let weekday = calendar.shortWeekdaySymbols[(calendar.component(.weekday, from: date) - 1 + 7) % 7]
        let day = calendar.component(.day, from: date)
        let month = calendar.shortMonthSymbols[calendar.component(.month, from: date) - 1]
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let zone = zone.abbreviation(for: date) ?? "UK"
        return String(format: "%@ %d %@, %02d:%02d %@", weekday, day, month, hour, minute, zone)
    }

    public static func dayLabel(_ date: Date) -> String {
        let calendar = calendar()
        let day = calendar.component(.day, from: date)
        let month = calendar.shortMonthSymbols[calendar.component(.month, from: date) - 1]
        return "\(day) \(month)"
    }

    public static func checkedLine(_ date: Date) -> String {
        let calendar = calendar()
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "Checked at %02d:%02d UK", hour, minute)
    }
}
