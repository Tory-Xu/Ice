//
//  PresentationRequest.swift
//  Ice
//

import Foundation

/// Owns preparation synchronously so a second click can cancel before the task starts.
@MainActor
final class PresentationRequest<Section> {
    private(set) var id: UUID?
    private(set) var pendingSection: Section?
    private(set) var currentSection: Section?
    private var task: Task<Void, Never>?

    func isCurrent(_ id: UUID) -> Bool {
        self.id == id && !Task.isCancelled
    }

    func start(
        id: UUID,
        section: Section,
        prepare: @escaping (UUID) async -> Bool,
        present: @escaping () -> Bool,
        didPresent: @escaping () -> Void
    ) {
        cancel()
        self.id = id
        pendingSection = section
        task = Task { [weak self] in
            guard let self, isCurrent(id) else { return }
            guard await prepare(id), isCurrent(id) else {
                if self.id == id { cancel() }
                return
            }
            let isVisible = present()
            guard isCurrent(id) else { return }
            guard isVisible else {
                cancel()
                return
            }
            pendingSection = nil
            currentSection = section
            task = nil
            didPresent()
        }
    }

    func cancel() {
        id = nil
        task?.cancel()
        task = nil
        pendingSection = nil
        currentSection = nil
    }
}
