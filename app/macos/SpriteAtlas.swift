import Cocoa

/// Uses the approved PNG itself. Geometry and animation timing live here; no redrawn heads or bodies.
enum SpriteAtlas {
    private struct Frame { let rect: CGRect; let ground: CGFloat }
    // Alpha bounds of the 18 orange poses in the approved 1536 x 1024 sheet, top-left coordinates.
    private static let frames: [Frame] = [
        Frame(rect: CGRect(x: 44, y: 99, width: 214, height: 140), ground: 243),
        Frame(rect: CGRect(x: 289, y: 107, width: 220, height: 133), ground: 243),
        Frame(rect: CGRect(x: 547, y: 80, width: 210, height: 162), ground: 243),
        Frame(rect: CGRect(x: 786, y: 107, width: 221, height: 136), ground: 243),
        Frame(rect: CGRect(x: 1048, y: 100, width: 209, height: 143), ground: 243),
        Frame(rect: CGRect(x: 1301, y: 92, width: 200, height: 151), ground: 243),
        Frame(rect: CGRect(x: 31, y: 349, width: 225, height: 124), ground: 480),
        Frame(rect: CGRect(x: 284, y: 314, width: 218, height: 160), ground: 480),
        Frame(rect: CGRect(x: 525, y: 321, width: 255, height: 119), ground: 480),
        Frame(rect: CGRect(x: 800, y: 347, width: 224, height: 133), ground: 480),
        Frame(rect: CGRect(x: 1046, y: 362, width: 220, height: 118), ground: 480),
        Frame(rect: CGRect(x: 1295, y: 320, width: 216, height: 145), ground: 480),
        Frame(rect: CGRect(x: 64, y: 532, width: 155, height: 180), ground: 714),
        Frame(rect: CGRect(x: 296, y: 585, width: 185, height: 116), ground: 714),
        Frame(rect: CGRect(x: 548, y: 595, width: 197, height: 109), ground: 714),
        Frame(rect: CGRect(x: 787, y: 528, width: 222, height: 184), ground: 714),
        Frame(rect: CGRect(x: 1058, y: 552, width: 146, height: 158), ground: 714),
        Frame(rect: CGRect(x: 1284, y: 566, width: 214, height: 148), ground: 714),
    ]
    private static let source: CGImage? = {
        guard let url = Bundle.main.url(forResource: "CatAtlas", withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return NSBitmapImageRep(data: data)?.cgImage
    }()
    private static var images: [Int: NSImage] = [:]
    static var available: Bool { source != nil }
    static let sourceScale: CGFloat = 24.0 / 180.0  // tallest standing adult = 24 pt, never enlarged per pose

    private static func frameIndex(_ cat: Cat) -> Int {
        let walking = Int(max(0, cat.gait) / (9 * cat.size.scale) * 6) % 6
        let running = 6 + Int(max(0, cat.gait) / (20 * cat.size.scale) * 6) % 6
        switch cat.action {
        case .sleeping: return 14
        case .loafing: return 13
        case .sitting, .held: return 12
        case .grooming: return 16
        case .stretching: return 15
        case .stalking: return 10
        case .pouncing, .hopping: return 6 + min(5, Int(cat.elapsed / 0.55 * 6))
        case .walking: return walking
        case .running, .chasing, .goingHome: return abs(cat.velocity) > 18 ? running : walking
        case .playing: return abs(cat.velocity) > 20 ? running : (abs(cat.velocity) > 2 ? walking : 10)
        }
    }
    private static func image(_ index: Int, coat: Int) -> NSImage? {
        let key = coat * frames.count + index
        if let cached = images[key] { return cached }
        guard let crop = source?.cropping(to: frames[index].rect) else { return nil }
        let final: CGImage
        if coat == 0 { final = crop } // The orange cat is the exact approved artwork, without recoloring.
        else { final = recolor(crop, coat: coat) ?? crop }
        let image = NSImage(cgImage: final, size: NSSize(width: final.width, height: final.height))
        images[key] = image
        return image
    }
    private static func recolor(_ input: CGImage, coat: Int) -> CGImage? {
        let width = input.width, height = input.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let palette: [(Double, Double, Double)] = [(1, 0.69, 0.35), (0.24, 0.25, 0.29), (0.98, 0.96, 0.90), (0.67, 0.72, 0.78), (1, 0.86, 0.66), (0.24, 0.25, 0.29), (0.98, 0.95, 0.88), (0.87, 0.79, 0.66)]
        return pixels.withUnsafeMutableBytes { bytes -> CGImage? in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(input, in: CGRect(x: 0, y: 0, width: width, height: height))
            let data = bytes.bindMemory(to: UInt8.self)
            for y in 0..<height { for x in 0..<width {
                let i = (y * width + x) * 4, a = Double(data[i + 3]) / 255
                guard a > 0.01 else { continue }
                let r = Double(data[i]) / (255 * a), g = Double(data[i + 1]) / (255 * a), b = Double(data[i + 2]) / (255 * a)
                let light = 0.3 * r + 0.59 * g + 0.11 * b
                let pink = r > g * 1.1 && b > g * 1.1 && light > 0.35
                if [1, 5].contains(coat) && !pink && light < 0.29 {
                    // A neutral gray rim keeps dark fur readable against a dark menu bar.
                    data[i] = UInt8(0.54 * a * 255); data[i + 1] = UInt8(0.55 * a * 255); data[i + 2] = UInt8(0.60 * a * 255)
                    continue
                }
                guard !pink && light > 0.20 else { continue } // Keep the original eyes, line work and ear interiors.
                let u = Double(x) / Double(width), v = Double(y) / Double(height)
                var color = palette[max(0, min(7, coat))]
                if coat == 5 && ((u > 0.64 && v < 0.56) || v < 0.14) { color = (0.98, 0.96, 0.91) }
                if coat == 6 {
                    if u < 0.46 { color = (0.91, 0.51, 0.22) }
                    else if u < 0.63 && v > 0.42 { color = (0.25, 0.26, 0.29) }
                }
                if coat == 7 && ((u > 0.67 && v > 0.35) || v < 0.17 || u < 0.18) { color = (0.39, 0.30, 0.26) }
                let shade = min(1.10, max(0.47, light / 0.76))
                data[i] = UInt8(min(255, max(0, color.0 * shade * a * 255)))
                data[i + 1] = UInt8(min(255, max(0, color.1 * shade * a * 255)))
                data[i + 2] = UInt8(min(255, max(0, color.2 * shade * a * 255)))
            }}
            return context.makeImage()
        }
    }
    @discardableResult static func draw(_ cat: Cat, at point: NSPoint, scale: CGFloat) -> Bool {
        let index = frameIndex(cat)
        guard let image = image(index, coat: cat.coat) else { return false }
        var scale = scale * cat.size.scale
        var lift: CGFloat = 0
        if cat.action == .hopping {
            let q = CGFloat(min(1, cat.elapsed / Colony.hopTime))
            scale *= cat.hopIn ? 1 - 0.55 * q * q : 0.45 + 0.55 * q
            lift = sin(q * .pi) * 7
        } else if cat.action == .pouncing { lift = sin(min(1, cat.elapsed / 0.45) * .pi) * 4.5 }
        let factor = Self.sourceScale * scale
        let breathing: CGFloat = [.sleeping, .loafing].contains(cat.action) ? 1 + sin(cat.phase * 1.5) * 0.015 : 1
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: point.x, yBy: point.y + lift * scale)
        transform.scaleX(by: cat.direction, yBy: 1)
        if cat.action == .held { transform.rotate(byDegrees: -max(-12, min(12, cat.swing / 8)) * cat.direction) }
        transform.concat()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(x: -image.size.width * factor / 2, y: (frames[index].ground - frames[index].rect.maxY) * factor,
                             width: image.size.width * factor, height: image.size.height * factor * breathing))
        NSGraphicsContext.restoreGraphicsState()
        return true
    }
}
