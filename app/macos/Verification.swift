import Cocoa
import SwiftUI
import ImageIO

func runSelfTests() {
    var checks = 0
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    expect(SpriteAtlas.available, "approved sprite atlas is bundled; never substitute the old drawing")
    let lanes = Habitat.freeLanes(width: 1000, obstacles: [Lane(lower: 0, upper: 220), Lane(lower: 800, upper: 1000)])
    expect(lanes == [Lane(lower: 228, upper: 792)], "menu padding")
    expect(Habitat.freeLanes(width: 500, obstacles: [Lane(lower: 0, upper: 500)]).isEmpty, "fully occupied")
    expect(Habitat.freeLanes(width: 520, obstacles: [Lane(lower: 20, upper: 300), Lane(lower: 200, upper: 450)]) == [Lane(lower: 458, upper: 520)], "overlapping obstacles merge")
    expect(Habitat.freeLanes(width: 500, obstacles: [Lane(lower: -100, upper: 600)]).isEmpty, "out of bounds clipping")
    // Size changes screen speed and stride together, never the relative walking cadence.
    var distances: [CatSize: Double] = [:]
    for size in CatSize.allCases {
        let motion = Colony(count: 1, random: { 0.5 })
        motion.updateLanes([Lane(lower: 0, upper: 4000)])
        motion.cats[0].size = size; motion.cats[0].x = 100; motion.cats[0].destination = 3000
        motion.cats[0].action = .walking; motion.cats[0].remaining = 100; motion.cats[0].hiddenFor = 0
        for _ in 0..<300 { motion.step(1.0 / 30) }
        distances[size] = motion.cats[0].x - 100
    }
    for size in CatSize.allCases {
        expect(abs(distances[size]! / distances[.adult]! - size.scale) < 0.001, "travel speed scales with kitten/young/adult size")
        for i in 0..<80 {
            let time = Double(i) * 0.071 + 0.013
            var adult = Cat(x: 0, destination: 0, action: .walking, coat: 0)
            adult.gait = 15 * time
            var smaller = adult; smaller.size = size; smaller.gait *= size.scale
            expect(SpriteAtlas.frameIndex(adult) == SpriteAtlas.frameIndex(smaller), "small cats do not cycle frames faster")
        }
    }
    var frameRateDistances: [Double] = []
    for fps in [8, 15, 30] {
        let motion = Colony(count: 1, random: { 0.5 })
        motion.updateLanes([Lane(lower: 0, upper: 4000)])
        motion.cats[0].size = .adult; motion.cats[0].x = 100; motion.cats[0].destination = 3000
        motion.cats[0].action = .walking; motion.cats[0].remaining = 100; motion.cats[0].hiddenFor = 0
        for _ in 0..<(fps * 10) { motion.step(1.0 / Double(fps)) }
        frameRateDistances.append(motion.cats[0].x)
    }
    expect(frameRateDistances.max()! - frameRateDistances.min()! < 0.2, "power-saving frame rates do not slow physical travel")
    for coat in 0..<8 {
        let held = Colony(count: 1, random: { 0.5 })
        held.updateLanes([Lane(lower: 0, upper: 900)])
        held.cats[0].x = 300; held.cats[0].coat = coat; held.cats[0].hiddenFor = 0
        held.grab(0)
        expect(SpriteAtlas.frameIndex(held.cats[0]) == 18, "pickup uses the neutral dangling sprite, not sitting")
        // A moving cat that has stopped stands instead of freezing mid-stride.
        var stopped = held.cats[0]
        for action in [CatAction.walking, .running, .chasing, .goingHome] {
            stopped.action = action; stopped.velocity = 0; stopped.gait = 4.5
            expect(SpriteAtlas.frameIndex(stopped) == SpriteAtlas.standFrame, "stopped \(action) cat stands")
        }
        stopped.action = .walking; stopped.velocity = 12
        expect(SpriteAtlas.group(SpriteAtlas.frameIndex(stopped)) == SpriteAtlas.group(0), "moving cat still walks")
        for _ in 0..<15 { held.cats[0].swing = 100; held.step(1.0 / 30) }
        expect(SpriteAtlas.frameIndex(held.cats[0]) == 19, "dragging right makes the body trail left")
        for _ in 0..<25 { held.cats[0].swing = -100; held.step(1.0 / 30) }
        expect(SpriteAtlas.frameIndex(held.cats[0]) == 20, "dragging left makes the body trail right")
        held.cats[0].swing = 0
        for _ in 0..<120 { held.step(1.0 / 30) }
        expect(abs(held.cats[0].heldLean) < 0.01 && SpriteAtlas.frameIndex(held.cats[0]) == 18, "held sway damps to rest")
        held.release(0)
        expect(held.cats[0].action == .grooming, "drop returns to grooming")
    }
    // Power levels follow CPU headroom with smoothing and a gap between thresholds.
    var governor = PowerGovernor()
    _ = governor.update(cpu: 0.95, lowPowerMode: false, thermal: .nominal)
    expect(governor.level == .full, "one spike does not change the mode")
    for _ in 0..<10 { _ = governor.update(cpu: 0.9, lowPowerMode: false, thermal: .nominal) }
    expect(governor.level == .low, "a busy Mac goes to low power")
    for _ in 0..<10 { _ = governor.update(cpu: 0.45, lowPowerMode: false, thermal: .nominal) }
    expect(governor.level == .eco, "half busy is eco")
    for _ in 0..<10 { _ = governor.update(cpu: 0.4, lowPowerMode: false, thermal: .nominal) }
    expect(governor.level == .eco, "no flip back while still in between")
    for _ in 0..<10 { _ = governor.update(cpu: 0.05, lowPowerMode: false, thermal: .nominal) }
    expect(governor.level == .full && governor.liveliness > 0, "an idle Mac gets full, lively cats")
    expect(governor.update(cpu: 0.05, lowPowerMode: true, thermal: .nominal) == .low, "Low Power Mode means low power")
    expect(PowerLevel.low.frameInterval > PowerLevel.full.frameInterval && PowerLevel.low.scanInterval > PowerLevel.full.scanInterval, "low power slows timers")
    do {
        var restSeed: UInt64 = 7
        let resting = Colony(random: { restSeed = restSeed &* 6364136223846793005 &+ 1; return Double(restSeed >> 11) / Double(UInt64(1) << 53) })
        resting.mood = PowerLevel.low.mood
        resting.updateLanes([Lane(lower: 0, upper: 900)])
        var ran = false
        for _ in 0..<9000 { resting.step(1.0 / 30); ran = ran || resting.cats.contains { $0.action == .running && !$0.escaping } }
        expect(!ran, "no zoomies in low power")
    }
    var seed: UInt64 = 42
    let colony = Colony(random: { seed = seed &* 6364136223846793005 &+ 1; return Double(seed >> 11) / Double(UInt64(1) << 53) })
    expect(Set(colony.cats.map(\.coat)).count == 3, "random startup selects distinct coats")
    var seenCoats = Set<Int>(), seenSizes = Set<CatSize>(), startingPoints = Set<Int>()
    colony.updateLanes([Lane(lower: 50, upper: 850)])
    for _ in 0..<100 {
        colony.shuffle()
        for cat in colony.cats {
            seenCoats.insert(cat.coat); seenSizes.insert(cat.size); startingPoints.insert(Int(cat.x))
            expect(colony.lanes.contains { $0.contains(cat.x, margin: cat.radius) }, "random starts respect each cat's size")
        }
    }
    expect(seenCoats.count == 8 && seenSizes.count == 3 && startingPoints.count > 50, "startup randomization covers coats, sizes and positions")
    for coat in 0..<8 {
        for size in CatSize.allCases {
            let chosen = [CatAppearance](repeating: CatAppearance(coat: coat, size: size), count: 3)
            colony.applyAppearances(chosen)
            expect(colony.cats.map(\.appearance) == chosen, "custom appearances apply to all slots")
            let decoded = try! JSONDecoder().decode([CatAppearance].self, from: JSONEncoder().encode(chosen))
            expect(decoded == chosen, "chosen lineup survives persistence")
            for i in colony.cats.indices {
                colony.cats[i].x = 250
                colony.grab(i); colony.drag(i, to: -100, dt: 0.016)
                expect(abs(colony.cats[i].x - (50 + colony.cats[i].radius)) < 0.001, "drag uses the actual kitten/young/adult radius")
                colony.release(i)
            }
        }
    }
    colony.shuffle()
    var actions = Set<CatAction>()
    var lastFlip = [Double](repeating: -10, count: 3)
    var facing = colony.cats.map(\.direction)
    var jitter: [String: Int] = [:]
    var escapeTicks = [0, 0, 0]
    let configurations: [[Lane]] = [lanes, [Lane(lower: 280, upper: 380), Lane(lower: 500, upper: 740)], [], [Lane(lower: 10, upper: 100)], [Lane(lower: 100, upper: 900)]]
    for tick in 0..<30000 {
        if tick % 173 == 0 { colony.updateLanes(configurations[(tick / 173) % configurations.count]) }
        if tick % 911 == 0 { colony.play() }
        colony.step(1.0 / 30)
        for (i, cat) in colony.cats.enumerated() {
            actions.insert(cat.action)
            let time = Double(tick) / 30
            if cat.visible && !cat.escaping && cat.action != .hopping && cat.direction != facing[i] {
                // Turning back within half a second reads as frantic left-right shaking.
                if time - lastFlip[i] < 0.5 { jitter[cat.action.rawValue, default: 0] += 1 }
                lastFlip[i] = time
            }
            facing[i] = cat.direction
            if cat.visible && cat.action == .hopping {
                expect(colony.cats[i].elapsed <= Colony.hopTime + 0.1, "tower hops are short")
            } else if cat.visible && cat.escaping {
                // A covered cat must head for the nearest free spot and get there quickly.
                escapeTicks[i] += 1
                expect(escapeTicks[i] < 45, "covered cat reaches free space within 1.5 s")
            } else if cat.visible {
                escapeTicks[i] = 0
                expect(colony.lanes.contains { $0.contains(cat.x, margin: cat.radius) }, "cat cannot overlap an obstacle")
                expect(colony.lanes.contains { $0.contains(cat.x, margin: cat.radius) && $0.contains(cat.destination, margin: cat.radius) }, "path stays in one connected interval: x \(cat.x) dest \(cat.destination) \(cat.action) lanes \(colony.lanes) tick \(tick)")
            }
        }
        if let ball = colony.ball {
            expect(colony.lanes.contains { $0.contains(ball.x, margin: 4) }, "ball stays in free space")
        }
    }
    expect(jitter.isEmpty, "no rapid direction flips: \(jitter)")
    let expected: [CatAction] = [.sleeping, .walking, .playing, .grooming, .running, .stalking, .stretching, .loafing]
    expect(expected.allSatisfy(actions.contains), "routine covers every behavior: missing \(expected.filter { !actions.contains($0) })")
    // Dragging never carries a cat past the edge of its free interval.
    colony.quiet = false
    colony.updateLanes([Lane(lower: 100, upper: 300), Lane(lower: 400, upper: 700)])
    for _ in 0..<90 { colony.step(1.0 / 30) }  // let covered cats reach free space first
    if let i = colony.cats.indices.first(where: { colony.cats[$0].visible && !colony.cats[$0].escaping && colony.cats[$0].x < 300 }) {
        colony.grab(i)
        colony.drag(i, to: 650, dt: 0.016); colony.step(1.0 / 30)
        expect(colony.cats[i].x <= 300 - colony.cats[i].radius, "drag stays in its own free interval")
        colony.drag(i, to: -50, dt: 0.016)
        expect(colony.cats[i].x >= 100 + colony.cats[i].radius, "drag clamps at the left edge")
        colony.release(i)
        expect(colony.cats[i].action != .held, "release puts the cat down")
    } else { expect(false, "a cat is available to drag") }
    // A hunt always ends in a pounce at the prey.
    colony.updateLanes([Lane(lower: 0, upper: 600)])
    for _ in 0..<60 { colony.step(1.0 / 30) }
    colony.cats[0].x = 200; colony.cats[0].velocity = 0; colony.cats[0].escaping = false
    colony.start(0, .stalking, for: 30); colony.cats[0].target = 300; colony.cats[0].destination = 280
    var pounced = false
    for _ in 0..<600 where !pounced { colony.step(1.0 / 30); pounced = colony.cats[0].action == .pouncing }
    expect(pounced, "stalking leads to a pounce")
    // A ball resting at the very end of the free space is still batted, and no cat freezes while playing.
    do {
        let edge = Colony(count: 1, random: { 0.5 })
        edge.updateLanes([Lane(lower: 0, upper: 400)])
        for _ in 0..<30 { edge.step(1.0 / 30) }
        edge.cats[0].x = 200; edge.cats[0].velocity = 0; edge.cats[0].escaping = false
        edge.ball = ToyBall(x: 5, velocity: 0, lifetime: 30, lane: edge.lanes[0])
        edge.start(0, .playing, for: 30)
        var batted = false, stillFor = 0.0, longest = 0.0
        for _ in 0..<600 {
            edge.step(1.0 / 30)
            if let toy = edge.ball, abs(toy.velocity) > 20 { batted = true }
            stillFor = abs(edge.cats[0].velocity) < 0.5 && edge.cats[0].action == .playing && edge.cats[0].pounceCooldown <= 0 ? stillFor + 1.0 / 30 : 0
            longest = max(longest, stillFor)
        }
        expect(batted, "ball at the edge gets batted")
        expect(longest < 2.7, "a playing cat never stands still for long: \(longest)")
    }
    // Calling the cats home: everyone ends up in the tower, then comes back out into free space.
    colony.updateLanes([Lane(lower: 0, upper: 600)])
    for _ in 0..<60 { colony.step(1.0 / 30) }
    colony.callHome(at: 700)
    for _ in 0..<900 { colony.step(1.0 / 30) }
    expect(colony.homeCount == colony.cats.count, "called cats all go into the tower: \(colony.cats.map { $0.action })")
    colony.letOut(at: 700)
    for _ in 0..<300 { colony.step(1.0 / 30) }
    expect(colony.cats.allSatisfy { $0.visible && !$0.home && colony.lanes[0].contains($0.x, margin: $0.radius) }, "cats come back out into free space")
    // The ball lands somewhere random and every cat sharing that space joins in.
    colony.play()
    expect(colony.ball != nil && colony.cats.allSatisfy { $0.action == .playing }, "everyone in that space plays: \(colony.cats.map { $0.action })")
    colony.updateLanes([Lane(lower: 0, upper: 400)])
    colony.quiet = true; for _ in 0..<60 { colony.step(1.0 / 30) }  // covered cats first reach free space
    expect(colony.ball == nil && colony.cats.allSatisfy { $0.action == .sleeping }, "quiet time stops play")
    colony.updateLanes([])
    expect(colony.cats.allSatisfy { !$0.visible } && colony.ball == nil, "unreadable or absent space hides everyone")
    colony.setCount(2); expect(colony.cats.count == 2, "count control")
    print("PASS: \(checks) assertions; 30,000 simulation steps with changing obstacles")
}

