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
    static var available: Bool {
        metadata.count == 8 && metadata.allSatisfy { $0.count == 21 } && names.allSatisfy { name in
            (0..<21).allSatisfy { index in FileManager.default.fileExists(atPath: folder!.appendingPathComponent("\(name)/\(index).png").path) }
        }
    }
    static let sourceScale: CGFloat = 24.0 / 180.0
    /// Temporary standing pose until a dedicated one is drawn: the walk frame with the legs gathered under the body.
    static let standFrame = 4
    static func frameIndex(_ cat: Cat) -> Int {
        // A moving cat that has stopped (turning, arriving, waiting at the tower) stands, not frozen mid-stride.
        let stopped = abs(cat.velocity) < 1.5 * cat.size.scale
        let walking = stopped ? standFrame : Int(max(0, cat.gait) / (9 * cat.size.scale) * 6) % 6
        let running = 6 + Int(max(0, cat.gait) / (20 * cat.size.scale) * 6) % 6
        switch cat.action {
        case .sleeping: return 14
        case .loafing: return 13
        case .sitting: return 12
        case .held:
            let localLean = cat.heldLean * cat.direction
            return localLean < -0.2 ? 19 : (localLean > 0.2 ? 20 : 18)
        case .grooming: return 16
        case .stretching: return 15
        case .stalking: return 10
        case .pouncing, .hopping: return 6 + min(5, Int(cat.elapsed / 0.55 * 6))
        case .walking: return walking
        case .running, .chasing, .goingHome: return abs(cat.velocity) > 18 * cat.size.scale ? running : walking
        case .playing:
            if abs(cat.velocity) > 20 * cat.size.scale { return running }
            if abs(cat.velocity) > 2 * cat.size.scale { return walking }
            // After a bat it sits and watches; it crouches only just before the next one.
            return cat.pounceCooldown > 0.35 ? 12 : 10
        }
    }
    private static func image(_ frame: Int, coat: Int) -> NSImage? {
        let key = coat * 21 + frame
        if let image = images[key] { return image }
        guard names.indices.contains(coat), let url = folder?.appendingPathComponent("\(names[coat])/\(frame).png"),
              let image = NSImage(contentsOf: url) else { return nil }
        images[key] = image
        return image
    }
    /// Frames in the same cycle step through each other; anything else is a pose change worth blending.
    static func group(_ frame: Int) -> Int {
        switch frame {
        case 0..<6: -1
        case 6..<12: -2
        case 18...20: -3
        default: frame
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
        let factor = cat.action == .held ? 24 * scale / Double(frame.height) : Self.sourceScale * scale
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
        transform.concat()
        NSGraphicsContext.current?.imageInterpolation = .high
        drawn.draw(in: rect, from: .zero, operation: .sourceOver, fraction: alpha)
        NSGraphicsContext.restoreGraphicsState()
        return true
    }
}
