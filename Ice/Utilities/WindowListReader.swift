//
//  WindowListReader.swift
//  Ice
//

import CoreGraphics

/// Distinguishes a failed window read from a readable window that is not an item.
enum WindowListReader {
    enum ReadError: Error {
        case unavailableWindow(CGWindowID)
    }

    static func read<Window, Item>(
        windowIDs: [CGWindowID],
        readWindow: (CGWindowID) -> Window?,
        makeItem: (Window) -> Item?
    ) throws -> [Item] {
        try windowIDs.compactMap { id in
            guard let window = readWindow(id) else {
                throw ReadError.unavailableWindow(id)
            }
            return makeItem(window)
        }
    }
}
