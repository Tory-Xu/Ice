//
//  RefreshCache.swift
//  Ice
//

import Foundation

/// Commits a cache key only after a complete refresh. A successful empty value is valid.
@MainActor
final class RefreshCache<Key: Equatable, Value> {
    private(set) var key: Key?
    private(set) var value: Value
    private var generation = UUID()
    private let emptyValue: Value

    init(emptyValue: Value) {
        self.emptyValue = emptyValue
        self.value = emptyValue
    }

    func refresh(key: Key, load: () async throws -> Value) async throws {
        guard self.key != key else { return }
        let generation = UUID()
        self.generation = generation
        self.key = nil
        do {
            let value = try await load()
            try Task.checkCancellation()
            guard self.generation == generation else { return }
            self.value = value
            self.key = key
        } catch {
            if self.generation == generation {
                self.value = emptyValue
                self.key = nil
            }
            throw error
        }
    }
}
