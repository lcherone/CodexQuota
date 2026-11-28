import CodexQuotaCore
import Foundation
import Observation

@MainActor
@Observable
public final class AppModel {
    public let loginItem: LoginItemControlling
    private let notifications: LocalNotificationControlling

    public private(set) var store: StoreFile
    public private(set) var phase: [String: AccountPhase] = [:]
    public private(set) var refreshFailures: Set<String> = []
    public private(set) var banners: [String: String] = [:]
    public private(set) var authRequired: Set<String> = []
    public private(set) var alertPermission: LocalNotificationPermission = .unknown
    public private(set) var aggregateRefresh: AggregateRefreshState = .idle
    public private(set) var workspaceDetails: [String: DetailsLoad<WorkspaceMessagesDetails>] = [:]
    public private(set) var conversationDetails: [String: DetailsLoad<ConversationPage>] = [:]
    public private(set) var conversationUsageDetails: [String: DetailsLoad<ConversationUsageDetails>] = [:]
    private var detailsGenerations: [String: UUID] = [:]
    private var libraryNotice = LibraryNoticeState()
    public private(set) var libraryReady = false
    private let history: AppHistory
    private let service: AppQuotaService
    private var loop: Task<Void, Never>?
    private var refreshRunning = false
    private var refreshAgain = false
    private var signInOperations: [String: SignInOperation] = [:]

    private let openBrowser: @MainActor @Sendable (URL) -> Void
    private let now: @Sendable () -> Date
    private let makeID: @Sendable () -> String

