public enum RefreshScheduler {
    public static let backgroundLimit = 2

    public static func run(
        accountIDs: [String],
        selectedID: String?,
        backgroundLimit: Int = RefreshScheduler.backgroundLimit,
        operation: @escaping @Sendable (String) async -> Void
    ) async {
        let orderedIDs = uniqueOrder(accountIDs: accountIDs, selectedID: selectedID)
        guard let firstID = orderedIDs.first else { return }

        if firstID == selectedID {
            await operation(firstID)
            guard !Task.isCancelled else { return }
        }

        let remainingIDs = firstID == selectedID ? orderedIDs.dropFirst() : orderedIDs[...]
        guard !remainingIDs.isEmpty else { return }

        let limit = max(1, backgroundLimit)
        await withTaskGroup(of: Void.self) { group in
            var iterator = remainingIDs.makeIterator()
            for _ in 0..<min(limit, remainingIDs.count) {
                guard let id = iterator.next() else { break }
                group.addTask { await operation(id) }
            }

            while await group.next() != nil {
                guard !Task.isCancelled, let id = iterator.next() else {
                    group.cancelAll()
                    continue
                }
                group.addTask { await operation(id) }
            }
        }
    }

    private static func uniqueOrder(accountIDs: [String], selectedID: String?) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        if let selectedID, accountIDs.contains(selectedID) {
            seen.insert(selectedID)
            result.append(selectedID)
        }
        for id in accountIDs where seen.insert(id).inserted {
            result.append(id)
        }
        return result
    }
}
