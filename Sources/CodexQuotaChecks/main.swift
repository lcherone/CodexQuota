import CodexQuotaCore
import Foundation

enum Check {
    nonisolated(unsafe) static var failures: [String] = []

    static func fail(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
        failures.append("\(file):\(line) \(message)")
    }

    static func ok(_ condition: Bool, _ message: String = "expected true", file: StaticString = #fileID, line: UInt = #line) {
        if !condition { fail(message, file: file, line: line) }
    }

    static func equal<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #fileID, line: UInt = #line) {
        if actual != expected { fail("\(actual) != \(expected)", file: file, line: line) }
    }

    static func equal<T: Equatable>(_ actual: T?, _ expected: T, file: StaticString = #fileID, line: UInt = #line) {
        if actual != expected { fail("\(String(describing: actual)) != \(expected)", file: file, line: line) }
    }

    static func close(_ actual: Double, _ expected: Double, accuracy: Double, file: StaticString = #fileID, line: UInt = #line) {
        if abs(actual - expected) > accuracy { fail("\(actual) != \(expected) ± \(accuracy)", file: file, line: line) }
    }

    static func close(_ actual: Double?, _ expected: Double, accuracy: Double, file: StaticString = #fileID, line: UInt = #line) {
        guard let actual else {
            fail("nil != \(expected)", file: file, line: line)
            return
        }
        close(actual, expected, accuracy: accuracy, file: file, line: line)
    }

    static func isNil<T>(_ value: T?, file: StaticString = #fileID, line: UInt = #line) {
        if value != nil { fail("expected nil, got \(String(describing: value))", file: file, line: line) }
    }

    static func notNil<T>(_ value: T?, file: StaticString = #fileID, line: UInt = #line) {
        if value == nil { fail("expected a value", file: file, line: line) }
    }

    static func `throws`(_ operation: () throws -> Void, file: StaticString = #fileID, line: UInt = #line) {
        do {
            try operation()
            fail("expected an error", file: file, line: line)
        } catch {}
    }
}

@main
struct CodexQuotaChecks {
    static func main() async {
        PacingChecks.run()
        UsageChecks.run()
        FormattingChecks.run()
        LibraryNoticeChecks.run()
        QuotaRefreshPolicyChecks.run()
        HistoryChecks.run()
        await RefreshSchedulerChecks.run()
        await SessionChecks.run()
        if Check.failures.isEmpty {
            print("CodexQuotaChecks passed")
        } else {
            for failure in Check.failures { fputs(failure + "\n", stderr) }
            fputs("\(Check.failures.count) failed\n", stderr)
            exit(1)
        }
    }
}

enum QuotaRefreshPolicyChecks {
    static func run() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let exactlyStale = now.addingTimeInterval(-QuotaTiming.staleInterval)
        let stale = exactlyStale.addingTimeInterval(-1)
        let fresh = exactlyStale.addingTimeInterval(1)

        Check.ok(shouldRefresh(selectionChanged: true, latestSampledAt: nil, isBusy: false, now: now))
        Check.ok(shouldRefresh(selectionChanged: true, latestSampledAt: stale, isBusy: false, now: now))
        Check.ok(!shouldRefresh(selectionChanged: true, latestSampledAt: fresh, isBusy: false, now: now))
        Check.ok(!shouldRefresh(selectionChanged: true, latestSampledAt: exactlyStale, isBusy: false, now: now))
        Check.ok(!shouldRefresh(selectionChanged: false, latestSampledAt: stale, isBusy: false, now: now))
        Check.ok(
            !shouldRefresh(selectionChanged: true, latestSampledAt: stale, isBusy: true, now: now),
            "an account already refreshing should not refresh again"
        )
        Check.ok(
            !shouldRefresh(selectionChanged: true, latestSampledAt: nil, isBusy: true, now: now),
            "an account already signing in should not refresh"
        )
    }

    private static func shouldRefresh(
        selectionChanged: Bool,
        latestSampledAt: Date?,
        isBusy: Bool,
        now: Date
    ) -> Bool {
        QuotaRefreshPolicy.shouldRefreshAfterSelection(
            selectionChanged: selectionChanged,
            latestSampledAt: latestSampledAt,
            isBusy: isBusy,
            now: now
        )
    }
}

enum LibraryNoticeChecks {
    static func run() {
        saveFailurePersistsUntilAConfirmedRecovery()
        durableNoticesReappearAfterRecovery()
    }

    static func saveFailurePersistsUntilAConfirmedRecovery() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        var notice = LibraryNoticeState()
        do {
            try Data().write(to: directory)
            let history = HistoryStore(directory: directory)

            save(.empty(), with: history, notice: &notice)
            Check.equal(notice.displayedNotice, LibraryNoticeState.saveFailureNotice)

            save(.empty(), with: history, notice: &notice)
            Check.equal(notice.displayedNotice, LibraryNoticeState.saveFailureNotice)

            try FileManager.default.removeItem(at: directory)
            save(.empty(), with: history, notice: &notice)
            Check.isNil(notice.displayedNotice)
            Check.ok(FileManager.default.fileExists(atPath: history.fileURL.path))
        } catch {
            Check.fail("save notice recovery failed: \(error)")
        }
    }

    static func durableNoticesReappearAfterRecovery() {
        let durableNotices = [
            "This library uses an unsupported version.",
            "Codex Quota couldn't safely read the library.",
            "The previous library couldn't be read. It was kept for inspection."
        ]
        for durableNotice in durableNotices {
            var notice = LibraryNoticeState(durableNotice: durableNotice)
            Check.equal(notice.displayedNotice, durableNotice)
            notice.saveFailed()
            Check.equal(notice.displayedNotice, LibraryNoticeState.saveFailureNotice)
            notice.saveSucceeded()
            Check.equal(notice.displayedNotice, durableNotice)
        }
    }

    private static func save(_ store: StoreFile, with history: HistoryStore, notice: inout LibraryNoticeState) {
        do {
            try history.save(store)
            notice.saveSucceeded()
        } catch {
            notice.saveFailed()
        }
    }
}

