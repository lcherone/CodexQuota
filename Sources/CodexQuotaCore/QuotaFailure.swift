import Foundation

public enum QuotaFailure: Error, Equatable, Sendable {
    case codexMissing(String)
    case notRunning
    case timedOut(String)
    case serverStopped
    case unreadable
    case refused(String)
    case signInLink
    case signInTimedOut
    case signInFailed
    case library(String)

    public var message: String {
        switch self {
        case let .codexMissing(text):
            return text
        case .notRunning:
            return "Codex isn't running."
        case let .timedOut(method):
            return "Codex took too long on \(method)."
        case .serverStopped:
            return "The Codex app server stopped."
        case .unreadable:
            return "Codex sent a response this app couldn't read."
        case let .refused(method):
            return "Codex refused \(method)."
        case .signInLink:
            return "Codex didn't return a browser sign-in link."
        case .signInTimedOut:
            return "Sign-in is still waiting. Try again when the browser has finished."
        case .signInFailed:
            return "Sign-in didn't finish."
        case let .library(text):
            return text
        }
    }
}

public enum QuotaTiming {
    /// Menu-bar refresh cadence after the first successful library exists.
    public static let refreshInterval: TimeInterval = 5 * 60
    /// A reading older than this is shown as stale.
    public static let staleInterval: TimeInterval = 15 * 60
    public static let rpcTimeout: TimeInterval = 30
    public static let signInTimeout: TimeInterval = 180
    public static let sampleCoalesce: TimeInterval = 120
    public static let historyWeeks: TimeInterval = 26 * 7 * 24 * 60 * 60
    public static let sampleCap = 4000
    /// Weekly points of slack before a day or the week is called over or under.
    public static let tolerance: Double = 0.5
    public static let weeklyMinutes = 10_080.0
    public static let weeklyLower = 8_640.0
    public static let weeklyUpper = 11_520.0
    public static let sliceCount = 7
}

public enum CodexBinary {
    public static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        which: (String) -> String? = CodexBinary.which
    ) -> Result<String, QuotaFailure> {
        if let configured = environment["CODEX_BIN"], !configured.isEmpty {
            if isExecutable(configured) {
                return .success(configured)
            }
            return .failure(.codexMissing("CODEX_BIN doesn't point at an executable."))
        }
        let home = environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "/usr/bin/codex"
        ]
        if let found = candidates.first(where: isExecutable) {
            return .success(found)
        }
        if let found = which("codex"), isExecutable(found) {
            return .success(found)
        }
        return .failure(.codexMissing("The Codex CLI isn't on this Mac. Install it, or set CODEX_BIN."))
    }

    public static func which(_ name: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let path, !path.isEmpty else { return nil }
        return path
    }
}
