import Foundation

public struct CodexLaunch: Equatable, Sendable {
    public var executable: String
    public var arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

public actor CodexSession {
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var stderr: FileHandle?
    private var buffer = Data()
    private var nextID = 0
    private var pending: [Int: Pending] = [:]
    private var notifications: [JSONValue] = []

    public func start(launch: CodexLaunch, codexHome: String, extraEnvironment: [String: String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launch.executable)
        process.arguments = launch.arguments
        try FileManager.default.createDirectory(atPath: codexHome, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: codexHome)
        process.currentDirectoryURL = URL(fileURLWithPath: codexHome, isDirectory: true)
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = codexHome
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        process.terminationHandler = { [weak self] _ in
            Task { await self?.failAll(.serverStopped) }
        }
        do {
            try process.run()
        } catch {
            throw QuotaFailure.codexMissing("The Codex CLI isn't on this Mac.")
        }
        self.process = process
        stdin = input.fileHandleForWriting
        stdout = output.fileHandleForReading
        stderr = errors.fileHandleForReading
        stderr?.readabilityHandler = { handle in
            _ = handle.availableData
        }
        stdout?.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.ingest(data) }
        }
    }

    private struct Pending {
        var method: String
        var continuation: CheckedContinuation<JSONValue, Error>
    }

    public func initialize() async throws {
        _ = try await request(method: "initialize", params: QuotaCalls.initializeParams, timeout: QuotaTiming.rpcTimeout)
        try write(ProtocolCodec.notificationLine(method: "initialized", params: .object([:])))
    }

    public func request(method: String, params: JSONValue?, timeout: TimeInterval) async throws -> JSONValue {
        try await withThrowingTaskGroup(of: JSONValue.self) { group in
            group.addTask {
                try await self.requestOnce(method: method, params: params)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw QuotaFailure.timedOut(method)
            }
            do {
                guard let value = try await group.next() else { throw QuotaFailure.timedOut(method) }
                group.cancelAll()
                while (try? await group.next()) != nil {}
                return value
            } catch {
                group.cancelAll()
                while (try? await group.next()) != nil {}
                throw error
            }
        }
    }

    public func takeNotification(method: String) -> JSONValue? {
        guard let index = notifications.firstIndex(where: { $0.object?["method"]?.string == method }) else {
            return nil
        }
        return notifications.remove(at: index)
    }

    public func stop() async {
        stdout?.readabilityHandler = nil
        stderr?.readabilityHandler = nil
        try? stdin?.close()
        stdin = nil
        let process = self.process
        if let process, process.isRunning {
            process.terminate()
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                process?.waitUntilExit()
                continuation.resume()
            }
        }
        self.process = nil
    }

    private func requestOnce(method: String, params: JSONValue?) async throws -> JSONValue {
        nextID += 1
        let id = nextID
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = Pending(method: method, continuation: continuation)
                do {
                    try write(ProtocolCodec.requestLine(id: id, method: method, params: params))
                } catch {
                    pending[id] = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: Int) {
        guard let pending = pending.removeValue(forKey: id) else { return }
        pending.continuation.resume(throwing: CancellationError())
    }

    private func ingest(_ data: Data) {
        if data.isEmpty {
            if process?.isRunning != true {
                failAll(.serverStopped)
            }
            return
        }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[..<newline]
            buffer.removeSubrange(...newline)
            guard let text = String(data: line, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                continue
            }
            handle(text)
        }
    }

    private func handle(_ line: String) {
        guard let message = try? JSONValue.parse(Data(line.utf8)), let object = message.object else {
            failAll(.unreadable)
            return
        }
        if let id = object["id"]?.int64 {
            if object["method"] != nil, object["result"] == nil, object["error"] == nil {
                try? write(ProtocolCodec.errorLine(id: Int(id), code: -32601, message: "Codex Quota doesn't accept this request."))
                return
            }
            guard let waiter = pending.removeValue(forKey: Int(id)) else { return }
            if object["error"] != nil {
                waiter.continuation.resume(throwing: QuotaFailure.refused(waiter.method))
                return
            }
            waiter.continuation.resume(returning: object["result"] ?? .object([:]))
            return
        }
        if object["method"] != nil {
            notifications.append(message)
        }
    }

    private func failAll(_ error: QuotaFailure) {
        let waiters = pending
        pending.removeAll()
        for waiter in waiters.values {
            waiter.continuation.resume(throwing: error)
        }
    }

    private func write(_ line: String) throws {
        guard let stdin else { throw QuotaFailure.notRunning }
        guard let data = (line + "\n").data(using: .utf8) else { throw QuotaFailure.unreadable }
        try stdin.write(contentsOf: data)
    }
}

public enum QuotaCalls {
    public static let initializeParams = JSONValue.object([
        "clientInfo": .object([
            "name": .string("codexquota"),
            "title": .string("Codex Quota"),
            "version": .string("0.1.0")
        ]),
        "capabilities": .object([
            "experimentalApi": .bool(true),
            "requestAttestation": .bool(false)
        ])
    ])

    public static let loginParams = JSONValue.object([
        "type": .string("chatgpt"),
        "codexStreamlinedLogin": .bool(true),
        "useHostedLoginSuccessPage": .bool(true),
        "appBrand": .string("codex")
    ])

    public static let accountRead = JSONValue.object(["refreshToken": .bool(false)])
    public static let accountReadRefresh = JSONValue.object(["refreshToken": .bool(true)])
    public static let empty = JSONValue.object([:])
}
