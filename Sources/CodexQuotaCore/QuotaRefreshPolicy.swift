import Foundation

public enum QuotaRefreshPolicy {
    public static func shouldRefreshAfterSelection(
        selectionChanged: Bool,
        latestSampledAt: Date?,
        isBusy: Bool,
        now: Date
    ) -> Bool {
        guard selectionChanged, !isBusy else { return false }
        guard let latestSampledAt else { return true }
        return now.timeIntervalSince(latestSampledAt) > QuotaTiming.staleInterval
    }
}
