import Cocoa

/// Each cat owns its artwork. No runtime recoloring or rectangular coat masks.
enum SpriteAtlas {
    private struct Frame: Decodable { var headX: Double; var footLift: Double; var width: Int; var height: Int }
    private static let names = ["orange", "black", "white", "silver", "cream", "tuxedo", "calico", "siamese"]
    private static let folder = Bundle.main.resourceURL?.appendingPathComponent("Cats")
    private static let metadata: [[Frame]] = {
        guard let url = folder?.appendingPathComponent("metadata.json"), let data = try? Data(contentsOf: url),
              let frames = try? JSONDecoder().decode([[Frame]].self, from: data) else { return [] }
        return frames
    }()
    private static var images: [Int: NSImage] = [:]
    static let frameCount = 62
    private static let resolvedCoats: [String] = {
        guard let url = folder?.appendingPathComponent("coats.json"), let data = try? Data(contentsOf: url),
              let names = try? JSONDecoder().decode([String].self, from: data), names.count == 8 else { return [] }
        return names
    }()
    static func artworkName(for coat: Int) -> String? { resolvedCoats.indices.contains(coat) ? resolvedCoats[coat] : nil }
    static var available: Bool {
        guard let folder, metadata.count == 8, resolvedCoats.count == 8 else { return false }
        return metadata.allSatisfy { $0.count == frameCount } && Set(resolvedCoats).allSatisfy { name in
            (0..<frameCount).allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(name)/\($0).png").path) }
        }
    }
    static let sourceScale: CGFloat = 24.0 / 180.0
    // V3: stand 0, idle 1–3, walk 4–11, run 12–19, turn 20–23,
    // stand→sit 24–26, sit→loaf 27–29, loaf→sleep 30–32, sleep 33–34,
    // groom 35–38, stretch 39–43, yawn 44–45, crouch 46–47,
    // creep 48–51, wiggle 52–53, pounce 54–57, bat 58–59, held 60–61.
    // Playback is wall-clock based, identical for every cat size. Travel speed stays in Habitat.swift.
    static let walkFPS = 10.0
    static let runFPS = 16.0
    static let standFrame = 0
    static func frameIndex(_ cat: Cat) -> Int {
        func loop(_ start: Int, _ count: Int, _ fps: Double) -> Int { start + Int(max(0, cat.elapsed) * fps) % count }
        func once(_ start: Int, _ count: Int, _ seconds: Double) -> Int { start + min(count-1, Int(max(0, cat.elapsed) / seconds * Double(count))) }
        let stopped = abs(cat.velocity) < 1.5 * cat.size.scale
        let idle = cat.elapsed > 1 && cat.turnCooldown <= 0 ? [1,2,3,2][Int(cat.elapsed * 1.5) % 4] : standFrame
        let walking = stopped ? idle : 4 + Int(max(0, cat.phase) * walkFPS) % 8
        let running = stopped ? standFrame : 12 + Int(max(0, cat.phase) * runFPS) % 8
        switch cat.action {
        case .sleeping: return loop(33, 2, 0.65)
        case .loafing: return 29
        case .sitting:
            let yawn = max(0, cat.elapsed - 4).truncatingRemainder(dividingBy: 12)
            return cat.elapsed > 4 && yawn < 0.6 ? 44 + min(1, Int(yawn * 4)) : 26
        case .held: return loop(60, 2, abs(cat.swing) > 5 ? 4 : 1.5)
        case .grooming: return loop(35, 4, 4)
        case .stretching: return once(39, 5, Colony.stretchTime)
        case .stalking:
            if cat.wiggle > 0 { return loop(52, 2, 5) }
            if stopped { return cat.elapsed < 0.2 ? 46 : 47 }
            return 48 + Int(max(0, cat.phase) * 5) % 4
        case .pouncing, .hopping: return once(54, 4, cat.action == .hopping ? Colony.hopTime : 0.45)
        case .walking: return walking
        case .running, .chasing, .goingHome: return abs(cat.velocity) > 18 * cat.size.scale ? running : walking
        case .playing:
            if abs(cat.velocity) > 20 * cat.size.scale { return running }
            if !stopped { return walking }
            if cat.pounceCooldown > 0.35 { return 58 + Int(cat.pounceCooldown * 5) % 2 }
            return 47
        }
    }
    /// Rest poses are connected by their actual in-between art; other changes retain Claude's short blend.
    static func transition(from: Int, to: Int) -> [Int] {
        func rank(_ f: Int) -> Int {
            switch f { case 26...28, 35...38, 44...45, 58...59: return 1
            case 29...31: return 2
            case 32...34: return 3
            default: return 0 }
        }
        let a = rank(from), b = rank(to)
        guard a != b else { return [] }
        let links = [[24,25,26], [27,28,29], [30,31,32]]
        if a < b { return (a..<b).flatMap { links[$0] } }
        return (b..<a).reversed().flatMap { Array(links[$0].reversed()) }
    }
    private static func image(_ frame: Int, coat: Int) -> NSImage? {
        let key = coat * frameCount + frame
        if let image = images[key] { return image }
        guard let name = artworkName(for: coat), let url = folder?.appendingPathComponent("\(name)/\(frame).png"),
              let image = NSImage(contentsOf: url) else { return nil }
        images[key] = image
        return image
    }
    /// Frames in the same cycle step through each other; anything else is a pose change worth blending.
    static func group(_ frame: Int) -> Int {
        switch frame {
        case 0...3: return 0
        case 4...11: return 4
        case 12...19: return 12
        case 20...23: return 20
        case 24...26, 44...45: return 26
        case 27...29: return 29
        case 30...34: return 33
        case 35...38: return 35
        case 39...43: return 39
        case 46...47: return 47
        case 48...51: return 48
        case 52...53: return 52
        case 54...57: return 54
        case 58...59: return 58
        default: return 60
        }
    }
    private static func offsetFor(_ cat: Cat, _ scale: CGFloat) -> CGFloat { cat.action == .held ? 0 : 9 * scale }
    /// Pixels per point of the menu bar display (the overlay lives on the primary screen).
    static var screenScale: CGFloat { NSScreen.screens.first?.backingScaleFactor ?? 2 }

