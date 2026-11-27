import Foundation

public struct AccountRecord: Codable, Equatable, Identifiable, Sendable {
    public static let maximumLabelLength = 40

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

    public static func normalizedLabel(_ input: String, retaining fallback: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallback }
        return String(trimmed.prefix(maximumLabelLength))
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
    public var longestRunningTurnSec: Int64? = nil
    public var currentStreakDays: Int64? = nil
    public var longestStreakDays: Int64? = nil
    public var optionalStatisticsSampledAt: Date? = nil
    public var optionalStatisticsArePartial: Bool? = nil

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
        dailyBuckets: [DailyBucket],
        longestRunningTurnSec: Int64? = nil,
        currentStreakDays: Int64? = nil,
        longestStreakDays: Int64? = nil,
        optionalStatisticsSampledAt: Date? = nil,
        optionalStatisticsArePartial: Bool? = nil
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
        self.longestRunningTurnSec = longestRunningTurnSec
        self.currentStreakDays = currentStreakDays
        self.longestStreakDays = longestStreakDays
        self.optionalStatisticsSampledAt = optionalStatisticsSampledAt
        self.optionalStatisticsArePartial = optionalStatisticsArePartial
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
        dailyBuckets: [DailyBucket] = [],
        longestRunningTurnSec: Int64? = nil,
        currentStreakDays: Int64? = nil,
        longestStreakDays: Int64? = nil,
        optionalStatisticsSampledAt: Date? = nil,
        optionalStatisticsArePartial: Bool? = nil
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
            dailyBuckets: dailyBuckets,
            longestRunningTurnSec: longestRunningTurnSec,
            currentStreakDays: currentStreakDays,
            longestStreakDays: longestStreakDays,
            optionalStatisticsSampledAt: optionalStatisticsSampledAt,
            optionalStatisticsArePartial: optionalStatisticsArePartial
        )
    }

    public static func merging(
        accountId: String,
        sampledAt: Date,
        reading: UsageReading,
        previous: UsageSample?
    ) -> UsageSample? {
        guard let identity = reading.identity else { return nil }
        let retained = reading.optionalUsageSucceeded ? nil : previous
        let retainedStatisticsTime = retained?.optionalStatisticsSampledAt
            ?? (retained?.hasOptionalStatistics == true ? retained?.sampledAt : nil)
        return UsageSample(
            accountId: accountId,
            sampledAt: sampledAt,
            email: identity.email,
            planType: reading.weekly?.planType ?? identity.planType,
            limitId: reading.weekly?.limitId,
            limitName: reading.weekly?.limitName,
            usedPercent: reading.weekly?.usedPercent,
            windowDurationMins: reading.weekly?.windowDurationMins,
            resetsAt: reading.weekly?.resetsAt,
            reached: reading.weekly?.reached,
            lifetimeTokens: retained?.lifetimeTokens ?? reading.lifetimeTokens,
            peakDailyTokens: retained?.peakDailyTokens ?? reading.peakDailyTokens,
            shortUsedPercent: reading.shortWindow?.usedPercent,
            shortDurationMins: reading.shortWindow?.windowDurationMins,
            dailyBuckets: retained?.dailyBuckets ?? reading.dailyBuckets,
            longestRunningTurnSec: retained?.longestRunningTurnSec ?? reading.longestRunningTurnSec,
            currentStreakDays: retained?.currentStreakDays ?? reading.currentStreakDays,
            longestStreakDays: retained?.longestStreakDays ?? reading.longestStreakDays,
            optionalStatisticsSampledAt: reading.optionalUsageSucceeded ? sampledAt : retainedStatisticsTime,
            optionalStatisticsArePartial: !reading.optionalUsageSucceeded
        )
    }

    public var hasOptionalStatistics: Bool {
        lifetimeTokens != nil
            || peakDailyTokens != nil
            || !dailyBuckets.isEmpty
            || longestRunningTurnSec != nil
            || currentStreakDays != nil
            || longestStreakDays != nil
    }
}

