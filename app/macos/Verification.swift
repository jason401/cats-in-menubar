import Cocoa

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
    let configurations: [[Lane]] = [lanes, [Lane(lower: 280, upper: 380), Lane(lower: 500, upper: 740)], [], [Lane(lower: 10, upper: 100)], [Lane(lower: 100, upper: 900)]]
    for tick in 0..<30000 {
        if tick % 173 == 0 { colony.updateLanes(configurations[(tick / 173) % configurations.count]) }
        if tick % 911 == 0 { colony.play() }
        colony.step(1.0 / 30)
        for (i, cat) in colony.cats.enumerated() {
            actions.insert(cat.action)
            let time = Double(tick) / 30
            if cat.visible && cat.direction != facing[i] {
                // Turning back within half a second reads as frantic left-right shaking.
                if time - lastFlip[i] < 0.5 { jitter[cat.action.rawValue, default: 0] += 1 }
                lastFlip[i] = time
            }
            facing[i] = cat.direction
            if cat.visible {
                expect(colony.lanes.contains { $0.contains(cat.x, margin: Habitat.catRadius) }, "cat cannot overlap an obstacle")
                expect(colony.lanes.contains { $0.contains(cat.x, margin: Habitat.catRadius) && $0.contains(cat.destination, margin: Habitat.catRadius) }, "path stays in one connected interval")
            }
        }
        if let ball = colony.ball {
            expect(colony.lanes.contains { $0.contains(ball.x, margin: 4) }, "ball stays in free space")
        }
    }
    expect(jitter.isEmpty, "no rapid direction flips: \(jitter)")
    expect(actions.contains(.sleeping) && actions.contains(.walking) && actions.contains(.playing) && actions.contains(.grooming), "routine covers idle and active behaviors")
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
    let width = 1000, height = 360
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(calibratedRed: 0.07, green: 0.085, blue: 0.11, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()
    let heading: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 25, weight: .semibold), .foregroundColor: NSColor.white]
    ("Cats in Menubar" as NSString).draw(at: NSPoint(x: 30, y: 306), withAttributes: heading)
    let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.lightGray]
    ("Original vector cats · walking / sleeping / sitting / grooming / playing" as NSString).draw(at: NSPoint(x: 30, y: 280), withAttributes: label)
    for (i, action) in [CatAction.walking, .sleeping, .sitting, .grooming, .playing].enumerated() {
        let x = CGFloat(100 + i * 195)
        var cat = Cat(x: 0, destination: 0, action: action, phase: 1.3, visible: true, coat: i % 3)
        cat.velocity = action == .walking ? 15 : 0; cat.gait = 3
        CatDrawing.cat(cat, at: NSPoint(x: x, y: 140), scale: 5)
        (action.rawValue.capitalized as NSString).draw(at: NSPoint(x: x - 30, y: 105), withAttributes: label)
        cat.phase = 2.4
        CatDrawing.cat(cat, at: NSPoint(x: x, y: 43))
    }
    ("Actual size" as NSString).draw(at: NSPoint(x: 30, y: 17), withAttributes: label)
    NSGraphicsContext.restoreGraphicsState()
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("Preview: \(path)")
}
