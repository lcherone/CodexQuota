import Foundation

public enum DayStatus: Equatable, Sendable {
    case over
    case on
    case under
    case unknown
}

public enum SliceKind: Equatable, Sendable {
    case measured
    case estimated
    case partial
    case unknown
}

public struct PaceSlice: Equatable, Sendable {
    public var index: Int
    public var start: Date
    public var end: Date
    public var midpoint: Date
    public var londonDate: String
    public var points: Double?
    public var kind: SliceKind
}

public struct PaceReport: Equatable, Sendable {
    public var slices: [PaceSlice]
    public var todayIndex: Int
    public var weeklyUsedPercent: Double
    public var todayWeeklyPoints: Double?
    public var todaySlicePercent: Double?
    public var todayKind: SliceKind
    public var dayStatus: DayStatus
    public var expectedTodayPoints: Double
    public var remainingPercent: Double
    public var futureFullSlices: Int
    public var weekHasRoom: Bool
    public var windowStart: Date
    public var reset: Date
    public var weekLinearStatus: DayStatus
    public var sliceBudget: Double
}

public enum Pace {
    public static func evaluate(
        now: Date,
        usedPercent: Double,
        resetsAt: Date,
        windowDurationMins: Double,
        samples: [UsageSample],
        buckets: [DailyBucket]
    ) -> PaceReport? {
        guard windowDurationMins > 0, windowDurationMins.isFinite, usedPercent.isFinite else { return nil }
        let used = min(100, max(0, usedPercent))
        let duration = windowDurationMins * 60
        let windowStart = resetsAt.addingTimeInterval(-duration)
        guard now >= windowStart, now < resetsAt else { return nil }
        let slice = duration / Double(QuotaTiming.sliceCount)
        guard slice > 0 else { return nil }
        var index = Int(now.timeIntervalSince(windowStart) / slice)
        index = min(QuotaTiming.sliceCount - 1, max(0, index))

        let relevant = samples
            .filter { sample in
                guard let sampleReset = sample.resetsAt, sameReset(sampleReset, resetsAt), sample.usedPercent != nil else {
                    return false
                }
                return true
            }
            .sorted { $0.sampledAt < $1.sampledAt }

        var slices: [PaceSlice] = []
        for offset in 0..<QuotaTiming.sliceCount {
            let start = windowStart.addingTimeInterval(Double(offset) * slice)
            let end = windowStart.addingTimeInterval(Double(offset + 1) * slice)
            let midpoint = start.addingTimeInterval(slice / 2)
            let measured = consumption(start: start, end: end, now: now, samples: relevant)
            slices.append(PaceSlice(
                index: offset,
                start: start,
                end: end,
                midpoint: midpoint,
                londonDate: LondonClock.isoDate(midpoint),
                points: measured?.points,
                kind: measured?.kind ?? .unknown
            ))
        }

        applyEstimates(usedPercent: used, buckets: buckets, slices: &slices)

        let today = slices[index]
        let fraction = min(1, max(0, now.timeIntervalSince(today.start) / slice))
        let budget = 100.0 / Double(QuotaTiming.sliceCount)
        let expectedToday = fraction * budget
        let dayStatus = status(actual: today.points, expected: expectedToday, kind: today.kind)
        let elapsed = min(1, max(0, now.timeIntervalSince(windowStart) / duration))
        let future = QuotaTiming.sliceCount - index - 1
        let remaining = 100 - used
        let room = remaining + 0.000_001 >= Double(future) * budget

        return PaceReport(
            slices: slices,
            todayIndex: index,
            weeklyUsedPercent: used,
            todayWeeklyPoints: today.points,
            todaySlicePercent: today.points.map { $0 / budget * 100 },
            todayKind: today.kind,
            dayStatus: dayStatus,
            expectedTodayPoints: expectedToday,
            remainingPercent: remaining,
            futureFullSlices: future,
            weekHasRoom: room,
            windowStart: windowStart,
            reset: resetsAt,
            weekLinearStatus: status(actual: used, expected: elapsed * 100, kind: .measured),
            sliceBudget: budget
        )
    }

    public static func menuTitle(todaySlicePercent: Double?, todayKind: SliceKind, dayStatus: DayStatus, weeklyUsed: Double?) -> String {
        if let todaySlicePercent, todayKind == .measured || todayKind == .estimated {
            let rounded = Int(todaySlicePercent.rounded())
            if dayStatus == .over {
                return "\(rounded)% over"
            }
            return "\(rounded)%"
        }
        if let weeklyUsed {
            return "\(Int(weeklyUsed.rounded()))% wk"
        }
        return "Quota"
    }

