import XCTest

@MainActor
final class RecoveryTests: XCTestCase {
    enum Failure: Error { case read, ordering }

    func testTransientReadFailureRetriesUnchangedWindowIDs() async throws {
        try await assertRetry(after: .read)
    }

    func testOrderingFailureRetriesUnchangedWindowIDs() async throws {
        try await assertRetry(after: .ordering)
    }

    private func assertRetry(after failure: Failure) async throws {
        let cache = RefreshCache<[Int], [String]>(emptyValue: [])
        try await cache.refresh(key: [1]) { ["previous"] }
        do {
            try await cache.refresh(key: [1, 2]) { throw failure }
            XCTFail("Expected failure")
        } catch is Failure { }
        XCTAssertNil(cache.key)
        XCTAssertEqual(cache.value, [])
        try await cache.refresh(key: [1, 2]) { ["recovered"] }
        XCTAssertEqual(cache.value, ["recovered"])
        try await cache.refresh(key: [1, 2]) {
            XCTFail("Successful refresh should be reused")
            return []
        }
    }

    func testSuccessfulEmptyCacheIsValid() async throws {
        let cache = RefreshCache<[Int], [String]>(emptyValue: [])
        try await cache.refresh(key: []) { [] }
        XCTAssertEqual(cache.key, [])
        try await cache.refresh(key: []) {
            XCTFail("An empty successful cache is not a failure")
            return ["unexpected"]
        }
        XCTAssertEqual(cache.value, [])
    }

    func testCloseDuringEachPreparationStageDoesNotPresent() async {
        for stage in 0...1 {
            let request = PresentationRequest<String>()
            let gate = Gate()
            var presented = false
            var completed = false
            request.start(id: UUID(), section: "hidden") { id in
                if stage == 0 { await gate.wait() }
                guard request.isCurrent(id) else { return false }
                if stage == 1 { await gate.wait() }
                return request.isCurrent(id)
            } present: {
                presented = true
                return true
            } didPresent: { completed = true }
            await gate.waitUntilEntered()
            XCTAssertNil(request.currentSection)
            XCTAssertEqual(request.pendingSection, "hidden")
            request.cancel()
            await gate.resumeAndDrain()
            XCTAssertFalse(presented)
            XCTAssertFalse(completed)
            XCTAssertNil(request.currentSection)
            XCTAssertNil(request.pendingSection)
        }
    }

    func testImmediateSecondClickCancelsBeforeTaskRuns() async {
        let request = PresentationRequest<String>()
        request.start(id: UUID(), section: "hidden") { _ in true } present: {
            XCTFail("Cancelled request must not show a window")
            return true
        } didPresent: { XCTFail("Must not start rehide checks") }
        XCTAssertEqual(request.pendingSection, "hidden")
        request.cancel()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertNil(request.currentSection)
    }

    func testNewRequestWinsEvenWhenOldPreparationIgnoresCancellation() async {
        let request = PresentationRequest<String>()
        let gate = Gate()
        let shown = expectation(description: "new request shown")
        request.start(id: UUID(), section: "old") { _ in
            await gate.wait()
            return true
        } present: {
            XCTFail("Old request must not reopen the panel")
            return true
        } didPresent: { XCTFail("Old request must not change controls") }
        await gate.waitUntilEntered()
        request.start(id: UUID(), section: "new") { _ in true } present: { true } didPresent: { shown.fulfill() }
        await fulfillment(of: [shown], timeout: 2)
        await gate.resumeAndDrain()
        XCTAssertEqual(request.currentSection, "new")
        XCTAssertNil(request.pendingSection)
    }

    func testCloseDuringWindowPresentationDoesNotRestoreState() async {
        let request = PresentationRequest<String>()
        let attempted = expectation(description: "window attempted")
        request.start(id: UUID(), section: "hidden") { _ in true } present: {
            request.cancel()
            attempted.fulfill()
            return true
        } didPresent: { XCTFail("Close during orderFront must win") }
        await fulfillment(of: [attempted], timeout: 2)
        XCTAssertNil(request.currentSection)
        XCTAssertNil(request.pendingSection)
    }

    func testOlderCacheFailureCannotEraseNewerSuccess() async throws {
        let cache = RefreshCache<[Int], [String]>(emptyValue: [])
        let gate = Gate()
        let oldRefresh = Task {
            try await cache.refresh(key: [1]) {
                await gate.wait()
                throw Failure.read
            }
        }
        await gate.waitUntilEntered()
        try await cache.refresh(key: [2]) { ["new"] }
        await gate.resumeAndDrain()
        do {
            try await oldRefresh.value
            XCTFail("Expected old read failure")
        } catch is Failure { }
        XCTAssertEqual(cache.key, [2])
        XCTAssertEqual(cache.value, ["new"])
    }

    func testFailedWindowPresentationDoesNotComplete() async {
        let request = PresentationRequest<String>()
        let attempted = expectation(description: "window attempted")
        request.start(id: UUID(), section: "hidden") { _ in true } present: {
            attempted.fulfill()
            return false
        } didPresent: { XCTFail("Invisible panel must not start rehide checks") }
        await fulfillment(of: [attempted], timeout: 2)
        XCTAssertNil(request.currentSection)
        XCTAssertNil(request.pendingSection)
    }
}

@MainActor
private final class Gate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilEntered() async {
        while continuation == nil { await Task.yield() }
    }

    func resumeAndDrain() async {
        continuation?.resume()
        continuation = nil
        for _ in 0..<10 { await Task.yield() }
    }
}
