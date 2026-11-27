import AppKit
import CodexQuotaCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()
    let loginItem = LoginItemController()

    private(set) var store: StoreFile
    private(set) var phase: [String: AccountPhase] = [:]
    private(set) var banners: [String: String] = [:]
    private(set) var authRequired: Set<String> = []
    private(set) var libraryNote: String?
    private let history: HistoryStore
    private let service: QuotaService
    private var loop: Task<Void, Never>?
    private var refreshRunning = false
    private var refreshAgain = false

    init(history: HistoryStore = .resolve(), service: QuotaService = .production()) {
        self.history = history
        self.service = service
        do {
            let loaded = try history.load()
            store = loaded.store
            if let kept = loaded.replacedCorruptFile {
                libraryNote = "The previous library couldn't be read. It was kept as \(kept.lastPathComponent)."
            }
        } catch let error as QuotaFailure {
            store = .empty()
            libraryNote = error.message
        } catch {
            store = .empty()
            libraryNote = "The library on this Mac couldn't be opened."
        }
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
        guard loop == nil else { return }
        loop = Task { [weak self] in
            await self?.refreshAll()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(QuotaTiming.refreshInterval * 1_000_000_000))
                await self?.refreshAll()
            }
        }
    }

    func select(_ id: String) {
        var copy = store
        copy.selectedAccountId = id
        store = copy
        persist()
    }

    func setAppearance(_ appearance: PanelAppearance) {
        guard store.appearance != appearance else { return }
        var copy = store
        copy.appearance = appearance
        store = copy
        persist()
    }

    func addAccount(label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = String((trimmed.isEmpty ? suggestedLabel() : trimmed).prefix(40))
        let id = UUID().uuidString.lowercased()
        let home: String
        do {
            home = try history.makeHome(id: id)
        } catch {
            libraryNote = "A home for this account couldn't be created on this Mac."
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
        guard let account = store.accounts.first(where: { $0.id == id }) else { return }
        if phase[id] == .refreshing || phase[id] == .signingIn { return }
        phase[id] = .refreshing
        banners[id] = nil
        do {
            let reading = try await service.refresh(home: account.codexHome)
            apply(reading, to: id)
            phase[id] = .idle
        } catch let error as QuotaFailure {
            phase[id] = .failed(error.message)
        } catch {
            phase[id] = .failed("Codex couldn't be read.")
        }
    }

    func signIn(_ id: String) async {
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
            apply(reading, to: id)
            phase[id] = .idle
        } catch let error as QuotaFailure {
            phase[id] = .failed(error.message)
        } catch {
            phase[id] = .failed(QuotaFailure.signInFailed.message)
        }
    }

    func signOut(_ id: String) async {
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

    private func apply(_ reading: UsageReading, to id: String) {
        let sampledAt = Date()
        guard let sample = UsageSample.merging(
            accountId: id,
            sampledAt: sampledAt,
            reading: reading,
            previous: latestSample(for: id)
        ) else {
            authRequired.insert(id)
            banners[id] = "Sign in with ChatGPT to read this account."
            return
        }
        authRequired.remove(id)
        var copy = store
        history.record(sample, into: &copy, now: sample.sampledAt)
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
    }

    private func persist() {
        do {
            try history.save(store)
        } catch {
            libraryNote = "The latest reading couldn't be saved on this Mac."
        }
    }
}

enum AccountPhase: Equatable {
    case idle
    case refreshing
    case signingIn
    case failed(String)
}
