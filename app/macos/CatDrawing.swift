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
    private enum Piece { case fill(NSBezierPath), line(NSBezierPath, CGFloat, Bool) }
    enum Eyes { case open, wide, half, closed }
    struct Leg { var hip: NSPoint; var knee: NSPoint; var foot: NSPoint; var near: Bool }
    /// A tiny skeleton in points, facing right, feet on y = 0, inside a 38 pt wide envelope.
    struct Pose {
        var shoulder = NSPoint(x: 5, y: 9.4)
        var hip = NSPoint(x: -6.5, y: 9.6)
        var body: CGFloat = 8          // trunk thickness; 0 = drawn by `blobs` only
        var head = NSPoint(x: 10.4, y: 13.6)
        var legs: [Leg] = []
        var tail: [NSPoint] = []
        var blobs: [NSRect] = []
        var earBack: CGFloat = 0
        var eyes = Eyes.open
        var lift: CGFloat = 0
    }
    static let headRadius: CGFloat = 4.2

    private static func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: y) }
    private static func leg(_ hip: NSPoint, _ foot: NSPoint, bend: CGFloat, near: Bool) -> Leg {
        Leg(hip: hip, knee: p((hip.x + foot.x) / 2 + bend, (hip.y + foot.y) / 2 + 0.3), foot: foot, near: near)
    }
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

    // MARK: Poses
    static func pose(_ cat: Cat) -> Pose {
        let t = CGFloat(cat.phase), e = CGFloat(cat.elapsed), seed = CGFloat(cat.coat) * 1.7
        let speed = CGFloat(abs(cat.velocity))
        switch cat.action {
        case .sleeping: return sleep(t)
        case .loafing: return loaf(t, seed)
        case .sitting: return sit(t, seed, grooming: false)
        case .grooming: return sit(t, seed, grooming: true)
        case .stretching: return stretch(min(1, e / CGFloat(Colony.stretchTime)), t)
        case .stalking: return stalk(cat, t)
        case .pouncing:
            // Gathered take-off, then fully stretched out in the air, then landing.
            let q = min(1, e / 0.45)
            var pose = run(cycle: -.pi / 2 + min(1, q * 2.2) * .pi, strength: 1.15, t: t)
            pose.lift = sin(q * .pi) * 4.5; pose.eyes = .wide
            return pose
        case .held: return held(cat, t)
        case .hopping:
            // A gathered spring, stretched in the air, tucked on landing.
            let q = CGFloat(cat.hopJump ?? 1)
            var pose = run(cycle: -.pi / 2 + q * 2 * .pi * 0.75, strength: 1, t: t)
            pose.lift = sin(q * .pi) * 7
            return pose
        case .running, .chasing, .goingHome:
            return speed > 18 ? run(cycle: CGFloat(cat.gait) / 20 * 2 * .pi, strength: min(1, speed / 40), t: t) : walk(cat, t, seed)
        case .playing:
            if speed < 4 { var pose = stalk(cat, t); pose.eyes = .wide; return pose }
            return speed > 20 ? run(cycle: CGFloat(cat.gait) / 20 * 2 * .pi, strength: min(1, speed / 40), t: t) : walk(cat, t, seed)
        case .walking: return walk(cat, t, seed)
        }
    }
    private static func walk(_ cat: Cat, _ t: CGFloat, _ seed: CGFloat) -> Pose {
        let s = min(1, CGFloat(abs(cat.velocity)) / 12)
        let c = CGFloat(cat.gait) / 9 * 2 * .pi             // one stride every 9 pt, so feet never slide
        let bob = abs(sin(c)) * 0.5 * s
        var pose = Pose()
        pose.shoulder = p(5, 9.4 + bob); pose.hip = p(-6.5, 9.6 + bob)
        // Diagonal pairs move together, like a real walk.
        for (x, offset, near, front) in [(CGFloat(5.6), CGFloat.pi, false, true), (-5.8, 0, false, false), (4.4, 0, true, true), (-7.2, .pi, true, false)] {
            let swing = sin(c + offset) * 2.8 * s
            let lift = max(0, cos(c + offset)) * 1.5 * s
            let top = front ? pose.shoulder.y - 2 : pose.hip.y - 2
            pose.legs.append(leg(p(x, top), p(x + swing, 0.9 + lift), bend: front ? 0.5 : -1.3, near: near))
        }
        let wag = sin(t * 2.2 + seed) * 2
        pose.tail = [p(-9.5, 10.6 + bob), p(-14, 11.5), p(-12 + wag, 17), p(-15 + wag, 19)]
        pose.head = p(10.4, 13.6 + bob * 0.5)
        return pose
    }
    /// Gallop, keyed like a hand-drawn cycle: push off nose-up, stretch flat with the tail straight back,
    /// land nose-down, gather into a ball with the tail curled over the back. Big poses hold a moment,
    /// the tail lags behind the body, and the head stays steadier than the spine.
    private static func run(cycle raw: CGFloat, strength s: CGFloat, t: CGFloat) -> Pose {
        let c = raw + 0.35 * sin(2 * raw) * s                // linger at full stretch and full gather
        let e = sin(c) * s                                    // +1 stretched, -1 gathered
        let pitch = 0.24 * cos(c) * s                         // + nose up (push off), - nose down (landing)
        let center = p(0, 9.4 + 1.3 * abs(sin(c)) * s)
        let half = 5.6 + 2.6 * e
        func rotate(_ point: NSPoint, _ angle: CGFloat) -> NSPoint {
            let dx = point.x - center.x, dy = point.y - center.y
            return p(center.x + dx * cos(angle) - dy * sin(angle), center.y + dx * sin(angle) + dy * cos(angle))
        }
        var pose = Pose()
        pose.body = 8 - 0.5 * e                               // squash when gathered, slimmer when stretched
        pose.shoulder = rotate(p(half, center.y + 0.4), pitch)
        pose.hip = rotate(p(-half, center.y), pitch)
        for (offset, near) in [(CGFloat(0), false), (0.3, true)] {
            let a = c + offset
            let frontHip = rotate(p(half - 0.4, center.y - 2.2), pitch)
            let backHip = rotate(p(-half + 0.4, center.y - 2.2), pitch)
            let front = p(frontHip.x + 0.5 + 4.6 * sin(a) * s, 0.9 + max(0, cos(a)) * 2.6 * s)
            let back = p(backHip.x - 0.5 - 4.6 * sin(a) * s, 0.9 + max(0, -cos(a)) * 2.6 * s)
            pose.legs.append(leg(frontHip, front, bend: 0.9, near: near))
            pose.legs.append(leg(backHip, back, bend: -1.7, near: near))
        }
        // The head rides on the shoulder but only takes a little of the pitch.
        pose.head = rotate(p(half + 4.4, center.y + 3.6), pitch * 0.35)
        pose.earBack = 1.0 * s
        // Tail follow-through: shape is driven by a lagging phase, straight back when stretched, curled up when gathered.
        let u = (1 - sin(c - 0.9) * s) / 2
        let base = rotate(p(-half - 2.2, center.y + 0.6), pitch)
        let wave = sin(t * 3) * 0.4
        pose.tail = [base, p(base.x - 4, base.y + 1 + 3 * u), p(base.x - 8 + 3 * u, base.y + 1.2 + 7 * u + wave),
                     p(max(-18.5, base.x - 10.5 + 7 * u), min(21.5, base.y + 1.5 + 8.5 * u + wave))]
        return pose
    }
    /// Hunting crouch: belly low, elbows up, eyes wide; the rear wiggles before a pounce.
    private static func stalk(_ cat: Cat, _ t: CGFloat) -> Pose {
        let creep = min(1, CGFloat(abs(cat.velocity)) / 5)
        let c = CGFloat(cat.gait) / 6 * 2 * .pi
        let wiggle: CGFloat = cat.wiggle > 0 ? 1 : 0
        var pose = Pose()
        pose.body = 7.4
        pose.shoulder = p(4.5, 5.6)
        pose.hip = p(-7 + sin(t * 18) * 0.8 * wiggle, 6.4 + wiggle * 0.9)
        pose.head = p(10.2, 7.8)
        for (dx, near) in [(CGFloat(-1), false), (0, true)] {
            let step = sin(c + (near ? .pi : 0)) * 1.2 * creep
            pose.legs.append(Leg(hip: p(pose.shoulder.x + dx, pose.shoulder.y - 1), knee: p(pose.shoulder.x + dx + 2.6, 4.4), foot: p(pose.shoulder.x + dx + 3.2 + step, 0.9), near: near))
            pose.legs.append(Leg(hip: p(pose.hip.x + dx, pose.hip.y - 1), knee: p(pose.hip.x + dx + 2.4, 3.8), foot: p(pose.hip.x + dx - 0.6 - step, 0.9), near: near))
        }
        let twitch = sin(t * 7) * 1.2
        pose.tail = [p(pose.hip.x - 2.5, pose.hip.y), p(-13, 4.5), p(-15, 3 + twitch), p(-16.5, 3.8 + twitch)]
        pose.eyes = .wide
        return pose
    }
    /// Front stretch (chest down, rear up) then back stretch (one hind leg reaching back).
    private static func stretch(_ q: CGFloat, _ t: CGFloat) -> Pose {
        var pose = Pose()
        if q < 0.5 {
            let k = sin(q / 0.5 * .pi)
            pose.shoulder = p(6, 9.2 - 4.6 * k); pose.hip = p(-6, 9.4 + 1.6 * k)
            for (dx, near) in [(CGFloat(-0.8), false), (0.4, true)] {
                pose.legs.append(leg(p(pose.shoulder.x + dx, pose.shoulder.y - 1.5), p(pose.shoulder.x + dx + 1 + 6.5 * k, 0.9), bend: 0, near: near))
                pose.legs.append(leg(p(pose.hip.x + dx, pose.hip.y - 2), p(pose.hip.x + dx - 0.3, 0.9), bend: -1 * (1 - k), near: near))
            }
            pose.head = p(pose.shoulder.x + 4.6 + 1.2 * k, pose.shoulder.y + 3.6 - 1.2 * k)
            pose.eyes = k > 0.35 ? .closed : .open
            let y = pose.hip.y
            pose.tail = [p(pose.hip.x - 2.5, y + 1), p(-12, y + 4), p(-11, y + 8.5), p(-13, min(21, y + 10.5))]
        } else {
            let k = sin((q - 0.5) / 0.5 * .pi)
            pose.shoulder = p(6, 9.4 + 1.2 * k); pose.hip = p(-6, 9.4 - 1.6 * k)
            for (dx, near) in [(CGFloat(-0.8), false), (0.4, true)] {
                pose.legs.append(leg(p(pose.shoulder.x + dx, pose.shoulder.y - 2), p(pose.shoulder.x + dx + 0.4, 0.9), bend: 0.3, near: near))
                let reach = near ? k : 0
                pose.legs.append(leg(p(pose.hip.x + dx, pose.hip.y - 2), p(pose.hip.x + dx - 6 * reach, 0.9 + 1.5 * reach), bend: -1.2 * (1 - reach), near: near))
            }
            pose.head = p(pose.shoulder.x + 4.8, pose.shoulder.y + 4 + 0.6 * k)
            pose.eyes = k > 0.5 ? .closed : .open
            let y = pose.hip.y
            pose.tail = [p(pose.hip.x - 2.5, y + 0.5), p(-12, y), p(-14.5, y - 0.5), p(-16.5, y + 1)]
        }
        return pose
    }
    private static func sit(_ t: CGFloat, _ seed: CGFloat, grooming: Bool) -> Pose {
        var pose = Pose()
        pose.body = 8.4
        pose.shoulder = p(0.6, 10.8); pose.hip = p(-3.8, 4.6)
        pose.blobs = [NSRect(x: -10.1, y: 0, width: 11, height: 8.6)]  // haunch
        let s = pose.shoulder
        pose.legs.append(leg(p(s.x - 0.4, s.y - 2), p(s.x + 0.6, 0.9), bend: 0, near: false))
        if grooming {
            let lick = sin(t * 7) * 0.8
            pose.legs.append(Leg(hip: p(s.x + 1.2, s.y - 2), knee: p(s.x + 3.6, s.y - 0.6), foot: p(s.x + 4.6, s.y + 2.6 + lick), near: true))
            pose.head = p(3.8, 14.4 + lick * 0.3)
            pose.eyes = .closed
        } else {
            pose.legs.append(leg(p(s.x + 1.2, s.y - 2), p(s.x + 2.2, 0.9), bend: 0, near: true))
            pose.head = p(2.8 + sin(t * 0.4 + seed) * 0.6, 15.6)
        }
        // The tail wraps around the paws; its tip flicks now and then.
        let flick = pow(max(0, sin(t * 1.1 + seed)), 4) * 2.5
        pose.tail = [p(-8, 2.2), p(-12.5, 0.4), p(-3, -0.4), p(5, 1.2 + flick)]
        return pose
    }
    private static func loaf(_ t: CGFloat, _ seed: CGFloat) -> Pose {
        var pose = Pose()
        pose.body = 0
        pose.blobs = [NSRect(x: -12, y: 0.1, width: 21, height: 9.4)]
        pose.head = p(7.2, 9 + sin(t * 0.5 + seed) * 0.2)
        pose.tail = [p(-11, 2.6), p(-13.5, 0.6), p(-4, -0.2), p(4, 1.1)]
        pose.eyes = sin(t * 0.3 + seed) > 0.2 ? .half : .open
        return pose
    }
    private static func sleep(_ t: CGFloat) -> Pose {
        let breath = 1 + 0.05 * sin(t * 1.6)
        var pose = Pose()
        pose.body = 0
        pose.blobs = [NSRect(x: -11.5, y: 0.1, width: 20, height: 8.6 * breath)]
        pose.head = p(6.2, 5.4 * breath)
        pose.tail = [p(-10.5, 2.4), p(-14, 0), p(2, -0.4), p(9.5, 1.2)]
        pose.eyes = .closed; pose.earBack = 0.6
        return pose
    }
    /// Carried by the scruff: hanging body, dangling legs and tail that swing with the drag.
    private static func held(_ cat: Cat, _ t: CGFloat) -> Pose {
        // Like a pendulum: the scruff leads, the body and legs trail behind the drag.
        let sw = -max(-1, min(1, CGFloat(cat.swing) / 80)) * CGFloat(cat.direction)
        var pose = Pose()
        pose.shoulder = p(1 - sw * 1.5, 12.6); pose.hip = p(-1.2 + sw * 2, 5.8)
        let dangle = sin(t * 3) * 0.4
        for (dx, near) in [(CGFloat(-0.6), false), (0.8, true)] {
            pose.legs.append(leg(p(pose.shoulder.x + dx, pose.shoulder.y - 2), p(pose.shoulder.x + dx + sw * 2 + dangle, pose.shoulder.y - 7.5), bend: 0, near: near))
            pose.legs.append(leg(p(pose.hip.x + dx, pose.hip.y - 1.5), p(pose.hip.x + dx + sw * 2.5 - dangle, 0.8), bend: 0, near: near))
        }
        pose.head = p(2.4 - sw, 16.6)
        pose.tail = [p(pose.hip.x - 1.5, pose.hip.y - 1), p(-4 + sw * 4, 1.2), p(-6 + sw * 6, 0.6), p(-8 + sw * 8 + sin(t * 2) * 1.5, 2)]
        pose.eyes = .wide
        return pose
    }

    // MARK: Rendering
    /// Faces right, centered on `point`; `cat.direction` mirrors it.
    static func cat(_ cat: Cat, at point: NSPoint, scale: CGFloat = 1) {
        guard cat.visible && cat.hiddenFor <= 0 else { return }
        if SpriteAtlas.draw(cat, at: point, scale: scale) { return }
        var scale = scale * cat.size.scale
        if cat.action == .hopping {
            // Shrinks into the tower icon, grows back on the way out.
            let q = CGFloat(min(1, cat.elapsed / Colony.hopTime))
            scale *= cat.hopIn ? 1 - 0.55 * q * q : 0.45 + 0.55 * q
        }
        let pose = pose(cat)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y + pose.lift * scale)
        transform.scaleX(by: scale * cat.direction, yBy: scale)
        transform.concat()
        NSGraphicsContext.current?.shouldAntialias = true
        let coat = coats[cat.coat % coats.count]
        let r = headRadius, head = pose.head
        // Occasional ear flick, staggered per cat.
        let flick: CGFloat = sin(CGFloat(cat.phase) * 0.9 + CGFloat(cat.coat) * 1.7) > 0.985 ? 1.2 : 0
        let earY = head.y + r * 0.5
        let ears = [(head.x - r * 0.55 - pose.earBack, -0.4 - flick - pose.earBack * 1.5), (head.x + r * 0.6 - pose.earBack, 0.4 - pose.earBack * 1.5)]
        var pieces: [Piece] = []
        for leg in pose.legs where !leg.near { pieces.append(.line(stroke([leg.hip, leg.knee, leg.foot]), 2.2, true)) }
        if !pose.tail.isEmpty { pieces.append(.line(stroke(pose.tail), 2.1, false)) }
        for blob in pose.blobs { pieces.append(.fill(NSBezierPath(ovalIn: blob))) }
        if pose.body > 0 {
            pieces.append(.line(stroke([pose.hip, pose.shoulder]), pose.body, false))
            pieces.append(.fill(oval(pose.shoulder.x, pose.shoulder.y, pose.body + 0.8, pose.body + 0.8)))
        }
        for leg in pose.legs where leg.near { pieces.append(.line(stroke([leg.hip, leg.knee, leg.foot]), 2.4, false)) }
        for (x, tilt) in ears {
            let ear = NSBezierPath()
            ear.move(to: p(x - 2, earY)); ear.line(to: p(x + tilt, earY + 3.9)); ear.line(to: p(x + 2, earY)); ear.close()
            ear.lineJoinStyle = .round
            pieces.append(.fill(ear))
        }
        pieces.append(.fill(oval(head.x, head.y, r * 2.15, r * 1.95)))
        // One soft outline around the whole silhouette, then fur on top, so joints stay seamless.
        let shade = coat.fur.blended(withFraction: 0.18, of: .black) ?? coat.fur
        for outline in [true, false] {
            for piece in pieces {
                switch piece {
                case .fill(let path):
                    (outline ? coat.line : coat.fur).set(); path.fill()
                    if outline { path.lineWidth = 1.6; path.stroke() }
                case .line(let path, let width, let far):
                    (outline ? coat.line : (far ? shade : coat.fur)).set()
                    path.lineWidth = width + (outline ? 1.6 : 0); path.stroke()
                }
            }
        }
        coat.ear.set()
        for (x, tilt) in ears {
            let inner = NSBezierPath()
            inner.move(to: p(x - 1, earY + 0.3)); inner.line(to: p(x + tilt * 0.8, earY + 2.8)); inner.line(to: p(x + 1, earY + 0.3)); inner.close()
            inner.fill()
        }
        let blink = sin(CGFloat(cat.phase) * 0.7 + CGFloat(cat.coat) * 3.4) > 0.992
        let eyeY = head.y + 0.3
        for eyeX in [head.x + 0.1, head.x + 2.5] {
            switch blink ? .closed : pose.eyes {
            case .closed:
                (cat.coat == 1 ? coat.line : coat.eye).set()
                let lid = stroke([p(eyeX - 0.9, eyeY + 0.3), p(eyeX - 0.4, eyeY - 0.4), p(eyeX + 0.4, eyeY - 0.4), p(eyeX + 0.9, eyeY + 0.3)])
                lid.lineWidth = 0.75; lid.stroke()
            case .half: coat.eye.set(); oval(eyeX, eyeY - 0.3, 1.4, 0.9).fill()
            case .wide: coat.eye.set(); oval(eyeX, eyeY, 1.7, 2.4).fill()
            case .open: coat.eye.set(); oval(eyeX, eyeY, 1.3, 1.9).fill()
            }
        }
        NSColor(calibratedRed: 1.0, green: 0.55, blue: 0.62, alpha: 1).set()
        oval(head.x + 1.4, head.y - 1.4, 1.2, 0.8).fill()
        if cat.action == .sleeping {
            // A small "z" drifts up and fades.
            let cycle = (CGFloat(cat.phase) / 2.6).truncatingRemainder(dividingBy: 1)
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 5 + cycle * 2, weight: .bold),
                                                       .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(1 - cycle)]
            ("z" as NSString).draw(at: p(8 + cycle * 3, 9 + cycle * 7), withAttributes: attrs)
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    static func thumbnail(_ appearance: CatAppearance) -> NSImage {
        NSImage(size: NSSize(width: 46, height: 30), flipped: false) { _ in
            var cat = Cat(x: 0, destination: 0, action: .walking, phase: 1.3, visible: true, coat: appearance.coat, size: appearance.size)
            cat.velocity = 15; cat.gait = 3
            Self.cat(cat, at: NSPoint(x: 23, y: 2))
            return true
        }
    }
    /// Same order as `Toy.colors`.
    static let toyColors: [NSColor] = [.systemMint, .systemRed, .systemBlue, .systemYellow, .systemPink, .systemPurple, .systemOrange]
    static func toy(_ toy: Toy, baseline: CGFloat) {
        switch toy.kind {
        case .ball: ball(toy, baseline: baseline)
        case .laser: laser(toy, baseline: baseline)
        }
    }
    /// A red pointer dot on the floor of the menu bar, with a soft glow.
    static func laser(_ toy: Toy, baseline: CGFloat) {
        let fade = CGFloat(min(1, toy.lifetime / 0.25))
        let center = NSPoint(x: toy.x, y: baseline + 3)
        func dot(_ radius: CGFloat, _ color: NSColor) {
            color.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
        }
        // Small and see-through, so it reads as light on the bar rather than a solid ball.
        dot(3.5, NSColor.systemRed.withAlphaComponent(0.12 * fade))
        dot(2, NSColor.systemRed.withAlphaComponent(0.3 * fade))
        dot(1.1, NSColor(calibratedRed: 1, green: 0.2, blue: 0.15, alpha: 0.75 * fade))
        dot(0.45, NSColor.white.withAlphaComponent(0.5 * fade))
    }
    static func ball(_ toy: Toy, baseline: CGFloat) {
        let rect = NSRect(x: toy.x - 3, y: baseline + 1, width: 6, height: 6)
        NSColor(calibratedWhite: 0.1, alpha: 1).setFill(); NSBezierPath(ovalIn: rect.insetBy(dx: -1, dy: -1)).fill()
        toyColors[max(0, min(toyColors.count - 1, toy.color))].setFill(); NSBezierPath(ovalIn: rect).fill()
        NSColor.white.withAlphaComponent(0.8).setFill()
        NSRect(x: toy.x + sin(toy.phase) * 1.5 - 0.5, y: baseline + 2, width: 1, height: 3).fill()
    }
}