enum RefreshSchedulerChecks {
    static func run() async {
        await selectedRunsFirstAndBackgroundWorkIsBounded()
        await absentSelectionAndEmptyLibraryFollowProductionPolicy()
    }

    static func selectedRunsFirstAndBackgroundWorkIsBounded() async {
        let probe = SchedulerProbe()
        let scheduling = Task {
            await RefreshScheduler.run(
                accountIDs: ["background-1", "selected", "background-2", "background-1", "background-3"],
                selectedID: "selected"
            ) { id in
                await probe.run(id)
            }
        }

        await probe.waitForStartCount(1)
        var snapshot = await probe.snapshot()
        Check.equal(snapshot.started, ["selected"])
        Check.equal(snapshot.active, 1)

        await probe.release("selected")
        await probe.waitForStartCount(3)
        snapshot = await probe.snapshot()
        Check.equal(Set(snapshot.started), Set(["selected", "background-1", "background-2"]))
        Check.equal(snapshot.active, 2)

        await probe.release("background-1")
        await probe.waitForStartCount(4)
        snapshot = await probe.snapshot()
        Check.equal(Set(snapshot.started), Set(["selected", "background-1", "background-2", "background-3"]))
        Check.equal(snapshot.maximumActive, 2)

        await probe.releaseAll()
        await scheduling.value
        snapshot = await probe.snapshot()
        Check.equal(snapshot.started.count, 4)
        Check.equal(snapshot.active, 0)
    }

    static func absentSelectionAndEmptyLibraryFollowProductionPolicy() async {
        let recorder = SchedulerRecorder()
        await RefreshScheduler.run(accountIDs: ["first", "second", "first"], selectedID: "missing") { id in
            await recorder.append(id)
        }
        Check.equal(Set(await recorder.ids), Set(["first", "second"]))
        Check.equal((await recorder.ids).count, 2)

        await RefreshScheduler.run(accountIDs: [], selectedID: "missing") { id in
            await recorder.append(id)
        }
        Check.equal((await recorder.ids).count, 2)
    }
}

actor SchedulerProbe {
    struct Snapshot: Sendable {
        let started: [String]
        let active: Int
        let maximumActive: Int
    }

    private var started: [String] = []
    private var active = 0
    private var maximumActive = 0
    private var gates: [String: CheckedContinuation<Void, Never>] = [:]
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func run(_ id: String) async {
        started.append(id)
        active += 1
        maximumActive = max(maximumActive, active)
        resumeSatisfiedStartWaiters()
        await withCheckedContinuation { continuation in
            gates[id] = continuation
        }
        active -= 1
    }

    func waitForStartCount(_ count: Int) async {
        if started.count >= count { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((count, continuation))
        }
    }

    func release(_ id: String) {
        gates.removeValue(forKey: id)?.resume()
    }

    func releaseAll() {
        let continuations = gates.values
        gates.removeAll()
        for continuation in continuations {
            continuation.resume()
        }
    }

    func snapshot() -> Snapshot {
        Snapshot(started: started, active: active, maximumActive: maximumActive)
    }

    private func resumeSatisfiedStartWaiters() {
        var pending: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        for waiter in startWaiters {
            if started.count >= waiter.count {
                waiter.continuation.resume()
            } else {
                pending.append(waiter)
            }
        }
        startWaiters = pending
    }
}

actor SchedulerRecorder {
    private(set) var ids: [String] = []

    func append(_ id: String) {
        ids.append(id)
    }
}

enum PacingChecks {
    static func run() {
        resetAnchoredLondonExample()
        todayCanBeAheadWhileLaterDaysStillHaveRoom()
        laterDaysAreShort()
        resetInstantIsOutsideTheWindow()
        windowStartIsTheFirstSlice()
        tokenEstimateFillsAnUnknownSlice()
        measuredHistoryBeatsTokenEstimate()
        partialSliceOnlyCountsAsOverWhenTheMinimumAlreadyIs()
        menuTitles()
        weekTotalsDeduplicateBuckets()
        completedWeekAverageExcludesCurrentWeek()
        openWeekProvidesFallbackState()
    }

    static func resetAnchoredLondonExample() {
        let reset = london(2026, 11, 25, 17)
        let now = london(2026, 11, 24, 12)
        let baseline = UsageSample.make(sampledAt: london(2026, 11, 23, 17), usedPercent: 55, resetsAt: reset)
        let current = UsageSample.make(sampledAt: now, usedPercent: 62, resetsAt: reset)
        let report = Pace.evaluate(now: now, usedPercent: 62, resetsAt: reset, windowDurationMins: 10_080, samples: [baseline, current], buckets: [])
        Check.equal(report?.todayIndex, 5)
        Check.equal(report?.slices.map(\.londonDate), [
            "2026-11-19", "2026-11-20", "2026-11-21", "2026-11-22", "2026-11-23", "2026-11-24", "2026-11-25"
        ])
        Check.close(report?.slices[0].end.timeIntervalSince(report!.slices[0].start), 86_400, accuracy: 0.001)
        Check.close(report?.todayWeeklyPoints, 7, accuracy: 0.001)
        Check.close(report?.todaySlicePercent, 49, accuracy: 0.001)
        Check.equal(report?.todayKind, .measured)
        Check.equal(report?.dayStatus, .under)
        Check.close(report?.expectedTodayPoints, (19.0 / 24.0) * (100.0 / 7.0), accuracy: 0.001)
        Check.equal(report?.futureFullSlices, 1)
        Check.equal(report?.weekHasRoom, true)
        Check.equal(report?.weekLinearStatus, .under)
        Check.equal(LondonClock.calendar().component(.weekday, from: reset), 4)
        Check.ok(LondonClock.resetLine(reset).contains("25 Nov"))
        Check.ok(LondonClock.resetLine(reset).contains("17:00"))
    }

