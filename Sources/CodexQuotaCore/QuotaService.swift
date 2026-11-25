import Foundation

public struct QuotaService: Sendable {
    public var launch: @Sendable () throws -> CodexLaunch
    public var extraEnvironment: [String: String]

    public init(launch: @escaping @Sendable () throws -> CodexLaunch, extraEnvironment: [String: String]) {
        self.launch = launch
        self.extraEnvironment = extraEnvironment
    }

    public static func production() -> QuotaService {
        QuotaService(
            launch: {
                switch CodexBinary.resolve() {
                case let .success(path):
                    return CodexLaunch(executable: path, arguments: ["app-server", "--listen", "stdio://"])
                case let .failure(error):
                    throw error
                }
            },
            extraEnvironment: [:]
        )
    }

    public func refresh(home: String) async throws -> UsageReading {
        try await withSession(home: home) { session in
            try await session.initialize()
            let account = try await session.request(method: "account/read", params: QuotaCalls.accountRead, timeout: QuotaTiming.rpcTimeout)
            guard UsageParsing.isSignedIn(account) else {
                return UsageReading(identity: nil, weekly: nil, shortWindow: nil, lifetimeTokens: nil, peakDailyTokens: nil, dailyBuckets: [])
            }
            return try await self.readQuota(session, account: account)
        }
    }

    public func signIn(home: String, open: @escaping @Sendable (URL) -> Void) async throws -> UsageReading {
        try await withSession(home: home) { session in
            try await session.initialize()
            let login = try await session.request(method: "account/login/start", params: QuotaCalls.loginParams, timeout: QuotaTiming.rpcTimeout)
            guard let url = UsageParsing.loginURL(login) else { throw QuotaFailure.signInLink }
            open(url)
            let started = Date()
            var ready = false
            var account = JSONValue.object([:])
            while Date().timeIntervalSince(started) < QuotaTiming.signInTimeout {
                if let note = await session.takeNotification(method: "account/login/completed"),
                   note.object?["params"]?.object?["success"]?.bool == false {
                    throw QuotaFailure.signInFailed
                }
                account = try await session.request(method: "account/read", params: QuotaCalls.accountRead, timeout: QuotaTiming.rpcTimeout)
                if UsageParsing.isSignedIn(account) {
                    ready = true
                    break
                }
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
            guard ready else { throw QuotaFailure.signInTimedOut }
            _ = try await session.request(method: "account/read", params: QuotaCalls.accountReadRefresh, timeout: QuotaTiming.rpcTimeout)
            return try await self.readQuota(session, account: account)
        }
    }

    public func signOut(home: String) async throws {
        try await withSession(home: home) { session in
            try await session.initialize()
            _ = try await session.request(method: "account/logout", params: nil, timeout: QuotaTiming.rpcTimeout)
        }
    }

    private func readQuota(_ session: CodexSession, account: JSONValue) async throws -> UsageReading {
        let limits = try await session.request(method: "account/rateLimits/read", params: QuotaCalls.empty, timeout: QuotaTiming.rpcTimeout)
        let usage = try? await session.request(method: "account/usage/read", params: QuotaCalls.empty, timeout: QuotaTiming.rpcTimeout)
        return UsageParsing.reading(account: account, limits: limits, usage: usage ?? .object([:]))
    }

    private func withSession<T: Sendable>(home: String, body: (CodexSession) async throws -> T) async throws -> T {
        let session = CodexSession()
        let launch = try launch()
        try await session.start(launch: launch, codexHome: home, extraEnvironment: extraEnvironment)
        do {
            let value = try await body(session)
            await session.stop()
            return value
        } catch {
            await session.stop()
            throw error
        }
    }
}
