import Foundation

private struct StoredLibraryVersion: Decodable {
    var version: Int
}

public enum LibraryAccess: Equatable, Sendable {
    case writable
    case writableAfterQuarantine(URL)
    case blocked(String)

    public var isWritable: Bool {
        if case .blocked = self { return false }
        return true
    }
}

public struct LibraryLoad: Equatable, Sendable {
    public var store: StoreFile
    public var access: LibraryAccess
}

public struct HistoryStore: Sendable {
    public var directory: URL
    private let moveItem: @Sendable (URL, URL) throws -> Void
    private let removeItem: @Sendable (URL) throws -> Void

    public init(
        directory: URL,
        moveItem: @escaping @Sendable (URL, URL) throws -> Void = { try FileManager.default.moveItem(at: $0, to: $1) },
        removeItem: @escaping @Sendable (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) {
        self.directory = directory
        self.moveItem = moveItem
        self.removeItem = removeItem
    }

    public var fileURL: URL { directory.appendingPathComponent("store.json") }
    public var homesURL: URL { directory.appendingPathComponent("homes", isDirectory: true) }

    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment) -> HistoryStore {
        if let override = environment["CODEX_QUOTA_DIR"], !override.isEmpty {
            return HistoryStore(directory: URL(fileURLWithPath: override, isDirectory: true))
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true).appendingPathComponent("Library/Application Support", isDirectory: true)
        return HistoryStore(directory: base.appendingPathComponent("CodexQuota", isDirectory: true))
    }

    public func load(now: Date = Date()) throws -> LibraryLoad {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return LibraryLoad(store: .empty(), access: .writable)
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            return blockedLoad(
                "Codex Quota couldn't safely read the library, so it was left unchanged at \(fileURL.path). Resolve the file problem or move it yourself, then relaunch Codex Quota."
            )
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let storedVersion = try decoder.decode(StoredLibraryVersion.self, from: data)
            guard storedVersion.version == StoreFile.currentVersion else {
                return blockedLoad(
                    "This library uses an unsupported version. Codex Quota left it unchanged at \(fileURL.path). Move it or install a compatible version, then relaunch Codex Quota."
                )
            }
            let store = try decoder.decode(StoreFile.self, from: data)
            return LibraryLoad(store: pruned(store, now: now), access: .writable)
        } catch {
            let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
            let kept = directory.appendingPathComponent("store.json.unreadable-\(stamp)")
            do {
                try moveItem(fileURL, kept)
                return LibraryLoad(store: .empty(), access: .writableAfterQuarantine(kept))
            } catch {
                return blockedLoad(
                    "Codex Quota couldn't safely preserve and replace the unreadable library, so it was left unchanged at \(fileURL.path). Resolve the file problem or move it yourself, then relaunch Codex Quota."
                )
            }
        }
    }

    private func blockedLoad(_ message: String) -> LibraryLoad {
        LibraryLoad(store: .empty(), access: .blocked(message))
    }

    public func save(_ store: StoreFile) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(pruned(store, now: Date()))
        let temporary = fileURL.appendingPathExtension("tmp")
        try data.write(to: temporary, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
        if fileManager.fileExists(atPath: fileURL.path) {
            _ = try fileManager.replaceItemAt(fileURL, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: fileURL)
        }
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func makeHome(id: String) throws -> String {
        let url = homesURL.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url.path
    }

    public func removeHome(_ path: String) throws {
        let home = URL(fileURLWithPath: path).standardizedFileURL
        let ownedHomes = homesURL.standardizedFileURL
        guard home.deletingLastPathComponent() == ownedHomes,
              try home.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
              home.resolvingSymlinksInPath().deletingLastPathComponent()
                == ownedHomes.resolvingSymlinksInPath() else {
            throw QuotaFailure.library("Codex Quota refused to remove a home outside its managed homes directory.")
        }
        try removeItem(home)
    }

    public func removingAccount(_ id: String, from store: StoreFile) throws -> StoreFile {
        guard let account = store.accounts.first(where: { $0.id == id }) else { return store }
        try removeHome(account.codexHome)
        var copy = store
        copy.accounts.removeAll { $0.id == id }
        copy.samples.removeAll { $0.accountId == id }
        if copy.selectedAccountId == id {
            copy.selectedAccountId = copy.accounts.first?.id
        }
        return copy
    }

    public func record(_ sample: UsageSample, into store: inout StoreFile, now: Date) {
        if let index = store.samples.lastIndex(where: { $0.accountId == sample.accountId }) {
            let previous = store.samples[index]
            if now.timeIntervalSince(previous.sampledAt) < QuotaTiming.sampleCoalesce,
               previous.usedPercent == sample.usedPercent,
               previous.resetsAt == sample.resetsAt,
               previous.lifetimeTokens == sample.lifetimeTokens {
                store.samples[index] = sample
                store = pruned(store, now: now)
                return
            }
        }
        store.samples.append(sample)
        store = pruned(store, now: now)
    }

    public func pruned(_ store: StoreFile, now: Date) -> StoreFile {
        var copy = store
        let cutoff = now.addingTimeInterval(-QuotaTiming.historyWeeks)
        copy.samples = copy.samples.filter { $0.sampledAt >= cutoff }
        if copy.samples.count > QuotaTiming.sampleCap {
            copy.samples = Array(copy.samples.suffix(QuotaTiming.sampleCap))
        }
        return copy
    }
}