func renderPreview(to path: String) {
    _ = NSApplication.shared
    let width = 1200, height = 620
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(calibratedRed: 0.07, green: 0.085, blue: 0.11, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    let heading: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: NSColor.white]
    ("Cats in Menubar · poses" as NSString).draw(at: NSPoint(x: 24, y: 584), withAttributes: heading)
    let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.lightGray]
    func sample(_ action: CatAction, coat: Int, velocity: Double = 0, gait: Double = 3, elapsed: Double = 0, wiggle: Double = 0, swing: Double = 0) -> Cat {
        var cat = Cat(x: 0, destination: 0, action: action, phase: 1.3, visible: true, coat: coat)
        cat.velocity = velocity; cat.gait = gait; cat.elapsed = elapsed; cat.wiggle = wiggle; cat.swing = swing
        return cat
    }
    let poses: [(String, Cat)] = [
        ("walk", sample(.walking, coat: 0, velocity: 15)), ("run", sample(.running, coat: 1, velocity: 58, gait: 6.5)),
        ("run gathered", sample(.running, coat: 1, velocity: 58, gait: 19.5)), ("stalk", sample(.stalking, coat: 2, wiggle: 0.5)),
        ("pounce", sample(.pouncing, coat: 0, elapsed: 0.22)), ("stretch front", sample(.stretching, coat: 2, elapsed: 0.8)),
        ("stretch back", sample(.stretching, coat: 0, elapsed: 2.4)), ("sit", sample(.sitting, coat: 1)),
        ("groom", sample(.grooming, coat: 0)), ("loaf", sample(.loafing, coat: 2)),
        ("sleep", sample(.sleeping, coat: 1)), ("held", sample(.held, coat: 0, swing: 40)),
    ]
    for (i, (name, cat)) in poses.enumerated() {
        let x = CGFloat(100 + (i % 6) * 190), y = CGFloat(i < 6 ? 440 : 250)
        // Guide box: the 38 pt collision envelope and the 26 pt usable height.
        NSColor(white: 1, alpha: 0.08).setStroke()
        NSBezierPath(rect: NSRect(x: x - 19 * 4, y: y, width: 38 * 4, height: 26 * 4)).stroke()
        CatDrawing.cat(cat, at: NSPoint(x: x, y: y), scale: 4)
        (name as NSString).draw(at: NSPoint(x: x - 30, y: y - 22), withAttributes: label)
    }
    ("run cycle, actual size ×3" as NSString).draw(at: NSPoint(x: 24, y: 175), withAttributes: label)
    for frame in 0..<10 {
        let cat = sample(.running, coat: 2, velocity: 58, gait: Double(frame) * 2.0)
        CatDrawing.cat(cat, at: NSPoint(x: CGFloat(70 + frame * 115), y: 95), scale: 3)
    }
    // Menu bar icon with 0-3 cats at home, enlarged and at actual size.
    for n in 0...3 {
        let icon = TowerIcon.menuBar(cats: n)
        let tinted = NSImage(size: icon.size, flipped: false) { rect in
            icon.draw(in: rect); NSColor.white.set(); rect.fill(using: .sourceAtop); return true
        }
        tinted.draw(in: NSRect(x: 640 + n * 140, y: 540, width: 72, height: 72))
        tinted.draw(in: NSRect(x: 720 + n * 140, y: 545, width: 18, height: 18))
    }
    ("actual size" as NSString).draw(at: NSPoint(x: 24, y: 40), withAttributes: label)
    for (i, (_, cat)) in poses.enumerated() { CatDrawing.cat(cat, at: NSPoint(x: CGFloat(140 + i * 85), y: 20)) }
    NSGraphicsContext.restoreGraphicsState()
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("Preview: \(path)")
}