final class HabitatView: NSView {
    let colony: Colony
    var showLanes = false
    private(set) var dragging: Int?
    private(set) var lasering = false
    private var grabOffset = 0.0
    private var lastDrag = 0.0
    init(colony: Colony, frame: NSRect) { self.colony = colony; super.init(frame: frame) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Last pose shown per cat slot, so a pose change (sit, stand, turn) blends instead of jumping.
    private struct Shown {
        var frame: Int
        var direction: Double
        var fromFrame = -1
        var fromDirection = 1.0
        var since = 0.0
        var sequence: [Int] = []
        var sequenceDirection = 1.0
    }
    private var shown: [Int: Shown] = [:]
    static let blendTime = 0.15
    /// True while some cat is blending between poses; the app keeps full frame rate for it.
    var blending: Bool {
        let now = ProcessInfo.processInfo.systemUptime
        return shown.values.contains { $0.fromFrame >= 0 && now - $0.since < max(HabitatView.blendTime, Double($0.sequence.count) * 0.09) }
    }
    private func drawCat(_ i: Int, baseline: CGFloat) {
        let cat = colony.cats[i]
        let point = NSPoint(x: cat.x, y: baseline)
        guard cat.visible && cat.hiddenFor <= 0 else { shown[i] = nil; return }
        let frame = SpriteAtlas.frameIndex(cat)
        let now = ProcessInfo.processInfo.systemUptime
        var memory = shown[i] ?? Shown(frame: frame, direction: cat.direction)
        let inTransition = now - memory.since < Double(memory.sequence.count) * 0.09
            && cat.action != .held && cat.action != .hopping
        let turn = SpriteAtlas.cells(.turn, coat: cat.coat)
        if (!inTransition && SpriteAtlas.group(frame, coat: cat.coat) != SpriteAtlas.group(memory.frame, coat: cat.coat)) || cat.direction != memory.direction {
            let old = memory
            memory = Shown(frame: frame, direction: cat.direction, fromFrame: old.frame, fromDirection: old.direction, since: now)
            memory.sequence = cat.direction != old.direction ? turn : SpriteAtlas.transition(from: old.frame, to: frame, coat: cat.coat)
            memory.sequenceDirection = cat.direction != old.direction ? old.direction : cat.direction
        } else { memory.frame = frame }
        shown[i] = memory
        let step = Int(max(0, now - memory.since) / 0.09)
        if memory.sequence.indices.contains(step), cat.action != .held && cat.action != .hopping {
            var at = point
            if memory.sequence == turn {
                // Turn in place: slide the body's middle from where it was to where the turned pose will be,
                // so the last turn frame meets the mirrored pose without a sideways jump.
                let start = SpriteAtlas.bodyCenter(memory.fromFrame, cat: cat, direction: memory.fromDirection)
                let end = SpriteAtlas.bodyCenter(frame, cat: cat, direction: cat.direction)
                let target = start + (end - start) * CGFloat(step + 1) / CGFloat(turn.count)
                at.x += target - SpriteAtlas.bodyCenter(memory.sequence[step], cat: cat, direction: memory.sequenceDirection)
            }
            SpriteAtlas.draw(cat, at: at, scale: 1, frame: memory.sequence[step], direction: memory.sequenceDirection)
            return
        }
        CatDrawing.cat(cat, at: point)
        // The old pose fades out on top of the new one, so there is never a see-through moment.
        let q = (now - memory.since) / HabitatView.blendTime
        if memory.sequence.isEmpty && memory.fromFrame >= 0 && q < 1 && cat.action != .hopping {
            SpriteAtlas.draw(cat, at: point, scale: 1, frame: memory.fromFrame, direction: memory.fromDirection, alpha: CGFloat(1 - q))
        }
    }
    private var drawnRects: [NSRect] = []
    /// Redraws only the strips around cats and the ball (where they were and where they are now),
    /// instead of the whole menu bar width every frame.
    func invalidateCats() {
        guard !showLanes else { needsDisplay = true; return }
        var rects = colony.cats.filter(\.visible).map { NSRect(x: $0.x - 30, y: 0, width: 60, height: bounds.height) }
        if let toy = colony.ball { rects.append(NSRect(x: toy.x - 8, y: 0, width: 16, height: bounds.height)) }
        for rect in drawnRects + rects { setNeedsDisplay(rect) }
        drawnRects = rects
    }
    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let canDrag = UserDefaults.standard.bool(forKey: Pref.allowDrag)
        guard canDrag, let i = colony.catIndex(at: point.x) else {
            // Empty menu bar space: press and hold for the laser pointer.
            if UserDefaults.standard.bool(forKey: Pref.laser) && colony.laser(at: point.x) { lasering = true; needsDisplay = true }
            return
        }
        dragging = i; grabOffset = 0; lastDrag = event.timestamp
        colony.grab(i); colony.drag(i, to: point.x, dt: 1.0 / 30); NSCursor.closedHand.set(); needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        if lasering { colony.laser(at: convert(event.locationInWindow, from: nil).x); return }
        guard let i = dragging else { return }
        let point = convert(event.locationInWindow, from: nil)
        colony.drag(i, to: point.x + grabOffset, dt: event.timestamp - lastDrag)
        lastDrag = event.timestamp; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { endDrag(); NSCursor.openHand.set() }
    func endDrag() {
        if let i = dragging { colony.release(i); needsDisplay = true }
        if lasering { colony.laserOff(); lasering = false }
        dragging = nil
    }
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !colony.lanes.isEmpty else { return }
        NSGraphicsContext.saveGraphicsState()
        let clip = NSBezierPath()
        for lane in colony.lanes { clip.appendRect(NSRect(x: lane.lower, y: 0, width: lane.width, height: bounds.height)) }
        // Between the two sides of the notch only the notch itself, which hides a crossing cat.
        if let ends = colony.tunnelEnds() { clip.appendRect(NSRect(x: ends.left.upper, y: 0, width: ends.right.lower - ends.left.upper, height: bounds.height)) }
        clip.addClip()
        if showLanes {
            NSColor.systemMint.withAlphaComponent(0.15).setFill()
            for lane in colony.lanes { NSRect(x: lane.lower, y: 0, width: lane.width, height: bounds.height).fill() }
        }
        let baseline = max(0, floor((bounds.height - 22) / 2))
        for (i, cat) in colony.cats.enumerated() where !cat.escaping && cat.action != .hopping { drawCat(i, baseline: baseline) }
        if let toy = colony.ball { CatDrawing.toy(toy, baseline: baseline) }
        NSGraphicsContext.restoreGraphicsState()
        // Cats leaving covered space or hopping into the tower may briefly pass over icons.
        for (i, cat) in colony.cats.enumerated() where cat.visible && (cat.escaping || cat.action == .hopping) {
            drawCat(i, baseline: baseline)
        }
    }
}