public enum PanelAppearance: String, Codable, Equatable, Sendable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    public var id: String { rawValue }
}

public struct QuotaAlertPreferences: Codable, Equatable, Sendable {
    public static let defaultThreshold = 80
    public static let supportedThresholds = 1...100

    public var enabled: Bool
    public var weeklyThreshold: Int

    public init(enabled: Bool = false, weeklyThreshold: Int = defaultThreshold) {
        self.enabled = enabled
        self.weeklyThreshold = Self.normalizedThreshold(weeklyThreshold)
    }

    public static func normalizedThreshold(_ threshold: Int) -> Int {
        min(supportedThresholds.upperBound, max(supportedThresholds.lowerBound, threshold))
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
        case weeklyThreshold
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        weeklyThreshold = Self.normalizedThreshold(
            try container.decodeIfPresent(Int.self, forKey: .weeklyThreshold) ?? Self.defaultThreshold
        )
    }
}

public struct QuotaAlertReceipt: Codable, Equatable, Sendable {
    public var accountId: String
    public var resetAt: Date
    public var eventId: String
    public var deliveredAt: Date

    public init(accountId: String, resetAt: Date, eventId: String, deliveredAt: Date) {
        self.accountId = accountId
        self.resetAt = resetAt
        self.eventId = eventId
        self.deliveredAt = deliveredAt
    }
}

public struct StoreFile: Codable, Equatable, Sendable {
    public var version: Int
    public var selectedAccountId: String?
    public var accounts: [AccountRecord]
    public var samples: [UsageSample]
    public var appearance: PanelAppearance
    public var alertPreferences: QuotaAlertPreferences
    public var alertReceipts: [QuotaAlertReceipt]

    public static let currentVersion = 1

    public init(
        version: Int,
        selectedAccountId: String?,
        accounts: [AccountRecord],
        samples: [UsageSample],
        appearance: PanelAppearance = .system,
        alertPreferences: QuotaAlertPreferences = QuotaAlertPreferences(),
        alertReceipts: [QuotaAlertReceipt] = []
    ) {
        self.version = version
        self.selectedAccountId = selectedAccountId
        self.accounts = accounts
        self.samples = samples
        self.appearance = appearance
        self.alertPreferences = alertPreferences
        self.alertReceipts = alertReceipts
    }

    public static func empty() -> StoreFile {
        StoreFile(version: currentVersion, selectedAccountId: nil, accounts: [], samples: [])
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case selectedAccountId
        case accounts
        case samples
        case appearance
        case alertPreferences
        case alertReceipts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        selectedAccountId = try container.decodeIfPresent(String.self, forKey: .selectedAccountId)
        accounts = try container.decode([AccountRecord].self, forKey: .accounts)
        samples = try container.decode([UsageSample].self, forKey: .samples)
        appearance = try container.decodeIfPresent(PanelAppearance.self, forKey: .appearance) ?? .system
        alertPreferences = try container.decodeIfPresent(QuotaAlertPreferences.self, forKey: .alertPreferences) ?? QuotaAlertPreferences()
        alertReceipts = try container.decodeIfPresent([QuotaAlertReceipt].self, forKey: .alertReceipts) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encodeIfPresent(selectedAccountId, forKey: .selectedAccountId)
        try container.encode(accounts, forKey: .accounts)
        try container.encode(samples, forKey: .samples)
        try container.encode(appearance, forKey: .appearance)
        try container.encode(alertPreferences, forKey: .alertPreferences)
        try container.encode(alertReceipts, forKey: .alertReceipts)
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
    public var longestRunningTurnSec: Int64? = nil
    public var currentStreakDays: Int64? = nil
    public var longestStreakDays: Int64? = nil
    public var optionalUsageSucceeded: Bool = true
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
    public var completedWeekAveragePercent: Double?
    public var currentWeekPercent: Double?
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
