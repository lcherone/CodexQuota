import Foundation

public struct QuotaWindowDetails: Codable, Equatable, Sendable {
    public var usedPercent: Double?
    public var durationMinutes: Double?
    public var resetsAt: Date?
}

public struct CreditDetails: Codable, Equatable, Sendable {
    public var hasCredits: Bool?
    public var unlimited: Bool?
    public var balance: String?
}

public struct MonthlyLimitDetails: Codable, Equatable, Sendable {
    public var limit: String?
    public var used: String?
    public var remainingPercent: Double?
    public var resetsAt: Date?
}

public struct QuotaBucketDetails: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var plan: String?
    public var primary: QuotaWindowDetails?
    public var secondary: QuotaWindowDetails?
    public var credits: CreditDetails?
    public var monthlyLimit: MonthlyLimitDetails?
    public var spendControlReached: Bool?
    public var reached: String?
}

public struct EarnedResetDetails: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var type: String?
    public var status: String?
    public var grantedAt: Date?
    public var expiresAt: Date?
    public var title: String?
    public var description: String?
}

public struct QuotaDetails: Codable, Equatable, Sendable {
    public var buckets: [QuotaBucketDetails]
    public var availableResets: Int64?
    public var resets: [EarnedResetDetails]?
}

public struct WorkspaceMessageDetails: Equatable, Identifiable, Sendable {
    public var id: String
    public var type: String?
    public var body: String
    public var createdAt: Date?
    public var archivedAt: Date?
}

public struct WorkspaceMessagesDetails: Equatable, Sendable {
    public var featureEnabled: Bool
    public var messages: [WorkspaceMessageDetails]
}

public struct ConversationSummary: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var provider: String?
    public var updatedAt: Date?
    public var directory: String?
}

public struct ConversationPage: Equatable, Sendable {
    public var conversations: [ConversationSummary]
    public var nextCursor: String?
}

public struct ConversationUsageGroup: Equatable, Sendable {
    public var model: String?
    public var reasoningEffort: String?
    public var speed: String?
    public var creditsMicros: Int64?
    public var newInputTokens: Int64?
    public var cachedInputTokens: Int64?
    public var inputTokens: Int64?
    public var outputTokens: Int64?
    public var totalTokens: Int64?
}

public struct ConversationUsageDetails: Equatable, Sendable {
    public var threadID: String
    public var creditsMicros: Int64?
    public var usdMicros: Int64?
    public var nativeUsdMicros: Int64?
    public var groups: [ConversationUsageGroup]
}

public enum AccountDetailsParsing {
    private static func date(_ value: JSONValue?) -> Date? {
        UsageParsing.resetDate(value?.double)
    }

    private static func window(_ value: JSONValue?) -> QuotaWindowDetails? {
        guard let fields = value?.object else { return nil }
        return QuotaWindowDetails(
            usedPercent: fields["usedPercent"]?.double,
            durationMinutes: fields["windowDurationMins"]?.double,
            resetsAt: date(fields["resetsAt"])
        )
    }

