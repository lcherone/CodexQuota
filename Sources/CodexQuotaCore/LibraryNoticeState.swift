public struct LibraryNoticeState: Equatable, Sendable {
    public static let saveFailureNotice = "The latest reading couldn't be saved on this Mac."

    public var durableNotice: String?
    public private(set) var hasSaveFailure: Bool

    public init(durableNotice: String? = nil, hasSaveFailure: Bool = false) {
        self.durableNotice = durableNotice
        self.hasSaveFailure = hasSaveFailure
    }

    public var displayedNotice: String? {
        hasSaveFailure ? Self.saveFailureNotice : durableNotice
    }

    public mutating func saveFailed() {
        hasSaveFailure = true
    }

    public mutating func saveSucceeded() {
        hasSaveFailure = false
    }
}