    // MARK: Shrink once, reuse
    private static var small: [String: NSImage] = [:]
    /// The frame reduced to exactly `width` x `height` pixels, made once and kept.
    /// Halving step by step keeps thin outlines clean instead of losing them in one big jump.
    static func shrunk(_ index: Int, coat: Int, width: Int, height: Int) -> NSImage? {
        guard width > 0, height > 0 else { return nil }
        let key = "\(coat)-\(index)-\(width)x\(height)"
        if let cached = small[key] { return cached }
        guard let source = image(index, coat: coat)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var current = source
        while current.width / 2 >= width * 2 && current.height / 2 >= height * 2,
              let half = resample(current, width: current.width / 2, height: current.height / 2) { current = half }
        guard let final = resample(current, width: width, height: height) else { return nil }
        let result = NSImage(cgImage: final, size: NSSize(width: CGFloat(width) / screenScale, height: CGFloat(height) / screenScale))
        small[key] = result
        return result
    }
    private static func resample(_ image: CGImage, width: Int, height: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
    @discardableResult static func draw(_ cat: Cat, at point: NSPoint, scale: CGFloat, frame override: Int? = nil, direction: Double? = nil, alpha: CGFloat = 1) -> Bool {
        let index = override ?? frameIndex(cat)
        guard metadata.indices.contains(cat.coat), metadata[cat.coat].indices.contains(index), let image = image(index, coat: cat.coat) else { return false }
        let frame = metadata[cat.coat][index]
        var scale = scale * cat.size.scale
        var lift: CGFloat = 0
        if cat.action == .hopping {
            let q = CGFloat(min(1, cat.elapsed / Colony.hopTime))
            scale *= cat.hopIn ? 1 - 0.55 * q * q : 0.45 + 0.55 * q
            lift = sin(q * .pi) * 7
        } else if cat.action == .pouncing { lift = sin(min(1, cat.elapsed / 0.45) * .pi) * 4.5 }
        let factor = Self.sourceScale * scale
        let breathing: CGFloat = [.sleeping, .loafing].contains(cat.action) ? 1 + sin(cat.phase * 1.5) * 0.015 : 1
        // In the menu bar (scale 1) draw a copy shrunk once to the exact pixel size and snap it to the pixel grid;
        // previews at other scales and the brief tower hop draw the original.
        let pixels = scale == cat.size.scale && cat.action != .hopping ? screenScale : 0
        func snap(_ value: CGFloat) -> CGFloat { pixels > 0 ? (value * pixels).rounded() / pixels : value }
        var rect = NSRect(x: snap(offsetFor(cat, scale) - frame.headX * factor), y: snap(frame.footLift * factor),
                          width: Double(frame.width) * factor, height: Double(frame.height) * factor)
        var drawn = image
        if pixels > 0, let small = shrunk(index, coat: cat.coat, width: Int((rect.width * pixels).rounded()), height: Int((rect.height * pixels).rounded())) {
            drawn = small
            rect.size = NSSize(width: small.size.width, height: small.size.height)
        }
        rect.size.height *= breathing
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: snap(point.x), yBy: snap(point.y + lift * scale))
        transform.scaleX(by: direction ?? cat.direction, yBy: 1)
        if cat.action == .held {
            // Keep the head/grab point fixed; both new dangling drawings sway with the existing spring.
            transform.translateX(by: 0, yBy: 24 * scale)
            transform.rotate(byDegrees: cat.heldLean * cat.direction * 12)
            transform.translateX(by: 0, yBy: -24 * scale)
        }
        transform.concat()
        NSGraphicsContext.current?.imageInterpolation = .high
        drawn.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
        NSGraphicsContext.restoreGraphicsState()
        return true
    }
}