    static func todayCanBeAheadWhileLaterDaysStillHaveRoom() {
        let reset = london(2026, 11, 25, 17)
        let now = london(2026, 11, 24, 12)
        let samples = [
            UsageSample.make(sampledAt: london(2026, 11, 23, 17), usedPercent: 40, resetsAt: reset),
            UsageSample.make(sampledAt: now, usedPercent: 62, resetsAt: reset)
        ]
        let report = Pace.evaluate(now: now, usedPercent: 62, resetsAt: reset, windowDurationMins: 10_080, samples: samples, buckets: [])
        Check.close(report?.todayWeeklyPoints, 22, accuracy: 0.001)
        Check.equal(report?.dayStatus, .over)
        Check.equal(report?.weekHasRoom, true)
        Check.equal(Pace.menuTitle(todaySlicePercent: report?.todaySlicePercent, todayKind: .measured, dayStatus: .over, weeklyUsed: 62), "154% over")
    }

    static func laterDaysAreShort() {
        let reset = london(2026, 11, 25, 17)
        let now = london(2026, 11, 24, 12)
        let samples = [
            UsageSample.make(sampledAt: london(2026, 11, 23, 17), usedPercent: 68, resetsAt: reset),
            UsageSample.make(sampledAt: now, usedPercent: 90, resetsAt: reset)
        ]
        let report = Pace.evaluate(now: now, usedPercent: 90, resetsAt: reset, windowDurationMins: 10_080, samples: samples, buckets: [])
        Check.equal(report?.dayStatus, .over)
        Check.equal(report?.weekHasRoom, false)
        Check.close(report?.remainingPercent, 10, accuracy: 0.001)
    }

    static func resetInstantIsOutsideTheWindow() {
        let reset = london(2026, 11, 25, 17)
        Check.isNil(Pace.evaluate(now: reset, usedPercent: 10, resetsAt: reset, windowDurationMins: 10_080, samples: [], buckets: []))
    }

    static func windowStartIsTheFirstSlice() {
        let reset = london(2026, 11, 25, 17)
        let start = reset.addingTimeInterval(-7 * 86_400)
        let report = Pace.evaluate(now: start, usedPercent: 0, resetsAt: reset, windowDurationMins: 10_080, samples: [], buckets: [])
        Check.equal(report?.todayIndex, 0)
        Check.equal(report?.slices[0].londonDate, "2026-11-19")
    }

    static func tokenEstimateFillsAnUnknownSlice() {
        let reset = london(2026, 11, 25, 17)
        let now = london(2026, 11, 24, 12)
        let buckets = [
            DailyBucket(startDate: "2026-11-23", tokens: 9_300),
            DailyBucket(startDate: "2026-11-24", tokens: 700)
        ]
        let report = Pace.evaluate(now: now, usedPercent: 62, resetsAt: reset, windowDurationMins: 10_080, samples: [], buckets: buckets)
        Check.equal(report?.todayKind, .estimated)
        Check.close(report?.todayWeeklyPoints, 62 * 700 / 10_000, accuracy: 0.001)
        Check.equal(report?.dayStatus, .under)
    }

    static func measuredHistoryBeatsTokenEstimate() {
        let reset = london(2026, 11, 25, 17)
        let now = london(2026, 11, 24, 12)
        let samples = [
            UsageSample.make(sampledAt: london(2026, 11, 23, 17), usedPercent: 55, resetsAt: reset),
            UsageSample.make(sampledAt: now, usedPercent: 62, resetsAt: reset)
        ]
        let buckets = [DailyBucket(startDate: "2026-11-24", tokens: 1)]
        let report = Pace.evaluate(now: now, usedPercent: 62, resetsAt: reset, windowDurationMins: 10_080, samples: samples, buckets: buckets)
        Check.equal(report?.todayKind, .measured)
        Check.close(report?.todayWeeklyPoints, 7, accuracy: 0.001)
    }

    static func partialSliceOnlyCountsAsOverWhenTheMinimumAlreadyIs() {
        let reset = london(2026, 11, 25, 17)
        let now = london(2026, 11, 24, 12)
        let quiet = [
            UsageSample.make(sampledAt: london(2026, 11, 23, 18), usedPercent: 60, resetsAt: reset),
            UsageSample.make(sampledAt: now, usedPercent: 62, resetsAt: reset)
        ]
        let quietReport = Pace.evaluate(now: now, usedPercent: 62, resetsAt: reset, windowDurationMins: 10_080, samples: quiet, buckets: [])
        Check.equal(quietReport?.todayKind, .partial)
        Check.equal(quietReport?.dayStatus, .unknown)
        let loud = [
            UsageSample.make(sampledAt: london(2026, 11, 23, 18), usedPercent: 42, resetsAt: reset),
            UsageSample.make(sampledAt: now, usedPercent: 62, resetsAt: reset)
        ]
        let loudReport = Pace.evaluate(now: now, usedPercent: 62, resetsAt: reset, windowDurationMins: 10_080, samples: loud, buckets: [])
        Check.close(loudReport?.todayWeeklyPoints, 20, accuracy: 0.001)
        Check.equal(loudReport?.dayStatus, .over)
    }

    static func menuTitles() {
        Check.equal(Pace.menuTitle(todaySlicePercent: 49, todayKind: .measured, dayStatus: .under, weeklyUsed: 62), "49%")
        Check.equal(Pace.menuTitle(todaySlicePercent: 14, todayKind: .partial, dayStatus: .unknown, weeklyUsed: 62), "62% wk")
        Check.equal(Pace.menuTitle(todaySlicePercent: nil, todayKind: .unknown, dayStatus: .unknown, weeklyUsed: nil), "Quota")
    }