/// Renders the dashboard and settings pages to PNG files for visual review.
func renderPanels(to directory: String) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    UserDefaults.standard.register(defaults: Pref.defaults)
    let model = AppModel()
    model.catSummary = "3 cats · 840 pt of room"
    model.lineup = [CatAppearance(coat: 0, size: .adult), CatAppearance(coat: 6, size: .young), CatAppearance(coat: 7, size: .kitten)]
    let system = SystemMonitor()
    system.sample(); Thread.sleep(forTimeInterval: 1); system.sample()
    func save(_ view: NSView, _ name: String) {
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(directory)/\(name).png"))
    }
    try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    let dashboard = NSHostingView(rootView: DashboardView(model: model, system: system, openSettings: {}, play: {}).background(Color(nsColor: .windowBackgroundColor)))
    dashboard.frame = NSRect(origin: .zero, size: dashboard.fittingSize)
    save(dashboard, "dashboard")
    let controller = SettingsWindowController(model: model)
    for (index, tab) in SettingsWindowController.tabs.enumerated() {
        let view = NSHostingView(rootView: controller.view(for: index))
        view.frame = NSRect(origin: .zero, size: SettingsWindowController.size)
        save(view, "settings-\(tab.0)")
    }
    print("Panels: \(directory)")
}


/// Eight coats at three sizes, plus native-size silhouettes on a menu-bar background.
func renderLineup(to path: String) {
    _ = NSApplication.shared
    let width = 1120, height = 680
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(calibratedRed: 0.07, green: 0.085, blue: 0.11, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    let heading: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: NSColor.white]
    let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.lightGray]
    ("Cats in Menubar · meet the cats" as NSString).draw(at: NSPoint(x: 24, y: 632), withAttributes: heading)
    ("Kitten 64% / Young 82% / Adult 100% · original approved PNG / unchanged proportions" as NSString).draw(at: NSPoint(x: 24, y: 608), withAttributes: label)
    for coat in 0..<8 {
        let left = CGFloat(24 + (coat % 4) * 278), base = CGFloat(coat < 4 ? 375 : 135)
        (CatAppearance.names[coat] as NSString).draw(at: NSPoint(x: left, y: base + 178), withAttributes: heading.merging([.font: NSFont.systemFont(ofSize: 15, weight: .semibold)]) { _, new in new })
        for size in CatSize.allCases {
            let x = left + CGFloat(35 + size.rawValue * 84)
            var cat = Cat(x: 0, destination: 0, action: .walking, phase: 1.3, visible: true, coat: coat, size: size)
            cat.velocity = 15; cat.gait = 3
            CatDrawing.cat(cat, at: NSPoint(x: x, y: base + 60), scale: 2)
            (size.label as NSString).draw(at: NSPoint(x: x - 19, y: base + 31), withAttributes: label)
            CatDrawing.cat(cat, at: NSPoint(x: x, y: base))
        }
    }
    ("Native size below each trio · original PNG sprites at every size" as NSString).draw(at: NSPoint(x: 24, y: 72), withAttributes: label)
    NSGraphicsContext.restoreGraphicsState()
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("Lineup: \(path)")
}


