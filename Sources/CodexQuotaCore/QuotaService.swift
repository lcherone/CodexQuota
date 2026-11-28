import Foundation

public extension UsageReading {
    init(
        identity: AccountIdentity?, weekly: WeeklyWindow?, shortWindow: ShortWindow? = nil,
        lifetimeTokens: Int64? = nil, peakDailyTokens: Int64? = nil,
        dailyBuckets: [DailyBucket] = [], optionalUsageSucceeded: Bool = true
    ) {
        self.identity = identity
        self.weekly = weekly
        self.shortWindow = shortWindow
        self.lifetimeTokens = lifetimeTokens
        self.peakDailyTokens = peakDailyTokens
        self.dailyBuckets = dailyBuckets
        self.optionalUsageSucceeded = optionalUsageSucceeded
    }
}

public extension AccountIdentity {
    static func workflow(type: String, email: String?, planType: String?) -> AccountIdentity {
        AccountIdentity(type: type, email: email, planType: planType)
    }
}

public extension WeeklyWindow {
    static func workflow(limitId: String?, limitName: String, planType: String?, usedPercent: Double, windowDurationMins: Double, resetsAt: Date?, reached: String?) -> WeeklyWindow {
        WeeklyWindow(limitId: limitId, limitName: limitName, planType: planType, usedPercent: usedPercent, windowDurationMins: windowDurationMins, resetsAt: resetsAt, reached: reached)
    }
}

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

    public func workspaceMessages(home: String) async throws -> WorkspaceMessagesDetails {
        try await withSession(home: home) { session in
            try await session.initialize()
            let value = try await session.request(method: "account/workspaceMessages/read", params: nil, timeout: QuotaTiming.rpcTimeout)
            return try AccountDetailsParsing.workspace(value)
        }
    }

    public func conversations(home: String, cursor: String?, archived: Bool) async throws -> ConversationPage {
        try await withSession(home: home) { session in
            try await session.initialize()
            var params: [String: JSONValue] = [
                "limit": .number(20), "sortKey": .string("updated_at"), "sortDirection": .string("desc"),
                "archived": .bool(archived), "modelProviders": .array([]), "useStateDbOnly": .bool(true)
            ]
            if let cursor { params["cursor"] = .string(cursor) }
            let value = try await session.request(method: "thread/list", params: .object(params), timeout: QuotaTiming.rpcTimeout)
            return try AccountDetailsParsing.conversations(value)
        }
    }

    public func conversationUsage(home: String, threadID: String) async throws -> ConversationUsageDetails? {
        guard UUID(uuidString: threadID) != nil else { throw QuotaFailure.refused("an invalid conversation ID") }
        return try await withSession(home: home) { session in
            try await session.initialize()
            let value = try await session.request(method: "account/usage/read", params: .object(["threadId": .string(threadID)]), timeout: QuotaTiming.rpcTimeout)
            return try AccountDetailsParsing.conversationUsage(value, threadID: threadID)
        }
    }

    private func readQuota(_ session: CodexSession, account: JSONValue) async throws -> UsageReading {
        let limits = try await session.request(method: "account/rateLimits/read", params: QuotaCalls.empty, timeout: QuotaTiming.rpcTimeout)
        do {
            let usage = try await session.request(method: "account/usage/read", params: QuotaCalls.empty, timeout: QuotaTiming.rpcTimeout)
            return UsageParsing.reading(account: account, limits: limits, usage: usage)
        } catch {
            var reading = UsageParsing.reading(account: account, limits: limits, usage: .object([:]))
            reading.optionalUsageSucceeded = false
            return reading
        }
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