    public static func quota(_ value: JSONValue) -> QuotaDetails {
        let byID = value.object?["rateLimitsByLimitId"]?.object ?? [:]
        let snapshots: [(String, JSONValue)]
        if !byID.isEmpty {
            snapshots = byID.sorted { $0.key < $1.key }
        } else if let legacy = value.object?["rateLimits"], legacy.object != nil {
            snapshots = [(legacy.object?["limitId"]?.string ?? "codex", legacy)]
        } else {
            snapshots = []
        }
        let buckets = snapshots.map { key, snapshot in
            let fields = snapshot.object ?? [:]
            let credits = fields["credits"]?.object.map {
                CreditDetails(hasCredits: $0["hasCredits"]?.bool, unlimited: $0["unlimited"]?.bool, balance: $0["balance"]?.string)
            }
            let monthly = fields["individualLimit"]?.object.map {
                MonthlyLimitDetails(limit: $0["limit"]?.string, used: $0["used"]?.string,
                                    remainingPercent: $0["remainingPercent"]?.double, resetsAt: date($0["resetsAt"]))
            }
            return QuotaBucketDetails(
                id: key, name: fields["limitName"]?.string ?? fields["limitId"]?.string ?? key,
                plan: fields["planType"]?.string, primary: window(fields["primary"]), secondary: window(fields["secondary"]),
                credits: credits, monthlyLimit: monthly, spendControlReached: fields["spendControlReached"]?.bool,
                reached: fields["rateLimitReachedType"]?.string
            )
        }
        let resets = value.object?["rateLimitResetCredits"]?.object
        let rows = resets?["credits"]?.array?.compactMap { value -> EarnedResetDetails? in
            guard let fields = value.object, let id = fields["id"]?.string else { return nil }
            return EarnedResetDetails(id: id, type: fields["resetType"]?.string, status: fields["status"]?.string,
                                     grantedAt: date(fields["grantedAt"]), expiresAt: date(fields["expiresAt"]),
                                     title: fields["title"]?.string, description: fields["description"]?.string)
        }
        return QuotaDetails(buckets: buckets, availableResets: resets?["availableCount"]?.int64, resets: rows)
    }

    public static func workspace(_ value: JSONValue) throws -> WorkspaceMessagesDetails {
        guard let enabled = value.object?["featureEnabled"]?.bool,
              let rows = value.object?["messages"]?.array else { throw QuotaFailure.unreadable }
        return WorkspaceMessagesDetails(featureEnabled: enabled, messages: rows.compactMap { value in
            guard let fields = value.object, let id = fields["messageId"]?.string,
                  let body = fields["messageBody"]?.string else { return nil }
            return WorkspaceMessageDetails(id: id, type: fields["messageType"]?.string, body: body,
                                           createdAt: date(fields["createdAt"]), archivedAt: date(fields["archivedAt"]))
        })
    }

    public static func conversations(_ value: JSONValue) throws -> ConversationPage {
        guard let rows = value.object?["data"]?.array else { throw QuotaFailure.unreadable }
        return ConversationPage(conversations: rows.compactMap { value in
            guard let fields = value.object, let id = fields["id"]?.string else { return nil }
            let name = fields["name"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = fields["preview"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = [name, preview].compactMap { $0 }.first { !$0.isEmpty } ?? id
            return ConversationSummary(id: id, title: title, provider: fields["modelProvider"]?.string,
                                       updatedAt: date(fields["updatedAt"]), directory: fields["cwd"]?.string)
        }, nextCursor: value.object?["nextCursor"]?.string)
    }

    public static func conversationUsage(_ value: JSONValue, threadID: String) throws -> ConversationUsageDetails? {
        guard let usage = value.object?["threadUsage"], !usage.isNull else { return nil }
        guard let fields = usage.object, fields["threadId"]?.string == threadID else { throw QuotaFailure.unreadable }
        let groups: [ConversationUsageGroup] = fields["groups"]?.array?.map { value in
            let row = value.object ?? [:]
            return ConversationUsageGroup(
                model: row["model"]?.string, reasoningEffort: row["reasoningEffort"]?.string, speed: row["speed"]?.string,
                creditsMicros: row["estimatedUsageCreditsMicros"]?.int64, newInputTokens: row["netNewInputTokens"]?.int64,
                cachedInputTokens: row["cachedInputTokens"]?.int64, inputTokens: row["inputTokens"]?.int64,
                outputTokens: row["outputTokens"]?.int64, totalTokens: row["totalTokens"]?.int64
            )
        } ?? []
        return ConversationUsageDetails(threadID: threadID, creditsMicros: fields["estimatedUsageCreditsMicros"]?.int64,
                                        usdMicros: fields["estimatedUsageUsdMicros"]?.int64,
                                        nativeUsdMicros: fields["nativeUsageUsdMicros"]?.int64, groups: groups)
    }
}