/// Motion proof: identical walk cadence at three physically scaled travel speeds.
func renderMotion(to path: String) {
    _ = NSApplication.shared
    let url = URL(fileURLWithPath: path)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "com.compuserve.gif" as CFString, 120, nil) else { return }
    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let colony = Colony(random: { 0.5 })
    colony.updateLanes([Lane(lower: 0, upper: 900)])
    for i in 0..<3 {
        colony.cats[i].size = [CatSize.adult, .young, .kitten][i]
        colony.cats[i].coat = i == 1 ? 6 : 0
        colony.cats[i].x = 65; colony.cats[i].destination = 800
        colony.cats[i].action = .walking; colony.cats[i].remaining = 100
        colony.cats[i].hiddenFor = 0; colony.cats[i].visible = true
    }
    for _ in 0..<120 {
        colony.step(1.0 / 15)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 900, pixelsHigh: 440, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor(calibratedRed: 0.07, green: 0.085, blue: 0.11, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 900, height: 440).fill()
        let title: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor.white]
        let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.lightGray]
        ("Size changes travel speed, not frantic frame speed" as NSString).draw(at: NSPoint(x: 24, y: 399), withAttributes: title)
        for i in 0..<3 {
            let y = CGFloat(288 - i * 104)
            ("\(colony.cats[i].size.label) · \(String(format: "%.1f", 15 * colony.cats[i].size.scale)) pt/s" as NSString).draw(at: NSPoint(x: 24, y: y + 58), withAttributes: label)
            NSColor.white.withAlphaComponent(0.12).setFill(); NSRect(x: 24, y: y - 2, width: 850, height: 1).fill()
            CatDrawing.cat(colony.cats[i], at: NSPoint(x: colony.cats[i].x * 2, y: y), scale: 2)
        }
        ("2x view · rounded calico patches · consistent head anchor and foot baseline" as NSString).draw(at: NSPoint(x: 24, y: 22), withAttributes: label)
        NSGraphicsContext.restoreGraphicsState()
        CGImageDestinationAddImage(destination, bitmap.cgImage!, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / 15]] as CFDictionary)
    }
    _ = CGImageDestinationFinalize(destination)
    print("Motion: \(path)")
}


