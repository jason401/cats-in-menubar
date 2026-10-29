import Cocoa

/// Each cat owns its artwork. No runtime recoloring or rectangular coat masks.
enum SpriteAtlas {
    /// One sprite sheet per artwork set: 128 equal cells (8 x 16), unused cells empty.
    /// The build also writes copies already shrunk for the menu bar: `sheet-<density>x-<size>.png`.
    struct Sheet: Decodable {
        struct Frame: Decodable { var lift: Double; var left: Double; var right: Double }
        var columns: Int, rows: Int, cellWidth: Int, cellHeight: Int
        var headX: Double, ground: Double
        var pixelsPerPoint: Double
        var walkStride: Double
        var animations: [String: [Int]]
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
    static var frameCount: Int { sheet(for: 0)?.frames.count ?? 0 }
    static let cellCount = 128
    /// Every behavior's cells, in play order, from the sheet's own table of contents (`animations` in sheet.json).
    /// Code asks for poses by name, so artwork can be reordered or given more frames without touching code.
    enum Pose: String, CaseIterable {
        case stand, idle, walk, run, turn, sitDown, sit, loafDown, loaf, sleepDown, sleep
        case groom, stretch, yawn, crouch, creep, wiggle, pounce, bat, held
    }
    static func cells(_ pose: Pose, coat: Int) -> [Int] { sheet(for: coat)?.animations[pose.rawValue] ?? [] }
    /// The `step`th cell of a pose, wrapping around; cell 0 if the artwork is missing.
    static func cell(_ pose: Pose, _ step: Int, coat: Int) -> Int {
        let list = cells(pose, coat: coat)
        return list.isEmpty ? 0 : list[step % list.count]
    }
    private static var owners: [String: [Int: (pose: Pose, step: Int)]] = [:]
    /// Which pose a cell belongs to, and its place in that pose.
    static func pose(of cell: Int, coat: Int) -> (pose: Pose, step: Int)? {
        guard let name = artworkName(for: coat), let sheet = sheet(name) else { return nil }
        if owners[name] == nil {
            var map: [Int: (pose: Pose, step: Int)] = [:]
            for pose in Pose.allCases { for (step, cell) in (sheet.animations[pose.rawValue] ?? []).enumerated() { map[cell] = (pose, step) } }
            owners[name] = map
        }
        return owners[name]?[cell]
    }
    static func walkStride(for coat: Int) -> Double { sheet(for: coat)?.walkStride ?? 12 }
    private static let resolvedCoats: [String] = {
        guard let url = folder?.appendingPathComponent("coats.json"), let data = try? Data(contentsOf: url),
              let names = try? JSONDecoder().decode([String].self, from: data), names.count == 8 else { return [] }
        return names
    }()
    static func artworkName(for coat: Int) -> String? { resolvedCoats.indices.contains(coat) ? resolvedCoats[coat] : nil }
    static var available: Bool {
        guard let folder, resolvedCoats.count == 8 else { return false }
        return Set(resolvedCoats).allSatisfy { name in
            let named = Pose.allCases.compactMap { sheet(name)?.animations[$0.rawValue] }
            guard let sheet = sheet(name), sheet.frames.count <= cellCount, sheet.columns == 8, sheet.rows == 16,
                  sheet.pixelsPerPoint > 0, sheet.walkStride > 0, named.count == Pose.allCases.count,
                  named.allSatisfy({ !$0.isEmpty && $0.allSatisfy(sheet.frames.indices.contains) }),
                  Set(named.joined()).count == named.joined().count else { return false }
            return (["sheet.png"] + sheet.variants.keys.map { "sheet-\($0).png" }).allSatisfy {
                FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(name)/\($0)").path)
            }
        }
    }
    // Leg frames advance with distance walked, so feet never slide: slow down and the legs slow down too.
    // Strides scale with cat size like travel speed does, so every size keeps the same rhythm
    // (at cruising speed this equals 10 fps walking, 16 fps running, 5 fps creeping).
    static var walkStride: Double { walkStride(for: 0) }
    static let runStride = 29.0    // pt per 8-frame gallop, adult
    static let creepStride = 4.8   // pt per 4-frame creep, adult
    static var walkFPS: Double { Double(cells(.walk, coat: 0).count) * Colony.walkSpeed / walkStride }
    static let runFPS = 16.0       // reference cadence at 58 pt/s
    static func frameIndex(_ cat: Cat) -> Int {
        func at(_ pose: Pose, _ step: Int) -> Int { cell(pose, step, coat: cat.coat) }
        func count(_ pose: Pose) -> Int { max(1, cells(pose, coat: cat.coat).count) }
        func loop(_ pose: Pose, _ fps: Double) -> Int { at(pose, Int(max(0, cat.elapsed) * fps)) }
        func once(_ pose: Pose, _ seconds: Double) -> Int { at(pose, min(count(pose) - 1, Int(max(0, cat.elapsed) / seconds * Double(count(pose))))) }
        func cycle(_ pose: Pose, _ stride: Double) -> Int { at(pose, Int(max(0, cat.gait) / (stride * cat.size.scale) * Double(count(pose)))) }
        let stopped = abs(cat.velocity) < 1.5 * cat.size.scale
        let stand = at(.stand, 0)
        // Idle sways through its cells and back (1, 2, 3, 2 for three cells).
        let sway = Array(0..<count(.idle)) + Array((1..<max(1, count(.idle) - 1)).reversed())
        let idle = cat.elapsed > 1 && cat.turnCooldown <= 0 ? at(.idle, sway[Int(cat.elapsed * 1.5) % sway.count]) : stand
        let walking = stopped ? idle : cycle(.walk, walkStride(for: cat.coat))
        let running = stopped ? stand : cycle(.run, runStride)
        switch cat.action {
        case .sleeping: return loop(.sleep, 0.65)
        case .loafing: return at(.loaf, 0)
        case .sitting:
            let yawn = max(0, cat.elapsed - 4).truncatingRemainder(dividingBy: 12)
            return cat.elapsed > 4 && yawn < 0.6 ? at(.yawn, min(count(.yawn) - 1, Int(yawn * 4))) : at(.sit, 0)
        case .held: return loop(.held, abs(cat.swing) > 5 ? 4 : 1.5)
        case .grooming: return loop(.groom, 4)
        case .stretching: return once(.stretch, Colony.stretchTime)
        case .stalking:
            if cat.wiggle > 0 { return loop(.wiggle, 5) }
            // The medium crouch (first crouch cell) sits closest to the creeping height, so starting to creep does not pop up.
            if stopped { return at(.crouch, 0) }
            return cycle(.creep, creepStride)
        case .pouncing: return once(.pounce, 0.45)
        case .hopping:
            // Running to (or from) a far tower, then the jump itself.
            guard let q = cat.hopJump else { return cycle(.run, runStride) }
            return at(.pounce, min(count(.pounce) - 1, Int(q * Double(count(.pounce)))))
        case .walking: return walking
        case .running, .chasing, .goingHome: return abs(cat.velocity) > 18 * cat.size.scale ? running : walking
        case .playing:
            if abs(cat.velocity) > 20 * cat.size.scale { return running }
            if !stopped { return walking }
            // One swipe right after hitting the ball, then sit and watch; crouch again just before the next swipe.
            let sinceBat = cat.phase - cat.batAt
            if sinceBat < 0.3 { return at(.bat, sinceBat < 0.15 ? 0 : 1) }
            if cat.pounceCooldown > 0.35 { return at(.sit, 0) }
            return at(.crouch, 0)
        }
    }
    /// Rest poses are connected by their actual in-between art; other changes retain Claude's short blend.
    static func transition(from: Int, to: Int, coat: Int) -> [Int] {
        // How far down the rest ladder a pose is: standing, sitting, loafing, asleep.
        func rank(_ cell: Int) -> Int {
            switch pose(of: cell, coat: coat)?.pose {
            case .sit, .loafDown, .groom, .yawn, .bat: return 1
            case .loaf, .sleepDown: return 2
            case .sleep: return 3
            default: return 0 }
        }
        let a = rank(from), b = rank(to)
        guard a != b else { return [] }
        let links = [cells(.sitDown, coat: coat) + cells(.sit, coat: coat), cells(.loafDown, coat: coat) + cells(.loaf, coat: coat), cells(.sleepDown, coat: coat)]
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
    static func group(_ frame: Int, coat: Int) -> Pose? {
        switch pose(of: frame, coat: coat)?.pose {
        case .stand, .idle: return .stand
        case .sitDown, .sit, .yawn: return .sit
        case .loafDown, .loaf: return .loaf
        case .sleepDown, .sleep: return .sleep
        case let other: return other
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
        return CGFloat(direction) * (offsetFor(cat, cat.size.scale) + middle / sheet.pixelsPerPoint * cat.size.scale)
    }
    private static func offsetFor(_ cat: Cat, _ scale: CGFloat) -> CGFloat { cat.action == .held ? 0 : 9 * scale }
    /// Pixels per point of the menu bar display (the overlay lives on the primary screen).
    static var screenScale: CGFloat { NSScreen.screens.first?.backingScaleFactor ?? 2 }

    @discardableResult static func draw(_ cat: Cat, at point: NSPoint, scale: CGFloat, frame override: Int? = nil, direction: Double? = nil, alpha: CGFloat = 1) -> Bool {
        let index = override ?? frameIndex(cat)
        guard let sheet = sheet(for: cat.coat), sheet.frames.indices.contains(index), var drawn = cell(index, coat: cat.coat) else { return false }
        var scale = scale * cat.size.scale
        var lift: CGFloat = 0
        if cat.action == .hopping, let jump = cat.hopJump {
            let q = CGFloat(jump)
            scale *= cat.hopIn ? 1 - 0.55 * q * q : 0.45 + 0.55 * q
            lift = sin(q * .pi) * 7
        } else if cat.action == .pouncing { lift = sin(min(1, cat.elapsed / 0.45) * .pi) * 4.5 }
        let factor = scale / sheet.pixelsPerPoint
        let breathing: CGFloat = [.sleeping, .loafing].contains(cat.action) ? 1 + sin(cat.phase * 1.5) * 0.015 : 1
        // In the menu bar (scale 1) draw the cell from the sheet shrunk at build time for this screen and cat size,
        // snapped to the pixel grid; previews at other scales and the brief tower hop draw the original.
        let pixels = scale == cat.size.scale && (cat.action != .hopping || cat.hopJump == nil) ? CGFloat(density) : 0
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