    static func weekTotalsDeduplicateBuckets() {
        let now = london(2026, 11, 24, 12)
        let openReset = london(2026, 11, 25, 17)
        let closedReset = london(2026, 11, 18, 17)
        let samples = [
            UsageSample.make(sampledAt: london(2026, 11, 17, 12), usedPercent: 40, resetsAt: closedReset, lifetimeTokens: 10, dailyBuckets: [DailyBucket(startDate: "2026-11-17", tokens: 5)]),
            UsageSample.make(sampledAt: london(2026, 11, 18, 12), usedPercent: 80, resetsAt: closedReset, lifetimeTokens: 20, dailyBuckets: [DailyBucket(startDate: "2026-11-17", tokens: 9)]),
            UsageSample.make(sampledAt: now, usedPercent: 62, resetsAt: openReset, lifetimeTokens: 30, peakDailyTokens: 12, dailyBuckets: [DailyBucket(startDate: "2026-11-24", tokens: 4)])
        ]
        let weeks = UsageStats.weeks(samples: samples, now: now)
        Check.equal(weeks.map(\.usedPercent), [62, 80])
        Check.equal(weeks.map(\.complete), [false, true])
        let totals = UsageStats.totals(samples: samples, now: now)
        Check.equal(totals.lifetimeTokens, Int64(30))
        Check.equal(totals.peakDailyTokens, Int64(12))
        Check.equal(totals.recordedTokens, Int64(13))
        Check.equal(totals.weeks, 2)
        Check.close(totals.completedWeekAveragePercent, 80, accuracy: 0.001)
        Check.close(totals.currentWeekPercent, 62, accuracy: 0.001)
    }

    static func completedWeekAverageExcludesCurrentWeek() {
        let now = london(2026, 11, 24, 12)
        let samples = [
            UsageSample.make(sampledAt: london(2026, 11, 11, 12), usedPercent: 60, resetsAt: london(2026, 11, 12, 17)),
            UsageSample.make(sampledAt: london(2026, 11, 18, 12), usedPercent: 80, resetsAt: london(2026, 11, 19, 17)),
            UsageSample.make(sampledAt: now, usedPercent: 10, resetsAt: london(2026, 11, 26, 17))
        ]
        let initial = UsageStats.totals(samples: samples, now: now)
        Check.close(initial.completedWeekAveragePercent, 70, accuracy: 0.001)
        Check.close(initial.currentWeekPercent, 10, accuracy: 0.001)

        let changedCurrentWeek = samples + [
            UsageSample.make(sampledAt: london(2026, 11, 24, 13), usedPercent: 25, resetsAt: london(2026, 11, 26, 17))
        ]
        let updated = UsageStats.totals(samples: changedCurrentWeek, now: now)
        Check.close(updated.completedWeekAveragePercent, 70, accuracy: 0.001)
        Check.close(updated.currentWeekPercent, 25, accuracy: 0.001)
    }

    static func openWeekProvidesFallbackState() {
        let now = london(2026, 11, 24, 12)
        let openOnly = [
            UsageSample.make(sampledAt: now, usedPercent: 18, resetsAt: london(2026, 11, 26, 17))
        ]
        let totals = UsageStats.totals(samples: openOnly, now: now)
        Check.isNil(totals.completedWeekAveragePercent)
        Check.close(totals.currentWeekPercent, 18, accuracy: 0.001)

        let unavailable = UsageStats.totals(samples: [], now: now)
        Check.isNil(unavailable.completedWeekAveragePercent)
        Check.isNil(unavailable.currentWeekPercent)
    }

    static func london(_ year: Int, _ month: Int, _ day: Int, _ hour: Int) -> Date {
        LondonClock.calendar().date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }
}

enum UsageChecks {
    static func run() {
        summaryStatsAndLegacySamples()
        partialUsageMergesAndRecovers()
        weeklyWindowIgnoresTheFiveHourWindow()
        codexBucketWinsOverAnotherWeeklyWindow()
        millisecondResetAndClampedPercent()
        missingWeeklyWindowLeavesTheShortWindow()
        signedOutAccountAndLoginLink()
        initializeAndLoginPayloads()
        codexBinaryHonoursCODEXBIN()
    }

