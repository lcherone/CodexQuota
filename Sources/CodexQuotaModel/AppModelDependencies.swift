import CodexQuotaCore
import Foundation

public struct AppHistory: Sendable {
    public var fileURL: URL
    public var load: @Sendable () throws -> LibraryLoad
    public var save: @Sendable (StoreFile) throws -> Void
    public var makeHome: @Sendable (String) throws -> String
    public var removingAccount: @Sendable (String, StoreFile) throws -> StoreFile
    public var record: @Sendable (UsageSample, inout StoreFile, Date) -> Void

    public init(_ history: HistoryStore) {
        fileURL = history.fileURL
        load = { try history.load() }
        save = { try history.save($0) }
        makeHome = { try history.makeHome(id: $0) }
        removingAccount = { try history.removingAccount($0, from: $1) }
        record = { history.record($0, into: &$1, now: $2) }
    }

    public init(
        fileURL: URL,
        load: @escaping @Sendable () throws -> LibraryLoad,
        save: @escaping @Sendable (StoreFile) throws -> Void,
        makeHome: @escaping @Sendable (String) throws -> String,
        removingAccount: @escaping @Sendable (String, StoreFile) throws -> StoreFile,
        record: @escaping @Sendable (UsageSample, inout StoreFile, Date) -> Void
    ) {
        self.fileURL = fileURL
        self.load = load
        self.save = save
        self.makeHome = makeHome
        self.removingAccount = removingAccount
        self.record = record
    }
}

public struct AppQuotaService: Sendable {
    public var refresh: @Sendable (String) async throws -> UsageReading
    public var signIn: @Sendable (String, @escaping @Sendable (URL) -> Void) async throws -> UsageReading
    public var signOut: @Sendable (String) async throws -> Void

    public init(_ service: QuotaService) {
        refresh = { try await service.refresh(home: $0) }
        signIn = { try await service.signIn(home: $0, open: $1) }
        signOut = { try await service.signOut(home: $0) }
    }

    public init(
        refresh: @escaping @Sendable (String) async throws -> UsageReading,
        signIn: @escaping @Sendable (String, @escaping @Sendable (URL) -> Void) async throws -> UsageReading,
        signOut: @escaping @Sendable (String) async throws -> Void
    ) {
        self.refresh = refresh
        self.signIn = signIn
        self.signOut = signOut
    }
}

public enum LocalNotificationPermission: Equatable, Sendable {
    case unknown, notDetermined, authorized, denied, unavailable
}

@MainActor
public protocol LocalNotificationControlling: AnyObject {
    var permission: LocalNotificationPermission { get }
    func refreshPermission() async
    func requestPermission() async -> Bool
    func openNotificationSettings()
    func deliver(accountLabel: String, event: QuotaAlertEvent) async -> Bool
}

@MainActor
public protocol LoginItemControlling: AnyObject {
    var error: String? { get }
    var canConfigure: Bool { get }
    var isEnabled: Bool { get }
    var needsApproval: Bool { get }
    func refresh()
    func setEnabled(_ enabled: Bool)
    func openSettings()
}
