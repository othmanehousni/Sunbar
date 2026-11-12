import AppKit
import Metal
import QuartzCore

enum BoostMethod: String, CaseIterable, Identifiable {
    case native = "Native HDR"
    case direct = "Direct Backlight"
    case systemLayer = "System Layer"
    case allSpaces = "All Spaces"

    var id: Self { self }
}

@MainActor
final class XDROverlay {
    let windows: [NSWindow]
    let placement: BoostMethod
    private let space: PinnedSpace?
    private let renderer: EDRRenderer
    private let triggerOnly: Bool
    private var rendering = false
    private(set) var framesSubmitted = 0
    private(set) var presentedFactor = 1.0

    init?(screen: NSScreen, placement requested: BoostMethod, triggerOnly: Bool = false) {
        let frames = OverlayGeometry.frames(for: screen.frame, triggerOnly: triggerOnly)
        guard let renderer = EDRRenderer(surfaceCount: frames.count) else { return nil }
        self.renderer = renderer
        self.triggerOnly = triggerOnly
        windows = zip(frames, renderer.layers).map { frame, layer in
            Self.makeWindow(frame: frame, layer: layer)
        }

        space = requested == .systemLayer ? PinnedSpace(windows: windows) : nil
        placement = space == nil ? .allSpaces : .systemLayer
        for window in windows {
            window.collectionBehavior = [.stationary, .ignoresCycle]
            if placement == .allSpaces {
                window.collectionBehavior.formUnion([.canJoinAllSpaces, .fullScreenAuxiliary, .canJoinAllApplications])
            }
            window.orderFrontRegardless()
        }
    }

    static func makeWindow(frame: CGRect, layer: CAMetalLayer, sharing: NSWindow.SharingType = .none) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.canHide = false
        window.sharingType = sharing
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        window.setAccessibilityElement(false)

        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        layer.frame = view.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.wantsLayer = true
        view.layer = layer
        window.contentView = view
        window.setFrame(frame, display: false)
        return window
    }

    func refresh(on screen: NSScreen, factor: Double) {
        for (window, frame) in zip(windows, OverlayGeometry.frames(for: screen.frame, triggerOnly: triggerOnly)) {
            if window.frame != frame {
                window.setFrame(frame, display: false)
                window.contentView?.layer?.frame = CGRect(origin: .zero, size: frame.size)
            }
            if !window.isVisible { window.orderFrontRegardless() }
        }
        guard !rendering else { return }
        rendering = true

        // nextDrawable can wait for WindowServer during a transition. Keep menus responsive.
        DispatchQueue.global(qos: .userInitiated).async { [weak self, renderer] in
            let submitted = renderer.present(factor: factor)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                rendering = false
                if submitted {
                    framesSubmitted += 1
                    presentedFactor = factor
                }
            }
        }
    }

    func close() {
        for window in windows { window.orderOut(nil) }
        space?.close()
        for window in windows { window.close() }
    }
}

// The layers are configured before use. Only one render accesses their drawable queues at a time.
private final class EDRRenderer: @unchecked Sendable {
    let layers: [CAMetalLayer]
    private let queue: MTLCommandQueue

    init?(surfaceCount: Int) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        layers = (0..<surfaceCount).map { index in
            let layer = CAMetalLayer()
            layer.device = device
            layer.pixelFormat = .rgba16Float
            layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
            layer.wantsExtendedDynamicRangeContent = true
            layer.allowsNextDrawableTimeout = true
            let trigger = index == surfaceCount - 1
            layer.drawableSize = trigger ? CGSize(width: 1, height: 1) : CGSize(width: 2, height: 2)
            if !trigger {
                layer.isOpaque = false
                layer.compositingFilter = "multiply"
            }
            return layer
        }
    }

    func present(factor: Double) -> Bool {
        let drawables = layers.compactMap { $0.nextDrawable() }
        guard drawables.count == layers.count, let buffer = queue.makeCommandBuffer() else { return false }
        for (index, drawable) in drawables.enumerated() {
            // The unfiltered corner pixel keeps the HDR grant active during the ramp.
            let value = index == drawables.count - 1 ? 1.8 : factor
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = drawable.texture
            pass.colorAttachments[0].loadAction = .clear
            pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColor(red: value, green: value, blue: value, alpha: 1)
            guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return false }
            encoder.endEncoding()
        }
        for drawable in drawables { buffer.present(drawable) }
        buffer.commit()
        return true
    }
}

@MainActor
final class PinnedSpace {
    private typealias Connection = @convention(c) () -> UInt32
    private typealias Create = @convention(c) (UInt32, Int32, CFDictionary?) -> UInt64
    private typealias SetLevel = @convention(c) (UInt32, UInt64, Int32) -> Int32
    private typealias SetVisibility = @convention(c) (UInt32, CFArray) -> Int32
    private typealias ChangeMembership = @convention(c) (UInt32, CFArray, CFArray) -> Void
    private typealias CopyMembership = @convention(c) (UInt32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias Destroy = @convention(c) (UInt32, UInt64) -> Void

    private var cleanup: (() -> Void)?

    init?(windows overlayWindows: [NSWindow]) {
        guard overlayWindows.allSatisfy({ $0.windowNumber > 0 }),
              let connection = Self.symbol("CGSMainConnectionID", as: Connection.self)?(), connection != 0,
              let create = Self.symbol("CGSSpaceCreate", as: Create.self),
              let setLevel = Self.symbol("CGSSpaceSetAbsoluteLevel", as: SetLevel.self),
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
        guard setLevel(connection, id, 200) == 0 else {
            destroy(connection, id)
            return nil
        }
        _ = show(connection, spaces)
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