    static func summaryStatsAndLegacySamples() {
        do {
            let usage = try json(#"{"summary":{"lifetimeTokens":44194077000,"peakDailyTokens":1712023700,"longestRunningTurnSec":7322,"currentStreakDays":4,"longestStreakDays":19},"dailyUsageBuckets":[{"startDate":"2026-11-24","tokens":700},{"startDate":"2026-11-25","tokens":0}]}"#)
            let reading = UsageParsing.reading(account: try json(account), limits: try json(limits), usage: usage)
            Check.equal(reading.longestRunningTurnSec, Int64(7322))
            Check.equal(reading.currentStreakDays, Int64(4))
            Check.equal(reading.longestStreakDays, Int64(19))
            Check.equal(reading.dailyBuckets.count, 2)
            let missing = UsageParsing.reading(account: try json(account), limits: try json(limits), usage: .object([:]))
            Check.isNil(missing.currentStreakDays)
            Check.isNil(missing.longestStreakDays)
            Check.isNil(missing.longestRunningTurnSec)
            let oldSample = Data(#"{"accountId":"legacy","sampledAt":0,"dailyBuckets":[]}"#.utf8)
            let decoded = try JSONDecoder().decode(UsageSample.self, from: oldSample)
            Check.isNil(decoded.currentStreakDays)
            Check.isNil(decoded.optionalStatisticsSampledAt)
            Check.isNil(decoded.optionalStatisticsArePartial)
            var sample = decoded
            sample.currentStreakDays = reading.currentStreakDays
            sample.longestStreakDays = reading.longestStreakDays
            sample.longestRunningTurnSec = reading.longestRunningTurnSec
            let restored = try JSONDecoder().decode(UsageSample.self, from: JSONEncoder().encode(sample))
            Check.equal(restored, sample)
        } catch {
            Check.fail("summary stats or legacy sample failed: \(error)")
        }
    }

    static func partialUsageMergesAndRecovers() {
        let firstTime = Date(timeIntervalSince1970: 1_800_000_000)
        let partialTime = firstTime.addingTimeInterval(300)
        let recoveredTime = partialTime.addingTimeInterval(300)
        let oldBuckets = [DailyBucket(startDate: "2026-11-24", tokens: 700)]
        let previous = UsageSample.make(
            sampledAt: firstTime,
            usedPercent: 10,
            lifetimeTokens: 123_456,
            peakDailyTokens: 999,
            shortUsedPercent: 25,
            shortDurationMins: 300,
            dailyBuckets: oldBuckets,
            longestRunningTurnSec: 7_322,
            currentStreakDays: 4,
            longestStreakDays: 19,
            optionalStatisticsSampledAt: firstTime,
            optionalStatisticsArePartial: false
        )
        var failed = UsageReading(
            identity: AccountIdentity(type: "chatgpt", email: "new@example.com", planType: "plus"),
            weekly: WeeklyWindow(limitId: "codex", limitName: "Codex", planType: "plus", usedPercent: 20, windowDurationMins: 10_080, resetsAt: recoveredTime, reached: nil),
            shortWindow: ShortWindow(usedPercent: 30, windowDurationMins: 300, resetsAt: recoveredTime),
            lifetimeTokens: nil,
            peakDailyTokens: nil,
            dailyBuckets: []
        )
        failed.optionalUsageSucceeded = false
        let partial = UsageSample.merging(accountId: "account", sampledAt: partialTime, reading: failed, previous: previous)
        Check.close(partial?.usedPercent, 20, accuracy: 0.001)
        Check.close(partial?.shortUsedPercent, 30, accuracy: 0.001)
        Check.equal(partial?.lifetimeTokens, Int64(123_456))
        Check.equal(partial?.peakDailyTokens, Int64(999))
        Check.equal(partial?.dailyBuckets, oldBuckets)
        Check.equal(partial?.longestRunningTurnSec, Int64(7_322))
        Check.equal(partial?.currentStreakDays, Int64(4))
        Check.equal(partial?.longestStreakDays, Int64(19))
        Check.equal(partial?.optionalStatisticsSampledAt, firstTime)
        Check.equal(partial?.optionalStatisticsArePartial, true)
        do {
            let reloaded = try JSONDecoder().decode(UsageSample.self, from: JSONEncoder().encode(partial))
            Check.equal(reloaded.optionalStatisticsSampledAt, firstTime)
            Check.equal(reloaded.optionalStatisticsArePartial, true)
        } catch {
            Check.fail("partial sample persistence failed: \(error)")
        }

        let noPrior = UsageSample.merging(accountId: "account", sampledAt: partialTime, reading: failed, previous: nil)
        Check.isNil(noPrior?.lifetimeTokens)
        Check.equal(noPrior?.dailyBuckets, [])
        Check.isNil(noPrior?.optionalStatisticsSampledAt)
        Check.equal(noPrior?.optionalStatisticsArePartial, true)

        var recovered = failed
        recovered.lifetimeTokens = 222_222
        recovered.peakDailyTokens = 1_111
        recovered.dailyBuckets = [DailyBucket(startDate: "2026-11-25", tokens: 800)]
        recovered.longestRunningTurnSec = 8_000
        recovered.currentStreakDays = 5
        recovered.longestStreakDays = 20
        recovered.optionalUsageSucceeded = true
        let complete = UsageSample.merging(accountId: "account", sampledAt: recoveredTime, reading: recovered, previous: partial)
        Check.equal(complete?.lifetimeTokens, Int64(222_222))
        Check.equal(complete?.dailyBuckets, recovered.dailyBuckets)
        Check.equal(complete?.optionalStatisticsSampledAt, recoveredTime)
        Check.equal(complete?.optionalStatisticsArePartial, false)

        var successfulEmpty = recovered
        successfulEmpty.lifetimeTokens = nil
        successfulEmpty.peakDailyTokens = nil
        successfulEmpty.dailyBuckets = []
        successfulEmpty.longestRunningTurnSec = nil
        successfulEmpty.currentStreakDays = nil
        successfulEmpty.longestStreakDays = nil
        let empty = UsageSample.merging(accountId: "account", sampledAt: recoveredTime, reading: successfulEmpty, previous: partial)
        Check.isNil(empty?.lifetimeTokens)
        Check.equal(empty?.dailyBuckets, [])
        Check.equal(empty?.optionalStatisticsSampledAt, recoveredTime)
        Check.equal(empty?.optionalStatisticsArePartial, false)
    }

    static func weeklyWindowIgnoresTheFiveHourWindow() {
        do {
            let reading = UsageParsing.reading(account: try json(account), limits: try json(limits), usage: try json(usage))
            Check.equal(reading.identity?.email, "person@example.com")
            Check.equal(reading.identity?.planType, "plus")
            Check.equal(reading.weekly?.limitId, "codex")
            Check.close(reading.weekly?.usedPercent, 10, accuracy: 0.001)
            Check.close(reading.weekly?.windowDurationMins, 10_080, accuracy: 0.001)
            Check.equal(reading.weekly?.resetsAt, Date(timeIntervalSince1970: 1_800_000_000))
            Check.close(reading.shortWindow?.usedPercent, 25, accuracy: 0.001)
            Check.close(reading.shortWindow?.windowDurationMins, 300, accuracy: 0.001)
            Check.equal(reading.lifetimeTokens, Int64(123_456))
            Check.equal(reading.dailyBuckets, [DailyBucket(startDate: "2026-11-24", tokens: 700)])
        } catch {
            Check.fail("parse failed")
        }
    }

    static func codexBucketWinsOverAnotherWeeklyWindow() {
        let limits = """
        {"rateLimitsByLimitId":{
          "image":{"limitId":"image","limitName":"Images","primary":null,"secondary":{"usedPercent":80,"windowDurationMins":10080,"resetsAt":1800000000}},
          "codex":{"limitId":"codex","limitName":"Codex","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1800000000},"secondary":{"usedPercent":10,"windowDurationMins":10080,"resetsAt":1800000000}}
        }}
        """
        do {
            let reading = UsageParsing.reading(account: try json(account), limits: try json(limits), usage: .object([:]))
            Check.close(reading.weekly?.usedPercent, 10, accuracy: 0.001)
            Check.equal(reading.weekly?.limitId, "codex")
        } catch {
            Check.fail("parse failed")
        }
    }

    static func millisecondResetAndClampedPercent() {
        let limits = """
        {"rateLimits":{"limitId":"codex","limitName":"Codex","primary":null,"secondary":{"usedPercent":140,"windowDurationMins":10080,"resetsAt":1800000000000}}}
        """
        do {
            let reading = UsageParsing.reading(account: try json(account), limits: try json(limits), usage: .object([:]))
            Check.close(reading.weekly?.usedPercent, 100, accuracy: 0.001)
            Check.equal(reading.weekly?.resetsAt, Date(timeIntervalSince1970: 1_800_000_000))
        } catch {
            Check.fail("parse failed")
        }
    }

    static func missingWeeklyWindowLeavesTheShortWindow() {
        let limits = """
        {"rateLimits":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1800000000},"secondary":null}}
        """
        do {
            let reading = UsageParsing.reading(account: try json(account), limits: try json(limits), usage: .object([:]))
            Check.isNil(reading.weekly)
            Check.close(reading.shortWindow?.windowDurationMins, 300, accuracy: 0.001)
        } catch {
            Check.fail("parse failed")
        }
    }

    static func signedOutAccountAndLoginLink() {
        do {
            Check.ok(!UsageParsing.isSignedIn(try json(#"{"account":null,"requiresOpenaiAuth":true}"#)))
            Check.ok(UsageParsing.isSignedIn(try json(account)))
            Check.equal(
                UsageParsing.loginURL(try json(#"{"type":"chatgpt","loginId":"login-1","authUrl":"https://example.test/login"}"#))?.absoluteString,
                "https://example.test/login"
            )
            Check.isNil(UsageParsing.loginURL(try json(#"{"type":"chatgpt","authUrl":"http://example.test/login"}"#)))
        } catch {
            Check.fail("parse failed")
        }
    }

    static func initializeAndLoginPayloads() {
        do {
            let line = try ProtocolCodec.requestLine(id: 1, method: "initialize", params: QuotaCalls.initializeParams)
            let message = try JSONValue.parse(Data(line.utf8))
            Check.equal(message.object?["method"]?.string, "initialize")
            Check.equal(message.object?["params"]?.object?["clientInfo"]?.object?["name"]?.string, "codexquota")
            Check.equal(message.object?["params"]?.object?["capabilities"]?.object?["experimentalApi"]?.bool, true)
            Check.equal(message.object?["params"]?.object?["capabilities"]?.object?["requestAttestation"]?.bool, false)
            let login = try ProtocolCodec.requestLine(id: 2, method: "account/login/start", params: QuotaCalls.loginParams)
            let loginMessage = try JSONValue.parse(Data(login.utf8))
            Check.equal(loginMessage.object?["params"]?.object?["type"]?.string, "chatgpt")
            Check.equal(loginMessage.object?["params"]?.object?["appBrand"]?.string, "codex")
            let logout = try ProtocolCodec.requestLine(id: 3, method: "account/logout", params: nil)
            Check.isNil(try JSONValue.parse(Data(logout.utf8)).object?["params"])
        } catch {
            Check.fail("payload failed")
        }
    }

    static func codexBinaryHonoursCODEXBIN() {
        let missing = CodexBinary.resolve(environment: ["CODEX_BIN": "/missing/codex"], isExecutable: { _ in false }, which: { _ in nil })
        if case let .failure(error) = missing {
            Check.equal(error, .codexMissing("CODEX_BIN doesn't point at an executable."))
        } else {
            Check.fail("expected a missing binary")
        }
        let found = CodexBinary.resolve(environment: ["HOME": "/Users/dev"], isExecutable: { $0 == "/opt/homebrew/bin/codex" }, which: { _ in nil })
        if case let .success(path) = found {
            Check.equal(path, "/opt/homebrew/bin/codex")
        } else {
            Check.fail("expected a resolved binary")
        }
    }

    static func json(_ text: String) throws -> JSONValue {
        try JSONValue.parse(Data(text.utf8))
    }

    static let account = #"{"account":{"type":"chatgpt","email":"person@example.com","planType":"plus"},"requiresOpenaiAuth":false}"#
    static let limits = """
    {"rateLimitsByLimitId":{"codex":{"limitId":"codex","limitName":"Codex","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":1800000000},"secondary":{"usedPercent":10,"windowDurationMins":10080,"resetsAt":1800000000},"planType":"plus","rateLimitReachedType":null}}}
    """
    static let usage = #"{"summary":{"lifetimeTokens":123456,"peakDailyTokens":999},"dailyUsageBuckets":[{"startDate":"2026-11-24","tokens":700}]}"#
}

enum HistoryChecks {
    static func run() {
        roundTripPermissionsAndCoalescing()
        corruptLibraryIsKeptBesideAnEmptyOne()
        unsupportedLibraryIsBlockedAndUnchanged()
        failedQuarantineIsBlockedAndUnchanged()
        oldSamplesAreDropped()
        failedHomeRemovalPreservesAccountStateForRetry()
        removingHomesStaysInsideTheOwnedDirectory()
        appearanceSurvivesAndOlderLibrariesStaySystem()
    }

    static func roundTripPermissionsAndCoalescing() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let history = HistoryStore(directory: directory)
        var store = StoreFile.empty()
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let first = UsageSample.make(sampledAt: reset.addingTimeInterval(-86_400), usedPercent: 10, resetsAt: reset, lifetimeTokens: 5)
        history.record(first, into: &store, now: first.sampledAt)
        let replaced = UsageSample.make(sampledAt: first.sampledAt.addingTimeInterval(30), usedPercent: 10, resetsAt: reset, lifetimeTokens: 5)
        history.record(replaced, into: &store, now: replaced.sampledAt)
        Check.equal(store.samples.count, 1)
        Check.equal(store.samples[0].sampledAt, replaced.sampledAt)
        let later = UsageSample.make(sampledAt: replaced.sampledAt.addingTimeInterval(180), usedPercent: 12, resetsAt: reset, lifetimeTokens: 5)
        history.record(later, into: &store, now: later.sampledAt)
        Check.equal(store.samples.count, 2)
        do {
            try history.save(store)
            let loaded = try history.load(now: later.sampledAt)
            Check.equal(loaded.store.samples.count, 2)
            let fileMode = try FileManager.default.attributesOfItem(atPath: history.fileURL.path)[.posixPermissions] as? NSNumber
            let directoryMode = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
            Check.equal((fileMode?.intValue ?? 0) & 0o777, 0o600)
            Check.equal((directoryMode?.intValue ?? 0) & 0o777, 0o700)
        } catch {
            Check.fail("history save failed \(error)")
        }
    }

    static func corruptLibraryIsKeptBesideAnEmptyOne() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let history = HistoryStore(directory: directory)
            try Data("not json".utf8).write(to: history.fileURL)
            let loaded = try history.load()
            Check.equal(loaded.store, .empty())
            if case let .writableAfterQuarantine(kept) = loaded.access {
                Check.ok(FileManager.default.fileExists(atPath: kept.path))
                let original = try Data(contentsOf: kept)
                try history.save(.empty())
                Check.equal(try Data(contentsOf: kept), original)
                Check.ok(FileManager.default.fileExists(atPath: history.fileURL.path))
            } else {
                Check.fail("corrupt library was not quarantined")
            }
        } catch {
            Check.fail("corrupt library failed \(error)")
        }
    }

    static func unsupportedLibraryIsBlockedAndUnchanged() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let original = Data("{\"version\":2,\"accounts\":[],\"samples\":[]}".utf8)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let history = HistoryStore(directory: directory)
            try original.write(to: history.fileURL)
            let loaded = try history.load()
            Check.ok(!loaded.access.isWritable, "unsupported library was not blocked")
            Check.equal(try Data(contentsOf: history.fileURL), original)
        } catch {
            Check.fail("unsupported library check failed \(error)")
        }
    }

    static func failedQuarantineIsBlockedAndUnchanged() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let original = Data("not json".utf8)
        let history = HistoryStore(directory: directory, moveItem: { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        })
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try original.write(to: history.fileURL)
            let loaded = try history.load()
            Check.ok(!loaded.access.isWritable, "failed quarantine was not blocked")
            Check.equal(try Data(contentsOf: history.fileURL), original)
            Check.equal(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["store.json"])
        } catch {
            Check.fail("failed quarantine check failed \(error)")
        }
    }

    static func appearanceSurvivesAndOlderLibrariesStaySystem() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let history = HistoryStore(directory: directory)
        let older = """
        {"version":1,"accounts":[],"samples":[]}
        """
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(older.utf8).write(to: history.fileURL)
            let loaded = try history.load()
            Check.equal(loaded.store.appearance, .system)
            var store = loaded.store
            store.appearance = .dark
            try history.save(store)
            let saved = try history.load()
            Check.equal(saved.store.appearance, .dark)
        } catch {
            Check.fail("appearance library failed \(error)")
        }
    }

    static func removingHomesStaysInsideTheOwnedDirectory() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let history = HistoryStore(directory: directory)
        let sibling = directory.appendingPathComponent("homes-unrelated", isDirectory: true)
        do {
            let owned = try history.makeHome(id: "owned")
            try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)
            Check.throws { try history.removeHome(sibling.path) }
            Check.ok(FileManager.default.fileExists(atPath: sibling.path))
            Check.throws { try history.removeHome(history.homesURL.path) }
            Check.ok(FileManager.default.fileExists(atPath: history.homesURL.path))
            let link = history.homesURL.appendingPathComponent("linked")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: sibling)
            Check.throws { try history.removeHome(link.path) }
            Check.ok(FileManager.default.fileExists(atPath: link.path))
            Check.ok(FileManager.default.fileExists(atPath: sibling.path))
            try history.removeHome(owned)
            Check.ok(!FileManager.default.fileExists(atPath: owned))
        } catch {
            Check.fail("home removal boundary failed: \(error)")
        }
    }

    static func failedHomeRemovalPreservesAccountStateForRetry() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        final class RemovalControl: @unchecked Sendable {
            var failure: Error? = CocoaError(.fileWriteNoPermission)
        }
        let control = RemovalControl()
        let history = HistoryStore(directory: directory) { url in
            if let failure = control.failure { throw failure }
            try FileManager.default.removeItem(at: url)
        }
        do {
            let accountID = "selected"
            let home = try history.makeHome(id: accountID)
            let account = AccountRecord(id: accountID, label: "Work", codexHome: home, createdAt: Date())
            let remainingAccount = AccountRecord(id: "personal", label: "Personal", codexHome: try history.makeHome(id: "personal"), createdAt: Date())
            let sample = UsageSample.make(accountId: accountID, sampledAt: Date(), usedPercent: 25, resetsAt: Date().addingTimeInterval(86_400))
            let remainingSample = UsageSample.make(accountId: remainingAccount.id, sampledAt: Date(), usedPercent: 10, resetsAt: Date().addingTimeInterval(86_400))
            var store = StoreFile.empty()
            store.accounts = [remainingAccount, account]
            store.samples = [remainingSample, sample]
            store.selectedAccountId = accountID

            Check.throws { _ = try history.removingAccount(accountID, from: store) }
            Check.equal(store.accounts, [remainingAccount, account])
            Check.equal(store.samples, [remainingSample, sample])
            Check.equal(store.selectedAccountId, accountID)
            Check.ok(FileManager.default.fileExists(atPath: home))

            control.failure = nil
            store = try history.removingAccount(accountID, from: store)
            Check.ok(!FileManager.default.fileExists(atPath: home))
            Check.equal(store.accounts, [remainingAccount])
            Check.equal(store.samples, [remainingSample])
            Check.equal(store.selectedAccountId, remainingAccount.id)
        } catch {
            Check.fail("failed home removal retry failed: \(error)")
        }
    }

    static func oldSamplesAreDropped() {
        let history = HistoryStore(directory: URL(fileURLWithPath: "/tmp"))
        var store = StoreFile.empty()
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let old = UsageSample.make(sampledAt: now.addingTimeInterval(-(QuotaTiming.historyWeeks + 86_400)), usedPercent: 1, resetsAt: now)
        history.record(old, into: &store, now: now)
        Check.ok(store.samples.isEmpty)
    }
}

