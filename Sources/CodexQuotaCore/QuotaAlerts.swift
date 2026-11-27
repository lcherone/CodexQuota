import Foundation

public enum QuotaAlertEvent: Equatable, Sendable {
    case weeklyThreshold(Int)
    case ahead(slice: Int)
    case reached

    public var eventId: String {
        switch self {
        case let .weeklyThreshold(threshold): "threshold-\(threshold)"
        case let .ahead(slice): "ahead-slice-\(slice)"
        case .reached: "reached"
        }
    }
}

public struct QuotaAlertCandidate: Equatable, Sendable {
    public var accountId: String
    public var resetAt: Date
    public var event: QuotaAlertEvent

    public init(accountId: String, resetAt: Date, event: QuotaAlertEvent) {
        self.accountId = accountId
        self.resetAt = resetAt
        self.event = event
    }
}

public enum QuotaAlerts {
    public static let receiptCap = 200

    public static func candidates(
        accountId: String,
        previousSample: UsageSample?,
        previousPace: PaceReport?,
        sample: UsageSample,
        pace: PaceReport?,
        preferences: QuotaAlertPreferences,
        receipts: [QuotaAlertReceipt]
    ) -> [QuotaAlertCandidate] {
        guard preferences.enabled, let resetAt = sample.resetsAt else { return [] }
        let sameWindow = previousSample?.resetsAt.map { abs($0.timeIntervalSince(resetAt)) < 1 } == true
        var events: [QuotaAlertEvent] = []

        if sameWindow,
           let previousUsed = previousSample?.usedPercent,
           let used = sample.usedPercent,
           previousUsed < Double(preferences.weeklyThreshold),
           used >= Double(preferences.weeklyThreshold) {
            events.append(.weeklyThreshold(preferences.weeklyThreshold))
        }
        if sameWindow,
           let previousPace,
           previousPace.dayStatus != .over,
           let pace,
           pace.dayStatus == .over {
            events.append(.ahead(slice: pace.todayIndex))
        }
        if sameWindow, !isReached(previousSample?.reached), isReached(sample.reached) {
            events.append(.reached)
        }

        return events.compactMap { event in
            let alreadyDelivered = receipts.contains {
                $0.accountId == accountId
                    && abs($0.resetAt.timeIntervalSince(resetAt)) < 1
                    && $0.eventId == event.eventId
            }
            return alreadyDelivered ? nil : QuotaAlertCandidate(accountId: accountId, resetAt: resetAt, event: event)
        }
    }

    public static func addingReceipt(
        for candidate: QuotaAlertCandidate,
        deliveredAt: Date,
        to receipts: [QuotaAlertReceipt],
        activeResetDates: [Date]
    ) -> [QuotaAlertReceipt] {
        let active = receipts.filter { receipt in
            activeResetDates.contains { abs($0.timeIntervalSince(receipt.resetAt)) < 1 }
        }
        let receipt = QuotaAlertReceipt(
            accountId: candidate.accountId,
            resetAt: candidate.resetAt,
            eventId: candidate.event.eventId,
            deliveredAt: deliveredAt
        )
        return Array((active + [receipt]).suffix(receiptCap))
    }

    public static func prunedReceipts(
        _ receipts: [QuotaAlertReceipt],
        activeResetDates: [Date]
    ) -> [QuotaAlertReceipt] {
        Array(receipts.filter { receipt in
            activeResetDates.contains { abs($0.timeIntervalSince(receipt.resetAt)) < 1 }
        }.suffix(receiptCap))
    }

    private static func isReached(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
