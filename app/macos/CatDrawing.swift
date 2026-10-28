import Cocoa

// Original, code-drawn vector cats: simple rounded silhouettes, no downloaded assets.
enum CatDrawing {
    struct Coat { let fur: NSColor; let line: NSColor; let eye: NSColor; let ear: NSColor }
    static let coats: [Coat] = [
        Coat(fur: NSColor(calibratedRed: 0.98, green: 0.70, blue: 0.40, alpha: 1), line: NSColor(calibratedRed: 0.45, green: 0.25, blue: 0.10, alpha: 1),
             eye: NSColor(calibratedWhite: 0.12, alpha: 1), ear: NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.62, alpha: 1)),
        Coat(fur: NSColor(calibratedRed: 0.20, green: 0.20, blue: 0.24, alpha: 1), line: NSColor(calibratedWhite: 0.62, alpha: 1),
             eye: NSColor(calibratedRed: 0.95, green: 0.85, blue: 0.35, alpha: 1), ear: NSColor(calibratedRed: 0.55, green: 0.38, blue: 0.42, alpha: 1)),
        Coat(fur: NSColor(calibratedRed: 0.97, green: 0.95, blue: 0.91, alpha: 1), line: NSColor(calibratedWhite: 0.38, alpha: 1),
             eye: NSColor(calibratedWhite: 0.12, alpha: 1), ear: NSColor(calibratedRed: 1.0, green: 0.68, blue: 0.70, alpha: 1)),
    ]
    private enum Piece { case fill(NSBezierPath), line(NSBezierPath, CGFloat) }
    private static func oval(_ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
    }
    private static func stroke(_ points: [NSPoint]) -> NSBezierPath {
        let path = NSBezierPath(); path.move(to: points[0])
        if points.count == 4 { path.curve(to: points[3], controlPoint1: points[1], controlPoint2: points[2]) }
        else { points.dropFirst().forEach { path.line(to: $0) } }
        path.lineCapStyle = .round; path.lineJoinStyle = .round
        return path
    }
    private static func ear(_ x: CGFloat, _ y: CGFloat, tilt: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x - 2.6, y: y)); path.line(to: NSPoint(x: x + tilt, y: y + 5)); path.line(to: NSPoint(x: x + 2.6, y: y)); path.close()
        path.lineJoinStyle = .round
        return path
    }
    /// Faces right in a 34 x 26 pt envelope centered on `point`; `cat.direction` mirrors it.
    static func cat(_ cat: Cat, at point: NSPoint, scale: CGFloat = 1) {
        guard cat.visible && cat.hiddenFor <= 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y)
        transform.scaleX(by: scale * cat.direction, yBy: scale)
        transform.concat()
        NSGraphicsContext.current?.shouldAntialias = true
        let coat = coats[cat.coat % coats.count]
        let t = CGFloat(cat.phase)
        let speed = abs(cat.velocity)
        var pieces: [Piece] = []
        var head = NSPoint.zero, headRadius: CGFloat = 5.6, eyesClosed = false, earTilt: CGFloat = 0
        // Occasional ear flick and blink, staggered per cat.
        let seed = CGFloat(cat.coat) * 1.7
        if sin(t * 0.9 + seed) > 0.985 { earTilt = 1.2 }
        let blink = sin(t * 0.7 + seed * 2) > 0.992
        switch cat.action {
        case .sleeping:
            let breath = 1 + 0.05 * sin(t * 1.6)
            pieces.append(.line(stroke([NSPoint(x: -11, y: 3), NSPoint(x: -14, y: -0.5), NSPoint(x: 2, y: -0.5), NSPoint(x: 9, y: 1.4)]), 2.4))
            pieces.append(.fill(oval(-1.5, 4.6 * breath, 22, 9.4 * breath)))
            head = NSPoint(x: 7.5, y: 6.2 * breath); headRadius = 5
            eyesClosed = true
        case .sitting, .grooming:
            let grooming = cat.action == .grooming
            let sway = sin(t * 1.3 + seed) * 1.6
            pieces.append(.line(stroke([NSPoint(x: -7, y: 1.5), NSPoint(x: -13, y: 0.5), NSPoint(x: -12, y: 6 + sway), NSPoint(x: -14.5, y: 9 + sway)]), 2.4))
            pieces.append(.fill(oval(-4.5, 4.8, 12, 9.6)))      // haunch
            pieces.append(.fill(oval(-1, 8, 10.5, 14)))         // upright body
            pieces.append(.line(stroke([NSPoint(x: 2.8, y: 7), NSPoint(x: 3.2, y: 1.2)]), 2.6))
            if grooming {
                let lick = sin(t * 7) * 0.8
                pieces.append(.line(stroke([NSPoint(x: 1.5, y: 8), NSPoint(x: 6.5, y: 12.5 + lick)]), 2.6))
                head = NSPoint(x: 4.8, y: 15 + lick * 0.4); eyesClosed = true
            } else {
                pieces.append(.line(stroke([NSPoint(x: 0.4, y: 7), NSPoint(x: 0.6, y: 1.2)]), 2.6))
                head = NSPoint(x: 3.4, y: 16.4 + sin(t * 0.5 + seed) * 0.3)
            }
        case .walking, .chasing, .playing:
            let crouch: CGFloat = cat.action == .playing && speed < 4 ? 2 : 0
            let cycle = CGFloat(cat.gait) / 10 * 2 * .pi       // one stride every 10 pt walked
            let stride = min(1, CGFloat(speed) / 12)
            let bob = abs(sin(cycle)) * 0.8 * stride
            let hip: CGFloat = 7 - crouch
            for (x, offset, near) in [(CGFloat(-6.5), CGFloat.pi, false), (CGFloat(5), 0, false), (-8.5, 0, true), (3, .pi, true)] {
                let swing = sin(cycle + offset) * 2.6 * stride
                let lift = max(0, cos(cycle + offset)) * 1.4 * stride
                let leg = stroke([NSPoint(x: x, y: hip + bob), NSPoint(x: x + swing, y: 1.2 + lift)])
                pieces.append(.line(leg, near ? 2.8 : 2.4))
            }
            let wag = sin(t * (cat.action == .playing ? 9 : 2.2) + seed) * 2
            pieces.append(.line(stroke([NSPoint(x: -10, y: 10 + bob - crouch), NSPoint(x: -15, y: 12), NSPoint(x: -13 + wag, y: 17), NSPoint(x: -15.5 + wag, y: 19 - crouch)]), 2.4))
            pieces.append(.fill(NSBezierPath(roundedRect: NSRect(x: -11.5, y: 5 + bob - crouch, width: 20, height: 9.5), xRadius: 4.8, yRadius: 4.8)))
            head = NSPoint(x: 9, y: 14.2 + bob * 0.6 - crouch * 1.5)
        }
        let headPath = oval(head.x, head.y, headRadius * 2.1, headRadius * 1.9)
        let leftEar = ear(head.x - headRadius * 0.55, head.y + headRadius * 0.55, tilt: -0.4 - earTilt)
        let rightEar = ear(head.x + headRadius * 0.6, head.y + headRadius * 0.55, tilt: 0.4)
        pieces += [.fill(leftEar), .fill(rightEar), .fill(headPath)]
        // One soft outline around the whole silhouette, then the fur on top, so joints stay seamless.
        for (color, extra) in [(coat.line, CGFloat(1.6)), (coat.fur, 0)] {
            color.set()
            for piece in pieces {
                switch piece {
                case .fill(let path):
                    path.fill()
                    if extra > 0 { path.lineWidth = extra; path.stroke() }
                case .line(let path, let width):
                    path.lineWidth = width + extra; path.stroke()
                }
            }
        }
        coat.ear.set()
        for (x, sign) in [(head.x - headRadius * 0.55, CGFloat(-1)), (head.x + headRadius * 0.6, 1)] {
            let inner = NSBezierPath()
            let tip = NSPoint(x: x + sign * 0.3 + (sign < 0 ? -earTilt : 0), y: head.y + headRadius * 0.55 + 3.2)
            inner.move(to: NSPoint(x: x - 1.2, y: head.y + headRadius * 0.6)); inner.line(to: tip); inner.line(to: NSPoint(x: x + 1.2, y: head.y + headRadius * 0.6)); inner.close()
            inner.fill()
        }
        let eyeY = head.y + 0.4
        for eyeX in [head.x - 0.4, head.x + 2.8] {
            if eyesClosed || blink {
                coat.eye == coats[1].eye ? coat.line.set() : coat.eye.set()
                let lid = stroke([NSPoint(x: eyeX - 1, y: eyeY + 0.3), NSPoint(x: eyeX - 0.4, y: eyeY - 0.5), NSPoint(x: eyeX + 0.4, y: eyeY - 0.5), NSPoint(x: eyeX + 1, y: eyeY + 0.3)])
                lid.lineWidth = 0.8; lid.stroke()
            } else {
                coat.eye.set(); oval(eyeX, eyeY, 1.6, 2.2).fill()
            }
        }
        NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.62, alpha: 1).set()
        oval(head.x + 1.3, head.y - 1.6, 1.5, 1.0).fill()
        if cat.action == .sleeping {
            // A small "z" drifts up and fades.
            let cycle = (t / 2.6).truncatingRemainder(dividingBy: 1)
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 5 + cycle * 2, weight: .bold),
                                                       .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(1 - cycle)]
            ("z" as NSString).draw(at: NSPoint(x: 9 + cycle * 3, y: 10 + cycle * 7), withAttributes: attrs)
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
