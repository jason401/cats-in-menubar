import Cocoa

// Original cat-tower icon: a base, post, side shelf and a little house with a round door.
enum TowerIcon {
    /// Draws the tower in a 18 x 18 unit box. `fill` colors parts; nil cuts the door out (template use).
    private static func draw(wood: NSColor, house: NSColor, post: NSColor, door: NSColor?) {
        post.set()
        NSBezierPath(roundedRect: NSRect(x: 7.2, y: 2.5, width: 2.6, height: 9), xRadius: 0.6, yRadius: 0.6).fill()
        wood.set()
        NSBezierPath(roundedRect: NSRect(x: 1.5, y: 0.8, width: 15, height: 2.3), xRadius: 1.1, yRadius: 1.1).fill()
        NSBezierPath(roundedRect: NSRect(x: 9.2, y: 6.6, width: 7, height: 1.9), xRadius: 0.9, yRadius: 0.9).fill()
        house.set()
        let body = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 10.4, width: 12, height: 6.8), xRadius: 2, yRadius: 2)
        let hole = NSBezierPath(ovalIn: NSRect(x: 6.1, y: 11.5, width: 4.8, height: 4.4))
        if door == nil { body.append(hole.reversed) }
        body.fill()
        if let door { door.set(); hole.fill() }
    }
    /// Monochrome template image for the menu bar.
    static func menuBar() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            draw(wood: .black, house: .black, post: .black, door: nil); return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Cats in Menubar"
        return image
    }
    /// Colored app icon with a cat peeking out of the house.
    static func app(size: CGFloat) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let inset = size * 0.1
            let tile = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: size * 0.18, yRadius: size * 0.18)
            NSGradient(starting: NSColor(calibratedRed: 0.62, green: 0.82, blue: 0.95, alpha: 1),
                       ending: NSColor(calibratedRed: 0.86, green: 0.93, blue: 0.99, alpha: 1))!.draw(in: tile, angle: 90)
            NSGraphicsContext.saveGraphicsState()
            let unit = size * 0.62 / 18
            let transform = NSAffineTransform()
            transform.translateX(by: size * 0.19, yBy: size * 0.17); transform.scale(by: unit); transform.concat()
            let door = NSColor(calibratedRed: 0.33, green: 0.22, blue: 0.16, alpha: 1)
            draw(wood: NSColor(calibratedRed: 0.72, green: 0.50, blue: 0.32, alpha: 1),
                 house: NSColor(calibratedRed: 0.93, green: 0.55, blue: 0.40, alpha: 1),
                 post: NSColor(calibratedRed: 0.86, green: 0.79, blue: 0.64, alpha: 1), door: door)
            // Orange cat face in the doorway.
            let fur = NSColor(calibratedRed: 0.98, green: 0.70, blue: 0.40, alpha: 1)
            fur.set()
            NSBezierPath(ovalIn: NSRect(x: 6.9, y: 11.6, width: 3.2, height: 2.9)).fill()
            for x in [7.1, 8.9] as [CGFloat] {
                let ear = NSBezierPath(); ear.move(to: NSPoint(x: x, y: 13.9)); ear.line(to: NSPoint(x: x + 0.5, y: 15.2)); ear.line(to: NSPoint(x: x + 1, y: 13.9)); ear.close(); ear.fill()
            }
            NSColor(calibratedWhite: 0.12, alpha: 1).set()
            for x in [7.8, 9.0] as [CGFloat] { NSBezierPath(ovalIn: NSRect(x: x, y: 12.9, width: 0.45, height: 0.6)).fill() }
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
    }
    static func writeIconset(to directory: String) {
        _ = NSApplication.shared
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let pixels = points * scale
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                app(size: CGFloat(pixels)).draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
                NSGraphicsContext.restoreGraphicsState()
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(directory)/\(name)"))
            }
        }
    }
}
