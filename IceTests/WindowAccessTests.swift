import Cocoa
import XCTest

@MainActor
final class WindowAccessTests: XCTestCase {
    func testInvalidAppKitWindowNumbersDoNotTrap() {
        let window = NumberedWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        for number in [-1, Int.min, 0, Int(CGWindowID.max) + 1, Int.max] {
            window.number = number
            XCTAssertNil(window.cgWindowID, "Unexpected ID for \(number)")
        }
    }

    func testValidAppKitWindowNumbersArePreserved() {
        let window = NumberedWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        for number in [1, 34, Int(CGWindowID.max)] {
            window.number = number
            XCTAssertEqual(window.cgWindowID, CGWindowID(exactly: number))
        }
    }

    func testNonItemWindowDoesNotInvalidateMenuBarCache() async throws {
        // The crash session's WindowServer window 34 has layer 24, not status layer 25.
        let cache = RefreshCache<[CGWindowID], [CGWindowID]>(emptyValue: [])
        let windows = [CGWindowID(34): 24, CGWindowID(35): 25]
        try await cache.refresh(key: [34, 35]) {
            try WindowListReader.read(windowIDs: [34, 35]) { id in
                windows[id].map { (id, $0) }
            } makeItem: { id, layer in
                layer == 25 ? id : nil
            }
        }
        XCTAssertEqual(cache.value, [35])
        XCTAssertEqual(cache.key, [34, 35])
    }

    func testUnreadableWindowStillRetriesWithSameIDs() async throws {
        let cache = RefreshCache<[CGWindowID], [CGWindowID]>(emptyValue: [])
        do {
            try await cache.refresh(key: [35]) {
                try WindowListReader.read(windowIDs: [35], readWindow: { _ -> CGWindowID? in nil }, makeItem: { $0 })
            }
            XCTFail("An unavailable window must invalidate the snapshot")
        } catch WindowListReader.ReadError.unavailableWindow(let id) {
            XCTAssertEqual(id, 35)
        }
        XCTAssertNil(cache.key)
        try await cache.refresh(key: [35]) {
            try WindowListReader.read(windowIDs: [35], readWindow: { $0 }, makeItem: { $0 })
        }
        XCTAssertEqual(cache.key, [35])
        XCTAssertEqual(cache.value, [35])
    }
}

@MainActor
private final class NumberedWindow: NSWindow {
    var number = -1
    override var windowNumber: Int { number }
}
