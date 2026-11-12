// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Othmane HOUSNI

import AppKit

@MainActor
final class PinnedSpace {
    private typealias Connection = @convention(c) () -> UInt32
    private typealias Create = @convention(c) (UInt32, Int32, CFDictionary?) -> UInt64
    private typealias SetLevel = @convention(c) (UInt32, UInt64, Int32) -> Void
    private typealias GetLevel = @convention(c) (UInt32, UInt64) -> Int32
    private typealias SetVisibility = @convention(c) (UInt32, CFArray) -> Void
    private typealias ChangeMembership = @convention(c) (UInt32, CFArray, CFArray) -> Void
    private typealias CopyMembership = @convention(c) (UInt32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias Destroy = @convention(c) (UInt32, UInt64) -> Void

    private var cleanup: (() -> Void)?

    init?(windows overlayWindows: [NSWindow]) {
        guard !overlayWindows.isEmpty, overlayWindows.allSatisfy({ $0.windowNumber > 0 }),
              let connection = Self.symbol("CGSMainConnectionID", as: Connection.self)?(), connection != 0,
              let create = Self.symbol("CGSSpaceCreate", as: Create.self),
              let setLevel = Self.symbol("CGSSpaceSetAbsoluteLevel", as: SetLevel.self),
              let getLevel = Self.symbol("CGSSpaceGetAbsoluteLevel", as: GetLevel.self),
              let show = Self.symbol("CGSShowSpaces", as: SetVisibility.self),
              let add = Self.symbol("CGSAddWindowsToSpaces", as: ChangeMembership.self),
              let remove = Self.symbol("CGSRemoveWindowsFromSpaces", as: ChangeMembership.self),
              let copy = Self.symbol("CGSCopySpacesForWindows", as: CopyMembership.self),
              let destroy = Self.symbol("CGSSpaceDestroy", as: Destroy.self) else { return nil }

        let id = create(connection, 1, nil)
        guard id != 0 else { return nil }
        let spaces = [NSNumber(value: id)] as CFArray
        let windows = overlayWindows.map { NSNumber(value: $0.windowNumber) } as CFArray

        // An absolute layer puts the surfaces above the animated desktop groups.
        setLevel(connection, id, 200)
        // The setter has no return status. Read the level back before using the space.
        guard getLevel(connection, id) == 200 else {
            destroy(connection, id)
            return nil
        }
        show(connection, spaces)
        add(connection, windows, spaces)
        // Include private spaces in the query so only this space may own the window.
        let ownsEveryWindow = overlayWindows.allSatisfy { window in
            let windowID = [NSNumber(value: window.windowNumber)] as CFArray
            let membership = copy(connection, 0xF, windowID)?.takeRetainedValue() as? [NSNumber]
            return membership == [NSNumber(value: id)]
        }
        guard ownsEveryWindow else {
            remove(connection, windows, spaces)
            destroy(connection, id)
            return nil
        }
        cleanup = {
            remove(connection, windows, spaces)
            destroy(connection, id)
        }
    }

    func close() {
        cleanup?()
        cleanup = nil
    }

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let address = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else { return nil }
        return unsafeBitCast(address, to: type)
    }
}
