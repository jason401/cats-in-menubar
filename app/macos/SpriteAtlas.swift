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
        case .playing: return abs(cat.velocity) > 20 * cat.size.scale ? running : (abs(cat.velocity) > 2 * cat.size.scale ? walking : 10)
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
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y + lift * scale)
        transform.scaleX(by: direction ?? cat.direction, yBy: 1)
        transform.concat()
        NSGraphicsContext.current?.imageInterpolation = .high
        let offset = cat.action == .held ? 0 : 9 * scale
        image.draw(in: NSRect(x: offset - frame.headX * factor, y: frame.footLift * factor,
                             width: Double(frame.width) * factor, height: Double(frame.height) * factor * breathing),
                   from: .zero, operation: .sourceOver, fraction: alpha)
        NSGraphicsContext.restoreGraphicsState()
        return true
    }
}