enum SessionChecks {
    static func run() async {
        await refreshReadsTheMockAppServer()
        await optionalUsageFailureStillReturnsQuota()
        await signInOpensTheReturnedLinkAndDoesNotFetchIt()
    }

    static func optionalUsageFailureStillReturnsQuota() async {
        let service = QuotaService(launch: { launch() }, extraEnvironment: ["CODEX_QUOTA_MOCK": "usage-failure"])
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true).path
        do {
            let reading = try await service.refresh(home: home)
            Check.close(reading.weekly?.usedPercent, 10, accuracy: 0.001)
            Check.close(reading.shortWindow?.usedPercent, 25, accuracy: 0.001)
            Check.equal(reading.optionalUsageSucceeded, false)
            Check.isNil(reading.lifetimeTokens)
            Check.equal(reading.dailyBuckets, [])
        } catch {
            Check.fail("partial refresh failed \(error)")
        }
    }

    static func refreshReadsTheMockAppServer() async {
        let service = QuotaService(launch: { launch() }, extraEnvironment: [:])
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true).path
        do {
            let reading = try await service.refresh(home: home)
            Check.equal(reading.identity?.email, "person@example.com")
            Check.close(reading.weekly?.usedPercent, 10, accuracy: 0.001)
            Check.close(reading.weekly?.windowDurationMins, 10_080, accuracy: 0.001)
            Check.close(reading.shortWindow?.usedPercent, 25, accuracy: 0.001)
            Check.equal(reading.lifetimeTokens, Int64(123_456))
            Check.equal(reading.dailyBuckets.first?.tokens, Int64(700))
            Check.equal(reading.currentStreakDays, Int64(4))
            Check.equal(reading.longestStreakDays, Int64(19))
            Check.equal(reading.longestRunningTurnSec, Int64(7322))
        } catch {
            Check.fail("refresh failed \(error)")
        }
    }

    static func signInOpensTheReturnedLinkAndDoesNotFetchIt() async {
        let box = URLBox()
        let service = QuotaService(launch: { launch() }, extraEnvironment: ["CODEX_QUOTA_MOCK": "login"])
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true).path
        do {
            let reading = try await service.signIn(home: home) { box.add($0) }
            Check.equal(box.all.map(\.absoluteString), ["https://example.test/login"])
            Check.close(reading.weekly?.usedPercent, 10, accuracy: 0.001)
        } catch {
            Check.fail("sign-in failed \(error)")
        }
    }

    static func launch() -> CodexLaunch {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/mock_app_server.py")
            .path
        return CodexLaunch(executable: "/usr/bin/python3", arguments: [script])
    }
}

