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
    static func frameIndex(_ cat: Cat) -> Int {
        let walking = Int(max(0, cat.gait) / (9 * cat.size.scale) * 6) % 6
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
    @discardableResult static func draw(_ cat: Cat, at point: NSPoint, scale: CGFloat) -> Bool {
        let index = frameIndex(cat)
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
        transform.scaleX(by: cat.direction, yBy: 1)
        transform.concat()
        NSGraphicsContext.current?.imageInterpolation = .high
        let offset = cat.action == .held ? 0 : 9 * scale
        image.draw(in: NSRect(x: offset - frame.headX * factor, y: frame.footLift * factor,
                             width: Double(frame.width) * factor, height: Double(frame.height) * factor * breathing))
        NSGraphicsContext.restoreGraphicsState()
        return true
    }
}
