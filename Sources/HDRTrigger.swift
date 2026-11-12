// SPDX-License-Identifier: GPL-3.0-only
// Copyright (c) 2026 Othmane HOUSNI

import AppKit
import Metal
import QuartzCore

@MainActor
final class HDRTrigger {
    private let window: NSWindow
    private let space: PinnedSpace
    private let renderer: EDRRenderer
    private var rendering = false

    init?(screen: NSScreen) {
        guard let renderer = EDRRenderer() else { return nil }
        self.renderer = renderer
        let frame = CGRect(x: screen.frame.maxX - 1, y: screen.frame.minY, width: 1, height: 1)
        let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.canHide = false
        window.sharingType = .none
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()) + 1)
        window.collectionBehavior = [.stationary, .ignoresCycle, .fullScreenNone]
        window.setAccessibilityElement(false)

        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        renderer.layer.frame = view.bounds
        view.wantsLayer = true
        view.layer = renderer.layer
        window.contentView = view
        self.window = window
        guard let space = PinnedSpace(windows: [window]) else {
            window.close()
            return nil
        }
        self.space = space
        window.orderFrontRegardless()
    }

    func refresh() {
        if !window.isVisible { window.orderFrontRegardless() }
        guard !rendering else { return }
        rendering = true
        // nextDrawable can wait for WindowServer during a transition. Keep menus responsive.
        DispatchQueue.global(qos: .utility).async { [weak self, renderer] in
            renderer.present()
            DispatchQueue.main.async { [weak self] in self?.rendering = false }
        }
    }

    func close() {
        window.orderOut(nil)
        space.close()
        window.close()
    }
}

// Only one background submission accesses the configured layer at a time.
private final class EDRRenderer: @unchecked Sendable {
    let layer: CAMetalLayer
    private let queue: MTLCommandQueue

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.queue = queue
        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .rgba16Float
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        layer.wantsExtendedDynamicRangeContent = true
        layer.allowsNextDrawableTimeout = true
        layer.drawableSize = CGSize(width: 1, height: 1)
        self.layer = layer
    }

    func present() {
        guard let drawable = layer.nextDrawable(), let buffer = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 1.8, green: 1.8, blue: 1.8, alpha: 1)
        guard let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