final class URLBox: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func add(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
    var all: [URL] { lock.lock(); defer { lock.unlock() }; return urls }
}

enum FormattingChecks {
    static func run() {
        Check.equal(UsageFormatting.compact(nil), "—")
        Check.equal(UsageFormatting.compact(0), "0")
        Check.equal(UsageFormatting.compact(999), "999")
        Check.equal(UsageFormatting.compact(1000), "1K")
        Check.equal(UsageFormatting.compact(1250), "1.3K")
        Check.equal(UsageFormatting.compact(999_949), "999.9K")
        Check.equal(UsageFormatting.compact(999_950), "1M")
        Check.equal(UsageFormatting.compact(1_500_000), "1.5M")
        Check.equal(UsageFormatting.compact(44_194_077_000), "44.2B")
        Check.equal(UsageFormatting.compact(1_712_023_700), "1.7B")
        Check.equal(UsageFormatting.compact(1_500_000_000_000), "1.5T")
        Check.equal(UsageFormatting.compact(Int64.max), "9,223.4Q")
        Check.equal(UsageFormatting.exact(44_194_077_000), "44,194,077,000")
        Check.equal(UsageFormatting.duration(nil), "—")
        Check.equal(UsageFormatting.duration(0), "0s")
        Check.equal(UsageFormatting.duration(59), "59s")
        Check.equal(UsageFormatting.duration(60), "1m 0s")
        Check.equal(UsageFormatting.duration(7322), "2h 2m")
        Check.equal(UsageFormatting.duration(90_000), "1d 1h")
    }
}
