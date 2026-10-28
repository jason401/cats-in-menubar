import Cocoa

// Original, code-drawn pixel cats: no downloaded assets or runtime dependencies.
enum CatDrawing {
    static let coats: [NSColor] = [NSColor(calibratedRed: 0.94, green: 0.64, blue: 0.30, alpha: 1),
                                    NSColor(calibratedRed: 0.68, green: 0.75, blue: 0.84, alpha: 1),
                                    NSColor(calibratedRed: 0.94, green: 0.88, blue: 0.74, alpha: 1)]
    static func cat(_ cat: Cat, at point: NSPoint, scale: CGFloat = 1) {
        guard cat.visible && cat.hiddenFor <= 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y)
        transform.scaleX(by: scale * cat.direction, yBy: scale)
        transform.concat()
        NSGraphicsContext.current?.shouldAntialias = false
        let ink = NSColor(calibratedWhite: 0.12, alpha: 1)
        let coat = coats[cat.coat % coats.count]
        func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor) {
            color.setFill(); NSRect(x: x, y: y, width: w, height: h).fill()
        }
        func block(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ color: NSColor) {
            rect(x-1, y-1, w+2, h+2, ink); rect(x, y, w, h, color)
        }
        if cat.action == .sleeping {
            let breath: CGFloat = sin(cat.phase * 1.4) > 0 ? 1 : 0
            block(-10, 1, 19, 7 + breath, coat)
            block(4, 3, 8, 6, coat)
            block(4, 8, 3, 3, coat); block(9, 8, 3, 2, coat)
            rect(6, 5, 4, 1, ink)
            block(-12, 2, 9, 3, coat)
            if Int(cat.phase / 2) % 3 != 0 {
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 6, weight: .bold), .foregroundColor: NSColor.secondaryLabelColor]
                ("z" as NSString).draw(at: NSPoint(x: 8, y: 12), withAttributes: attrs)
            }
        } else {
            let moving = [.walking, .playing, .chasing].contains(cat.action)
            let stride: CGFloat = moving ? (Int(cat.phase * (cat.action == .chasing ? 12 : 7)) % 2 == 0 ? 2 : -2) : 0
            let bob: CGFloat = moving && stride > 0 ? 1 : 0
            block(-9, 5 + bob, 16, 7, coat)
            // Tail remains inside the 34-point collision envelope.
            block(-13, 8 + bob, 4, 3, coat)
            block(-15, 10 + bob + (Int(cat.phase * 2) % 2 == 0 ? 1 : 0), 3, 4, coat)
            block(-8 + stride, 1, 4, 5 + bob, coat)
            block(3 - stride, 1, 4, 5 + bob, coat)
            block(3, 9 + bob, 10, 7, coat)
            block(3, 15 + bob, 3, 4, coat); block(10, 15 + bob, 3, 4, coat)
            rect(4, 16 + bob, 1, 2, .systemPink); rect(11, 16 + bob, 1, 2, .systemPink)
            let blink = Int(cat.phase * 10) % 47 == 0
            rect(6, 12 + bob, 1, blink ? 1 : 2, ink)
            rect(11, 12 + bob, 1, blink ? 1 : 2, ink)
            rect(9, 10 + bob, 2, 1, .systemPink)
            if cat.coat == 0 { rect(-5, 10 + bob, 2, 2, ink.withAlphaComponent(0.4)); rect(0, 10 + bob, 2, 2, ink.withAlphaComponent(0.4)) }
            if cat.action == .grooming {
                block(8, 5 + CGFloat(Int(cat.phase * 4) % 2) * 3, 3, 5, coat)
                rect(10, 9, 2, 1, .systemPink)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    static func ball(_ toy: ToyBall, baseline: CGFloat) {
        let rect = NSRect(x: toy.x - 3, y: baseline + 1, width: 6, height: 6)
        NSColor(calibratedWhite: 0.1, alpha: 1).setFill(); NSBezierPath(ovalIn: rect.insetBy(dx: -1, dy: -1)).fill()
        NSColor.systemMint.setFill(); NSBezierPath(ovalIn: rect).fill()
        NSColor.white.withAlphaComponent(0.8).setFill()
        NSRect(x: toy.x + sin(toy.phase) * 1.5 - 0.5, y: baseline + 2, width: 1, height: 3).fill()
    }
}

final class HabitatView: NSView {
    let colony: Colony
    var showLanes = false
    init(colony: Colony, frame: NSRect) { self.colony = colony; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !colony.lanes.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath()
        for lane in colony.lanes { clip.appendRect(NSRect(x: lane.lower, y: 0, width: lane.width, height: bounds.height)) }
        clip.addClip()
        if showLanes {
            NSColor.systemMint.withAlphaComponent(0.15).setFill()
            for lane in colony.lanes { NSRect(x: lane.lower, y: 0, width: lane.width, height: bounds.height).fill() }
        }
        let baseline = max(0, floor((bounds.height - 22) / 2))
        for cat in colony.cats { CatDrawing.cat(cat, at: NSPoint(x: cat.x, y: baseline)) }
        if let toy = colony.ball { CatDrawing.ball(toy, baseline: baseline) }
        NSGraphicsContext.restoreGraphicsState()
    }
}
