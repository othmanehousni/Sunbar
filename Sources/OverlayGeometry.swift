import CoreGraphics

enum OverlayGeometry {
    static func frames(for screen: CGRect, triggerOnly: Bool = false) -> [CGRect] {
        let trigger = CGRect(x: screen.maxX - 1, y: screen.minY, width: 1, height: 1)
        if triggerOnly { return [trigger] }
        // Two abutting windows avoid AppKit promoting a screen-sized window to full screen.
        let lowerHeight = (screen.height / 2).rounded(.down)
        return [
            CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: lowerHeight),
            CGRect(x: screen.minX, y: screen.minY + lowerHeight, width: screen.width, height: screen.height - lowerHeight),
            trigger,
        ]
    }
}
