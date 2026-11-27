import Foundation

public struct LibraryLoad: Equatable, Sendable {
    public var store: StoreFile
    public var replacedCorruptFile: URL?
}

public struct HistoryStore: Sendable {
    public var directory: URL

    public init(directory: URL) {
        self.directory = directory
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
            return LibraryLoad(store: .empty(), replacedCorruptFile: nil)
        }
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let store = try decoder.decode(StoreFile.self, from: data)
            guard store.version == StoreFile.currentVersion else {
                throw QuotaFailure.library("This Mac has a Codex Quota library from another version.")
            }
            return LibraryLoad(store: pruned(store, now: now), replacedCorruptFile: nil)
        } catch let failure as QuotaFailure {
            throw failure
        } catch {
            let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
            let kept = directory.appendingPathComponent("store.json.unreadable-\(stamp)")
            try? fileManager.moveItem(at: fileURL, to: kept)
            return LibraryLoad(store: .empty(), replacedCorruptFile: kept)
        }
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

    public func removeHome(_ path: String) {
        let home = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let ownedHomes = homesURL.standardizedFileURL.resolvingSymlinksInPath()
        guard home.deletingLastPathComponent() == ownedHomes else { return }
        try? FileManager.default.removeItem(at: home)
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
