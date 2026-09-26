//
//  NSWindow+WindowID.swift
//  Ice
//

import Cocoa

extension NSWindow {
    /// A WindowServer identifier, if AppKit currently has a valid window number.
    var cgWindowID: CGWindowID? {
        let number = windowNumber
        guard number > 0 else { return nil }
        return CGWindowID(exactly: number)
    }
}