    public init(
        history: AppHistory,
        service: AppQuotaService,
        notifications: LocalNotificationControlling,
        loginItem: LoginItemControlling,
        openBrowser: @escaping @MainActor @Sendable (URL) -> Void,
        now: @escaping @Sendable () -> Date = { Date() },
        makeID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() }
    ) {
        self.history = history
        self.service = service
        self.notifications = notifications
        self.loginItem = loginItem
        self.openBrowser = openBrowser
        self.now = now
        self.makeID = makeID
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

    public var libraryNote: String? {
        libraryNotice.displayedNotice
    }

    public var alertsEnabled: Bool {
        store.alertPreferences.enabled && alertPermission == .authorized
    }

    public var selectedAccount: AccountRecord? {
        let id = store.selectedAccountId ?? store.accounts.first?.id
        return store.accounts.first { $0.id == id }
    }

    public var menuBarPresentation: MenuBarPresentation {
        guard let account = selectedAccount else {
            return MenuBarPresentation(selectedAccountLabel: nil, accountCount: 0, stateTitle: "Quota")
        }
        let latest = latestSample(for: account.id)
        let currentTime = now()
        let stateTitle: String
        if authRequired.contains(account.id) {
            stateTitle = "Sign in"
        } else if let latest {
            let pace = paceReport(for: account.id, sample: latest, now: currentTime)
            stateTitle = Pace.menuTitle(
                todaySlicePercent: pace?.todaySlicePercent,
                todayKind: pace?.todayKind ?? .unknown,
                dayStatus: pace?.dayStatus ?? .unknown,
                weeklyUsed: latest.usedPercent
            )
        } else {
            stateTitle = "Quota"
        }
        let health: MenuBarHealth
        if refreshFailures.contains(account.id) {
            health = .refreshFailed
        } else if isStale(latest, now: currentTime) {
            health = .stale
        } else {
            health = .current
        }
        return MenuBarPresentation(
            selectedAccountLabel: account.label,
            accountCount: store.accounts.count,
            stateTitle: stateTitle,
            health: health
        )
    }

    public func start() {
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

    public func select(_ id: String) {
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
            now: now()
        ) else { return }
        Task { await refresh(id) }
    }

    public func setAppearance(_ appearance: PanelAppearance) {
        guard libraryReady else { return }
        guard store.appearance != appearance else { return }
        var copy = store
        copy.appearance = appearance
        store = copy
        persist()
    }

    public func setAlertsEnabled(_ enabled: Bool) async {
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

    public func setAlertThreshold(_ threshold: Int) {
        guard libraryReady else { return }
        let normalized = QuotaAlertPreferences.normalizedThreshold(threshold)
        guard store.alertPreferences.weeklyThreshold != normalized else { return }
        var copy = store
        copy.alertPreferences.weeklyThreshold = normalized
        store = copy
        persist()
    }

    public func refreshAlertPermission() async {
        await notifications.refreshPermission()
        alertPermission = notifications.permission
    }

    public func openNotificationSettings() {
        notifications.openNotificationSettings()
    }

    public func addAccount(label: String) {
        guard libraryReady else { return }
        let name = AccountRecord.normalizedLabel(label, retaining: suggestedLabel())
        let id = makeID()
        let home: String
        do {
            home = try history.makeHome(id)
        } catch {
            libraryNotice.durableNotice = "A home for this account couldn't be created on this Mac."
            return
        }
        var copy = store
        copy.accounts.append(AccountRecord(id: id, label: name, codexHome: home, createdAt: now()))
        copy.selectedAccountId = id
        store = copy
        persist()
        Task { await refresh(id) }
    }

    public func renameAccount(_ id: String, label: String) {
        guard libraryReady else { return }
        guard let index = store.accounts.firstIndex(where: { $0.id == id }) else { return }
        let name = AccountRecord.normalizedLabel(label, retaining: store.accounts[index].label)
        guard name != store.accounts[index].label else { return }
        var copy = store
        copy.accounts[index].label = name
        store = copy
        persist()
    }

    public func removeAccount(_ id: String) {
        guard libraryReady else { return }
        guard !isBusy(id) else { return }
        guard let account = store.accounts.first(where: { $0.id == id }) else { return }
        do {
            store = try history.removingAccount(id, store)
        } catch {
            phase[id] = .failed("Couldn't remove \(account.label) because its Codex home couldn't be deleted. Check that the home is accessible, then try Remove again.")
            return
        }
        phase[id] = nil
        refreshFailures.remove(id)
        clearDetails(id)
        banners[id] = nil
        authRequired.remove(id)
        var cleaned = store
        cleaned.alertReceipts.removeAll { $0.accountId == id }
        store = cleaned
        persist()
    }

    public func suggestedLabel() -> String {
        let labels = Set(store.accounts.map { $0.label.lowercased() })
        if !labels.contains("personal") { return "Personal" }
        if !labels.contains("work") { return "Work" }
        var number = store.accounts.count + 1
        while labels.contains("account \(number)") { number += 1 }
        return "Account \(number)"
    }

    public func isBusy(_ id: String) -> Bool {
        phase[id] == .refreshing || phase[id] == .signingIn
    }

    public var isFullRefreshRunning: Bool {
        refreshRunning
    }

    public func refreshAll() async {
        await runFullRefresh(queueIfRunning: true)
    }

    public func refreshAllManually() async {
        await runFullRefresh(queueIfRunning: false)
    }

    private func runFullRefresh(queueIfRunning: Bool) async {
        guard libraryReady else { return }
        if refreshRunning {
            if queueIfRunning {
                refreshAgain = true
            }
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
        let total = Set(accountIDs).count
        aggregateRefresh = .running(total: total, completed: 0, failed: 0, busySkipped: 0)
        await RefreshScheduler.run(accountIDs: accountIDs, selectedID: selectedID) { [weak self] id in
            guard let self else { return }
            let outcome = await self.performRefresh(id)
            await self.recordAggregateRefresh(outcome)
        }
        guard case let .running(_, completed, failed, busySkipped) = aggregateRefresh else { return }
        aggregateRefresh = .completed(
            total: total,
            completed: completed,
            failed: failed,
            busySkipped: busySkipped
        )
    }

    public func refresh(_ id: String) async {
        _ = await performRefresh(id)
    }

    private func performRefresh(_ id: String) async -> AccountRefreshOutcome {
        guard libraryReady else { return .missingAccount }
        guard let account = store.accounts.first(where: { $0.id == id }) else { return .missingAccount }
        if phase[id] == .refreshing || phase[id] == .signingIn { return .busySkipped }
        phase[id] = .refreshing
        banners[id] = nil
        do {
            let reading = try await service.refresh(account.codexHome)
            await apply(reading, to: id)
            refreshFailures.remove(id)
            phase[id] = .idle
            return .success
        } catch let error as QuotaFailure {
            refreshFailures.insert(id)
            phase[id] = .failed(error.message)
            return .failed
        } catch {
            refreshFailures.insert(id)
            phase[id] = .failed("Codex couldn't be read.")
            return .failed
        }
    }

    private func recordAggregateRefresh(_ outcome: AccountRefreshOutcome) {
        guard case let .running(total, completed, failed, busySkipped) = aggregateRefresh else { return }
        aggregateRefresh = .running(
            total: total,
            completed: completed + 1,
            failed: failed + (outcome.isFailure ? 1 : 0),
            busySkipped: busySkipped + (outcome == .busySkipped ? 1 : 0)
        )
    }

    public func signIn(_ id: String) {
        guard libraryReady else { return }
        guard store.accounts.contains(where: { $0.id == id }) else { return }
        guard signInOperations[id] == nil else { return }
        if phase[id] == .refreshing { return }
        let token = UUID()
        let presentation = SignInPresentation(
            phase: phase[id],
            banner: banners[id],
            authRequired: authRequired.contains(id)
        )
        phase[id] = .signingIn
        clearDetails(id)
        banners[id] = nil
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performSignIn(id, token: token)
        }
        signInOperations[id] = SignInOperation(token: token, task: task, presentation: presentation)
    }

    public func cancelSignIn(_ id: String) {
        guard phase[id] == .signingIn else { return }
        signInOperations[id]?.task.cancel()
    }

    private func performSignIn(_ id: String, token: UUID) async {
        guard let operation = signInOperations[id], operation.token == token else { return }
        defer {
            if signInOperations[id]?.token == token {
                signInOperations[id] = nil
            }
        }
        guard let account = store.accounts.first(where: { $0.id == id }) else {
            restoreSignInPresentation(operation.presentation, for: id)
            return
        }
        do {
            let reading = try await service.signIn(account.codexHome) { url in
                Task { @MainActor [weak self] in self?.openBrowser(url) }
            }
            try Task.checkCancellation()
            guard reading.identity != nil else {
                authRequired.insert(id)
                phase[id] = .failed(QuotaFailure.signInFailed.message)
                return
            }
            clearDetails(id)
            await apply(reading, to: id)
            phase[id] = .idle
        } catch is CancellationError {
            restoreSignInPresentation(operation.presentation, for: id)
        } catch let error as QuotaFailure {
            phase[id] = .failed(error.message)
        } catch {
            phase[id] = .failed(QuotaFailure.signInFailed.message)
        }
    }

    private func restoreSignInPresentation(_ presentation: SignInPresentation, for id: String) {
        phase[id] = presentation.phase
        banners[id] = presentation.banner
        if presentation.authRequired {
            authRequired.insert(id)
        } else {
            authRequired.remove(id)
        }
    }

    public func signOut(_ id: String) async {
        guard libraryReady else { return }
        guard let account = store.accounts.first(where: { $0.id == id }) else { return }
        phase[id] = .refreshing
        do {
            try await service.signOut(account.codexHome)
            clearDetails(id)
            authRequired.insert(id)
            phase[id] = .idle
            banners[id] = "Signed out on this Mac."
        } catch let error as QuotaFailure {
            phase[id] = .failed(error.message)
        } catch {
            phase[id] = .failed("Codex couldn't sign this account out.")
        }
    }

    public func samples(for id: String) -> [UsageSample] {
        store.samples.filter { $0.accountId == id }
    }

    public func latestSample(for id: String) -> UsageSample? {
        samples(for: id).max { $0.sampledAt < $1.sampledAt }
    }

    public func paceReport(for id: String, sample: UsageSample, now: Date) -> PaceReport? {
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

    public func isStale(_ sample: UsageSample?, now: Date) -> Bool {
        guard let sample else { return false }
        return now.timeIntervalSince(sample.sampledAt) > QuotaTiming.staleInterval
    }

    private func apply(_ reading: UsageReading, to id: String) async {
        guard libraryReady else { return }
        let sampledAt = now()
        let previousSample = latestSample(for: id)
        let previousPace = previousSample.flatMap { paceReport(for: id, sample: $0, now: sampledAt) }
        guard let sample = UsageSample.merging(
            accountId: id,
            sampledAt: sampledAt,
            reading: reading,
            previous: previousSample
        ) else {
            clearDetails(id)
            authRequired.insert(id)
            banners[id] = "Sign in with ChatGPT to read this account."
            return
        }
        authRequired.remove(id)
        var copy = store
        history.record(sample, &copy, sample.sampledAt)
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
                deliveredAt: now(),
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

public enum AccountPhase: Equatable {
    case idle
    case refreshing
    case signingIn
    case failed(String)
}

public enum AggregateRefreshState: Equatable {
    case idle
    case running(total: Int, completed: Int, failed: Int, busySkipped: Int)
    case completed(total: Int, completed: Int, failed: Int, busySkipped: Int)
}

private enum AccountRefreshOutcome: Equatable {
    case success
    case failed
    case missingAccount
    case busySkipped

    var isFailure: Bool {
        self == .failed || self == .missingAccount
    }
}

private struct SignInPresentation {
    var phase: AccountPhase?
    var banner: String?
    var authRequired: Bool
}

private struct SignInOperation {
    var token: UUID
    var task: Task<Void, Never>
    var presentation: SignInPresentation
}

extension AppModel {
    public static func conversationsKey(_ accountID: String, archived: Bool) -> String {
        "\(accountID)/\(archived ? "archived" : "active")"
    }

    public static func conversationUsageKey(_ accountID: String, threadID: String) -> String {
        "\(accountID)/\(threadID.lowercased())"
    }

    private func detailsGeneration(_ id: String) -> UUID {
        if let generation = detailsGenerations[id] { return generation }
        let generation = UUID()
        detailsGenerations[id] = generation
        return generation
    }

    private func clearDetails(_ id: String) {
        detailsGenerations[id] = UUID()
        workspaceDetails[id] = nil
        conversationDetails = conversationDetails.filter { !$0.key.hasPrefix(id + "/") }
        conversationUsageDetails = conversationUsageDetails.filter { !$0.key.hasPrefix(id + "/") }
    }

    private func detailsHome(_ id: String) -> String? {
        guard libraryReady, !authRequired.contains(id), phase[id] != .signingIn else { return nil }
        return store.accounts.first { $0.id == id }?.codexHome
    }

    private func detailsError(_ error: Error) -> String {
        if let failure = error as? QuotaFailure { return failure.message }
        if error is CancellationError { return "Request cancelled. Try again." }
        return "These details couldn't be read. Try again."
    }

    public func loadWorkspaceDetails(_ id: String, force: Bool = false) async {
        guard let home = detailsHome(id) else { return }
        var state = workspaceDetails[id] ?? DetailsLoad()
        guard !state.isLoading else { return }
        if !force, let checked = state.checkedAt, now().timeIntervalSince(checked) < QuotaTiming.refreshInterval { return }
        let generation = detailsGeneration(id)
        state.isLoading = true
        state.error = nil
        workspaceDetails[id] = state
        do {
            let value = try await service.workspaceMessages(home)
            try Task.checkCancellation()
            state.value = value
            state.checkedAt = now()
        } catch {
            state.error = detailsError(error)
        }
        guard detailsGenerations[id] == generation else { return }
        state.isLoading = false
        workspaceDetails[id] = state
    }

    public func loadConversations(_ id: String, archived: Bool, more: Bool = false, force: Bool = false) async {
        guard let home = detailsHome(id) else { return }
        let key = Self.conversationsKey(id, archived: archived)
        var state = conversationDetails[key] ?? DetailsLoad()
        guard !state.isLoading else { return }
        if !more, !force, let checked = state.checkedAt, now().timeIntervalSince(checked) < QuotaTiming.refreshInterval { return }
        let cursor = more ? state.value?.nextCursor : nil
        if more, cursor == nil { return }
        let generation = detailsGeneration(id)
        state.isLoading = true
        state.error = nil
        conversationDetails[key] = state
        do {
            var page = try await service.conversations(home, cursor, archived)
            try Task.checkCancellation()
            if more {
                var seen = Set<String>()
                page.conversations = ((state.value?.conversations ?? []) + page.conversations).filter { seen.insert($0.id).inserted }
                if page.nextCursor == cursor { page.nextCursor = nil }
            }
            state.value = page
            state.checkedAt = now()
        } catch {
            state.error = detailsError(error)
        }
        guard detailsGenerations[id] == generation else { return }
        state.isLoading = false
        conversationDetails[key] = state
    }

    public func loadConversationUsage(_ id: String, threadID: String, force: Bool = false) async {
        guard let home = detailsHome(id), UUID(uuidString: threadID) != nil else { return }
        let key = Self.conversationUsageKey(id, threadID: threadID)
        var state = conversationUsageDetails[key] ?? DetailsLoad()
        guard !state.isLoading else { return }
        if !force, let checked = state.checkedAt, now().timeIntervalSince(checked) < QuotaTiming.refreshInterval { return }
        let generation = detailsGeneration(id)
        state.isLoading = true
        state.error = nil
        conversationUsageDetails[key] = state
        do {
            let value = try await service.conversationUsage(home, threadID)
            try Task.checkCancellation()
            state.value = value
            state.checkedAt = now()
        } catch {
            state.error = detailsError(error)
        }
        guard detailsGenerations[id] == generation else { return }
        state.isLoading = false
        conversationUsageDetails[key] = state
    }
}
