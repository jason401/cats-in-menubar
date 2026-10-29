import Cocoa

/// Each cat owns its artwork. No runtime recoloring or rectangular coat masks.
enum SpriteAtlas {
    /// One sprite sheet per artwork set: 64 equal cells (8 x 8), frame n at column n % 8, row n / 8, unused cells empty.
    /// The build also writes copies already shrunk for the menu bar: `sheet-<density>x-<size>.png`.
    struct Sheet: Decodable {
        struct Frame: Decodable { var lift: Double; var left: Double; var right: Double }
        var columns: Int, rows: Int, cellWidth: Int, cellHeight: Int
        var headX: Double, ground: Double
        var frames: [Frame]
        var variants: [String: [Int]]
    }
    private static let folder = Bundle.main.resourceURL?.appendingPathComponent("Cats")
    private static var sheets: [String: Sheet] = [:]
    static func sheet(_ name: String) -> Sheet? {
        if let known = sheets[name] { return known }
        guard let url = folder?.appendingPathComponent("\(name)/sheet.json"), let data = try? Data(contentsOf: url),
              let sheet = try? JSONDecoder().decode(Sheet.self, from: data) else { return nil }
        sheets[name] = sheet
        return sheet
    }
    private static func sheet(for coat: Int) -> Sheet? { artworkName(for: coat).flatMap(sheet) }
    static let frameCount = 62
    static let cellCount = 64
    private static let resolvedCoats: [String] = {
        guard let url = folder?.appendingPathComponent("coats.json"), let data = try? Data(contentsOf: url),
              let names = try? JSONDecoder().decode([String].self, from: data), names.count == 8 else { return [] }
        return names
    }()
    static func artworkName(for coat: Int) -> String? { resolvedCoats.indices.contains(coat) ? resolvedCoats[coat] : nil }
    static var available: Bool {
        guard let folder, resolvedCoats.count == 8 else { return false }
        return Set(resolvedCoats).allSatisfy { name in
            guard let sheet = sheet(name), sheet.frames.count == frameCount, sheet.columns * sheet.rows == cellCount else { return false }
            return (["sheet.png"] + sheet.variants.keys.map { "sheet-\($0).png" }).allSatisfy {
                FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(name)/\($0)").path)
            }
        }
    }
    static let sourceScale: CGFloat = 24.0 / 180.0
    // V3: stand 0, idle 1–3, walk 4–11, run 12–19, turn 20–23,
    // stand→sit 24–26, sit→loaf 27–29, loaf→sleep 30–32, sleep 33–34,
    // groom 35–38, stretch 39–43, yawn 44–45, crouch 46–47,
    // creep 48–51, wiggle 52–53, pounce 54–57, bat 58–59, held 60–61.
    // Leg frames advance with distance walked, so feet never slide: slow down and the legs slow down too.
    // Strides scale with cat size like travel speed does, so every size keeps the same rhythm
    // (at cruising speed this equals 10 fps walking, 16 fps running, 5 fps creeping).
    static let walkStride = 12.0   // pt per 8-frame walk cycle, adult
    static let runStride = 29.0    // pt per 8-frame gallop, adult
    static let creepStride = 4.8   // pt per 4-frame creep, adult
    static let walkFPS = 10.0      // reference cadence at 15 pt/s, used by previews
    static let runFPS = 16.0       // reference cadence at 58 pt/s
    static let standFrame = 0
    static func frameIndex(_ cat: Cat) -> Int {
        func loop(_ start: Int, _ count: Int, _ fps: Double) -> Int { start + Int(max(0, cat.elapsed) * fps) % count }
        func once(_ start: Int, _ count: Int, _ seconds: Double) -> Int { start + min(count-1, Int(max(0, cat.elapsed) / seconds * Double(count))) }
        let stopped = abs(cat.velocity) < 1.5 * cat.size.scale
        let idle = cat.elapsed > 1 && cat.turnCooldown <= 0 ? [1,2,3,2][Int(cat.elapsed * 1.5) % 4] : standFrame
        func cycle(_ start: Int, _ count: Int, _ stride: Double) -> Int {
            start + Int(max(0, cat.gait) / (stride * cat.size.scale) * Double(count)) % count
        }
        let walking = stopped ? idle : cycle(4, 8, walkStride)
        let running = stopped ? standFrame : cycle(12, 8, runStride)
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
            // The medium crouch (46) sits closest to the creeping height, so starting to creep does not pop up.
            if stopped { return 46 }
            return cycle(48, 4, creepStride)
        case .pouncing, .hopping: return once(54, 4, cat.action == .hopping ? Colony.hopTime : 0.45)
        case .walking: return walking
        case .running, .chasing, .goingHome: return abs(cat.velocity) > 18 * cat.size.scale ? running : walking
        case .playing:
            if abs(cat.velocity) > 20 * cat.size.scale { return running }
            if !stopped { return walking }
            // One swipe right after hitting the ball, then sit and watch; crouch again just before the next swipe.
            let sinceBat = cat.phase - cat.batAt
            if sinceBat < 0.3 { return sinceBat < 0.15 ? 58 : 59 }
            if cat.pounceCooldown > 0.35 { return 26 }
            return 46
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
    /// Screen pixels per point of the menu bar display, as one of the two baked densities.
    static var density: Int { screenScale >= 1.5 ? 2 : 1 }
    static func variant(for size: CatSize, density: Int) -> String { "\(density)x-\(size.rawValue)" }
    private static var sheetImages: [String: CGImage] = [:]
    private static var cells: [String: NSImage] = [:]
    /// One cell of a sheet: the original (`variant` nil) in source pixels, or a menu bar copy sized in points.
    static func cell(_ index: Int, coat: Int, variant: String? = nil) -> NSImage? {
        guard let name = artworkName(for: coat), let sheet = sheet(name), index >= 0, index < sheet.columns * sheet.rows else { return nil }
        let key = "\(name)/\(variant ?? "full")/\(index)"
        if let known = cells[key] { return known }
        let file = variant.map { "sheet-\($0).png" } ?? "sheet.png"
        let size = variant.flatMap { sheet.variants[$0] } ?? [sheet.cellWidth, sheet.cellHeight]
        guard size.count == 2, let image = sheetImage("\(name)/\(file)"),
              let cut = image.cropping(to: CGRect(x: index % sheet.columns * size[0], y: index / sheet.columns * size[1], width: size[0], height: size[1]))
        else { return nil }
        let pixelsPerPoint = variant == nil ? 1 : CGFloat(Int(variant!.prefix(1)) ?? 1)
        let result = NSImage(cgImage: cut, size: NSSize(width: CGFloat(size[0]) / pixelsPerPoint, height: CGFloat(size[1]) / pixelsPerPoint))
        cells[key] = result
        return result
    }
    private static func sheetImage(_ path: String) -> CGImage? {
        if let known = sheetImages[path] { return known }
        guard let url = folder?.appendingPathComponent(path), let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        sheetImages[path] = image
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
    // MARK: Ground and body position, measured from the art when the sheet is built
    /// Source pixels to raise a frame so its lowest paw stands on the ground line (232 px from the cell top).
    static func groundFix(_ index: Int, coat: Int) -> Double {
        guard let sheet = sheet(for: coat), sheet.frames.indices.contains(index) else { return 0 }
        return sheet.frames[index].lift
    }
    /// Where the visible body's middle is drawn, in points from the cat's position, for a given facing.
    static func bodyCenter(_ index: Int, cat: Cat, direction: Double) -> CGFloat {
        guard let sheet = sheet(for: cat.coat), sheet.frames.indices.contains(index) else { return 0 }
        let frame = sheet.frames[index]
        let middle = (frame.left + frame.right) / 2 - sheet.headX
        return CGFloat(direction) * (offsetFor(cat, cat.size.scale) + middle * sourceScale * cat.size.scale)
    }
    private static func offsetFor(_ cat: Cat, _ scale: CGFloat) -> CGFloat { cat.action == .held ? 0 : 9 * scale }
    /// Pixels per point of the menu bar display (the overlay lives on the primary screen).
    static var screenScale: CGFloat { NSScreen.screens.first?.backingScaleFactor ?? 2 }

    @discardableResult static func draw(_ cat: Cat, at point: NSPoint, scale: CGFloat, frame override: Int? = nil, direction: Double? = nil, alpha: CGFloat = 1) -> Bool {
        let index = override ?? frameIndex(cat)
        guard let sheet = sheet(for: cat.coat), sheet.frames.indices.contains(index), var drawn = cell(index, coat: cat.coat) else { return false }
        var scale = scale * cat.size.scale
        var lift: CGFloat = 0
        if cat.action == .hopping {
            let q = CGFloat(min(1, cat.elapsed / Colony.hopTime))
            scale *= cat.hopIn ? 1 - 0.55 * q * q : 0.45 + 0.55 * q
            lift = sin(q * .pi) * 7
        } else if cat.action == .pouncing { lift = sin(min(1, cat.elapsed / 0.45) * .pi) * 4.5 }
        let factor = Self.sourceScale * scale
        let breathing: CGFloat = [.sleeping, .loafing].contains(cat.action) ? 1 + sin(cat.phase * 1.5) * 0.015 : 1
        // In the menu bar (scale 1) draw the cell from the sheet shrunk at build time for this screen and cat size,
        // snapped to the pixel grid; previews at other scales and the brief tower hop draw the original.
        let pixels = scale == cat.size.scale && cat.action != .hopping ? CGFloat(density) : 0
        func snap(_ value: CGFloat) -> CGFloat { pixels > 0 ? (value * pixels).rounded() / pixels : value }
        // The cell bottom sits 24 source px below the ground line.
        let bottom = sheet.ground - Double(sheet.cellHeight) + sheet.frames[index].lift
        var rect = NSRect(x: snap(offsetFor(cat, scale) - sheet.headX * factor), y: snap(bottom * factor),
                          width: Double(sheet.cellWidth) * factor, height: Double(sheet.cellHeight) * factor)
        if pixels > 0, let small = cell(index, coat: cat.coat, variant: variant(for: cat.size, density: density)) {
            drawn = small
            rect.size = small.size
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
