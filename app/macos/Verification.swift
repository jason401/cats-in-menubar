import Cocoa
import SwiftUI

func runSelfTests() {
    var checks = 0
    func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        checks += 1
        if !condition() { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    let lanes = Habitat.freeLanes(width: 1000, obstacles: [Lane(lower: 0, upper: 220), Lane(lower: 800, upper: 1000)])
    expect(lanes == [Lane(lower: 228, upper: 792)], "menu padding")
    expect(Habitat.freeLanes(width: 500, obstacles: [Lane(lower: 0, upper: 500)]).isEmpty, "fully occupied")
    expect(Habitat.freeLanes(width: 500, obstacles: [Lane(lower: 20, upper: 300), Lane(lower: 200, upper: 450)]) == [Lane(lower: 458, upper: 500)], "overlapping obstacles merge")
    expect(Habitat.freeLanes(width: 500, obstacles: [Lane(lower: -100, upper: 600)]).isEmpty, "out of bounds clipping")
    var seed: UInt64 = 42
    let colony = Colony(random: { seed = seed &* 6364136223846793005 &+ 1; return Double(seed >> 11) / Double(UInt64(1) << 53) })
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
            if cat.visible && !cat.escaping && cat.direction != facing[i] {
                // Turning back within half a second reads as frantic left-right shaking.
                if time - lastFlip[i] < 0.5 { jitter[cat.action.rawValue, default: 0] += 1 }
                lastFlip[i] = time
            }
            facing[i] = cat.direction
            if cat.visible && cat.escaping {
                // A covered cat must head for the nearest free spot and get there quickly.
                escapeTicks[i] += 1
                expect(escapeTicks[i] < 45, "covered cat reaches free space within 1.5 s")
            } else if cat.visible {
                escapeTicks[i] = 0
                expect(colony.lanes.contains { $0.contains(cat.x, margin: Habitat.catRadius) }, "cat cannot overlap an obstacle")
                expect(colony.lanes.contains { $0.contains(cat.x, margin: Habitat.catRadius) && $0.contains(cat.destination, margin: Habitat.catRadius) }, "path stays in one connected interval: x \(cat.x) dest \(cat.destination) \(cat.action) lanes \(colony.lanes) tick \(tick)")
            }
        }
        if let ball = colony.ball {
            expect(colony.lanes.contains { $0.contains(ball.x, margin: 4) }, "ball stays in free space")
        }
    }
    expect(jitter.isEmpty, "no rapid direction flips: \(jitter)")
    let expected: [CatAction] = [.sleeping, .walking, .playing, .grooming, .running, .stalking, .pouncing, .stretching, .loafing]
    expect(expected.allSatisfy(actions.contains), "routine covers every behavior: missing \(expected.filter { !actions.contains($0) })")
    // Dragging never carries a cat past the edge of its free interval.
    colony.quiet = false
    colony.updateLanes([Lane(lower: 100, upper: 300), Lane(lower: 400, upper: 700)])
    for _ in 0..<90 { colony.step(1.0 / 30) }  // let covered cats reach free space first
    if let i = colony.cats.indices.first(where: { colony.cats[$0].visible && !colony.cats[$0].escaping && colony.cats[$0].x < 300 }) {
        colony.grab(i)
        colony.drag(i, to: 650, dt: 0.016); colony.step(1.0 / 30)
        expect(colony.cats[i].x <= 300 - Habitat.catRadius, "drag stays in its own free interval")
        colony.drag(i, to: -50, dt: 0.016)
        expect(colony.cats[i].x >= 100 + Habitat.catRadius, "drag clamps at the left edge")
        colony.release(i)
        expect(colony.cats[i].action != .held, "release puts the cat down")
    } else { expect(false, "a cat is available to drag") }
    colony.updateLanes([Lane(lower: 0, upper: 400)])
    colony.quiet = true; colony.step(0.1)
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
        // Guide box: the 34 pt collision envelope and the 26 pt usable height.
        NSColor(white: 1, alpha: 0.08).setStroke()
        NSBezierPath(rect: NSRect(x: x - 17 * 4, y: y, width: 34 * 4, height: 26 * 4)).stroke()
        CatDrawing.cat(cat, at: NSPoint(x: x, y: y), scale: 4)
        (name as NSString).draw(at: NSPoint(x: x - 30, y: y - 22), withAttributes: label)
    }
    ("run cycle, actual size ×2" as NSString).draw(at: NSPoint(x: 24, y: 160), withAttributes: label)
    for frame in 0..<10 {
        let cat = sample(.running, coat: frame % 3, velocity: 58, gait: Double(frame) * 2.6)
        CatDrawing.cat(cat, at: NSPoint(x: CGFloat(80 + frame * 110), y: 100), scale: 2)
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
    for page in SettingsPage.allCases {
        let state = SettingsState(); state.page = page
        let view = NSHostingView(rootView: SettingsView(model: model, state: state))
        view.frame = NSRect(x: 0, y: 0, width: 680, height: 460)
        save(view, "settings-\(page.rawValue.replacingOccurrences(of: " ", with: ""))")
    }
    print("Panels: \(directory)")
}
