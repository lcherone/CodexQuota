import AppKit
import CodexQuotaCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    let loginItem = LoginItemController()
    private let notifications: LocalNotificationControlling

    private(set) var store: StoreFile
    private(set) var phase: [String: AccountPhase] = [:]
    private(set) var banners: [String: String] = [:]
    private(set) var authRequired: Set<String> = []
    private(set) var alertPermission: LocalNotificationPermission = .unknown
    private var libraryNotice = LibraryNoticeState()
    private(set) var libraryReady = false
    private let history: HistoryStore
    private let service: QuotaService
    private var loop: Task<Void, Never>?
    private var refreshRunning = false
    private var refreshAgain = false

    init(
        history: HistoryStore = .resolve(),
        service: QuotaService = .production(),
        notifications: LocalNotificationControlling = LocalNotificationController()
    ) {
        self.history = history
        self.service = service
        self.notifications = notifications
        do {
            let loaded = try history.load()
            store = loaded.store
            switch loaded.access {
            case .writable:
                libraryReady = true
            case let .writableAfterQuarantine(kept):
                libraryReady = true
                libraryNotice.durableNotice = "The previous library couldn't be read. It was kept at \(kept.path)."
            case let .blocked(message):
                libraryNotice.durableNotice = message
            }
        } catch let error as QuotaFailure {
            store = .empty()
            libraryNotice.durableNotice = "\(error.message) The library was left at \(history.fileURL.path). Resolve or move it, then relaunch Codex Quota."
        } catch {
            store = .empty()
            libraryNotice.durableNotice = "The library couldn't be safely opened, so it was left at \(history.fileURL.path). Resolve or move it, then relaunch Codex Quota."
        }
    }

    var libraryNote: String? {
        libraryNotice.displayedNotice
    }

    var alertsEnabled: Bool {
        store.alertPreferences.enabled && alertPermission == .authorized
    }

    var selectedAccount: AccountRecord? {
        let id = store.selectedAccountId ?? store.accounts.first?.id
        return store.accounts.first { $0.id == id }
    }

    var menuTitle: String {
        guard let account = selectedAccount else { return "Quota" }
        if authRequired.contains(account.id) { return "Sign in" }
        let samples = store.samples.filter { $0.accountId == account.id }
        guard let latest = samples.max(by: { $0.sampledAt < $1.sampledAt }) else { return "Quota" }
        let pace = paceReport(for: account.id, sample: latest, now: Date())
        return Pace.menuTitle(
            todaySlicePercent: pace?.todaySlicePercent,
            todayKind: pace?.todayKind ?? .unknown,
            dayStatus: pace?.dayStatus ?? .unknown,
            weeklyUsed: latest.usedPercent
        )
    }

    func start() {
        guard libraryReady else { return }
        guard loop == nil else { return }
        loop = Task { [weak self] in
            await self?.notifications.refreshPermission()
            self?.alertPermission = self?.notifications.permission ?? .unknown
            await self?.refreshAll()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(QuotaTiming.refreshInterval * 1_000_000_000))
                await self?.refreshAll()
            }
        }
    }

    func select(_ id: String) {
        guard libraryReady else { return }
        guard store.accounts.contains(where: { $0.id == id }) else { return }
        let selectionChanged = selectedAccount?.id != id
        let latestSampledAt = latestSample(for: id)?.sampledAt
        let busy = isBusy(id)
        var copy = store
        copy.selectedAccountId = id
        store = copy
        persist()
        guard QuotaRefreshPolicy.shouldRefreshAfterSelection(
            selectionChanged: selectionChanged,
            latestSampledAt: latestSampledAt,
            isBusy: busy,
            now: Date()
        ) else { return }
        Task { await refresh(id) }
    }

    func setAppearance(_ appearance: PanelAppearance) {
        guard libraryReady else { return }
        guard store.appearance != appearance else { return }
        var copy = store
        copy.appearance = appearance
        store = copy
        persist()
    }

    func setAlertsEnabled(_ enabled: Bool) async {
        guard libraryReady else { return }
        let authorized: Bool
        if enabled {
            if notifications.permission == .authorized {
                authorized = true
            } else {
                authorized = await notifications.requestPermission()
            }
        } else {
            authorized = false
        }
        alertPermission = notifications.permission
        var copy = store
        copy.alertPreferences.enabled = enabled && authorized
        store = copy
        persist()
    }

    func setAlertThreshold(_ threshold: Int) {
        guard libraryReady else { return }
        let normalized = QuotaAlertPreferences.normalizedThreshold(threshold)
        guard store.alertPreferences.weeklyThreshold != normalized else { return }
        var copy = store
        copy.alertPreferences.weeklyThreshold = normalized
        store = copy
        persist()
    }

    func refreshAlertPermission() async {
        await notifications.refreshPermission()
        alertPermission = notifications.permission
    }

    func addAccount(label: String) {
        guard libraryReady else { return }
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = String((trimmed.isEmpty ? suggestedLabel() : trimmed).prefix(40))
        let id = UUID().uuidString.lowercased()
        let home: String
        do {
            home = try history.makeHome(id: id)
        } catch {
            libraryNotice.durableNotice = "A home for this account couldn't be created on this Mac."
            return
        }
        var copy = store
        copy.accounts.append(AccountRecord(id: id, label: name, codexHome: home, createdAt: Date()))
        copy.selectedAccountId = id
        store = copy
        persist()
        Task { await refresh(id) }
    }

    func removeAccount(_ id: String) {
        guard libraryReady else { return }
        guard !isBusy(id) else { return }
        guard let account = store.accounts.first(where: { $0.id == id }) else { return }
        do {
            store = try history.removingAccount(id, from: store)
        } catch {
            phase[id] = .failed("Couldn't remove \(account.label) because its Codex home couldn't be deleted. Check that the home is accessible, then try Remove again.")
            return
        }
        phase[id] = nil
        banners[id] = nil
        authRequired.remove(id)
        var cleaned = store
        cleaned.alertReceipts.removeAll { $0.accountId == id }
        store = cleaned
        persist()
    }

    func suggestedLabel() -> String {
        let labels = Set(store.accounts.map { $0.label.lowercased() })
        if !labels.contains("personal") { return "Personal" }
        if !labels.contains("work") { return "Work" }
        var number = store.accounts.count + 1
        while labels.contains("account \(number)") { number += 1 }
        return "Account \(number)"
    }

    func isBusy(_ id: String) -> Bool {
        phase[id] == .refreshing || phase[id] == .signingIn
    }

    func refreshAll() async {
        guard libraryReady else { return }
        if refreshRunning {
            refreshAgain = true
            return
        }
        refreshRunning = true
        defer {
            refreshRunning = false
            if refreshAgain {
                refreshAgain = false
                Task { await self.refreshAll() }
            }
        }
        let accountIDs = store.accounts.map(\.id)
        let selectedID = store.selectedAccountId ?? store.accounts.first?.id
        await RefreshScheduler.run(accountIDs: accountIDs, selectedID: selectedID) { [weak self] id in
            await self?.refresh(id)
        }
    }

    func refresh(_ id: String) async {
        guard libraryReady else { return }
        guard let account = store.accounts.first(where: { $0.id == id }) else { return }
        if phase[id] == .refreshing || phase[id] == .signingIn { return }
        phase[id] = .refreshing
        banners[id] = nil
        do {
            let reading = try await service.refresh(home: account.codexHome)
            await apply(reading, to: id)
            phase[id] = .idle
        } catch let error as QuotaFailure {
            phase[id] = .failed(error.message)
        } catch {
            phase[id] = .failed("Codex couldn't be read.")
        }
    }

    func signIn(_ id: String) async {
        guard libraryReady else { return }
        guard let account = store.accounts.first(where: { $0.id == id }) else { return }
        if phase[id] == .refreshing || phase[id] == .signingIn { return }
        phase[id] = .signingIn
        banners[id] = nil
        do {
            let reading = try await service.signIn(home: account.codexHome) { url in
                Task { @MainActor in
                    NSWorkspace.shared.open(url)
                }
            }
            guard reading.identity != nil else {
                authRequired.insert(id)
                phase[id] = .failed(QuotaFailure.signInFailed.message)
                return
            }
            await apply(reading, to: id)
            phase[id] = .idle
        } catch let error as QuotaFailure {
            phase[id] = .failed(error.message)
        } catch {
            phase[id] = .failed(QuotaFailure.signInFailed.message)
        }
    }

    func signOut(_ id: String) async {
        guard libraryReady else { return }
        guard let account = store.accounts.first(where: { $0.id == id }) else { return }
        phase[id] = .refreshing
        do {
            try await service.signOut(home: account.codexHome)
            authRequired.insert(id)
            phase[id] = .idle
            banners[id] = "Signed out on this Mac."
        } catch let error as QuotaFailure {
            phase[id] = .failed(error.message)
        } catch {
            phase[id] = .failed("Codex couldn't sign this account out.")
        }
    }

    func samples(for id: String) -> [UsageSample] {
        store.samples.filter { $0.accountId == id }
    }

    func latestSample(for id: String) -> UsageSample? {
        samples(for: id).max { $0.sampledAt < $1.sampledAt }
    }

    func paceReport(for id: String, sample: UsageSample, now: Date) -> PaceReport? {
        guard let used = sample.usedPercent, let reset = sample.resetsAt, let minutes = sample.windowDurationMins else {
            return nil
        }
        return Pace.evaluate(
            now: now,
            usedPercent: used,
            resetsAt: reset,
            windowDurationMins: minutes,
            samples: samples(for: id),
            buckets: sample.dailyBuckets
        )
    }

    func isStale(_ sample: UsageSample?, now: Date) -> Bool {
        guard let sample else { return false }
        return now.timeIntervalSince(sample.sampledAt) > QuotaTiming.staleInterval
    }

    private func apply(_ reading: UsageReading, to id: String) async {
        guard libraryReady else { return }
        let sampledAt = Date()
        let previousSample = latestSample(for: id)
        let previousPace = previousSample.flatMap { paceReport(for: id, sample: $0, now: sampledAt) }
        guard let sample = UsageSample.merging(
            accountId: id,
            sampledAt: sampledAt,
            reading: reading,
            previous: previousSample
        ) else {
            authRequired.insert(id)
            banners[id] = "Sign in with ChatGPT to read this account."
            return
        }
        authRequired.remove(id)
        var copy = store
        history.record(sample, into: &copy, now: sample.sampledAt)
        let pace = paceReport(for: id, sample: sample, now: sampledAt, store: copy)
        let candidates = QuotaAlerts.candidates(
            accountId: id,
            previousSample: previousSample,
            previousPace: previousPace,
            sample: sample,
            pace: pace,
            preferences: copy.alertPreferences,
            receipts: copy.alertReceipts
        )
        let activeResetDates = currentResetDates(in: copy)
        copy.alertReceipts = QuotaAlerts.prunedReceipts(copy.alertReceipts, activeResetDates: activeResetDates)
        store = copy
        if !reading.optionalUsageSucceeded {
            banners[id] = nil
        } else if reading.weekly == nil {
            banners[id] = "This account didn't include a 7-day allowance."
        } else if reading.weekly?.resetsAt == nil {
            banners[id] = "The reset time wasn't included, so today's slice is hidden."
        } else {
            banners[id] = nil
        }
        persist()
        guard let account = store.accounts.first(where: { $0.id == id }) else { return }
        for candidate in candidates {
            let deliveredSuccessfully = await notifications.deliver(accountLabel: account.label, event: candidate.event)
            alertPermission = notifications.permission
            guard deliveredSuccessfully else { continue }
            var delivered = store
            delivered.alertReceipts = QuotaAlerts.addingReceipt(
                for: candidate,
                deliveredAt: Date(),
                to: delivered.alertReceipts,
                activeResetDates: currentResetDates(in: delivered)
            )
            store = delivered
            persist()
        }
    }

    private func paceReport(for id: String, sample: UsageSample, now: Date, store: StoreFile) -> PaceReport? {
        guard let used = sample.usedPercent, let reset = sample.resetsAt, let minutes = sample.windowDurationMins else {
            return nil
        }
        return Pace.evaluate(
            now: now,
            usedPercent: used,
            resetsAt: reset,
            windowDurationMins: minutes,
            samples: store.samples.filter { $0.accountId == id },
            buckets: sample.dailyBuckets
        )
    }

    private func currentResetDates(in store: StoreFile) -> [Date] {
        store.accounts.compactMap { account in
            store.samples
                .filter { $0.accountId == account.id }
                .max { $0.sampledAt < $1.sampledAt }?
                .resetsAt
        }
    }

    private func persist() {
        guard libraryReady else { return }
        do {
            try history.save(store)
            libraryNotice.saveSucceeded()
        } catch {
            libraryNotice.saveFailed()
        }
    }
}

enum AccountPhase: Equatable {
    case idle
    case refreshing
    case signingIn
    case failed(String)
}
