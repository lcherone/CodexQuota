import Foundation

public enum UsageParsing {
    public static func reading(account: JSONValue, limits: JSONValue, usage: JSONValue) -> UsageReading {
        let identity = identity(from: account)
        let weekly = weeklyWindow(from: limits)
        let short = shortWindow(from: limits)
        let summary = usage.object?["summary"]?.object
        let buckets = usage.object?["dailyUsageBuckets"]?.array?.compactMap(bucket) ?? []
        var reading = UsageReading(
            identity: identity,
            weekly: weekly,
            shortWindow: short,
            lifetimeTokens: summary?["lifetimeTokens"]?.int64,
            peakDailyTokens: summary?["peakDailyTokens"]?.int64,
            dailyBuckets: buckets,
            longestRunningTurnSec: summary?["longestRunningTurnSec"]?.int64,
            currentStreakDays: summary?["currentStreakDays"]?.int64,
            longestStreakDays: summary?["longestStreakDays"]?.int64
        )
        reading.quotaDetails = AccountDetailsParsing.quota(limits)
        return reading
    }

    public static func isSignedIn(_ account: JSONValue) -> Bool {
        guard let value = account.object?["account"], !value.isNull else { return false }
        return true
    }

    public static func loginURL(_ login: JSONValue) -> URL? {
        guard login.object?["type"]?.string == "chatgpt",
              let raw = login.object?["authUrl"]?.string,
              let url = URL(string: raw),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false else {
            return nil
        }
        return url
    }

    private static func identity(from account: JSONValue) -> AccountIdentity? {
        guard let value = account.object?["account"], !value.isNull else { return nil }
        return AccountIdentity(
            type: value.object?["type"]?.string ?? "unknown",
            email: value.object?["email"]?.string,
            planType: value.object?["planType"]?.string
        )
    }

    private static func bucket(_ value: JSONValue) -> DailyBucket? {
        guard let date = value.object?["startDate"]?.string, !date.isEmpty, let tokens = value.object?["tokens"]?.int64 else {
            return nil
        }
        return DailyBucket(startDate: date, tokens: tokens)
    }

    private static func weeklyWindow(from limits: JSONValue) -> WeeklyWindow? {
        if let found = chooseWeekly(windows(from: limits)) { return found }
        guard let legacy = limits.object?["rateLimits"] else { return nil }
        return chooseWeekly(windows(in: [(legacy.object?["limitId"]?.string, legacy)]))
    }

    private static func chooseWeekly(_ candidates: [WindowCandidate]) -> WeeklyWindow? {
        let weekly = candidates.filter { $0.minutes >= QuotaTiming.weeklyLower && $0.minutes <= QuotaTiming.weeklyUpper }
        let preferred = weekly.filter(isCodex)
        let pool = preferred.isEmpty ? weekly : preferred
        return pool.min(by: { abs($0.minutes - QuotaTiming.weeklyMinutes) < abs($1.minutes - QuotaTiming.weeklyMinutes) })?.asWeekly
    }

    private static func shortWindow(from limits: JSONValue) -> ShortWindow? {
        let candidates = windows(from: limits).filter { $0.minutes >= 60 && $0.minutes <= 720 }
        let preferred = candidates.filter(isCodex)
        let pool = preferred.isEmpty ? candidates : preferred
        guard let best = pool.min(by: { abs($0.minutes - 300) < abs($1.minutes - 300) }) else { return nil }
        return ShortWindow(usedPercent: best.used, windowDurationMins: best.minutes, resetsAt: best.resetsAt)
    }

    private struct WindowCandidate {
        var key: String?
        var limitId: String?
        var limitName: String?
        var planType: String?
        var reached: String?
        var used: Double
        var minutes: Double
        var resetsAt: Date?

        var asWeekly: WeeklyWindow {
            WeeklyWindow(
                limitId: limitId ?? key,
                limitName: limitName ?? "Codex",
                planType: planType,
                usedPercent: used,
                windowDurationMins: minutes,
                resetsAt: resetsAt,
                reached: reached
            )
        }
    }

    private static func isCodex(_ candidate: WindowCandidate) -> Bool {
        let id = (candidate.limitId ?? candidate.key ?? "").lowercased()
        let name = (candidate.limitName ?? "").lowercased()
        return id == "codex" || name.contains("codex")
    }

    private static func windows(from limits: JSONValue) -> [WindowCandidate] {
        let byID = limits.object?["rateLimitsByLimitId"]?.object ?? [:]
        let primary = windows(in: byID.map { ($0.key, $0.value) })
        if !primary.isEmpty {
            return primary
        }
        guard let legacy = limits.object?["rateLimits"] else { return [] }
        return windows(in: [(legacy.object?["limitId"]?.string, legacy)])
    }

    private static func windows(in snapshots: [(String?, JSONValue)]) -> [WindowCandidate] {
        snapshots.flatMap { key, snapshot -> [WindowCandidate] in
            ["primary", "secondary"].compactMap { slot in
                guard let window = snapshot.object?[slot], let used = window.object?["usedPercent"]?.double, used >= 0,
                      let minutes = window.object?["windowDurationMins"]?.double, minutes > 0 else {
                    return nil
                }
                return WindowCandidate(
                    key: key,
                    limitId: snapshot.object?["limitId"]?.string,
                    limitName: snapshot.object?["limitName"]?.string,
                    planType: snapshot.object?["planType"]?.string,
                    reached: reached(snapshot.object?["rateLimitReachedType"]),
                    used: min(100, used),
                    minutes: minutes,
                    resetsAt: resetDate(window.object?["resetsAt"]?.double)
                )
            }
        }
    }

    private static func reached(_ value: JSONValue?) -> String? {
        guard let value, !value.isNull else { return nil }
        if let text = value.string, !text.isEmpty { return text }
        return "reached"
    }

    public static func resetDate(_ value: Double?) -> Date? {
        guard let value, value > 0, value.isFinite else { return nil }
        let seconds = value >= 100_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }
}
