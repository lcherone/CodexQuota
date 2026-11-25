import Foundation

public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public var object: [String: JSONValue]? {
        if case let .object(value) = self { return value }
        return nil
    }

    public var array: [JSONValue]? {
        if case let .array(value) = self { return value }
        return nil
    }

    public var string: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public var bool: Bool? {
        if case let .bool(value) = self { return value }
        return nil
    }

    public var double: Double? {
        switch self {
        case let .number(value) where value.isFinite:
            return value
        case let .string(value):
            return Double(value)
        default:
            return nil
        }
    }

    public var int64: Int64? {
        switch self {
        case let .number(value) where value.isFinite && value <= Double(Int64.max) && value >= Double(Int64.min):
            return Int64(value.rounded(.towardZero))
        case let .string(value):
            return Int64(value)
        default:
            return nil
        }
    }

    public var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        let raw = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try from(raw)
    }

    public func data() throws -> Data {
        let raw = foundation()
        guard JSONSerialization.isValidJSONObject(raw) else { throw QuotaFailure.unreadable }
        return try JSONSerialization.data(withJSONObject: raw, options: [.sortedKeys])
    }

    public func foundation() -> Any {
        switch self {
        case .null:
            return NSNull()
        case let .bool(value):
            return value
        case let .number(value):
            if value.rounded() == value, value <= Double(Int.max), value >= Double(Int.min) {
                return Int(value)
            }
            return value
        case let .string(value):
            return value
        case let .array(values):
            return values.map { $0.foundation() }
        case let .object(values):
            return values.mapValues { $0.foundation() }
        }
    }

    private static func from(_ raw: Any) throws -> JSONValue {
        if raw is NSNull { return .null }
        if let value = raw as? String { return .string(value) }
        if let value = raw as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                return .bool(value.boolValue)
            }
            return .number(value.doubleValue)
        }
        if let value = raw as? [Any] {
            return .array(try value.map(from))
        }
        if let value = raw as? [String: Any] {
            var object: [String: JSONValue] = [:]
            for (key, item) in value {
                object[key] = try from(item)
            }
            return .object(object)
        }
        if let value = raw as? NSDictionary {
            var object: [String: JSONValue] = [:]
            for (key, item) in value {
                guard let key = key as? String else { continue }
                object[key] = try from(item)
            }
            return .object(object)
        }
        if let value = raw as? NSArray {
            return .array(try value.map(from))
        }
        throw QuotaFailure.unreadable
    }
}

public enum ProtocolCodec {
    public static func requestLine(id: Int, method: String, params: JSONValue?) throws -> String {
        var payload: [String: JSONValue] = [
            "id": .number(Double(id)),
            "method": .string(method)
        ]
        if let params {
            payload["params"] = params
        }
        return try line(.object(payload))
    }

    public static func notificationLine(method: String, params: JSONValue) throws -> String {
        try line(.object([
            "method": .string(method),
            "params": params
        ]))
    }

    public static func errorLine(id: Int, code: Int, message: String) throws -> String {
        try line(.object([
            "id": .number(Double(id)),
            "error": .object([
                "code": .number(Double(code)),
                "message": .string(message)
            ])
        ]))
    }

    private static func line(_ value: JSONValue) throws -> String {
        let data = try value.data()
        guard let text = String(data: data, encoding: .utf8), !text.contains("\n") else {
            throw QuotaFailure.unreadable
        }
        return text
    }
}