    private struct Measured {
        var points: Double
        var kind: SliceKind
    }

    private static func consumption(start: Date, end: Date, now: Date, samples: [UsageSample]) -> Measured? {
        let horizon = min(now, end)
        guard horizon > start else { return nil }
        let baseline = samples.last { $0.sampledAt <= start }
        let inside = samples.filter { $0.sampledAt > start && $0.sampledAt <= horizon }
        guard let endSample = inside.last, let endUsed = endSample.usedPercent else {
            return nil
        }
        if let baseline, let baseUsed = baseline.usedPercent {
            return Measured(points: max(0, endUsed - baseUsed), kind: .measured)
        }
        guard let first = inside.first, let firstUsed = first.usedPercent, endSample.sampledAt > first.sampledAt else {
            return nil
        }
        return Measured(points: max(0, endUsed - firstUsed), kind: .partial)
    }

    private static func applyEstimates(usedPercent: Double, buckets: [DailyBucket], slices: inout [PaceSlice]) {
        let dates = Set(slices.map(\.londonDate))
        let matched = buckets.filter { dates.contains($0.startDate) }
        let sum = matched.reduce(Int64(0)) { $0 + max(0, $1.tokens) }
        guard sum > 0 else { return }
        for index in slices.indices where slices[index].kind == .unknown {
            guard let bucket = matched.first(where: { $0.startDate == slices[index].londonDate }) else { continue }
            slices[index].points = usedPercent * Double(max(0, bucket.tokens)) / Double(sum)
            slices[index].kind = .estimated
        }
    }

    private static func status(actual: Double?, expected: Double, kind: SliceKind) -> DayStatus {
        guard let actual else { return .unknown }
        switch kind {
        case .unknown:
            return .unknown
        case .partial:
            return actual > expected + QuotaTiming.tolerance ? .over : .unknown
        case .measured, .estimated:
            if actual > expected + QuotaTiming.tolerance { return .over }
            if actual < expected - QuotaTiming.tolerance { return .under }
            return .on
        }
    }

    private static func sameReset(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 1
    }
}

public enum UsageStats {
    public static func weeks(samples: [UsageSample], now: Date) -> [WeekStat] {
        struct Group {
            var resetsAt: Date
            var samples: [UsageSample]
        }
        var groups: [Int: Group] = [:]
        for sample in samples {
            guard let resetsAt = sample.resetsAt, sample.usedPercent != nil else { continue }
            let key = Int(resetsAt.timeIntervalSince1970.rounded())
            var group = groups[key] ?? Group(resetsAt: resetsAt, samples: [])
            group.samples.append(sample)
            groups[key] = group
        }
        return groups.values.map { group in
            let ordered = group.samples.sorted { $0.sampledAt < $1.sampledAt }
            let complete = group.resetsAt <= now
            let used: Double
            if complete {
                used = ordered.compactMap(\.usedPercent).max() ?? 0
            } else {
                used = ordered.last?.usedPercent ?? 0
            }
            return WeekStat(resetsAt: group.resetsAt, usedPercent: min(100, max(0, used)), complete: complete)
        }
        .sorted { $0.resetsAt > $1.resetsAt }
    }

    public static func totals(samples: [UsageSample], now: Date) -> UsageTotals {
        let ordered = samples.sorted { $0.sampledAt < $1.sampledAt }
        let weeks = weeks(samples: samples, now: now)
        var buckets: [String: (Date, Int64)] = [:]
        for sample in ordered {
            for bucket in sample.dailyBuckets where bucket.tokens >= 0 {
                if let existing = buckets[bucket.startDate], existing.0 > sample.sampledAt { continue }
                buckets[bucket.startDate] = (sample.sampledAt, bucket.tokens)
            }
        }
        let recorded = buckets.values.reduce(Int64(0)) { $0 + $1.1 }
        let average = weeks.isEmpty ? nil : weeks.map(\.usedPercent).reduce(0, +) / Double(weeks.count)
        return UsageTotals(
            lifetimeTokens: ordered.last { $0.lifetimeTokens != nil }?.lifetimeTokens,
            peakDailyTokens: ordered.last { $0.peakDailyTokens != nil }?.peakDailyTokens,
            recordedTokens: recorded,
            weeks: weeks.count,
            averageWeeklyPercent: average
        )
    }
}