func renderHeld(to path: String) {
    _ = NSApplication.shared
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1120, pixelsHigh: 650, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(calibratedRed: 0.07, green: 0.085, blue: 0.11, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: 1120, height: 650).fill()
    let heading: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 23, weight: .semibold), .foregroundColor: NSColor.white]
    let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.lightGray]
    ("Pick up · drag · gently settle" as NSString).draw(at: NSPoint(x: 24, y: 600), withAttributes: heading)
    ("Dedicated dangling artwork for every cat, with neutral / left-trailing / right-trailing poses" as NSString).draw(at: NSPoint(x: 24, y: 573), withAttributes: label)
    for coat in 0..<8 {
        let left = CGFloat(24 + (coat % 4) * 278), base = CGFloat(coat < 4 ? 335 : 95)
        (CatAppearance.names[coat] as NSString).draw(at: NSPoint(x: left, y: base + 180), withAttributes: label)
        for (i, lean) in [0.0, -0.75, 0.75].enumerated() {
            var cat = Cat(x: 0, destination: 0, action: .held, visible: true, coat: coat)
            cat.heldLean = lean
            let x = left + CGFloat(40 + i * 85)
            CatDrawing.cat(cat, at: NSPoint(x: x, y: base + 70), scale: 3)
            (["Rest", "Drag right", "Drag left"][i] as NSString).draw(at: NSPoint(x: x - 27, y: base + 42), withAttributes: label)
            CatDrawing.cat(cat, at: NSPoint(x: x, y: base))
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("Held: \(path)")
}
