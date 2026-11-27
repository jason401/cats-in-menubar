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
    expect(["THIRD_PARTY_NOTICES.md", "Apache-2.0.txt"].allSatisfy { FileManager.default.fileExists(atPath: Bundle.main.resourceURL!.appendingPathComponent($0).path) },
           "third-party notices and the Apache license ship inside the app")
    for coat in 0..<8 {
        let slug = ["orange", "black", "white", "silver", "cream", "tuxedo", "calico", "siamese"][coat]
        let ownExists = FileManager.default.fileExists(atPath: Bundle.main.resourceURL!.appendingPathComponent("Cats/\(slug)/sheet.json").path)
        expect(SpriteAtlas.artworkName(for: coat) == (ownExists ? slug : "orange"), "missing v3 coats share orange without changing preferences")
        for action in CatAction.allCases {
            for tick in 0..<100 {
                var cat = Cat(x: 0, destination: 100, action: action, coat: coat)
                cat.phase = Double(tick) * 0.1; cat.elapsed = cat.phase; cat.gait = Double(tick); cat.velocity = 15
                expect((0..<SpriteAtlas.frameCount).contains(SpriteAtlas.frameIndex(cat)), "v3 animation frame stays in range")
            }
        }
    }
    func cells(_ pose: SpriteAtlas.Pose) -> [Int] { SpriteAtlas.cells(pose, coat: 0) }
    let restLadder = cells(.sitDown) + cells(.sit) + cells(.loafDown) + cells(.loaf) + cells(.sleepDown)
    expect(SpriteAtlas.transition(from: cells(.stand)[0], to: cells(.sleep)[0], coat: 0) == restLadder, "rest transition reaches sleep through sitting and loaf")
    expect(SpriteAtlas.transition(from: cells(.sleep)[0], to: cells(.stand)[0], coat: 0) == Array(restLadder.reversed()), "waking reverses the transition art")
    // The sheet's table of contents names every behavior; each named cell is drawn, each cell belongs to one pose.
    for pose in SpriteAtlas.Pose.allCases {
        expect(!cells(pose).isEmpty, "\(pose) has cells in the sheet")
        for (step, cell) in cells(pose).enumerated() { expect(SpriteAtlas.pose(of: cell, coat: 0)! == (pose, step), "cell \(cell) is \(pose) step \(step)") }
    }
    let walkCells = cells(.walk)
    expect(walkCells == Array(walkCells[0]..<walkCells[0] + walkCells.count), "the walk sits in one unbroken run of cells")
    // Every artwork set is one 128-cell sprite sheet, plus copies shrunk for 1x/2x screens and each cat size.
    for name in Set((0..<8).compactMap(SpriteAtlas.artworkName)) {
        let sheet = SpriteAtlas.sheet(name)!
        expect(sheet.columns == 8 && sheet.rows == 16 && (62...128).contains(sheet.frames.count), "\(name) sheet is 8 x 16 cells")
        for density in [1, 2] { for size in CatSize.allCases {
            let cells = sheet.variants[SpriteAtlas.variant(for: size, density: density)]
            let expected = [sheet.cellWidth, sheet.cellHeight].map { Int((Double($0) * (1 / sheet.pixelsPerPoint) * size.scale * Double(density)).rounded()) }
            expect(cells == expected, "\(name) \(density)x \(size) cells are the menu bar pixel size: \(String(describing: cells))")
        }}
    }
    func coverage(_ image: NSImage?) -> Int {
        guard let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return -1 }
        let rep = NSBitmapImageRep(cgImage: cg)
        var solid = 0
        for y in Swift.stride(from: 0, to: cg.height, by: 2) { for x in Swift.stride(from: 0, to: cg.width, by: 2) where rep.colorAt(x: x, y: y)!.alphaComponent > 0.4 { solid += 1 } }
        return solid
    }
    for index in 0..<SpriteAtlas.cellCount {
        let filled = coverage(SpriteAtlas.cell(index, coat: 0)) > 0
        expect(filled == (index < SpriteAtlas.frameCount), "cell \(index) is \(index < SpriteAtlas.frameCount ? "a frame" : "empty, reserved for new art")")
    }
    for index in [0, 6, 26, 33, 60] {
        let small = SpriteAtlas.cell(index, coat: 0, variant: SpriteAtlas.variant(for: .adult, density: 1))
        expect(small?.size.width == CGFloat(Int((Double(SpriteAtlas.sheet(SpriteAtlas.artworkName(for: 0)!)!.cellWidth) / SpriteAtlas.sheet(SpriteAtlas.artworkName(for: 0)!)!.pixelsPerPoint).rounded())) && coverage(small) > 20, "1x adult cell \(index) is drawn and sized in points")
    }
    // Check the complete authored walk, including appended cells, instead of assuming contiguous IDs.
    let walkIDs = cells(.walk)
    expect(!walkIDs.isEmpty && Set(walkIDs).count == walkIDs.count, "walk uses distinct authored cells")
    var uniqueWalkArt = Set<Data>()
    for (phase, expected) in walkIDs.enumerated() {
        for size in CatSize.allCases {
            var cat = Cat(x: 0, destination: 100, action: .walking, coat: 0, size: size)
            cat.velocity = Colony.walkSpeed * size.scale
            cat.gait = (Double(phase) + 0.01) / Double(walkIDs.count) * SpriteAtlas.walkStride * size.scale
            expect(SpriteAtlas.frameIndex(cat) == expected, "walk follows its full frame order at every size")
            cat.gait += SpriteAtlas.walkStride * size.scale
            expect(SpriteAtlas.frameIndex(cat) == expected, "walk wraps without dropping or repeating a phase")
        }
        let cg = SpriteAtlas.cell(expected, coat: 0)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        uniqueWalkArt.insert(NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!)
    }
    expect(uniqueWalkArt.count == walkIDs.count, "walk does not repeat eight pictures to fake sixteen")
    let nativeSheet = SpriteAtlas.sheet(SpriteAtlas.artworkName(for: 0)!)!
    for id in walkIDs {
        let edges = nativeSheet.frames[id]
        let left = 9 + (edges.left-nativeSheet.headX)/nativeSheet.pixelsPerPoint
        let right = 9 + (edges.right-nativeSheet.headX)/nativeSheet.pixelsPerPoint
        expect(max(abs(left),abs(right)) <= Habitat.catRadius, "walk frame \(id) fits the existing physical collision margin")
    }
    // Inspect rendered assets, not just metadata: switching to run must keep the eye scale and anchor.
    var drawnEyeHeights: [Double] = []
    for index in walkIDs + cells(.run) {
        let sheet = SpriteAtlas.sheet(SpriteAtlas.artworkName(for: 0)!)!
        let registrationScale = sheet.pixelsPerPoint / 7.5
        let image = SpriteAtlas.cell(index, coat: 0)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = ctx.data!.assumingMemoryBound(to: UInt8.self)
        // Bitmap rows are top-down: eye is 256 - (24+97) = 135 pixels from the top.
        let left = Int((sheet.headX - 30 * registrationScale).rounded())
        let bottom = Int((sheet.ground - 142 * registrationScale).rounded())
        let w = Int((60 * registrationScale).rounded()), h = Int((65 * registrationScale).rounded())
        var mask = [Bool](repeating: false, count: w*h)
        for y in 0..<h { for x in 0..<w {
            let p = ((y+bottom)*image.width+x+left)*4
            // At native 2x the eye is only 3–4 pixels high; include its antialiased dark edge.
            let darkLimit: UInt8 = registrationScale < 0.5 ? 110 : 55
            mask[y*w+x] = pixels[p+3] > 180 && max(pixels[p], pixels[p+1], pixels[p+2]) < darkLimit
        }}
        var eyes: [[Int]] = []
        for start in mask.indices where mask[start] {
            var q = [start], cursor = 0; mask[start] = false
            while cursor < q.count {
                let p = q[cursor]; cursor += 1; let x = p%w, y = p/w
                for (xx,yy) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] where xx>=0 && yy>=0 && xx<w && yy<h {
                    let n = yy*w+xx
                    if mask[n] { mask[n]=false; q.append(n) }
                }
            }
            if q.count > max(1, Int(30 * registrationScale * registrationScale)) && !q.contains(where: { $0%w == 0 || $0%w == w-1 || $0/w == 0 || $0/w == h-1 }) { eyes.append(q) }
        }
        expect(!eyes.isEmpty, "registered frame has a visible eye")
        let eye = eyes.max(by: { $0.count < $1.count })!
        let eyeX = Double(eye.map { $0%w+left }.reduce(0,+))/Double(eye.count)
        let eyeY = Double(eye.map { $0/w+bottom }.reduce(0,+))/Double(eye.count)
        let height = eye.map { $0/w }.max()! - eye.map { $0/w }.min()! + 1
        // Resampled native pixels represent pixel centers, half a pixel inside the geometric anchor.
        let center = registrationScale < 0.5 ? 0.5 : 0
        expect(abs(eyeX-(sheet.headX-center)) < max(1.0, 2 * registrationScale), "frame \(index) uses the actual eye anchor (\(eyeX), \(eyeY))")
        // Height matters as drawn: each frame is lifted so its paws touch the ground, and the head must not jump from there.
        drawnEyeHeights.append((SpriteAtlas.groundFix(index, coat: 0) - eyeY) / sheet.pixelsPerPoint)
        expect(abs(Double(height) - 13 * registrationScale) <= max(1.1, registrationScale), "frame \(index) keeps head feature scale: \(height)")
    }
    expect(drawnEyeHeights.max()! - drawnEyeHeights.min()! < 2, "walking and running heads stay within a 2 pt bob: \(drawnEyeHeights)")
    let lanes = Habitat.freeLanes(width: 1000, obstacles: [Lane(lower: 0, upper: 220), Lane(lower: 800, upper: 1000)])
    expect(lanes == [Lane(lower: 228, upper: 792)], "menu padding")
    expect(Habitat.freeLanes(width: 500, obstacles: [Lane(lower: 0, upper: 500)]).isEmpty, "fully occupied")
    expect(Habitat.freeLanes(width: 520, obstacles: [Lane(lower: 20, upper: 300), Lane(lower: 200, upper: 450)]) == [Lane(lower: 458, upper: 520)], "overlapping obstacles merge")
    expect(Habitat.freeLanes(width: 500, obstacles: [Lane(lower: -100, upper: 600)]).isEmpty, "out of bounds clipping")
    // Size changes travel speed only; the animation clock does not read distance or size.
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
    }
    // Leg frames follow distance: a cat that barely moves barely steps, and every size keeps the same rhythm
    // at its own cruising speed (strides scale with size like speed does).
    for size in CatSize.allCases {
        for (action, speed, pose) in [(CatAction.walking, Colony.walkSpeed, SpriteAtlas.Pose.walk), (.running, 58.0, .run)] {
            var adult = Cat(x: 0, destination: 0, action: action, coat: 0); adult.velocity = speed
            var smaller = adult; smaller.size = size; smaller.velocity = speed * size.scale
            for i in 0..<80 {
                let time = Double(i) * 0.071 + 0.013
                adult.gait = speed * time; smaller.gait = speed * size.scale * time
                expect(SpriteAtlas.frameIndex(adult) == SpriteAtlas.frameIndex(smaller), "\(size) \(action) keeps the adult rhythm")
            }
            var creeping = adult; creeping.size = size
            creeping.velocity = (action == .running ? 19 : 2) * size.scale + 0.5
            creeping.gait = 0
            let start = SpriteAtlas.frameIndex(creeping)
            creeping.gait = 0.2 * size.scale
            expect(SpriteAtlas.frameIndex(creeping) == start && cells(pose).contains(start), "tiny distance does not flip legs")
        }
    }
    // Every grounded frame stands on the ground line; the gallop touches it on its lowest frame.
    if SpriteAtlas.available {
        var fixes: [String] = []
        for index in [cells(.stand)[0]] + walkIDs + [cells(.sit)[0], cells(.loaf)[0], cells(.sleep)[0], cells(.crouch)[0], cells(.creep)[0]] {
            let fix = SpriteAtlas.groundFix(index, coat: 0)
            fixes.append("\(index):\(Int(fix.rounded()))")
            expect(abs(fix) / nativeSheet.pixelsPerPoint < 40.0 / 7.5, "ground fix for frame \(index) is physically small: \(fix)")
        }
        let run = cells(.run).map { SpriteAtlas.groundFix($0, coat: 0) }
        expect(Set(run.map { Int($0.rounded()) }).count == 1, "the gallop moves as one piece")
        print("Ground fixes (source px): \(fixes.joined(separator: " ")) run \(Int(run[0].rounded()))")
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
        expect(SpriteAtlas.cells(.held, coat: coat).contains(SpriteAtlas.frameIndex(held.cats[0])), "pickup uses the neutral dangling sprite, not sitting")
        // A moving cat that has stopped stands instead of freezing mid-stride.
        var stopped = held.cats[0]
        for action in [CatAction.walking, .running, .chasing, .goingHome] {
            stopped.action = action; stopped.velocity = 0; stopped.gait = 4.5
            expect(SpriteAtlas.frameIndex(stopped) == SpriteAtlas.cells(.stand, coat: coat)[0], "stopped \(action) cat stands")
        }
        stopped.action = .walking; stopped.velocity = 12
        expect(SpriteAtlas.group(SpriteAtlas.frameIndex(stopped), coat: coat) == .walk, "moving cat still walks")
        for _ in 0..<15 { held.cats[0].swing = 100; held.step(1.0 / 30) }
        expect(held.cats[0].heldLean < -0.2, "dragging right makes the body trail left")
        for _ in 0..<25 { held.cats[0].swing = -100; held.step(1.0 / 30) }
        expect(held.cats[0].heldLean > 0.2, "dragging left makes the body trail right")
        held.cats[0].swing = 0
        for _ in 0..<120 { held.step(1.0 / 30) }
        expect(abs(held.cats[0].heldLean) < 0.01 && SpriteAtlas.cells(.held, coat: coat).contains(SpriteAtlas.frameIndex(held.cats[0])), "held sway damps to rest")
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
                expect(colony.cats[i].elapsed <= colony.cats[i].hopTotal + 0.1, "tower hops end on time")
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
    // Space taken over a cat: it is pulled out dangling like a held cat, then set down at the edge.
    do {
        let pulled = Colony(count: 1, random: { 0.5 })
        pulled.updateLanes([Lane(lower: 0, upper: 600)])
        for _ in 0..<30 { pulled.step(1.0 / 30) }
        pulled.cats[0].x = 400; pulled.cats[0].destination = 400; pulled.cats[0].visible = true; pulled.cats[0].hiddenFor = 0
        pulled.updateLanes([Lane(lower: 0, upper: 250)])
        var dangled = true, wasPulled = false, steps = 0
        while steps < 90 && (steps == 0 || pulled.cats[0].escaping) {
            pulled.step(1.0 / 30); steps += 1
            if pulled.cats[0].escaping {
                wasPulled = true
                dangled = dangled && SpriteAtlas.cells(.held, coat: pulled.cats[0].coat).contains(SpriteAtlas.frameIndex(pulled.cats[0]))
            }
        }
        expect(wasPulled && dangled, "a covered cat is pulled out in the held pose, not running")
        expect(!pulled.cats[0].escaping && pulled.lanes[0].contains(pulled.cats[0].x, margin: pulled.cats[0].radius) && pulled.cats[0].action == .grooming,
               "then it is set down in the free space and grooms: \(pulled.cats[0].action)")
    }
    // A ball resting at the very end of the free space is still batted, and no cat freezes while playing.
    do {
        let edge = Colony(count: 1, random: { 0.5 })
        edge.updateLanes([Lane(lower: 0, upper: 400)])
        for _ in 0..<30 { edge.step(1.0 / 30) }
        edge.cats[0].x = 200; edge.cats[0].velocity = 0; edge.cats[0].escaping = false
        edge.ball = Toy(x: 5, velocity: 0, lifetime: 30, lane: edge.lanes[0])
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
    // On a notched MacBook cats sometimes walk behind the notch and come out on the other side.
    do {
        var notchSeed: UInt64 = 11
        let notched = Colony(random: { notchSeed = notchSeed &* 6364136223846793005 &+ 1; return Double(notchSeed >> 11) / Double(UInt64(1) << 53) })
        let notch = Lane(lower: 500, upper: 700)
        notched.tunnel = notch
        notched.updateLanes(Habitat.freeLanes(width: 1200, obstacles: [Lane(lower: 0, upper: 150), notch]))
        let ends = notched.tunnelEnds()
        expect(ends?.left.upper == 492 && ends?.right.lower == 708, "the free spaces next to the notch are its two ends")
        let entrance = Colony(count: 1, random: { 0.5 })
        entrance.tunnel = notch; entrance.updateLanes(notched.lanes)
        entrance.cats[0].x = 468; entrance.cats[0].destination = 468
        entrance.cats[0].direction = -1; entrance.cats[0].visible = true; entrance.cats[0].hiddenFor = 0
        entrance.start(0, .walking, for: 100); entrance.cats[0].tunnelBound = true
        for _ in 0..<720 { entrance.step(1.0 / 30) }
        expect(!entrance.cats[0].inTunnel && entrance.cats[0].x > 700, "facing away at the entrance still crosses to the opposite side")
        var crossings = 0, inside = [Double](repeating: 0, count: 3), wasIn = notched.cats.map(\.inTunnel)
        var side = notched.cats.map { $0.x < 600 }
        for _ in 0..<60000 {
            notched.step(1.0 / 30)
            for (i, cat) in notched.cats.enumerated() where cat.visible {
                if cat.inTunnel {
                    inside[i] += 1.0 / 30
                    expect(cat.x >= 492 - cat.radius && cat.x <= 708 + cat.radius, "a crossing cat stays between the two sides")
                    // Another visible cat may occupy the same x while this cat crosses slowly.
                    expect(notched.catIndex(at: cat.x) != i, "the crossing cat itself cannot be picked up")
                } else {
                    expect(notched.lanes.contains { $0.contains(cat.x, margin: cat.radius) }, "outside the notch cats stay in free space")
                    if wasIn[i] {
                        expect(side[i] != (cat.x < 600), "a crossing ends on the other side")
                        expect(inside[i] < 24, "the slow walk through the crossing finishes: \(inside[i]) s")
                        crossings += 1
                    }
                    inside[i] = 0; side[i] = cat.x < 600
                }
                wasIn[i] = cat.inTunnel
            }
        }
        expect(crossings >= 3, "cats do use the notch tunnel: \(crossings)")
        // A held cat can be carried across the notch, and let go behind it, walks out of the nearer side.
        let carried = notched.cats.indices.first { !notched.cats[$0].inTunnel && notched.cats[$0].x < 492 && notched.cats[$0].x > 150 }
            ?? { notched.cats[0].inTunnel = false; notched.cats[0].x = 300; notched.cats[0].visible = true; notched.start(0, .sitting, for: 5); return 0 }()
        notched.grab(carried)
        for x in stride(from: notched.cats[carried].x, through: 900, by: 10) {
            notched.drag(carried, to: x, dt: 1.0 / 30); notched.step(1.0 / 30)
            expect(notched.cats[carried].action == .held && !notched.cats[carried].escaping, "a held cat goes through the notch without being dropped")
        }
        notched.drag(carried, to: 900, dt: 1.0 / 30); notched.updateLanes(notched.lanes)
        expect(abs(notched.cats[carried].x - 900) < 0.001 && notched.cats[carried].action == .held, "dragged across to the other side")
        notched.drag(carried, to: 640, dt: 1.0 / 30); notched.step(1.0 / 30); notched.updateLanes(notched.lanes)
        expect(notched.cats[carried].action == .held && notched.cats[carried].x == 640, "a cat can be held behind the notch while the layout refreshes")
        notched.release(carried)
        for _ in 0..<360 { notched.step(1.0 / 30) }
        expect(!notched.cats[carried].inTunnel && !notched.cats[carried].escaping && notched.cats[carried].x > 700, "let go behind the notch, the cat walks out of the nearer side: \(notched.cats[carried].x)")
        // The far side filling up mid-crossing sends the cat back out into the nearest free space.
        notched.cats[0].x = 600; notched.cats[0].direction = 1; notched.cats[0].inTunnel = true; notched.cats[0].visible = true
        notched.updateLanes(Habitat.freeLanes(width: 1200, obstacles: [Lane(lower: 0, upper: 150), Lane(lower: 500, upper: 1200)]))
        for _ in 0..<45 { notched.step(1.0 / 30) }
        expect(!notched.cats[0].inTunnel && notched.lanes.contains { $0.contains(notched.cats[0].x, margin: notched.cats[0].radius) }, "a closed tunnel lets the cat out on a free side")
        // Called home from the far side of the notch: it runs through the notch, never leaps across it.
        let homeward = Colony(count: 1, random: { 0.5 })
        homeward.tunnel = notch; homeward.updateLanes(Habitat.freeLanes(width: 1200, obstacles: [Lane(lower: 0, upper: 150), notch]))
        homeward.cats[0].x = 300; homeward.cats[0].destination = 300; homeward.cats[0].visible = true; homeward.cats[0].hiddenFor = 0
        homeward.callHome(at: 1180)
        var usedTunnel = false, longestHop = 0.0
        for _ in 0..<1200 where !homeward.cats[0].home {
            homeward.step(1.0 / 30)
            usedTunnel = usedTunnel || homeward.cats[0].inTunnel
            if homeward.cats[0].action == .hopping { longestHop = max(longestHop, abs(homeward.cats[0].hopTo - homeward.cats[0].hopFrom)) }
        }
        expect(homeward.cats[0].home && usedTunnel && longestHop < 40, "home past the notch is reached through it: tunnel \(usedTunnel), hop \(longestHop)")
    }
    // A covered cat dashes out: it speeds up (no instant slide), and its legs never cycle faster than a gallop.
    do {
        let dash = Colony(count: 1, random: { 0.5 })
        dash.updateLanes([Lane(lower: 0, upper: 1000)])
        dash.cats[0].x = 500; dash.cats[0].destination = 500; dash.cats[0].visible = true; dash.cats[0].hiddenFor = 0
        dash.updateLanes([Lane(lower: 0, upper: 380)])
        var ticks = 0, firstSpeed = -1.0, fastestLegs = 0.0
        while dash.cats[0].escaping || ticks == 0 {
            let gait = dash.cats[0].gait
            dash.step(1.0 / 30); ticks += 1
            if firstSpeed < 0 { firstSpeed = abs(dash.cats[0].velocity) }
            fastestLegs = max(fastestLegs, (dash.cats[0].gait - gait) * 30)
            if ticks > 60 { break }
        }
        expect(firstSpeed < 40 && ticks < 45, "an escape accelerates and is out within 1.5 s: first \(firstSpeed) pt/s, \(ticks) ticks")
        expect(fastestLegs <= Colony.runSpeed * 1.01, "escape strides lengthen instead of the legs blurring: \(fastestLegs)")
        // Space shrinking by a few points: no nudge. A cat facing the menu turns in place first,
        // then runs a few strides clear of the edge.
        let nudge = Colony(count: 1, random: { 0.5 })
        nudge.updateLanes([Lane(lower: 0, upper: 1000)])
        let r = nudge.cats[0].radius
        nudge.cats[0].x = 300; nudge.cats[0].destination = 300; nudge.cats[0].direction = -1
        nudge.cats[0].visible = true; nudge.cats[0].hiddenFor = 0
        nudge.updateLanes([Lane(lower: 300 - r + 4, upper: 1000)])
        var turned = false, pulled = false
        for _ in 0..<60 {
            nudge.step(1.0 / 30)
            if nudge.cats[0].direction != -1 || nudge.cats[0].turnHold > 0 { turned = true }
            if nudge.cats[0].escaping { pulled = true }
        }
        expect(pulled && !turned, "a cat pulled out from under a shrinking edge dangles without turning around")
        expect(abs(nudge.cats[0].x - (300 + 4)) < 0.5 && nudge.cats[0].action == .grooming, "it is set down right inside the edge: \(nudge.cats[0].x) \(nudge.cats[0].action)")
        // A far tower is run to over the icons, with the jump only at the tower.
        let far = Colony(count: 1, random: { 0.5 })
        far.updateLanes([Lane(lower: 0, upper: 300)])
        far.cats[0].visible = true; far.cats[0].hiddenFor = 0
        far.beginHop(0, from: 280, to: 480, entering: true)
        far.step(1.0 / 30)
        expect(far.cats[0].hopJump == nil && SpriteAtlas.cells(.run, coat: 0).contains(SpriteAtlas.frameIndex(far.cats[0])), "a long way to the tower is run, not glided")
        expect(abs(far.cats[0].hopTotal - 200 / (55 * far.cats[0].size.scale)) < 0.01, "the run to a far tower goes at gallop speed")
    }
    // Laser pointer: a press on free space lights a dot the cats chase; held still in front of a cat, it gets pounced.
    do {
        var seed: UInt64 = 5
        let pointer = Colony(count: 3, random: { seed = seed &* 6364136223846793005 &+ 1; return Double(seed >> 11) / Double(UInt64(1) << 53) })
        pointer.updateLanes([Lane(lower: 100, upper: 700), Lane(lower: 800, upper: 1000)])
        for i in pointer.cats.indices { pointer.cats[i].x = 200 + Double(i) * 120; pointer.cats[i].destination = pointer.cats[i].x; pointer.cats[i].visible = true; pointer.cats[i].hiddenFor = 0 }
        expect(!pointer.laser(at: 750), "no laser dot outside free space")
        expect(pointer.laser(at: 650) && pointer.ball?.kind == .laser, "pressing on free space lights the dot")
        pointer.laser(at: 760)
        expect(pointer.ball!.x <= 697, "the dot stays inside the free space where the press started")
        expect(pointer.cats.allSatisfy { $0.action == .playing }, "every cat in that space goes for the dot")
        // Sweep the dot back and forth: cats run after it.
        var ran = false
        for step in 0..<240 {
            pointer.laser(at: 400 + sin(Double(step) / 20) * 250)
            pointer.step(1.0 / 30)
            ran = ran || pointer.cats.contains { abs($0.velocity) > 20 * $0.size.scale }
        }
        expect(ran, "cats run after a moving dot")
        // Hold it still: someone stalks and pounces on it.
        var pounced = false
        for _ in 0..<360 {
            pointer.laser(at: pointer.ball!.x)
            pointer.step(1.0 / 30)
            pounced = pounced || pointer.cats.contains { $0.action == .pouncing }
        }
        expect(pounced, "a dot held still gets pounced")
        pointer.laserOff()
        for _ in 0..<12 { pointer.step(1.0 / 30) }
        expect(pointer.ball == nil, "letting go switches the dot off")
        for _ in 0..<150 { pointer.step(1.0 / 30) }
        expect(!pointer.cats.contains { $0.action == .playing }, "with the dot gone, the cats stop playing")
    }
    // Scroll reversing follows Scroll Reverser's rule: devices Natural/Classic against what macOS already did,
    // apps Reversed/Unchanged, horizontal matching vertical unless set, and a wheel click made N lines.
    do {
        for (mode, natural, flips) in [(ScrollMode.natural, true, false), (.natural, false, true), (.classic, true, true), (.classic, false, false),
                                       (.unchanged, true, false), (.unchanged, false, false), (.reversed, true, true), (.reversed, false, true)] {
            expect(mode.reverses(natural: natural) == flips, "\(mode) with natural=\(natural) reverses: \(flips)")
        }
        let trackpad = ScrollSourceRow(key: "t", kind: .device, category: .trackpad, name: nil, continuous: true)
        let mouse = ScrollSourceRow(key: "m", kind: .device, category: .mouse, name: nil, continuous: false)
        let app = ScrollSourceRow(key: "a", kind: .app, category: .other, name: nil, continuous: true)
        expect(trackpad.vertical == .natural && mouse.vertical == .classic && app.vertical == .unchanged, "new trackpads natural, mice classic, apps unchanged")
        expect(trackpad.adjustment(natural: false) == .init(reverseVertical: true, reverseHorizontal: true, stepSize: 0), "a classic trackpad is made natural both ways")
        expect(mouse.adjustment(natural: false) == .init(reverseVertical: false, reverseHorizontal: false, stepSize: 3), "a classic mouse stays, with 3-line wheel steps")
        var sideways = trackpad; sideways.horizontal = .unchanged
        expect(sideways.adjustment(natural: false).reverseHorizontal == false, "horizontal can be set apart from vertical")
        // Smooth scrolling: every delta flips, including point and fixed-point values.
        let smooth = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 12, wheel2: -5, wheel3: 0)!
        let before = [smooth.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), smooth.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)]
        applyScrollAdjustment(trackpad.adjustment(natural: false), to: smooth, hid: nil)
        expect([smooth.getIntegerValueField(.scrollWheelEventPointDeltaAxis1), smooth.getIntegerValueField(.scrollWheelEventPointDeltaAxis2)] == before.map { -$0 }
               && smooth.getDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1) < 0, "smooth scroll deltas are reversed: \(before)")
        // A wheel click: one line becomes three, reversed when asked.
        let click = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0)!
        applyScrollAdjustment(mouse.adjustment(natural: false), to: click, hid: nil)
        expect(click.getIntegerValueField(.scrollWheelEventDeltaAxis1) == 3, "a wheel click scrolls the step size")
        var reversedMouse = mouse; reversedMouse.vertical = .natural
        let click2 = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 1, wheel2: 0, wheel3: 0)!
        applyScrollAdjustment(reversedMouse.adjustment(natural: false), to: click2, hid: nil)
        expect(click2.getIntegerValueField(.scrollWheelEventDeltaAxis1) == -3, "a natural mouse wheel scrolls the other way")
        let untouched = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 7, wheel2: 0, wheel3: 0)!
        applyScrollAdjustment(app.adjustment(natural: false), to: untouched, hid: nil)
        expect(untouched.getIntegerValueField(.scrollWheelEventPointDeltaAxis1) == 7, "unchanged sources pass through")
        // Device keys: the serial when there is one; the name for built-in devices without IDs; trackpads by acceleration type.
        let builtIn = deviceSource(kind: .device, properties: [kIOHIDProductKey: "Apple Internal Keyboard / Trackpad", "HIDScrollAccelerationType": "HIDTrackpadScrollAcceleration"], trackpadDriver: false)
        expect(builtIn.key == "device||||Apple Internal Keyboard / Trackpad" && builtIn.category == .trackpad, "built-in trackpad key: \(builtIn.key)")
        let wireless = deviceSource(kind: .device, properties: [kIOHIDProductKey: "Mouse|1", kIOHIDTransportKey: "Bluetooth", kIOHIDVendorIDKey: 76, kIOHIDProductIDKey: 617, kIOHIDSerialNumberKey: "AB#C"], trackpadDriver: false)
        expect(wireless.key == "device|Bluetooth|76|617|sn:AB%23C" && wireless.category == .mouse, "mouse key: \(wireless.key)")
    }
    // Changing displays: the chosen display if it is there and has a menu bar, else the main one;
    // status items keep their distance from the right edge; the cats walk home, then come out on the new bar.
    do {
        let main = DisplayInfo(id: "A", name: "Built-in", hasMenuBar: true)
        let side = DisplayInfo(id: "B", name: "LG", hasMenuBar: true)
        let bare = DisplayInfo(id: "C", name: "TV", hasMenuBar: false)
        expect(Displays.pick(chosen: "B", available: [main, side])?.id == "B", "the chosen display is used")
        expect(Displays.pick(chosen: "", available: [main, side])?.id == "A", "no choice means the main display")
        expect(Displays.pick(chosen: "B", available: [main])?.id == "A", "an unplugged choice falls back to the main display")
        expect(Displays.pick(chosen: "C", available: [main, bare])?.id == "A", "a display without a menu bar falls back to the main display")
        let tower = Displays.mapRightAligned(NSRect(x: 1300, y: 952, width: 22, height: 30), from: NSRect(x: 0, y: 0, width: 1512, height: 982), to: NSRect(x: 1512, y: 0, width: 2560, height: 1440))
        expect(tower.minX == 3860 && tower.maxY == 1440, "the tower sits the same distance from the right edge on the other menu bar: \(tower)")
        let moving = Colony(count: 3, random: { 0.5 })
        moving.updateLanes([Lane(lower: 0, upper: 600)])
        for i in moving.cats.indices { moving.cats[i].x = 100 + Double(i) * 150; moving.cats[i].destination = moving.cats[i].x; moving.cats[i].visible = true; moving.cats[i].hiddenFor = 0 }
        moving.grab(0)
        moving.callHome(at: 640)
        expect(moving.cats[0].action == .goingHome, "a held cat is put down and heads home with the others")
        moving.play()
        expect(moving.ball == nil && !moving.laser(at: 300), "no ball or laser while the cats walk home")
        expect(moving.catIndex(at: moving.cats[1].x) == nil, "nobody can be picked up on the way home")
        moving.grab(1)
        expect(moving.cats[1].action != .held, "grabbing a cat on its way home does nothing")
        var steps = 0
        while !moving.cats.allSatisfy(\.home) && steps < 3000 { moving.step(1.0 / 30); steps += 1 }
        expect(moving.cats.allSatisfy(\.home), "everyone walks home before the move: \(steps) steps")
        expect(!moving.walkingHome, "once everyone is in, toys work again")
        moving.sendHomeNow(); moving.homeX = nil
        moving.updateLanes([Lane(lower: 0, upper: 1400)])
        moving.letOut(at: 1440)
        for _ in 0..<300 { moving.step(1.0 / 30) }
        expect(moving.cats.allSatisfy { $0.visible && !$0.home && moving.lanes[0].contains($0.x, margin: $0.radius) }, "then everyone comes out on the new menu bar")
        // A screen that vanishes: everyone goes straight inside, unseen.
        moving.sendHomeNow()
        expect(moving.cats.allSatisfy { $0.home && !$0.visible } && moving.ball == nil, "an unplugged screen sends everyone home at once")
    }
    // Launch: everyone starts in the tower and hops out one by one.
    do {
        let launch = Colony(count: 3, random: { 0.5 })
        launch.startInTower()
        launch.updateLanes([Lane(lower: 0, upper: 900)])
        launch.homeX = 1000
        expect(launch.cats.allSatisfy { $0.home && !$0.visible }, "at launch nobody is out yet")
        var outAt: [Int] = []
        for step in 0..<300 {
            launch.step(1.0 / 30)
            let out = launch.cats.filter { !$0.home }.count
            if out > outAt.count { outAt.append(step) }
        }
        expect(outAt.count == 3 && outAt[0] < outAt[1] && outAt[1] < outAt[2], "launch: cats come out one at a time: \(outAt)")
        expect(launch.cats.allSatisfy { $0.visible && launch.lanes[0].contains($0.x, margin: $0.radius) }, "launch: everyone ends up in the free space")
    }
    // Taking turns: one cat at a time goes into the tower and a different-looking cat comes out.
    do {
        var seed: UInt64 = 7
        let turns = Colony(count: 3, random: { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) })
        turns.updateLanes([Lane(lower: 0, upper: 900)])
        turns.homeX = 1000
        for i in turns.cats.indices { turns.cats[i].x = 100 + Double(i) * 250; turns.cats[i].destination = turns.cats[i].x; turns.cats[i].visible = true; turns.cats[i].hiddenFor = 0 }
        turns.rotation = 5...6
        var swaps = 0
        turns.swapped = { swaps += 1 }
        let before = turns.cats.map(\.coat)
        var mostSwapping = 0, othersPlayable = false, overlap = false
        for _ in 0..<(30 * 60) {
            turns.step(1.0 / 30)
            mostSwapping = max(mostSwapping, turns.cats.filter(\.swapping).count)
            if turns.cats.contains(where: { $0.swapping && !$0.home }) && !turns.walkingHome { othersPlayable = true }
            let worn = turns.cats.map(\.coat)
            if Set(worn).count != worn.count { overlap = true }
        }
        expect(swaps == 1 && mostSwapping == 1, "one cat swaps at a time, then a gap: \(swaps) swaps")
        expect(othersPlayable, "the other cats still play while one walks in to swap")
        expect(!overlap && turns.cats.map(\.coat) != before, "the new cat wears a coat nobody else has: \(before) -> \(turns.cats.map(\.coat))")
        expect(turns.cats.allSatisfy { !$0.home && $0.visible }, "everyone is back out after the swap")
        // Held or out of sight: no time passes toward a turn.
        turns.swapGap = 0
        for i in turns.cats.indices { turns.cats[i].stay = 1 }
        turns.grab(0); turns.onStage = false
        for _ in 0..<120 { turns.step(1.0 / 30) }
        expect(turns.cats.allSatisfy { !$0.swapping && $0.stay == 1 }, "no turns while the cats are out of sight")
        turns.onStage = true
        for _ in 0..<(30 * 30) { turns.step(1.0 / 30) }
        expect(turns.cats[0].action == .held && !turns.cats[0].swapping, "a held cat is never taken away")
        turns.release(0)
        // Called home while one waits inside to swap: nobody comes back out.
        var guard_ = 0
        while !turns.cats.contains(where: { $0.swapping && $0.home }) && guard_ < 30 * 120 { turns.step(1.0 / 30); guard_ += 1 }
        expect(turns.cats.contains { $0.swapping && $0.home }, "a cat goes in to swap")
        turns.callHome(at: 1000)
        for _ in 0..<(30 * 40) { turns.step(1.0 / 30) }
        expect(turns.cats.allSatisfy(\.home), "calling everyone home keeps the swapping cat inside too")
        // Turned off on the way in: it carries on as itself.
        turns.letOut(at: 1000)
        for _ in 0..<(30 * 10) { turns.step(1.0 / 30) }
        turns.swapGap = 0; turns.ball = nil
        for i in turns.cats.indices { turns.cats[i].stay = 0; turns.cats[i].remaining = 0 }
        turns.step(1.0 / 30)
        let walker = turns.cats.firstIndex(where: \.swapping)
        let look = walker.map { turns.cats[$0].appearance }
        turns.rotation = nil
        for _ in 0..<(30 * 30) { turns.step(1.0 / 30) }
        expect(walker != nil && turns.cats[walker!].action != .hopping && turns.cats[walker!].appearance == look && !turns.cats[walker!].swapping, "turning it off keeps the cat on its way in as it is: \(walker.map { "\(turns.cats[$0].action) \(turns.cats[$0].appearance)" } ?? "nobody") vs \(String(describing: look))")
    }
    // Turned off or put to sleep while one waits inside: it waits, then comes back out unchanged.
    do {
        let inside = Colony(count: 2, random: { 0.5 })
        inside.updateLanes([Lane(lower: 0, upper: 900)])
        inside.homeX = 1000
        inside.rotation = 5...6
        for i in inside.cats.indices { inside.cats[i].x = 100 + Double(i) * 300; inside.cats[i].destination = inside.cats[i].x; inside.cats[i].visible = true; inside.cats[i].hiddenFor = 0 }
        inside.cats[0].stay = 0; inside.cats[0].remaining = 0; inside.cats[1].stay = 1000
        var steps = 0
        while !inside.cats[0].home && steps < 30 * 60 { inside.step(1.0 / 30); steps += 1 }
        let look = inside.cats[0].appearance
        expect(inside.cats[0].home && inside.cats[0].swapping, "the cat goes in to swap")
        inside.quiet = true
        for _ in 0..<(30 * 20) { inside.step(1.0 / 30) }
        expect(inside.cats[0].home, "no cat comes out of a swap during quiet time")
        inside.quiet = false; inside.onStage = false
        for _ in 0..<(30 * 20) { inside.step(1.0 / 30) }
        expect(inside.cats[0].home, "no cat comes out of a swap out of sight")
        inside.onStage = true; inside.rotation = nil
        for _ in 0..<(30 * 20) { inside.step(1.0 / 30) }
        expect(!inside.cats[0].home && inside.cats[0].appearance == look, "turned off while inside: the same cat comes back out")
    }
    // The tower slides left (items to its right changed) during a swap: the cat comes out of the icon where it is now.
    do {
        let moved = Colony(count: 1, random: { 0.5 })
        moved.updateLanes([Lane(lower: 0, upper: 900)])
        moved.homeX = 1000
        moved.rotation = 5...6
        moved.cats[0].x = 400; moved.cats[0].destination = 400; moved.cats[0].visible = true; moved.cats[0].hiddenFor = 0
        moved.cats[0].stay = 0; moved.cats[0].remaining = 0
        var steps = 0
        while !moved.cats[0].home && steps < 30 * 60 { moved.step(1.0 / 30); steps += 1 }
        moved.updateLanes([Lane(lower: 0, upper: 600)]); moved.homeX = 700
        var farthest = 0.0
        for _ in 0..<(30 * 20) { moved.step(1.0 / 30); if !moved.cats[0].home { farthest = max(farthest, moved.cats[0].x) } }
        expect(!moved.cats[0].home && farthest <= 700 && moved.lanes[0].contains(moved.cats[0].x, margin: moved.cats[0].radius), "swap after the tower moved: out of the new spot, never past it: \(farthest)")
    }
    // Shuffling: everyone goes in first, changes inside, then comes back out one by one.
    do {
        var seed: UInt64 = 11
        let mix = Colony(count: 3, random: { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) })
        mix.updateLanes([Lane(lower: 0, upper: 900)])
        mix.homeX = 1000
        for i in mix.cats.indices { mix.cats[i].x = 100 + Double(i) * 250; mix.cats[i].destination = mix.cats[i].x; mix.cats[i].visible = true; mix.cats[i].hiddenFor = 0 }
        let before = mix.cats.map(\.coat)
        var done = 0
        mix.shuffled = { done += 1; mix.letOut(at: 1000, after: 1.5) }
        mix.beginShuffle(at: 1000)
        var changedOutside = false, steps = 0
        while done == 0 && steps < 30 * 60 {
            mix.step(1.0 / 30); steps += 1
            if mix.cats.indices.contains(where: { !mix.cats[$0].home && mix.cats[$0].coat != before[$0] }) { changedOutside = true }
            if done == 0 { mix.letOut(at: 1000) }   // a letting-out mid-shuffle (menu bar back, screen moved) waits for it
        }
        expect(done == 1 && mix.cats.allSatisfy(\.home) && !changedOutside, "shuffle: nobody changes until everyone is in: \(steps) steps")
        let after = mix.cats.map(\.coat)
        expect(Set(after).count == 3 && Set(after).isDisjoint(with: before), "shuffle: new coats, all different: \(before) -> \(after)")
        var outAt: [Int] = []
        for step in 0..<300 {
            mix.step(1.0 / 30)
            let out = mix.cats.filter { !$0.home }.count
            if out > outAt.count { outAt.append(step) }
        }
        expect(outAt.count == 3 && outAt[0] >= 40 && outAt[0] < outAt[1] && outAt[1] < outAt[2], "shuffle: a short wait, then out one at a time: \(outAt)")
        expect(mix.cats.allSatisfy { $0.visible && mix.lanes[0].contains($0.x, margin: $0.radius) }, "shuffle: everyone ends up in the free space")
        // Called home mid-shuffle: everyone stays in, as they were.
        mix.beginShuffle(at: 1000)
        for _ in 0..<15 { mix.step(1.0 / 30) }
        mix.shuffling = false; mix.callHome(at: 1000)
        for _ in 0..<(30 * 40) { mix.step(1.0 / 30) }
        expect(done == 1 && mix.cats.allSatisfy(\.home) && mix.cats.map(\.coat) == after, "shuffle cancelled by calling home: nobody comes out or changes")
        // A cat added mid-shuffle, or one with no free space, still lets it finish.
        let small = Colony(count: 2, random: { 0.5 })
        small.updateLanes([Lane(lower: 0, upper: 900)]); small.homeX = 1000
        var finished = false
        small.shuffled = { finished = true }
        small.beginShuffle(at: 1000)
        small.setCount(3)
        small.updateLanes([])
        for _ in 0..<30 { small.step(1.0 / 30) }
        expect(finished && small.cats.count == 3 && Set(small.cats.map(\.coat)).count == 3, "shuffle finishes with a cat added and no free space")
    }
    // Speed test: reads networkQuality's JSON (bits per second, RPM, milliseconds).
    let sample = #"{"dl_throughput": 641066112, "ul_throughput": 255409168, "responsiveness": 767.66, "base_rtt": 22.04, "interface_name": "en0"}"#
    let measured = SpeedTest.parse(Data(sample.utf8), date: Date(timeIntervalSince1970: 0))
    expect(measured?.download == 641066112 && measured?.upload == 255409168 && measured?.latency == 22.04 && measured?.responsiveness == 767.66, "speed test output is read")
    expect(SpeedTest.rate(641066112) == "641 Mbps" && SpeedTest.rate(25_540_000) == "25.5 Mbps", "speeds read in Mbps")
    expect(SpeedTest.parse(Data("{}".utf8), date: Date()) == nil, "unexpected output is not taken as a result")
    // Grades follow the stated scale, and the weakest part sets the overall grade.
    expect(SpeedTest.grade(download: 9e6) == .slow && SpeedTest.grade(download: 49e6) == .fair && SpeedTest.grade(download: 199e6) == .fast && SpeedTest.grade(download: 641e6) == .veryFast, "download grades")
    expect(SpeedTest.grade(upload: 2e6) == .slow && SpeedTest.grade(upload: 9e6) == .fair && SpeedTest.grade(upload: 49e6) == .fast && SpeedTest.grade(upload: 255e6) == .veryFast, "upload grades")
    expect(SpeedTest.grade(loadedLatency: 160) == .slow && SpeedTest.grade(loadedLatency: 78) == .fair && SpeedTest.grade(loadedLatency: 30) == .fast && SpeedTest.grade(loadedLatency: 10) == .veryFast, "busy-delay grades")
    expect(measured.map(SpeedTest.grade) == .fair && abs((measured?.loadedLatency ?? 0) - 60_000 / 767.66) < 0.01, "767 RPM means about 78 ms while busy, so a fast line grades Fair")
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
    // Each size has its own temperament: odds sum to 1, kittens play far more than adults.
    for size in CatSize.allCases { expect(abs(size.temperament.weights.reduce(0, +) - 1) < 1e-9, "\(size) odds sum to 1") }
    func lively(_ size: CatSize) -> Int {
        var seed: UInt64 = 7
        let c = Colony(count: 1, random: { seed = seed &* 6364136223846793005 &+ 1; return Double(seed >> 11) / Double(UInt64(1) << 53) })
        c.updateLanes([Lane(lower: 0, upper: 600)])
        c.cats[0].size = size
        var count = 0
        for _ in 0..<4000 {
            c.cats[0].action = .sitting; c.ball = nil
            c.choose(0, lane: c.lanes[0])
            if [.running, .stalking, .playing, .chasing].contains(c.cats[0].action) { count += 1 }
        }
        return count
    }
    let (kittenLively, youngLively, adultLively) = (lively(.kitten), lively(.young), lively(.adult))
    expect(kittenLively > youngLively && youngLively > adultLively * 2, "livelier when younger: \(kittenLively) \(youngLively) \(adultLively)")
    // Toys: a dropped ball gets a color, a new one each time unless Settings fixes it.
    var colors: [Int] = []
    for _ in 0..<6 { colony.ball = nil; colors.append(colony.makeToy(x: 50, velocity: 0, lifetime: 5, lane: Lane(lower: 0, upper: 100)).color) }
    expect(zip(colors, colors.dropFirst()).allSatisfy { $0 != $1 } && colors.allSatisfy { Toy.colors.indices.contains($0) }, "mixed ball colors change: \(colors)")
    colony.toyColor = 2
    expect(colony.makeToy(x: 50, velocity: 0, lifetime: 5, lane: Lane(lower: 0, upper: 100)).color == 2, "fixed ball color")
    colony.toyColor = nil
    // Top apps: this process shows up, values are sane and the lists are ranked.
    let sampler = AppUsageSampler()
    _ = sampler.sample(now: Date())
    var spin = 0.0; let until = Date().addingTimeInterval(0.3); while Date() < until { spin += sin(spin) + 1 }
    let started = Date()
    let usage = sampler.sample(now: Date())
    let cost = Date().timeIntervalSince(started)
    expect(spin > 0 && !usage.cpu.isEmpty && !usage.memory.isEmpty && usage.cpu.count <= 3, "top apps are read: \(usage)")
    expect(usage.cpu.allSatisfy { $0.value >= 0 && $0.value <= 1.01 }, "CPU shares are fractions of the Mac: \(usage.cpu)")
    expect(zip(usage.memory, usage.memory.dropFirst()).allSatisfy { $0.value >= $1.value }, "memory list is ranked")
    expect(cost < 0.25, "one app sample is cheap: \(cost) s")
    print("App sample: \(Int(cost * 1000)) ms; CPU \(usage.cpu.map { "\($0.name) \(Int($0.value * 1000) / 10)%" }); memory \(usage.memory.map { "\($0.name) \(Int($0.value / 1e6)) MB" })")
    testUpdateProgress(expect)
    testUpdateChannels(expect)
    testBatteryTone(expect)
    testSensors(expect)
    testFinderKeys(expect)
    testQuitOnClose(expect)
    testPanelHover(expect)
    testWheel(expect)
    testFaceStream(expect)
    testWheelBaton(expect)
    testWheelDrop(expect)
    testMenuBarTidy(expect)
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
    func sample(_ action: CatAction, coat: Int, velocity: Double = 0, phase: Double = 1.3, elapsed: Double = 0, wiggle: Double = 0, swing: Double = 0) -> Cat {
        var cat = Cat(x: 0, destination: 0, action: action, phase: 1.3, visible: true, coat: coat)
        cat.velocity = velocity; cat.phase = phase; cat.elapsed = elapsed; cat.wiggle = wiggle; cat.swing = swing
        return cat
    }
    let poses: [(String, Cat)] = [
        ("walk", sample(.walking, coat: 0, velocity: 15)), ("run", sample(.running, coat: 1, velocity: 58, phase: 2 / SpriteAtlas.runFPS)),
        ("run gathered", sample(.running, coat: 1, velocity: 58, phase: 0)), ("stalk", sample(.stalking, coat: 2, wiggle: 0.5)),
        ("pounce", sample(.pouncing, coat: 0, elapsed: 0.22)), ("stretch front", sample(.stretching, coat: 2, elapsed: 0.8)),
        ("stretch return", sample(.stretching, coat: 0, elapsed: 2.4)), ("sit", sample(.sitting, coat: 1)),
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
        let cat = sample(.running, coat: 2, velocity: 58, phase: Double(frame) / SpriteAtlas.runFPS)
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

/// Fixed battery states for tests and previews; nothing here reads the real power source or preferences.
func batteryPreviewStates() -> [(String, SystemStats)] {
    func stats(_ level: Double, charging: Bool = false, onAC: Bool = false, lowPower: Bool = false, battery: Bool = true) -> SystemStats {
        var s = SystemStats()
        s.hasBattery = battery; s.batteryLevel = level; s.charging = charging; s.onAC = onAC; s.lowPowerMode = lowPower
        return s
    }
    var charging = stats(0.52, charging: true, onAC: true); charging.power = 18.4
    var desktop = stats(0, onAC: true, battery: false); desktop.power = 7.2
    return [("charging-52", charging), ("battery-50", stats(0.50)), ("battery-15", stats(0.15)),
            ("battery-8", stats(0.08)), ("low-power-40", stats(0.40, lowPower: true)), ("adapter-full", stats(1.0, onAC: true)),
            ("adapter-low-power-8", stats(0.08, onAC: true, lowPower: true)), ("no-battery", desktop)]
}

func testFinderKeys(_ expect: (@autoclosure () -> Bool, String) -> Void) {
    let cmd = CGEventFlags.maskCommand
    let batchShortcut: CGEventFlags = [.maskControl, .maskCommand]
    let shifted: CGEventFlags = [.maskCommand, .maskShift]
    let on = FinderKeyContext(cutPaste: true, copyAdds: true, pasteImages: true, finderFront: true)
    func act(_ key: Int64, _ context: FinderKeyContext, _ flags: CGEventFlags = cmd) -> FinderKeyAction {
        FinderKeys.route(key: key, flags: flags, context)
    }
    expect(act(FinderKeys.x, on) == .collect(.move), "⌘X in Finder collects items to move")
    expect(act(FinderKeys.c, on) == .collect(.copy) && act(FinderKeys.c, on, shifted) == .pass,
           "plain ⌘C in Finder collects items to copy")
    var nativeCopy = on; nativeCopy.copyAdds = false
    expect(act(FinderKeys.c, nativeCopy) == .pass && act(FinderKeys.x, nativeCopy) == .collect(.move),
           "disabling copy accumulation preserves Finder copy and the cut shortcut")
    var cut = on; cut.batchKind = .move; cut.clipboardUnchanged = true
    expect(act(FinderKeys.v, cut) == .transfer(.move) && act(FinderKeys.v, cut, shifted) == .transfer(.move),
           "⌘V or ⇧⌘V after ⌘X moves items")
    var copied = cut; copied.batchKind = .copy
    expect(act(FinderKeys.v, copied) == .transfer(.copy) && act(FinderKeys.v, copied, batchShortcut) == .transfer(.copy),
           "pasting a copy batch copies its files")
    var stale = cut; stale.clipboardUnchanged = false
    expect(act(FinderKeys.v, stale) == .pasteImage && act(FinderKeys.v, stale, batchShortcut) == .transfer(.move),
           "after another copy, regular paste uses the clipboard and the explicit shortcut moves the cut batch")
    var staleCopy = stale; staleCopy.batchKind = .copy
    expect(act(FinderKeys.v, staleCopy) == .pasteImage && act(FinderKeys.v, staleCopy, batchShortcut) == .transfer(.copy),
           "a newer clipboard does not prevent explicit paste of the copied batch")
    expect(act(FinderKeys.v, stale, shifted) == .pass && act(FinderKeys.x, stale) == .collect(.move),
           "⇧⌘V passes through after another copy, and ⌘X can still collect items")
    var staleWithoutImages = staleCopy; staleWithoutImages.pasteImages = false
    expect(act(FinderKeys.v, staleWithoutImages) == .pass && act(FinderKeys.v, staleWithoutImages, batchShortcut) == .transfer(.copy),
           "regular paste and the retained batch both work with image pasting off")
    var collecting = copied; collecting.collecting = true
    expect(act(FinderKeys.v, collecting) == .waitForSelection && act(FinderKeys.v, collecting, batchShortcut) == .waitForSelection,
           "paste waits for an in-flight selection query before choosing the files")
    var busy = cut; busy.transferring = true
    expect(act(FinderKeys.v, busy) == .swallow && act(FinderKeys.v, busy, batchShortcut) == .swallow && act(FinderKeys.x, busy) == .swallow,
           "a transfer cannot be started twice")
    busy.clipboardUnchanged = false
    expect(act(FinderKeys.v, busy) == .pasteImage && act(FinderKeys.c, busy) == .pass,
           "unrelated clipboard shortcuts still work during a transfer")
    expect(act(FinderKeys.v, cut, [.maskCommand, .maskAlternate]) == .pass && act(FinderKeys.x, cut, batchShortcut) == .pass
           && act(FinderKeys.v, stale, [.maskControl, .maskCommand, .maskShift]) == .pass, "Finder's other modifier combinations pass through")
    expect(act(FinderKeys.v, on, batchShortcut) == .pass, "⌃⌘V passes through without a batch")
    expect(act(FinderKeys.v, on) == .pasteImage && act(FinderKeys.v, on, shifted) == .pass, "only plain ⌘V pastes images")
    var pasting = on; pasting.pastingImage = true
    expect(act(FinderKeys.v, pasting) == .pass, "one image paste at a time")
    var editing = cut; editing.editingText = true
    expect(act(FinderKeys.x, editing) == .pass && act(FinderKeys.v, editing) == .pass && act(FinderKeys.c, editing) == .pass
           && act(FinderKeys.v, editing, batchShortcut) == .pass, "renaming and search fields keep the keys")
    var other = cut; other.finderFront = false
    expect(act(FinderKeys.x, other) == .pass && act(FinderKeys.c, other) == .pass && act(FinderKeys.v, other) == .pass
           && act(FinderKeys.v, other, batchShortcut) == .pass, "other apps are never touched")
    var off = on; off.cutPaste = false; off.pasteImages = false
    expect(act(FinderKeys.x, off) == .pass && act(FinderKeys.c, off) == .pass && act(FinderKeys.v, off) == .pass, "both settings off: nothing changes")
    var imagesOnly = cut; imagesOnly.cutPaste = false
    expect(act(FinderKeys.x, imagesOnly) == .pass && act(FinderKeys.c, imagesOnly) == .pass && act(FinderKeys.v, imagesOnly) == .pasteImage
           && act(FinderKeys.v, imagesOnly, batchShortcut) == .pass, "with only images enabled, file shortcuts pass through")
    expect(act(FinderKeys.x, on, []) == .pass && act(53, cut, []) == .pass, "typing and Esc are left alone")
    expect(FinderKeys.imageType(["public.png", "public.tiff"]) == "public.png" && FinderKeys.imageType(["public.tiff"]) == "public.tiff"
           && FinderKeys.imageType(["public.file-url", "public.png"]) == nil && FinderKeys.imageType(["public.utf8-plain-text"]) == nil,
           "PNG first, any image next, never when files are copied")
    var parts = DateComponents(); parts.year = 2026; parts.month = 11; parts.day = 23; parts.hour = 21; parts.minute = 30; parts.second = 5
    let date = Calendar(identifier: .gregorian).date(from: parts)!
    expect(FinderKeys.imageName(at: date) == "Pasted_Image_20261123_213005.png", "pasted images are named Pasted_Image_ and the time")
    let taken: Set<String> = ["a.png", "a 2.png", "folder"]
    expect(FinderKeys.freeName("a.png") { taken.contains($0) } == "a 3.png" && FinderKeys.freeName("b.png") { taken.contains($0) } == "b.png"
           && FinderKeys.freeName("folder") { taken.contains($0) } == "folder 2", "taken names get 2, 3… like Finder")
    expect(FinderKeys.needsFinder(NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM)))
           && FinderKeys.needsFinder(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError))
           && FinderKeys.needsFinder(NSError(domain: NSCocoaErrorDomain, code: 1, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))]))
           && !FinderKeys.needsFinder(NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)), "permission errors go to Finder")
    let a = URL(fileURLWithPath: "/x/a"), b = URL(fileURLWithPath: "/x/b"), c = URL(fileURLWithPath: "/x/c")
    expect(FinderKeys.remaining([a, b, c], sourceGone: { $0 != b }, arrived: { $0 != c }) == [b, c], "an item counts as moved once gone from its folder and in the new one")
    expect(FinderKeys.position(0, of: 1) == nil && FinderKeys.position(1, of: 3) == "2 of 3", "a move counts items only when there are several")
    expect(FinderBridge.literal("a\"b\\c") == "\"a\\\"b\\\\c\"", "paths are quoted for AppleScript")
    expect(Pref.defaults[Pref.finderCutPasteHUD] as? Bool == true, "the cut panel shows unless turned off")
    let bFile = URL(fileURLWithPath: "/A/b.txt"), cFile = URL(fileURLWithPath: "/C/c.txt"), d = URL(fileURLWithPath: "/C/d.txt")
    expect(FinderKeys.merge([bFile], adding: [cFile, d]) == [bFile, cFile, d], "a second ⌘X adds items from another folder")
    expect(FinderKeys.merge([bFile, cFile], adding: [cFile, URL(fileURLWithPath: "/C/./c.txt")]) == [bFile, cFile], "an item cut twice is moved once")
    let folder = URL(fileURLWithPath: "/C"), inner = URL(fileURLWithPath: "/C/sub/e.txt")
    expect(FinderKeys.merge([folder], adding: [inner]) == [folder] && FinderKeys.merge([cFile, bFile], adding: [folder]) == [bFile, folder],
           "items inside a cut folder go with the folder")
    expect(FinderKeys.merge([URL(fileURLWithPath: "/Cat")], adding: [cFile]).count == 2, "a folder only takes in what is truly inside it")
    expect(Pref.defaults[Pref.finderCutAdds] as? Bool == true, "another ⌘X adds to the cut unless turned off")
    expect(Pref.defaults[Pref.finderCopyAdds] as? Bool == true, "copy accumulation is enabled by default when Finder file shortcuts are on")
    var batch = FinderFileBatch()
    batch.collect([bFile], as: .copy, appending: true)
    batch.clipboardCount = nil
    batch.collect([cFile, d, bFile], as: .copy, appending: true)
    expect(batch.kind == .copy && batch.urls == [bFile, cFile, d], "copies accumulate across folders and clipboard changes")
    batch.finish(.copy, remaining: batch.urls, succeeded: false)
    batch.collect([inner], as: .copy, appending: true)
    expect(batch.urls == [bFile, cFile, d, inner], "a failed paste leaves the current copy batch open")
    batch.finish(.copy, remaining: batch.urls, succeeded: true)
    expect(batch.urls == [bFile, cFile, d, inner], "after pasting, the copy batch remains available for repeated pastes")
    batch.collect([bFile], as: .copy, appending: true)
    expect(batch.urls == [bFile], "the next ⌘C after a successful paste starts a fresh copy batch")
    batch.collect([folder], as: .move, appending: true)
    expect(batch.kind == .move && batch.urls == [folder], "switching from copy to cut starts a new move batch")
    batch.collect([d], as: .copy, appending: true)
    expect(batch.kind == .copy && batch.urls == [d], "switching from cut to copy starts a new copy batch")

}

func testPanelHover(_ expect: (@autoclosure () -> Bool, String) -> Void) {
    typealias R = PanelHoverRules
    expect(R.mayOpen(.init()), "resting on the icon opens the panel")
    for (blocker, name) in [(R.Blockers(enabled: false), "the setting is off"), (R.Blockers(catBusy: true), "a cat is held or under the pointer"),
                            (R.Blockers(buttonDown: true), "a button is down"), (R.Blockers(command: true), "⌘ is down to move the icon"),
                            (R.Blockers(towerMoving: true), "the tidy moves the tower")] {
        expect(!R.mayOpen(blocker), "no panel from resting while \(name)")
    }
    expect(R.openDelay == 0.15 && R.closeDelay == 0.35 && R.switchDelay == 0.06, "open after 0.15 s, close after 0.35 s, change rows after 0.06 s")
    expect(!R.due(nil, 10, R.openDelay) && !R.due(10, 10.14, R.openDelay) && R.due(10, 10.15, R.openDelay), "the wait counts from when it began")
    // A 30 pt icon at the top right of a 1512 x 982 screen with a 37 pt menu bar.
    let screen = NSRect(x: 0, y: 0, width: 1512, height: 945)
    let icon = NSRect(x: 1300, y: 945, width: 30, height: 37)
    let summary = R.summaryFrame(size: NSSize(width: 300, height: 420), icon: icon, screen: screen)
    expect(summary.midX == icon.midX && summary.maxY == icon.minY - R.drop, "the summary hangs centered under the icon")
    let edge = R.summaryFrame(size: NSSize(width: 300, height: 420), icon: NSRect(x: 1490, y: 945, width: 22, height: 37), screen: screen)
    expect(edge.maxX == screen.maxX - R.margin, "near the screen edge the summary stays on screen")
    expect(R.near(NSPoint(x: icon.midX, y: icon.minY - R.drop / 2), icon: icon, panels: [summary]), "the gap between the icon and the summary still counts as on them")
    expect(R.near(NSPoint(x: summary.minX - 10, y: summary.midY), icon: icon, panels: [summary]), "slack around the panel forgives a small slip")
    expect(!R.near(NSPoint(x: summary.minX - 20, y: summary.midY), icon: icon, panels: [summary]), "farther away is away")
    let row = NSRect(x: summary.minX + 18, y: summary.maxY - 120, width: 264, height: 34)
    let detail = R.detailFrame(size: NSSize(width: 340, height: 150), summary: summary, row: row, screen: screen)
    expect(detail.maxX == summary.minX - R.gap && detail.maxY == row.maxY, "details open on the left, level with their row")
    expect(R.near(NSPoint(x: summary.minX - R.gap / 2, y: row.midY), icon: icon, panels: [summary, detail]), "the gap to the side panel still counts as on them")
    let low = NSRect(x: row.minX, y: 40, width: row.width, height: row.height)
    expect(R.detailFrame(size: NSSize(width: 340, height: 150), summary: summary, row: low, screen: screen).minY == screen.minY + R.margin, "a low row's details stay on screen")
    let leftSummary = R.summaryFrame(size: NSSize(width: 300, height: 420), icon: NSRect(x: 200, y: 945, width: 30, height: 37), screen: screen)
    let rightDetail = R.detailFrame(size: NSSize(width: 340, height: 150), summary: leftSummary, row: row, screen: screen)
    expect(rightDetail.minX == leftSummary.maxX + R.gap, "with no room on the left, details open on the right")
}

func testQuitOnClose(_ expect: (@autoclosure () -> Bool, String) -> Void) {
    typealias R = QuitOnCloseRules
    let window = WindowSample(id: 1, pid: 7, layer: 0, onscreen: true, alpha: 1, width: 600, height: 400)
    expect(R.kind(window, app: 7, everything: false) == .shown, "a visible window keeps its app open")
    var off = window; off.onscreen = false
    expect(R.kind(off, app: 7, everything: false) == .ownOffscreen, "an off-screen window needs a closer look")
    var small = window; small.width = 40
    var clear = window; clear.alpha = 0
    expect(R.kind(small, app: 7, everything: true) == .unrelated && R.kind(clear, app: 7, everything: true) == .unrelated, "tiny and transparent windows do not count")
    var toolbar = window; toolbar.pid = 9; toolbar.layer = 3
    expect(R.kind(toolbar, app: 7, everything: false) == .unrelated && R.kind(toolbar, app: 7, everything: true) == .shown,
           "other processes' visible windows count only in the last check before a quit")
    var ownPalette = window; ownPalette.layer = 3
    expect(R.kind(ownPalette, app: 7, everything: false) == .unrelated, "an app's floating palette alone does not mark a window shown")
    expect(R.offscreenKeepsApp(spaces: nil, visible: [1]), "no answer about desktops keeps the app")
    expect(!R.offscreenKeepsApp(spaces: [], visible: [1]), "a window on no desktop is a leftover (TextEdit keeps one)")
    expect(R.offscreenKeepsApp(spaces: [2], visible: [1]), "a window on another desktop keeps the app")
    expect(!R.offscreenKeepsApp(spaces: [1], visible: [1]), "an off-screen window on the desktop in front was only hidden")
    expect(R.offscreenKeepsApp(spaces: [1], visible: nil), "unknown desktops in front keep the app")
    expect(R.standardWindow(fullScreen: false, minimized: false, role: kAXWindowRole, subrole: kAXStandardWindowSubrole)
           && R.standardWindow(fullScreen: true, minimized: false, role: kAXWindowRole, subrole: "AXDialog")
           && R.standardWindow(fullScreen: false, minimized: true, role: kAXWindowRole, subrole: "AXDialog")
           && R.standardWindow(fullScreen: false, minimized: false, role: kAXWindowRole, subrole: nil), "standard, full screen and minimized windows count")
    expect(!R.standardWindow(fullScreen: false, minimized: false, role: kAXWindowRole, subrole: "AXDialog")
           && !R.standardWindow(fullScreen: false, minimized: false, role: kAXSheetRole, subrole: nil), "dialogs and sheets do not")
    expect(R.schedulesCheck(.windowDestroyed, closeRequested: false) && !R.schedulesCheck(.appHidden, closeRequested: false)
           && R.schedulesCheck(.appHidden, closeRequested: true) && !R.schedulesCheck(.other, closeRequested: true),
           "only a window going away, or hiding right after a close click, starts the checks")
    expect(!R.shouldQuit(hadWindows: false, terminated: false, hidden: false, closeRequested: false, minimized: false, userFacingWindow: false),
           "an app that never showed a window stays")
    expect(R.shouldQuit(hadWindows: true, terminated: false, hidden: false, closeRequested: false, minimized: false, userFacingWindow: false),
           "no window left: quit")
    expect(!R.shouldQuit(hadWindows: true, terminated: false, hidden: false, closeRequested: false, minimized: true, userFacingWindow: false)
           && !R.shouldQuit(hadWindows: true, terminated: false, hidden: false, closeRequested: false, minimized: false, userFacingWindow: true),
           "a minimized or open window keeps the app")
    expect(!R.shouldQuit(hadWindows: true, terminated: false, hidden: true, closeRequested: false, minimized: false, userFacingWindow: false)
           && R.shouldQuit(hadWindows: true, terminated: false, hidden: true, closeRequested: true, minimized: false, userFacingWindow: false),
           "a hidden app (⌘H) quits only right after a click on a close button")
    expect(R.checkDelays == [0.35, 1.0, 2.2] && R.confirmDelay == 1.2 && R.windowRereads == [0.5, 1.5, 4.0], "checks after a close, then a confirming one")
    let frame = CGRect(x: 100, y: 100, width: 600, height: 400)
    expect(R.inCloseArea(CGPoint(x: 120, y: 120), of: frame) && !R.inCloseArea(CGPoint(x: 200, y: 120), of: frame), "only the close button's corner is looked at")
    expect(R.onCloseButton(CGPoint(x: 120, y: 120), of: frame) && !R.onCloseButton(CGPoint(x: 140, y: 120), of: frame),
           "by place alone, only the close button's diagonal counts, never the minimize button")
    expect(R.minimized(tags: 1 << 60) && !R.minimized(tags: 1 << 39), "the window server's minimized tag")
    func covered(_ bundle: String, all: Bool = true, picked: Set<String> = [], kept: Set<String> = [], bars: Set<String> = [],
                 policy: NSApplication.ActivationPolicy = .regular, ui: Bool = false, background: Bool = false, url: URL? = nil) -> Bool {
        R.covered(bundle: bundle, url: url, policy: policy, own: "me", uiElement: ui, backgroundOnly: background,
                  scope: QuitScope(all: all, picked: picked, exceptions: kept, menuBarApps: bars), bundleID: { $0.lastPathComponent == "Host.app" ? "com.host" : nil })
    }
    expect(covered("com.apple.TextEdit") && !covered("com.apple.Music", kept: ["com.apple.Music"]), "all apps: everything but the ones kept running")
    expect(covered("com.apple.Preview", all: false, picked: ["com.apple.Preview"]) && !covered("com.apple.TextEdit", all: false, picked: ["com.apple.Preview"]),
           "picked: only the picked apps")
    expect(!covered("com.apple.finder") && !covered("com.apple.mobilephone", all: false, picked: ["com.apple.mobilephone"]) && !covered("me"),
           "Finder, Phone and this app never quit, even when picked")
    expect(!covered("x", policy: .accessory) && !covered("x", background: true) && !covered("x", all: false, picked: ["x"], background: true),
           "apps without a Dock icon and background apps never quit")
    expect(!covered("bar", ui: true) && covered("bar", bars: ["bar"], ui: true), "menu bar apps quit only once allowed")
    expect(!covered("com.host.helper", kept: ["com.host"], url: URL(fileURLWithPath: "/Applications/Host.app/Contents/Helpers/Helper.app")),
           "an app inside a kept app's bundle is kept too")
    expect(!covered("com.parallels.winapp.notepad", kept: ["com.parallels.desktop.console"]), "Windows apps of a kept Parallels are kept")
    expect(!R.pickable(bundle: "com.apple.finder", policy: .regular, own: "me") && !R.pickable(bundle: "me", policy: .regular, own: "me")
           && !R.pickable(bundle: "x", policy: .accessory, own: "me") && R.pickable(bundle: "com.apple.TextEdit", policy: .regular, own: "me"),
           "only regular apps can be listed, never Finder or this app")
    expect(QuitOnClose.flag(NSNumber(value: true)) && QuitOnClose.flag("YES") && !QuitOnClose.flag(nil) && !QuitOnClose.flag("0"), "Info.plist flags read as numbers or text")
    expect(Pref.defaults[Pref.quitOnCloseAll] as? Bool == true
           && (Pref.defaults[Pref.quitOnCloseExceptions] as? [String])?.contains("com.apple.Music") == true
           && R.defaultExceptions.contains("com.apple.mobilephone") && R.defaultExceptions.contains("com.kakao.KakaoTalkMac") && R.defaultExceptions.contains("local.aiilluminati"),
           "quit on close covers all apps, keeping players, calls and messengers running")
    expect(Pref.defaults[Pref.finderCutPaste] as? Bool == false && Pref.defaults[Pref.finderPasteImages] as? Bool == false
           && Pref.defaults[Pref.quitOnClose] as? Bool == false, "Finder shortcuts and quit on close start off")
    expect(SettingsWindowController.tabs.map(\.0) == ["General", "Cats", "Monitor", "Accessibility"], "tabs run General, Cats, Monitor, then Accessibility (scroll and menu bar settings live there)")
    expect(AppPicker.summary(0) == "None" && AppPicker.summary(1) == "1 app" && AppPicker.summary(4) == "4 apps", "app lists show how many are picked")
    expect(ScrollSourcesList.summary(0) == "None yet" && ScrollSourcesList.summary(1) == "1 source" && ScrollSourcesList.summary(3) == "3 sources", "the scroll row counts its sources")
}

/// Fixed GPU states for tests and previews.
func gpuPreviewStates() -> [(String, GPULoad)] {
    [("idle", GPULoad(device: 0.03, renderer: 0.02, tiler: 0.01)), ("busy", GPULoad(device: 0.95, renderer: 0.93, tiler: 0.4)),
     ("device-only", GPULoad(device: 0.42, renderer: nil, tiler: nil))]
}

func testSensors(_ expect: (@autoclosure () -> Bool, String) -> Void) {
    let load = Sensors.gpuLoad(from: ["Device Utilization %": 37, "Renderer Utilization %": 36, "Tiler Utilization %": 5])
    expect(load == GPULoad(device: 0.37, renderer: 0.36, tiler: 0.05), "GPU percentages become shares")
    expect(Sensors.gpuLoad(from: ["Renderer Utilization %": 50]) == nil, "no device share, no GPU reading")
    expect(Sensors.gpuLoad(from: ["Device Utilization %": 140])?.device == 1, "GPU share is capped at 100 %")
    expect(Sensors.gpuLoad(from: ["Device Utilization %": 12])?.renderer == nil, "renderer and tiler are optional")
    expect(Sensors.plausibleWatts(15.7) == 15.7 && Sensors.plausibleWatts(0) == nil && Sensors.plausibleWatts(-3) == nil
           && Sensors.plausibleWatts(.nan) == nil && Sensors.plausibleWatts(800) == nil && Sensors.plausibleWatts(nil) == nil,
           "only 0–500 W counts as a power reading")
    expect(Sensors.systemLoadWatts(["SystemLoad": 17421]) == 17.421 && Sensors.systemLoadWatts([:]) == nil, "battery gauge load is in milliwatts")
    expect(SMC.code("PSTR") == 0x5053_5452 && SMC.floatType == 0x666C_7420, "SMC keys are big-endian four-character codes")
    expect(MemoryLayout<SMC.Message>.stride == 80, "SMC message matches the 80-byte C struct")
    let bits = UInt64(Float(15.5).bitPattern)
    expect(SMC.float(type: SMC.floatType, size: 4, bytes: (bits, 0, 0, 0)) == 15.5, "SMC float values are little-endian")
    expect(SMC.float(type: SMC.code("ui16"), size: 2, bytes: (bits, 0, 0, 0)) == nil, "other SMC types are not read as floats")
    expect(watts(7.42) == "7.4 W" && watts(112.4) == "112 W", "watts read at a glance")
}

func testBatteryTone(_ expect: (@autoclosure () -> Bool, String) -> Void) {
    let tones = Dictionary(uniqueKeysWithValues: batteryPreviewStates().map { ($0.0, (BatteryTone($0.1), BatteryTone.icon($0.1))) })
    expect(tones["charging-52"]! == (.green, "battery.100.bolt"), "charging is green with the bolt")
    expect(tones["battery-50"]! == (.green, "battery.50"), "half charge on battery is green")
    expect(tones["battery-15"]! == (.orange, "battery.25"), "15% on battery is orange")
    expect(tones["battery-8"]! == (.red, "battery.0"), "8% on battery is red")
    expect(tones["low-power-40"]! == (.yellow, "battery.50"), "Low Power Mode is yellow")
    expect(tones["adapter-full"]! == (.green, "battery.100"), "a full battery is green, never the usage meters' orange")
    expect(tones["adapter-low-power-8"]!.0 == .green, "the adapter outranks low charge and Low Power Mode")
    var edge = SystemStats(); edge.hasBattery = true; edge.onAC = false
    edge.batteryLevel = 0.20; expect(BatteryTone(edge) == .orange, "20% is already orange")
    edge.batteryLevel = 0.10; expect(BatteryTone(edge) == .red, "10% is already red")
    edge.batteryLevel = 0.21; edge.lowPowerMode = true; expect(BatteryTone(edge) == .yellow, "Low Power Mode applies above 20%")
    edge.batteryLevel = 0.15; expect(BatteryTone(edge) == .orange, "low charge outranks Low Power Mode")
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
    system.detailed = true
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
    // The summary with a row's section beside it, as when the pointer rests on that row.
    for stat in DashboardStat.allCases {
        let hover = DashboardHover(); hover.detail = stat
        let view = NSHostingView(rootView: HStack(alignment: .top, spacing: PanelHoverRules.gap) {
            DashboardDetailView(system: system, stat: stat).background(Color(nsColor: .windowBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 10))
            DashboardView(model: model, system: system, hover: hover, openSettings: {}, play: {}).background(Color(nsColor: .windowBackgroundColor)).clipShape(RoundedRectangle(cornerRadius: 10))
        }.padding(8))
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        save(view, stat == .cpu ? "dashboard" : "dashboard-\(stat.rawValue)")
    }
    // Hidden menu bar apps in the header: two full rows and a "+N" menu.
    let apps = ["com.apple.Safari", "com.apple.mail", "com.apple.Notes", "com.apple.Music", "com.apple.Maps", "com.apple.Photos", "com.apple.iCal",
                "com.apple.reminders", "com.apple.FaceTime", "com.apple.Preview", "com.apple.TextEdit", "com.apple.calculator", "com.apple.Terminal",
                "com.apple.ActivityMonitor", "com.apple.systempreferences", "com.apple.AppStore"].map { TidyApp(bundle: $0) }
    for (name, count) in [("dashboard-tidy", 16), ("dashboard-tidy-few", 3)] {
        let view = NSHostingView(rootView: DashboardView(model: model, system: system, hover: DashboardHover(), openSettings: {}, play: {}, previewApps: Array(apps.prefix(count)))
            .background(Color(nsColor: .windowBackgroundColor)))
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        save(view, name)
    }
    let batteries = NSHostingView(rootView: VStack(alignment: .leading, spacing: 0) {
        ForEach(batteryPreviewStates(), id: \.0) { name, stats in
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.caption2).foregroundStyle(.secondary)
                BatterySection(stats: stats)
            }.padding(.vertical, 4)
        }
    }.padding(12).frame(width: 300).background(Color(nsColor: .windowBackgroundColor)))
    batteries.frame = NSRect(origin: .zero, size: batteries.fittingSize)
    save(batteries, "dashboard-battery-states")
    let gpus = NSHostingView(rootView: VStack(alignment: .leading, spacing: 0) {
        ForEach(gpuPreviewStates(), id: \.0) { name, load in
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.caption2).foregroundStyle(.secondary)
                GPUSection(gpu: load)
            }.padding(.vertical, 4)
        }
    }.padding(12).frame(width: 380).background(Color(nsColor: .windowBackgroundColor)))
    gpus.frame = NSRect(origin: .zero, size: gpus.fittingSize)
    save(gpus, "dashboard-gpu-states")
    let controller = SettingsWindowController(model: model)
    for (index, tab) in SettingsWindowController.tabs.enumerated() {
        let view = NSHostingView(rootView: controller.view(for: index))
        view.frame = NSRect(origin: .zero, size: SettingsWindowController.size)
        save(view, "settings-\(tab.0)")
    }
    for list in [AppPicker.quitOnClose, .tidy, .scrollSources] {
        let view = NSHostingView(rootView: list.view.frame(width: AppPicker.size.width, height: AppPicker.size.height))
        view.frame = NSRect(origin: .zero, size: AppPicker.size)
        save(view, "settings-apps-\(list.rawValue)")
    }
    // With the CPU wheel on, Your cats shows the wheel cat as a fourth row.
    model.wheelCat = CatAppearance(coat: 3, size: .young)
    if let cats = SettingsWindowController.tabs.firstIndex(where: { $0.0.lowercased() == "cats" }) {
        let view = NSHostingView(rootView: controller.view(for: cats))
        // Tall enough to reach Your cats without scrolling.
        view.frame = NSRect(x: 0, y: 0, width: SettingsWindowController.size.width, height: 1700)
        save(view, "settings-cats-wheel")
    }
    model.wheelCat = nil
    let now = Date()
    var progress = UpdateProgress(at: now.addingTimeInterval(-25))
    progress.move(to: 1, at: now.addingTimeInterval(-20))
    progress.show("Compiling app…", at: now)
    for state in ["building", "waiting", "failed"] {
        progress.waiting = state == "waiting"; progress.failed = state == "failed"
        let preview = NSHostingView(rootView: SettingsPage {
            SettingsCard(title: "Updates") { UpdateProgressBar(progress: progress).padding(10) }
        })
        preview.frame = NSRect(x: 0, y: 0, width: SettingsWindowController.size.width, height: 150)
        save(preview, "settings-update-\(state)")
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
    ("Kitten 64% / Young 82% / Adult 100% · v3 artwork preview / missing coats use orange" as NSString).draw(at: NSPoint(x: 24, y: 608), withAttributes: label)
    for coat in 0..<8 {
        let left = CGFloat(24 + (coat % 4) * 278), base = CGFloat(coat < 4 ? 375 : 135)
        (CatAppearance.names[coat] as NSString).draw(at: NSPoint(x: left, y: base + 178), withAttributes: heading.merging([.font: NSFont.systemFont(ofSize: 15, weight: .semibold)]) { _, new in new })
        for size in CatSize.allCases {
            let x = left + CGFloat(35 + size.rawValue * 84)
            var cat = Cat(x: 0, destination: 0, action: .walking, phase: 1.3, visible: true, coat: coat, size: size)
            cat.velocity = Colony.walkSpeed; cat.gait = 3
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
            ("\(colony.cats[i].size.label) · \(String(format: "%.1f", Colony.walkSpeed * colony.cats[i].size.scale)) pt/s" as NSString).draw(at: NSPoint(x: 24, y: y + 58), withAttributes: label)
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
    ("Shared v3 dangling artwork / spring sway / coat choices preserved" as NSString).draw(at: NSPoint(x: 24, y: 573), withAttributes: label)
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

/// Film strip of the real drawing path (ground fix, turn, transitions): a cat walks right, stops, turns and walks back.
/// Each frame is captured at actual 1x menu bar size and enlarged with hard pixels, with the ground line marked.
func renderScenario(to path: String) {
    _ = NSApplication.shared
    let colony = Colony(count: 1, random: { 0.5 })
    colony.updateLanes([Lane(lower: 0, upper: 300)])
    colony.cats[0].x = 60; colony.cats[0].visible = true; colony.cats[0].hiddenFor = 0
    colony.cats[0].appearance = CatAppearance(coat: 0, size: .adult)
    colony.start(0, .walking, for: 100); colony.cats[0].destination = 150
    let view = HabitatView(colony: colony, frame: NSRect(x: 0, y: 0, width: 300, height: 30))
    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = view
    var shots: [(CGImage, String)] = []
    for tick in 0..<120 {
        if tick == 50 { colony.cats[0].destination = 60 }           // turn back
        colony.step(1.0 / 30)
        Thread.sleep(forTimeInterval: 1.0 / 30)                     // transitions run on real time
        guard tick % 4 == 0 || (50...66).contains(tick) && tick % 2 == 0 else { continue }
        let cat = colony.cats[0]
        let box = NSRect(x: cat.x - 26, y: 0, width: 52, height: 30)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: box) else { continue }
        view.cacheDisplay(in: box, to: rep)
        if let image = rep.cgImage { shots.append((image, "\(tick) \(SpriteAtlas.frameIndex(cat))")) }
    }
    let zoom = 4, cellW = 52 * zoom + 6, cellH = 30 * zoom + 18, columns = 8
    let rows = (shots.count + columns - 1) / columns
    let width = cellW * columns, height = cellH * rows
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSColor(white: 0.16, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
    context.interpolationQuality = .none
    let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.lightGray]
    for (i, shot) in shots.enumerated() {
        let x = (i % columns) * cellW, y = height - (i / columns + 1) * cellH
        let baseline = CGFloat(max(0, floor((30 - 22) / 2))) * CGFloat(zoom)
        context.draw(shot.0, in: CGRect(x: x, y: y + 14, width: 52 * zoom, height: 30 * zoom))
        NSColor(white: 1, alpha: 0.35).setFill(); NSRect(x: CGFloat(x), y: CGFloat(y + 14) + baseline, width: CGFloat(52 * zoom), height: 1).fill()
        NSColor(red: 1, green: 0.4, blue: 0.4, alpha: 0.5).setFill(); NSRect(x: CGFloat(x + 26 * zoom), y: CGFloat(y + 14), width: 1, height: CGFloat(30 * zoom)).fill()
        (shot.1 as NSString).draw(at: NSPoint(x: x + 2, y: y), withAttributes: label)
    }
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    print("Scenario: \(path)")
}

/// Stable and Beta (main) in a throwaway pair of repositories: switching, going back, never downgrading.
/// The fixture "GitHub" commits directly instead of receiving a push, so this also runs where git push is blocked.
func testUpdateChannels(_ expect: (@autoclosure () -> Bool, String) -> Void) {
    expect(UpdateChannel.valid(nil) == "stable" && UpdateChannel.valid("beta") == "stable" && UpdateChannel.valid("main") == "main",
           "unknown update channels fall back to stable")
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("cats-channels-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    let origin = base.appendingPathComponent("origin"), checkout = base.appendingPathComponent("source")
    try! FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
    func run(_ folder: URL, _ arguments: [String]) throws -> String {
        let process = Process(), out = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", folder.path, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid", "-c", "commit.gpgsign=false"] + arguments
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": base.path, "GIT_CONFIG_NOSYSTEM": "1", "GIT_TERMINAL_PROMPT": "0"]
        process.standardOutput = out; process.standardError = out
        try process.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else { throw Updater.Failure(description: "git \(arguments.first ?? ""): \(text)") }
        return text
    }
    func github(_ arguments: String...) -> String { try! run(origin, arguments) }
    func commit(_ text: String) -> String {
        try! text.write(to: origin.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        _ = github("add", "file.txt"); _ = github("commit", "-q", "-m", text)
        return github("rev-parse", "HEAD")
    }
    let git: ChannelStep.Git = { arguments, _ in try run(checkout, arguments) }
    func branch() -> String { try! git(["rev-parse", "--abbrev-ref", "HEAD"], 60) }
    func look(_ channel: String, _ revision: String) -> ChannelStep { try! ChannelStep.look(branch: channel, revision: revision, git: git) }

    _ = github("init", "-q", "-b", "stable")
    let a = commit("A")
    _ = github("branch", "main")
    _ = github("checkout", "-q", "main")
    let b = commit("B")
    _ = try! run(base, ["clone", "-q", "--branch", "stable", "--single-branch", origin.path, checkout.path])

    expect(look("stable", a).outcome == .current, "stable app on stable: up to date")
    // A local build GitHub does not have is never compared, so never "updated" to an older version.
    expect(look("stable", String(repeating: "0", count: 40)).outcome == .localBuild, "an unpushed local build waits instead of installing stable")
    expect(UpdateChannel.proceeds(started: "main", now: "main") && UpdateChannel.proceeds(started: nil, now: "stable")
           && !UpdateChannel.proceeds(started: "main", now: "stable"), "an install stops when the channel changed before the swap")
    let beta = look("main", a)
    expect(beta.outcome == .newer && beta.new == b && beta.switching, "Beta finds main from a single-branch stable checkout")
    try! beta.advance(git)
    expect(branch() == "main" && (try! git(["rev-parse", "HEAD"], 60)) == b, "the checkout follows the chosen channel")
    beta.restore(git)
    expect(branch() == "stable" && (try! git(["rev-parse", "HEAD"], 60)) == a, "failed tests or build put the checkout back")
    try! beta.advance(git)
    expect(look("main", b).outcome == .current, "beta app on main: up to date")
    expect(look("stable", b).outcome == .ahead, "back to Stable never installs an older version")
    _ = github("checkout", "-q", "stable"); _ = github("merge", "-q", "--ff-only", "main")
    let c = commit("C")
    let caught = look("stable", b)
    expect(caught.outcome == .newer && caught.new == c && caught.switching, "Stable updates once it catches up")
    try! caught.advance(git)
    expect(branch() == "stable" && look("stable", c).outcome == .current, "the checkout is back on stable")
    _ = github("checkout", "-q", "main")
    expect(look("main", c).outcome == .ahead, "Beta behind the running app waits too")
    _ = try! git(["checkout", "-q", "-b", "local"], 60)
    expect(look("stable", c).outcome == .otherBranch, "a checkout on another branch is left alone")
}


/// Deterministic times exercise the progress shown in Settings and the dashboard.
func testUpdateProgress(_ expect: (@autoclosure () -> Bool, String) -> Void) {
    let start = Date(timeIntervalSince1970: 1_000)
    var progress = UpdateProgress(at: start)
    expect(progress.remaining(at: start) == nil && progress.fraction(at: start) == nil,
           "the first update does not invent an estimate")
    progress.move(to: 1, at: start.addingTimeInterval(10))
    expect(progress.seconds[0] == 10 && progress.stage == 1, "fetch timing ends at the build")
    expect(progress.quiet(at: start.addingTimeInterval(39)) == nil
           && progress.quiet(at: start.addingTimeInterval(40)) == 30, "quiet output appears after thirty seconds")
    progress.show("Compiling", at: start.addingTimeInterval(41))
    expect(progress.quiet(at: start.addingTimeInterval(42)) == nil, "new output resets the quiet timer")
    progress.estimates = [1: 100, 2: 30, 3: 10]
    expect(progress.remaining(at: start.addingTimeInterval(60)) == 90
           && progress.fraction(at: start.addingTimeInterval(60)) == 0.5, "time left uses previous step durations")
    progress.failed = true
    expect(progress.summary(at: start).contains("Stopped at Build") && progress.fraction(at: start) == 1
           && progress.quiet(at: start.addingTimeInterval(100)) == nil, "failure stays on its step and stops the quiet warning")
    progress.failed = false
    progress.waitForWork(at: start.addingTimeInterval(60), retry: 10)
    expect(progress.summary(at: start.addingTimeInterval(63)).contains("checking again in 7s")
           && progress.line.isEmpty && progress.waiting, "prepared update waits with a live retry countdown")
    expect(progress.summary(at: start.addingTimeInterval(90)).contains("checking again in 0s"),
           "waiting countdown never becomes negative")
    progress.resumeAfterWaiting(at: start.addingTimeInterval(65))
    expect(!progress.waiting && progress.waitNextAt == nil && progress.waitCheckedAt == nil
           && progress.stageStarted == start.addingTimeInterval(65), "resuming clears waiting without repeating completed stages")
    progress.waitForWork(at: start.addingTimeInterval(66), retry: 10)
    progress.move(to: 3, at: start.addingTimeInterval(70))
    expect(progress.skipped == [2] && !progress.waiting && progress.line.isEmpty,
           "reused steps are skipped and the next stage clears old output and waiting")
    progress.move(to: 2, at: start.addingTimeInterval(80))
    expect(progress.stage == 3, "stages never move backward")
    expect(UpdateProgress.lastLine(Data("\u{1B}[31mfirst\nlast\u{1B}[0m\n".utf8)) == "last",
           "the latest output strips terminal colors")
    expect(UpdateProgress.lastLine(Data("\n \n".utf8)) == nil, "blank output has no line")
}

/// The CPU wheel's pace, from fixed CPU values only (nothing reads the real CPU or preferences).
func testWheel(_ expect: (@autoclosure () -> Bool, String) -> Void) {
    func settled(_ cpu: Double) -> WheelPace { var pace = WheelPace(); for _ in 0..<12 { pace.update(cpu: cpu) }; return pace }
    expect(settled(0.01).gait == .rest && settled(0.12).gait == .walk && settled(0.6).gait == .run, "wheel: nap, walk, run by CPU")
    var pace = settled(0.6); for _ in 0..<12 { pace.update(cpu: 0.19) }
    expect(pace.gait == .run, "wheel: just under the run threshold keeps running (no flicker)")
    for _ in 0..<12 { pace.update(cpu: 0.1) }
    expect(pace.gait == .walk, "wheel: well under it slows to a walk")
    var spike = settled(0.01); spike.update(cpu: 0.9)
    expect(spike.cpu < 0.9, "wheel: one sample is averaged, not jumped to")
    expect(settled(0.25).motion().frameRate < settled(1).motion().frameRate, "wheel: busier runs faster")
    for step in 0...100 {
        for lowPower in [false, true] {
            let motion = settled(Double(step) / 100).motion(lowPower: lowPower)
            expect(motion.frameRate <= (lowPower ? WheelPace.lowPowerFPS : 24), "wheel: frame rate cap \(motion)")
            // 12 teeth are 30° apart: under 15° a frame the wheel never seems to turn backwards; ≤180°/s overall.
            expect(motion.frameRate == 0 ? motion.degreesPerSecond == 0 : motion.degreesPerSecond / motion.frameRate < 15 && motion.degreesPerSecond <= 180,
                   "wheel: teeth turn forward \(motion)")
        }
    }
    expect(TowerIcon.menuBar(wheel: 0).size == TowerIcon.wheelSize && TowerIcon.menuBar().size == NSSize(width: 18, height: 18), "wheel widens the icon only when on")
    for gait in [WheelPace.Gait.rest, .walk, .run] {
        expect((0..<8).allSatisfy { coat in (0..<20).allSatisfy { (0..<SpriteAtlas.frameCount).contains(WheelOverlayView.cell(gait, step: $0, coat: coat)) } },
               "wheel cat cells exist for \(gait) in every coat")
    }
    // Layout: wheel 0-20 pt, 2 pt gap, tower 22-40 pt; the teeth stay inside the image and left of the tower.
    let reach = TowerIcon.wheelOuter + TowerIcon.wheelTooth, c = TowerIcon.wheelCenter
    expect(TowerIcon.towerOffset + 18 == TowerIcon.wheelSize.width, "wheel layout: tower fills the right 18 pt")
    expect(c.x - reach >= 0 && c.x + reach <= TowerIcon.towerOffset - 2 && c.y - reach >= 0 && c.y + reach <= TowerIcon.wheelSize.height,
           "wheel layout: wheel with teeth fits its 20 pt square")
    expect(TowerIcon.wheelInner * 2 >= 14, "wheel layout: 14 pt inside the band for the cat")
    expect(TowerIcon.towerCenterX(in: NSRect(x: 100, y: 0, width: 40, height: 24), wheel: true) == 131
           && TowerIcon.towerCenterX(in: NSRect(x: 100, y: 0, width: 48, height: 24), wheel: true) == 135
           && TowerIcon.towerCenterX(in: NSRect(x: 100, y: 0, width: 26, height: 24), wheel: false) == 113,
           "wheel layout: towerX is the tower's center, with and without the wheel")
    // The cats walk home to a spot that is really ink of the tower (its post), with clear space between wheel and tower.
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 40, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    TowerIcon.menuBar(wheel: 7).draw(in: NSRect(x: 0, y: 0, width: 80, height: 40))
    NSGraphicsContext.restoreGraphicsState()
    func ink(_ x: CGFloat, _ y: CGFloat) -> Bool { (rep.colorAt(x: Int(x * 2), y: 39 - Int(y * 2))?.alphaComponent ?? 0) > 0.5 }
    let home = TowerIcon.towerCenterX(in: NSRect(x: 0, y: 0, width: 40, height: 20), wheel: true)
    expect(ink(home, 6) && ink(home, 2), "wheel layout: home spot is on the tower's post and base")
    expect((0..<40).allSatisfy { !ink(20.75, CGFloat($0) / 2) && !ink(21.25, CGFloat($0) / 2) }, "wheel layout: gap between wheel and tower")
    expect(ink(c.x, c.y + 8) && !ink(c.x, c.y + 6) && !ink(c.x + 5, c.y), "wheel layout: solid band with open inside")
    testWheelBattery(expect)
    // Taking turns: never the same cat twice in a row, a cat that is out playing only when all are out.
    let rolls = stride(from: 0.0, to: 1.0, by: 0.05)
    expect(rolls.allSatisfy { WheelOverlayView.nextCoat(after: 3, outside: [], roll: $0) != 3 }, "wheel: the next cat is a different one")
    expect(rolls.allSatisfy { ![0, 1, 2].contains(WheelOverlayView.nextCoat(after: 0, outside: [1, 2], roll: $0)) }, "wheel: skips cats that are out playing")
    expect(rolls.allSatisfy { WheelOverlayView.nextCoat(after: 0, outside: Set(0..<8), roll: $0) != 0 }, "wheel: everyone out still swaps")
    expect(Set(rolls.map { WheelOverlayView.nextCoat(after: 0, outside: [], roll: $0) }) == Set(1..<8), "wheel: every other cat gets a turn")
    // When: a random wait inside the preset range, the ends at roll 0 and 1, Off never swaps.
    let bounds: [Int: ClosedRange<Double>] = [1: 120...360, 2: 300...900, 3: 900...1800]
    expect(bounds.allSatisfy { range, b in rolls.allSatisfy { WheelShift.interval(range: range, roll: $0).map(b.contains) == true } }, "wheel turns: wait inside the range")
    expect(bounds.allSatisfy { WheelShift.interval(range: $0, roll: 0) == $1.lowerBound && WheelShift.interval(range: $0, roll: 1) == $1.upperBound }, "wheel turns: roll 0 and 1 hit the ends")
    expect(WheelShift.interval(range: 2, roll: -1) == 300 && WheelShift.interval(range: 2, roll: 2) == 900, "wheel turns: roll is clamped")
    expect(WheelShift.interval(range: 0, roll: 0.5) == nil && WheelShift.interval(range: 9, roll: 0.5) == nil, "wheel turns: Off (and unknown) never swaps")
    expect([0.0: 0, -1: 0, 5: 1, 15: 2, 30: 3, 3: 1, 10: 2, 60: 3].allSatisfy { WheelShift.preset(forMinutes: $0) == $1 }, "wheel turns: old interval to nearest preset")
    // Migration on a throwaway defaults suite, never the app's own.
    let suite = "CatsInMenubar.selftest.wheelShift"
    if let test = UserDefaults(suiteName: suite) {
        test.removePersistentDomain(forName: suite)
        test.register(defaults: [Pref.wheelSwapRange: WheelShift.defaultRange])   // as in the app: defaults first
        test.set(30.0, forKey: Pref.wheelSwap); WheelShift.migrate(test, domain: suite)
        let thirty = test.object(forKey: Pref.wheelSwapRange) as? Int, gone = test.object(forKey: Pref.wheelSwap) == nil
        test.set(0.0, forKey: Pref.wheelSwap); test.removeObject(forKey: Pref.wheelSwapRange); WheelShift.migrate(test, domain: suite)
        let off = test.object(forKey: Pref.wheelSwapRange) as? Int
        test.set(5.0, forKey: Pref.wheelSwap); test.set(2, forKey: Pref.wheelSwapRange); WheelShift.migrate(test, domain: suite)
        let kept = test.integer(forKey: Pref.wheelSwapRange)
        test.removeObject(forKey: Pref.wheelSwapRange); WheelShift.migrate(test, domain: suite)
        let fresh = test.persistentDomain(forName: suite)?[Pref.wheelSwapRange] == nil
        test.removePersistentDomain(forName: suite)
        expect(thirty == 3 && gone && off == 0 && kept == 2 && fresh, "wheel turns: wheelSwap migrates once over registered defaults, 0 to Off, new choice kept")
    } else { expect(false, "wheel turns: test defaults suite") }
}

/// The wheel's battery gauge: share and angle, the 20 % color line, Mono, and the plain band when off or
/// without a battery. Pixels are checked at 8x on the template image and on the colored overlay separately.
func testWheelBattery(_ expect: (@autoclosure () -> Bool, String) -> Void) {
    func gauge(_ level: Double, mono: Bool = false) -> WheelBattery { .gauge(hasBattery: true, level: level, enabled: true, mono: mono) }
    expect(gauge(0.5).degrees == 180 && gauge(0.25).degrees == 90 && gauge(1).degrees == 360 && gauge(0).degrees == 0, "battery ring: level to arc degrees")
    expect(gauge(0.734).percent == 73 && gauge(0.736).percent == 74 && gauge(1.2).percent == 100 && gauge(-1).percent == 0, "battery ring: whole percent, clamped")
    expect(gauge(0.734) == gauge(0.7349), "battery ring: under 1 % is no change (no redraw)")
    expect(TowerIcon.gaugeEnd(share: 0) == 90 && TowerIcon.gaugeEnd(share: 0.25) == 0 && TowerIcon.gaugeEnd(share: 0.5) == -90, "battery ring: fills clockwise from 12 o'clock")
    expect(gauge(0.21).ink == .green && gauge(0.20).ink == .red && gauge(0.204).ink == .green && gauge(0.199).ink == .red && gauge(0.206).ink == .green && gauge(0.05).ink == .red,
           "battery ring: green above 20 %, red at 20 % or less")
    expect(gauge(0.8, mono: true).ink == .template && gauge(0.2, mono: true).ink == .red && gauge(0.204, mono: true).ink == .template && gauge(0.1, mono: true).ink == .red, "battery ring: Mono replaces green only")
    expect(gauge(0.8).color == .systemGreen && gauge(0.1).color == .systemRed && gauge(0.8, mono: true).color == nil, "battery ring: overlay colors")
    expect(gauge(0.5).rims && gauge(1).rims && gauge(0).rims, "battery ring: every gauge has rims all around")
    expect(WheelBattery.gauge(hasBattery: false, level: 0.1, enabled: true, mono: false) == .plain
           && WheelBattery.gauge(hasBattery: true, level: 0.1, enabled: false, mono: true) == .plain, "battery ring: off or no battery is the plain band")
    expect(WheelBattery.plain.share == 1 && WheelBattery.plain.ink == .template && !WheelBattery.plain.rims, "battery ring: plain is the whole template band")
    // Pixels: probe the band's middle (r 8) and a rim (r 8.8) at 3 o'clock (25 % along) and 9 o'clock (75 % along).
    let scale: CGFloat = 8, c = TowerIcon.wheelCenter
    func render(_ draw: () -> Void) -> NSBitmapImageRep {
        let size = TowerIcon.wheelSize
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let t = NSAffineTransform(); t.scale(by: scale); t.concat()
        draw()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }
    func color(_ rep: NSBitmapImageRep, _ x: CGFloat, _ y: CGFloat) -> NSColor? {
        let color = rep.colorAt(x: Int(x * scale), y: rep.pixelsHigh - 1 - Int(y * scale))
        return (color?.alphaComponent ?? 0) > 0.5 ? color : nil
    }
    // Teeth drawn at 15° sit at 15 + 30k ± 5°, clear of the probes at 0° and 180°, and start outside r 8.8.
    let right = (c.x + 8, c.y), left = (c.x - 8, c.y), leftRim = (c.x - 8.8, c.y), innerRim = (c.x - 7.2, c.y)
    let template = { (battery: WheelBattery) in render { NSColor.black.set(); TowerIcon.drawWheel(angle: 15, battery: battery) } }
    let overlay = { (battery: WheelBattery) in render { WheelOverlayView.draw(battery: battery) } }
    let plain = template(.plain)
    expect(color(plain, right.0, right.1) != nil && color(plain, left.0, left.1) != nil, "battery ring: plain band is solid all around")
    let mono = template(gauge(0.5, mono: true))
    expect(color(mono, right.0, right.1) != nil && color(mono, left.0, left.1) == nil, "battery ring: Mono 50 % fills the right half in the template")
    expect(color(mono, leftRim.0, leftRim.1) != nil && color(mono, innerRim.0, innerRim.1) != nil, "battery ring: empty half keeps thin rims")
    let green = template(gauge(0.5))
    expect(color(green, right.0, right.1) == nil && color(green, left.0, left.1) == nil && color(green, leftRim.0, leftRim.1) != nil,
           "battery ring: a colored share leaves the template with rims only")
    let rightRim = (c.x + 8.8, c.y), rightInner = (c.x + 7.2, c.y)
    expect(color(green, rightRim.0, rightRim.1) != nil && color(green, rightInner.0, rightInner.1) != nil, "battery ring: rims also run past the filled share")
    expect(color(mono, rightRim.0, rightRim.1) != nil && color(mono, right.0, right.1) != nil, "battery ring: Mono share fills between its rims")
    let full = template(gauge(1))
    expect(color(full, leftRim.0, leftRim.1) != nil && color(full, left.0, left.1) == nil, "battery ring: a full colored gauge keeps its rims")
    let colored = overlay(gauge(0.5))
    if let ink = color(colored, right.0, right.1)?.usingColorSpace(.deviceRGB) {
        expect(ink.greenComponent > ink.redComponent + 0.3 && color(colored, left.0, left.1) == nil, "battery ring: overlay paints green on the filled half only")
        expect(color(colored, rightRim.0, rightRim.1) == nil && color(colored, rightInner.0, rightInner.1) == nil, "battery ring: green sits between the rims, not over them")
    } else { expect(false, "battery ring: overlay paints the filled half") }
    let low = overlay(gauge(0.15))
    let lowEdge = (c.x + 8 * cos(.pi / 2 - 0.25), c.y + 8 * sin(.pi / 2 - 0.25))   // ~14° past 12 o'clock, inside 15 %
    if let ink = color(low, lowEdge.0, lowEdge.1)?.usingColorSpace(.deviceRGB) {
        expect(ink.redComponent > ink.greenComponent + 0.3 && color(low, right.0, right.1) == nil, "battery ring: 15 % is a short red arc")
    } else { expect(false, "battery ring: 15 % arc is drawn") }
    expect(color(overlay(.plain), right.0, right.1) == nil && color(overlay(gauge(0.8, mono: true)), right.0, right.1) == nil, "battery ring: overlay is empty for plain and Mono green")
}

/// Wheel + tower at each pace on dark and light menu bars, enlarged and at actual Retina size, for both
/// tooth heights. The actual-size strips step the wheel 9° per slot, so the turning direction reads left to right.
func renderWheel(to path: String) {
    _ = NSApplication.shared
    let width = 1100, height = 900
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
    let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.darkGray]
    func icon(cats: Int, angle: Double, gait: WheelPace.Gait, step: Int, coat: Int = 0, tooth: CGFloat, at origin: NSPoint, scale: CGFloat, ink: NSColor) {
        let image = TowerIcon.menuBar(cats: cats, wheel: angle, tooth: tooth)
        let tinted = NSImage(size: image.size, flipped: false) { rect in image.draw(in: rect); ink.set(); rect.fill(using: .sourceAtop); return true }
        tinted.draw(in: NSRect(x: origin.x, y: origin.y, width: image.size.width * scale, height: image.size.height * scale))
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform(); transform.translateX(by: origin.x, yBy: origin.y); transform.scale(by: scale); transform.concat()
        WheelOverlayView.draw(cell: WheelOverlayView.cell(gait, step: step, coat: coat), coat: coat)
        NSGraphicsContext.restoreGraphicsState()
    }
    let states: [(String, WheelPace.Gait, Int, Double, Int)] = [("CPU 2% · nap", .rest, 0, 0, 0), ("CPU 12% · walk", .walk, 3, -20, 0),
        ("CPU 60% · run", .run, 1, -45, 1), ("CPU 95% · run", .run, 5, -75, 3)]
    for (row, (bar, ink)) in [(NSColor(calibratedWhite: 0.13, alpha: 1), NSColor(calibratedWhite: 0.95, alpha: 1)),
                              (NSColor(calibratedWhite: 0.9, alpha: 1), NSColor(calibratedWhite: 0.1, alpha: 1))].enumerated() {
        let y = CGFloat(710 - row * 420)
        for (i, (name, gait, step, angle, cats)) in states.enumerated() {
            let x = CGFloat(20 + i * 270)
            bar.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 250, height: 150), xRadius: 10, yRadius: 10).fill()
            icon(cats: cats, angle: angle, gait: gait, step: step, tooth: TowerIcon.wheelTooth, at: NSPoint(x: x + 15, y: y + 20), scale: 5.5, ink: ink)
            (name as NSString).draw(at: NSPoint(x: x + 6, y: y - 20), withAttributes: label)
        }
        // Actual size on a 2x screen: 1 pt = 2 px, menu bar 24 pt = 48 px.
        for (k, tooth) in ([0.75, 1.0] as [CGFloat]).enumerated() {
            let barY = y - 90 - CGFloat(k) * 70
            bar.setFill(); NSRect(x: 20, y: barY, width: 1060, height: 48).fill()
            ("teeth \(tooth) pt · actual size 2x · 9° per slot →" as NSString).draw(at: NSPoint(x: 24, y: barY - 18), withAttributes: label)
            for i in 0..<8 {
                let gait: WheelPace.Gait = i < 2 ? .rest : i < 4 ? .walk : .run
                // Each slot shows a different coat taking its turn.
                icon(cats: i % 4, angle: Double(-i * 9), gait: gait, step: i, coat: i, tooth: tooth, at: NSPoint(x: CGFloat(40 + i * 130), y: barY + 4), scale: 2, ink: ink)
            }
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("Wheel preview: \(path)")
    renderWheelBattery(to: (path as NSString).deletingPathExtension + "-battery.png")
    renderFaceWheel(to: (path as NSString).deletingPathExtension + "-face.png")
}

/// The wheel streamed to the AI Face board: real streamed pictures decoded back from RGB565 and cut to the
/// round screen, for resting, walking and running cats and battery states.
func renderFaceWheel(to path: String) {
    let states: [(String, WheelPace.Gait, Int, Double, Int, WheelBattery)] = [
        ("nap", .rest, 0, 0, 0, .plain), ("walk", .walk, 3, -20, 1, .gauge(hasBattery: true, level: 0.65, enabled: true, mono: false)),
        ("run", .run, 1, -45, 5, .gauge(hasBattery: true, level: 0.15, enabled: true, mono: false)),
        ("run · Mono", .run, 5, -75, 7, .gauge(hasBattery: true, level: 0.5, enabled: true, mono: true))]
    let size = WheelScene.size, gap = 20, width = states.count * (size + gap) + gap, height = size + 60
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor(calibratedWhite: 0.55, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
    let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.white]
    for (i, (name, gait, step, angle, coat, battery)) in states.enumerated() {
        let data = WheelScene.frame(angle: angle, cell: WheelOverlayView.cell(gait, step: step, coat: coat), coat: coat, battery: battery)
        var rgba = [UInt8](repeating: 255, count: size * size * 4)
        for p in 0..<size * size {
            let v = UInt16(data[p * 2]) | UInt16(data[p * 2 + 1]) << 8
            rgba[p * 4] = UInt8((v >> 11) << 3); rgba[p * 4 + 1] = UInt8(((v >> 5) & 63) << 2); rgba[p * 4 + 2] = UInt8((v & 31) << 3)
        }
        let image = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: CGDataProvider(data: Data(rgba) as CFData)!,
                            decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        let rect = NSRect(x: gap + i * (size + gap), y: 40, width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(ovalIn: rect).addClip()
        NSImage(cgImage: image, size: rect.size).draw(in: rect)
        NSGraphicsContext.restoreGraphicsState()
        (name as NSString).draw(at: NSPoint(x: rect.minX + 6, y: 12), withAttributes: label)
    }
    NSGraphicsContext.restoreGraphicsState()
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("AI Face wheel preview: \(path)")
}

/// The board picture's format and the AI Face client, against a stand-in for AI Face (no network, no real
/// controller.json).
func testFaceStream(_ expect: (@autoclosure () -> Bool, String) -> Void) {
    _ = NSApplication.shared
    // Pixel format: RGB565 little-endian, low byte first.
    expect(WheelScene.rgb565([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255]) == Data([0x00, 0xF8, 0xE0, 0x07, 0x1F, 0x00, 0xFF, 0xFF]),
           "red, green, blue and white pack as RGB565 little-endian")
    let rest = WheelScene.frame(angle: 0, cell: WheelOverlayView.cell(.rest, step: 0, coat: 0), coat: 0, battery: .plain)
    expect(rest.count == 115_200, "a board picture is 240 x 240 x 2 bytes")
    expect(rest == WheelScene.frame(angle: 0, cell: WheelOverlayView.cell(.rest, step: 0, coat: 0), coat: 0, battery: .plain), "the same wheel draws the same picture")
    func pixel(_ data: Data, _ x: Int, _ y: Int) -> UInt16 { UInt16(data[(y * 240 + x) * 2]) | UInt16(data[(y * 240 + x) * 2 + 1]) << 8 }
    let rgba = WheelScene.rgba(angle: 0, cell: 0, coat: 0, battery: .plain)
    let background = WheelScene.rgb565(Array(rgba[0..<4]))
    expect(pixel(rest, 0, 0) == UInt16(background[0]) | UInt16(background[1]) << 8, "corners show the background")
    // Rows go top to bottom: the cat sits low in the wheel, the panel above it is bare, nothing above the teeth.
    expect(pixel(rest, 120, 6) == pixel(rest, 0, 0), "the top edge above the teeth is background")
    let panel = WheelScene.rgb565(Array(WheelScene.rgba(angle: 0, cell: 0, coat: 0, battery: .plain)[(60 * 240 + 120) * 4..<(60 * 240 + 120) * 4 + 4]))
    expect(pixel(rest, 120, 60) != pixel(rest, 0, 0) && pixel(rest, 120, 60) == UInt16(panel[0]) | UInt16(panel[1]) << 8,
           "the wheel's back panel is lighter than the background, so a black cat shows")
    expect(pixel(rest, 120, 175) != pixel(rest, 120, 60), "the resting cat sits in the lower half (rows top to bottom)")
    expect(pixel(rest, 120, 0) == pixel(rest, 120, 239), "no stand cut off at the bottom of the round screen")
    expect(pixel(rest, 120, 120 - 92) != pixel(rest, 0, 0), "the band crosses the top of the wheel")
    expect(WheelScene.frame(angle: -15, cell: WheelOverlayView.cell(.rest, step: 0, coat: 0), coat: 0, battery: .plain) != rest, "turned teeth change the picture")
    let low = WheelScene.frame(angle: 0, cell: 0, coat: 0, battery: .gauge(hasBattery: true, level: 0.1, enabled: true, mono: false))
    let full = WheelScene.frame(angle: 0, cell: 0, coat: 0, battery: .gauge(hasBattery: true, level: 1, enabled: true, mono: false))
    expect(pixel(low, 120 + 92, 120) != pixel(full, 120 + 92, 120), "a low battery shows red where a full one is green")
    // Board pace: never more than 12 pictures a second, and never a turn that looks backwards.
    for i in 0...100 {
        var pace = WheelPace()
        for _ in 0..<6 { pace.update(cpu: Double(i) / 100) }
        let m = pace.motion(maxFrameRate: FaceStream.maxFPS)
        expect(m.frameRate <= FaceStream.maxFPS, "board frames stay at 12 a second or fewer")
        expect(m.frameRate == 0 ? m.degreesPerSecond == 0 : m.degreesPerSecond / m.frameRate < 15, "a board frame turns the teeth under half a tooth gap")
        expect(pace.motion(lowPower: true) == pace.motion(maxFrameRate: WheelPace.lowPowerFPS), "Low Power Mode keeps its 12 fps cap")
        expect(pace.motion() == pace.motion(maxFrameRate: .infinity), "uncapped motion is unchanged")
    }
    expect(FaceStream.maxTurn < 15, "a slow board's frame turns at most \(FaceStream.maxTurn)°")

    // The client against a stand-in AI Face.
    struct Call { var method: String; var path: String; var bytes: Int; var session: String? }
    var calls: [Call] = [], replies: [String: (Int, [String: Any])] = [:]
    var now = 100.0, pending: [() -> Void] = []
    let face = FaceStream()
    var input = FaceStream.Input(gait: .run, motion: WheelPace.Motion(frameRate: 12, degreesPerSecond: 90), coat: 0, battery: .plain)
    face.source = { input }
    var changes: [FaceStream.State] = []
    face.changed = { changes.append(face.state) }
    face.clock = { now }
    face.schedule = { _, work in pending.append(work); return nil }
    var endpoint: FaceStream.Endpoint? = nil
    face.locate = { endpoint }
    face.transport = { _, method, path, body, session, _, done in
        calls.append(Call(method: method, path: path, bytes: body.count, session: session))
        let reply = replies[path] ?? (200, ["streaming": true])
        done(reply.0, reply.1)
    }
    func runPending() { let work = pending; pending = []; work.forEach { $0() } }

    face.update(enabled: true, available: true)
    expect(face.state == .waiting("AI Face isn't running.") && calls.isEmpty, "no controller.json: waits for AI Face without a request")
    endpoint = FaceStream.Endpoint(port: 5000, token: "t")
    replies["stream/start"] = (409, ["busy_by": "Movie app"])
    runPending()
    expect(face.state == .waiting("Movie app is using the board."), "a busy board names the app using it")
    replies["stream/start"] = (200, ["session": "s1", "streaming": true])
    runPending()
    expect(face.state == .streaming, "a free board streams")
    expect(changes == [.connecting, .waiting("AI Face isn't running."), .waiting("Movie app is using the board."), .streaming], "each state change is reported once (the menu bar follows it)")
    expect(calls.last?.path == "stream/frame" && calls.last?.bytes == 115_200 && calls.last?.session == "s1", "the first picture goes whole with the session")
    let framesBefore = face.framesSent
    for _ in 0..<5 { now += 1 / 12; runPending() }
    expect(face.framesSent == framesBefore + 5, "a running wheel sends a picture each step")
    // A resting cat: the same picture is not sent again, only a keepalive about once a second.
    input = FaceStream.Input(gait: .rest, motion: WheelPace.Motion(frameRate: 0, degreesPerSecond: 0), coat: 0, battery: .plain)
    now += 0.25; runPending()
    let resting = face.framesSent
    let callsBefore = calls.count
    for _ in 0..<3 { now += 0.25; runPending() }
    expect(face.framesSent == resting && calls.count == callsBefore, "a still picture is not sent again")
    now += 0.5; runPending()
    expect(calls.last?.path == "stream/keepalive" && face.framesSent == resting, "a resting wheel renews the lease with a keepalive")
    // A swipe on the board: the stream ends and stays off.
    input.gait = .walk; input.motion = WheelPace.Motion(frameRate: 8, degreesPerSecond: 30)
    replies["stream/frame"] = (200, ["streaming": false]); replies["stream/info"] = (200, ["board": true])
    now += 0.1; runPending()
    expect(face.state == .left, "a swipe on the board ends the stream")
    let afterSwipe = calls.count
    face.update(enabled: true, available: true); runPending()
    expect(face.state == .left && calls.count == afterSwipe, "after a swipe the wheel does not take the board back by itself")
    face.update(enabled: false, available: true)
    expect(face.state == .off, "switching off clears it")
    replies["stream/frame"] = nil
    face.update(enabled: true, available: true)
    expect(face.state == .streaming, "switching on again streams again")
    // An unplugged board comes back by itself.
    replies["stream/frame"] = (200, ["streaming": false]); replies["stream/info"] = (200, ["board": false])
    now += 0.2; runPending()
    expect(face.state == .waiting("Connect the AI Face board."), "an unplugged board is waited for")
    replies["stream/frame"] = nil; replies["stream/info"] = nil
    runPending()
    expect(face.state == .streaming, "the board plugged in again streams again")
    // Sleep or the wheel turned off gives the board back.
    face.update(enabled: true, available: false)
    expect(face.state == .off && calls.last?.path == "stream/stop" && calls.last?.session != nil, "stopping hands the board back to AI Face")
    let stopped = calls.count
    runPending()
    expect(calls.count == stopped, "nothing more is sent after stopping")
    // AI Face restarted (new token): read controller.json again.
    var located = 0
    face.locate = { located += 1; return endpoint }
    replies["stream/start"] = (403, [:])
    face.update(enabled: true, available: true)
    expect(face.state == .waiting("AI Face restarted.") && located == 0, "a refused token waits for AI Face's new one")
    replies["stream/start"] = (200, ["session": "s2", "streaming": true])
    runPending()
    expect(face.state == .streaming && located == 1 && calls.last?.session == "s2", "the new port and token are read again")
    face.update(enabled: false, available: true)
}

/// The battery ring at 100/50/20/10/5 % in color and Mono on dark and light menu bars, enlarged, and a
/// row at actual Retina size. The last column is a Mac without a battery (plain band).
func renderWheelBattery(to path: String) {
    let width = 1240, height = 760
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill()
    let label: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.darkGray]
    let levels = [1.0, 0.5, 0.2, 0.1, 0.05]
    func battery(_ i: Int, mono: Bool) -> WheelBattery {
        i < levels.count ? .gauge(hasBattery: true, level: levels[i], enabled: true, mono: mono) : .gauge(hasBattery: false, level: 0, enabled: true, mono: mono)
    }
    func icon(_ battery: WheelBattery, step: Int, coat: Int, at origin: NSPoint, scale: CGFloat, ink: NSColor, dark: Bool) {
        let image = TowerIcon.menuBar(cats: 1, wheel: Double(-step * 9), battery: battery)
        let tinted = NSImage(size: image.size, flipped: false) { rect in image.draw(in: rect); ink.set(); rect.fill(using: .sourceAtop); return true }
        tinted.draw(in: NSRect(x: origin.x, y: origin.y, width: image.size.width * scale, height: image.size.height * scale))
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform(); transform.translateX(by: origin.x, yBy: origin.y); transform.scale(by: scale); transform.concat()
        // The overlay's system colors resolve against the menu bar's appearance, as in the real button.
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            WheelOverlayView.draw(battery: battery)
        }
        WheelOverlayView.draw(cell: WheelOverlayView.cell(.run, step: step, coat: coat), coat: coat)
        NSGraphicsContext.restoreGraphicsState()
    }
    let bars: [(String, NSColor, NSColor, Bool)] = [("dark", NSColor(calibratedWhite: 0.13, alpha: 1), NSColor(calibratedWhite: 0.95, alpha: 1), true),
                                                   ("light", NSColor(calibratedWhite: 0.9, alpha: 1), NSColor(calibratedWhite: 0.1, alpha: 1), false)]
    var y = CGFloat(height - 150)
    for (barName, bar, ink, dark) in bars {
        for mono in [false, true] {
            ("\(barName) · \(mono ? "Mono" : "color")" as NSString).draw(at: NSPoint(x: 20, y: y + 112), withAttributes: label)
            for i in 0...levels.count {
                let x = CGFloat(20 + i * 200)
                bar.setFill(); NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 185, height: 108), xRadius: 8, yRadius: 8).fill()
                icon(battery(i, mono: mono), step: i, coat: i, at: NSPoint(x: x + 12, y: y + 9), scale: 4, ink: ink, dark: dark)
                let name = i < levels.count ? "\(Int(levels[i] * 100)) %" : "no battery"
                let small: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: ink]
                (name as NSString).draw(at: NSPoint(x: x + 177 - (name as NSString).size(withAttributes: small).width, y: y + 88), withAttributes: small)
            }
            y -= 135
        }
    }
    // Actual size on a 2x screen: 1 pt = 2 px, menu bar 24 pt = 48 px.
    for (barName, bar, ink, dark) in bars {
        bar.setFill(); NSRect(x: 20, y: y + 60, width: 1200, height: 48).fill()
        ("\(barName) · actual size 2x · color 100…5 %, no battery | Mono 100…5 %, no battery" as NSString).draw(at: NSPoint(x: 24, y: y + 40), withAttributes: label)
        for mono in [false, true] {
            for i in 0...levels.count {
                icon(battery(i, mono: mono), step: i, coat: i, at: NSPoint(x: CGFloat(40 + (mono ? 600 : 0) + i * 95), y: y + 64), scale: 2, ink: ink, dark: dark)
            }
        }
        y -= 80
    }
    NSGraphicsContext.restoreGraphicsState()
    try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("Wheel battery preview: \(path)")
}

/// The wheel cat as one of the colony, and the baton pass in front of the wheel. Colony only, with a seeded
/// random source: nothing reads or writes the app's preferences.
func testWheelBaton(_ expect: (@autoclosure () -> Bool, String) -> Void) {
    var seed: UInt64 = 42
    func make(_ count: Int = 3) -> Colony {
        let c = Colony(count: count, random: { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(UInt64(1) << 53) })
        c.updateLanes([Lane(lower: 0, upper: 600)]); c.homeX = 700; c.wheelX = 680
        c.enableWheel(nil)
        for _ in 0..<60 { c.step(1.0 / 30) }
        return c
    }
    func run(_ c: Colony, seconds: Double, until done: () -> Bool = { false }) {
        for _ in 0..<Int(seconds * 30) { c.step(1.0 / 30); if done() { return } }
    }
    let c = make()
    expect(c.population == 4 && c.takenCoats.count == 4, "wheel: 3 cats out + 1 in the wheel, four different coats: \(c.takenCoats)")
    let two = make(2); two.setCount(3)
    expect(two.population == 4 && two.takenCoats.count == 4, "wheel: a third cat added never wears the wheel coat")
    let worn = make(); worn.enableWheel(worn.cats[1].appearance)
    expect(worn.takenCoats.count == 4, "wheel: a saved wheel cat whose coat is out now becomes another cat")
    let pick = make(); var clean = true
    for _ in 0..<200 { pick.swapAppearance(Int(seed % 3)); if pick.takenCoats.count != 4 { clean = false } }
    for _ in 0..<50 { pick.reroll(); if pick.takenCoats.count != 4 { clean = false } }
    expect(clean, "wheel: swap and reroll never pick the wheel cat's coat")
    pick.applyAppearances([CatAppearance(coat: pick.wheel!.coat, size: .kitten)])
    expect(pick.takenCoats.count == 4 && pick.cats[0].size == .kitten, "wheel: a cat picked by hand keeps its coat; the wheel cat changes")

    // Settings > Your cats: the wheel cat is the fourth row; a coat another cat wears is traded between the two.
    let dressed = make()
    let outsideCoat = dressed.cats[1].coat, wheelCoat = dressed.wheel!.coat
    dressed.dress(nil, CatAppearance(coat: outsideCoat, size: .kitten))
    expect(dressed.wheel == CatAppearance(coat: outsideCoat, size: .kitten) && dressed.cats[1].coat == wheelCoat && dressed.takenCoats.count == 4,
           "wheel row: picking an outside cat's coat swaps the two")
    let fromRow = dressed.cats[2].coat
    dressed.dress(2, CatAppearance(coat: dressed.wheel!.coat, size: .adult))
    expect(dressed.wheel!.coat == fromRow && dressed.cats[2].coat == outsideCoat && dressed.takenCoats.count == 4,
           "cat row: picking the wheel cat's coat swaps with the wheel cat")
    let peers = make(), peerCoat = peers.cats[2].coat, ownCoat = peers.cats[0].coat
    peers.dress(0, CatAppearance(coat: peerCoat, size: .young))
    expect(peers.cats[0].coat == peerCoat && peers.cats[2].coat == ownCoat && peers.takenCoats.count == 4, "cat row: two cats outside swap coats too")
    let sized = make(), sizedCoats = sized.takenCoats
    sized.dress(nil, CatAppearance(coat: sized.wheel!.coat, size: .kitten))
    expect(sized.takenCoats == sizedCoats && sized.wheel!.size == .kitten, "wheel row: a new size alone changes nobody else")
    var shuffledApart = true
    let mixer = make()
    for _ in 0..<50 { mixer.shuffle(); if mixer.takenCoats.count != 4 || mixer.population != 4 { shuffledApart = false } }
    expect(shuffledApart, "shuffle: the wheel cat is drawn again, all four coats differ")
    let rerolled = make(); let firstWheel = rerolled.wheel
    var newWheel = false
    for _ in 0..<8 { rerolled.reroll(); if rerolled.wheel != firstWheel { newWheel = true } }
    expect(newWheel, "shuffle: the wheel cat changes too")
    // Keep my cats: lineup and wheel cat saved as the app saves them, on a throwaway defaults suite.
    let keepSuite = "CatsInMenubar.selftest.keepWheel"
    if let prefs = UserDefaults(suiteName: keepSuite) {
        prefs.removePersistentDomain(forName: keepSuite)
        let kept = make()
        prefs.set(try? JSONEncoder().encode(kept.cats.map(\.appearance)), forKey: Pref.lineup)
        prefs.set(try? JSONEncoder().encode(kept.wheel!), forKey: Pref.wheelCat)
        let relaunch = make()
        if let data = prefs.data(forKey: Pref.lineup), let lineup = try? JSONDecoder().decode([CatAppearance].self, from: data) { relaunch.applyAppearances(lineup) }
        relaunch.enableWheel(prefs.data(forKey: Pref.wheelCat).flatMap { try? JSONDecoder().decode(CatAppearance.self, from: $0) })
        expect(relaunch.cats.map(\.appearance) == kept.cats.map(\.appearance) && relaunch.wheel == kept.wheel,
               "keep my cats: the wheel cat comes back with the lineup")
        var freshApart = true
        for _ in 0..<30 { relaunch.enableWheel(kept.wheel, fresh: true); if relaunch.takenCoats.count != 4 { freshApart = false } }
        expect(freshApart, "launch without keep: a new wheel cat, never an outside coat")
        prefs.removePersistentDomain(forName: keepSuite)
    } else { expect(false, "keep my cats: isolated defaults suite") }

    // The baton: one cat walks over, jumps in, and the wheel cat comes out wearing its own coat.
    let before = c.wheel!
    expect(c.beginBaton() == .started, "baton: starts with cats out")
    let a = c.cats.firstIndex(where: \.wheelBound)!, look = c.cats[a].appearance
    expect(c.beginBaton() == .busy, "baton: only one at a time")
    var waited = false
    run(c, seconds: 120) { if c.wheelWaiting { waited = true }; return !c.cats[a].wheelBound }
    expect(c.wheel == look && c.cats[a].appearance == before, "baton: the two trade coats: wheel \(String(describing: c.wheel)) cat \(c.cats[a].appearance)")
    expect(waited, "baton: the wheel cat waits as the other one comes close")
    run(c, seconds: 3)
    expect(c.cats[a].visible && !c.cats[a].home && c.lanes[0].contains(c.cats[a].x, margin: c.cats[a].radius) && c.takenCoats.count == 4,
           "baton: the cat from the wheel jumps out into free space")
    expect(c.swapGap > 0 && c.beginBaton() == .busy, "baton: spaced like auto rotation")
    c.swapGap = 0
    if c.beginBaton() == .started { expect(!c.cats.contains { $0.wheelBound && $0.coat == before.coat }, "baton: the cat that just left the wheel is not sent straight back") }
    c.callHome(at: 700)
    expect(!c.cats.contains(where: \.wheelBound), "baton: calling home cancels it")
    let held = c.wheel
    run(c, seconds: 60) { c.homeCount == c.cats.count }
    expect(c.homeCount == c.cats.count && c.wheel == held && c.takenCoats.count == 4, "baton: cancelled, the cat goes home as itself")

    // Nobody out: they trade in the tower, or (Keep my cats) a cat from outside the colony takes the wheel.
    expect(c.beginBaton() == .nobodyOut, "baton: nobody out to walk over")
    let inside = Set(c.cats.map(\.coat)), all = c.takenCoats, wheelBefore = c.wheel!.coat
    c.swapGap = 0; c.swapWheelOffstage(keepLineup: false)
    expect(inside.contains(c.wheel!.coat) && c.takenCoats == all && c.cats.contains { $0.coat == wheelBefore }, "fallback: trades with a cat in the tower")
    let lineup = c.cats.map(\.appearance)
    expect(!c.swapWheelOffstage(keepLineup: true) && c.cats.map(\.appearance) == lineup, "fallback: spaced from the last swap like auto rotation")
    c.swapGap = 0
    c.swapWheelOffstage(keepLineup: true)
    expect(c.cats.map(\.appearance) == lineup && c.takenCoats.count == 4, "fallback: Keep my cats keeps the lineup, a new wheel cat")
    let empty = make(); empty.updateLanes([])
    expect(empty.beginBaton() == .nobodyOut, "fallback: no free space means nobody out")
    let off = make(); off.wheelX = nil
    expect(off.beginBaton() == .nobodyOut, "fallback: no wheel position")

    // The wheel switched off mid-walk: the cat carries on as itself.
    let stop = make()
    _ = stop.beginBaton(); let w = stop.cats.firstIndex(where: \.wheelBound)!, mine = stop.cats[w].appearance
    run(stop, seconds: 1)
    stop.wheel = nil
    expect(!stop.cats[w].wheelBound && !stop.cats[w].homeBound && stop.cats[w].appearance == mine && stop.population == 3, "baton: wheel off cancels it")
    run(stop, seconds: 5)
    expect(stop.cats.allSatisfy { !$0.home }, "baton: after the wheel goes off nobody walks into the tower")
}


/// Manual drops use the same hop/appearance exchange, without touching production preferences.
/// The free space is 100...600; our status item spans 668...710 with the wheel centered at 680 and the tower at 700.
func testWheelDrop(_ expect: (@autoclosure () -> Bool, String) -> Void) {
    func make() -> Colony {
        let c = Colony(count: 2, random: { 0.4 })
        c.updateLanes([Lane(lower: 100, upper: 600)])
        c.wheelX = 680; c.enableWheel(nil); c.ownItem = Lane(lower: 668, upper: 710); c.homeX = 700
        for i in c.cats.indices {
            c.cats[i].visible = true; c.cats[i].home = false; c.cats[i].hiddenFor = 0
            c.cats[i].x = 300 + Double(i) * 100
            c.start(i, .sitting, for: 100)
        }
        return c
    }
    func held(_ c: Colony, at x: Double = 680, _ i: Int = 0) {
        c.grab(i); c.drag(i, to: x, dt: 1.0 / 30); c.step(1.0 / 30)
    }
    func finish(_ c: Colony) {
        for _ in 0..<600 { c.step(1.0 / 30); if !c.cats.contains(where: { $0.action == .hopping }) { break } }
    }
    func settled(_ c: Colony, _ i: Int = 0) -> Bool {
        for _ in 0..<300 { c.step(1.0 / 30) }
        return c.cats[i].visible && !c.cats[i].escaping && c.cats[i].action != .held && c.cats[i].action != .hopping
            && c.lanes.contains { $0.contains(c.cats[i].x, margin: c.cats[i].radius) }
    }

    // Carry corridor: over the icons toward ours, clamped as before the other way.
    let corridor = make(); corridor.grab(0)
    corridor.drag(0, to: 1000, dt: 1.0 / 30)
    expect(corridor.cats[0].x == 710 && corridor.heldOverIcons(0) && corridor.dropTarget(0) == .icons,
           "corridor: carried over the icons to the far edge of our status item")
    corridor.step(1.0 / 30); corridor.updateLanes(corridor.lanes)
    expect(corridor.cats[0].action == .held && corridor.cats[0].x == 710, "corridor: stays in hand over the icons across a rescan")
    corridor.drag(0, to: -100, dt: 1.0 / 30)
    expect(corridor.cats[0].x == 100 + corridor.cats[0].radius && !corridor.heldOverIcons(0), "corridor: the other way clamps at the free space")
    let gap = make(); gap.updateLanes([Lane(lower: 0, upper: 200), Lane(lower: 400, upper: 600)])
    gap.cats[0].x = 100; gap.cats[1].x = 500; gap.grab(0); gap.grab(1)
    gap.drag(0, to: 1000, dt: 1.0 / 30); gap.drag(1, to: -100, dt: 1.0 / 30)
    expect(gap.cats[0].x == 710, "corridor: crosses other icons and free space on the way to ours")
    expect(gap.cats[1].x == 400 + gap.cats[1].radius, "corridor: never toward another free space away from our icons")
    gap.drag(0, to: 500, dt: 1.0 / 30); gap.step(1.0 / 30); gap.updateLanes(gap.lanes)
    gap.drag(0, to: 50, dt: 1.0 / 30)
    expect(gap.cats[0].x == 50, "corridor: back to where it was picked up after passing another free space")
    let right = make(); right.updateLanes([Lane(lower: 800, upper: 1200)]); right.cats[0].x = 1000
    right.grab(0); right.drag(0, to: 0, dt: 1.0 / 30)
    let rightEnd = right.cats[0].x
    right.drag(0, to: 5000, dt: 1.0 / 30)
    expect(rightEnd == 668 && right.cats[0].x == 1200 - right.cats[0].radius, "corridor: our icon on the left side stretches leftward only")
    let notched = make(); notched.tunnel = Lane(lower: 308, upper: 332)
    notched.updateLanes([Lane(lower: 100, upper: 300), Lane(lower: 340, upper: 600)])
    notched.cats[0].x = 200; notched.cats[1].x = 500; notched.grab(0)
    notched.drag(0, to: 1000, dt: 1.0 / 30)
    let far = notched.cats[0].x
    notched.drag(0, to: 320, dt: 1.0 / 30); notched.step(1.0 / 30)
    expect(far == 710 && notched.cats[0].action == .held && notched.dropTarget(0) == .free && !notched.heldOverIcons(0),
           "corridor: the notch stays joined and hides the cat")
    notched.release(0)
    expect(notched.cats[0].inTunnel, "corridor: let go behind the notch still walks out of it")
    let plain = make(); plain.ownItem = nil; plain.grab(0); plain.drag(0, to: 1000, dt: 1.0 / 30)
    expect(plain.cats[0].x == 600 - plain.cats[0].radius, "corridor: unknown status item keeps the free space")

    // Drop targets: the wheel itself, the tower (drag 2/3), other icons.
    let targets = make(); targets.grab(0)
    for (x, want, name) in [(670.0, Colony.DropTarget.wheel, "left wheel edge"), (690, .wheel, "right wheel edge"),
                            (691, .tower, "tower left edge"), (709, .tower, "tower right edge"), (710, .icons, "past the tower"),
                            (650, .icons, "other icons"), (400, .free, "free space")] {
        targets.drag(0, to: x, dt: 1.0 / 30)
        expect(targets.dropTarget(0) == want, "drop target: " + name)
    }
    for (x, name) in [(650.0, "other icons"), (710, "beside the tower")] {
        let icons = make(); held(icons, at: x)
        let old = icons.wheel
        expect(!icons.dropped(0) && icons.wheel == old && !icons.cats[0].wheelBound, "icon drop: " + name + " is an ordinary drop")
        expect(settled(icons), "icon drop: back on free space after letting go over " + name)
    }

    let c = make()
    let before = c.wheel!, entering = c.cats[0].appearance
    var changes = 0
    var turnResets = 0
    c.wheelTurnCompleted = { turnResets += 1 }
    c.wheelChanged = { changes += 1 }
    held(c, at: 684)
    expect(c.wheelDropReady && c.cats[0].action == .held && c.heldOverIcons(0), "wheel drop: held over the wheel, the wheel cat waits")
    expect(c.dropped(0) && c.cats[0].action == .hopping && c.cats[0].hopFrom == 684
           && c.cats[0].hopTo == 680 && c.cats[0].hopTotal == Colony.hopTime && c.wheelWaiting,
           "wheel drop: a short hop in from where it was let go")
    finish(c)
    expect(c.wheel == entering && c.cats[0].appearance == before && changes == 1 && turnResets == 1,
           "wheel drop: exchanges whole appearance and notifies the timer owner once")
    expect(c.swapGap > 0 && !c.cats[0].home && c.cats[0].visible,
           "wheel drop: resets swap spacing and sends previous wheel cat outside")
    held(c)
    expect(c.dropped(0), "wheel drop: user can send the last wheel cat back during swap spacing")
    finish(c)
    expect(c.wheel == before, "wheel drop: last wheel cat can take over again")

    for size in CatSize.allCases {
        let sized = make(); sized.cats[0].size = size; held(sized)
        expect(sized.dropped(0), "wheel drop: every size can be carried onto the wheel")
    }

    // Switching off at any point of the short entry hop never sends the cat into the tower.
    for delay in [0.0, 0.2, 0.45] {
        let cancelled = make(); held(cancelled)
        let look = cancelled.cats[0].appearance
        var completed = 0
        cancelled.wheelTurnCompleted = { completed += 1 }
        expect(cancelled.dropped(0), "wheel cancel: starts entry")
        for _ in 0..<Int(delay * 30) { cancelled.step(1.0 / 30) }
        cancelled.wheel = nil
        var stayedOutside = true
        for _ in 0..<240 {
            cancelled.step(1.0 / 30)
            stayedOutside = stayedOutside && !cancelled.cats[0].home && cancelled.cats[0].visible
        }
        expect(stayedOutside && cancelled.cats[0].appearance == look && completed == 0,
               "wheel cancel: mid-hop lands outside as itself without completing turn")
    }

    let unrelated = make()
    unrelated.beginHop(1, from: 700, to: 400, entering: false)
    held(unrelated)
    expect(unrelated.dropped(0), "wheel drop: unrelated tower hop-out does not block")

    let appearanceOnly = make()
    var resets = 0
    appearanceOnly.wheelTurnCompleted = { resets += 1 }
    appearanceOnly.enableWheel(appearanceOnly.cats[0].appearance)
    appearanceOnly.applyAppearances([CatAppearance(coat: appearanceOnly.wheel!.coat, size: .kitten)])
    expect(resets == 0, "wheel timer: appearance reconciliation does not reset turn")

    let outside = make(); outside.grab(0); outside.drag(0, to: 450, dt: 1.0 / 30)
    expect(!outside.dropped(0) && outside.cats[0].action == .grooming && outside.cats[0].x == 450,
           "wheel drop: let go on free space grooms where it is")
    let programmatic = make(); held(programmatic)
    let original = programmatic.wheel
    programmatic.release(0)
    expect(programmatic.wheel == original && programmatic.cats[0].action == .grooming
           && !programmatic.cats[0].wheelBound, "wheel drop: programmatic release cannot swap")
    expect(settled(programmatic) && programmatic.wheel == original, "wheel drop: programmatic release over the wheel goes back to free space")

    let blockers: [(String, (Colony) -> Void)] = [
        ("off", { $0.wheel = nil }), ("no position", { $0.wheelX = nil }),
        ("quiet", { $0.quiet = true }), ("offstage", { $0.onStage = false }),
        ("shuffle", { $0.shuffling = true }),
        ("walking home", { $0.cats[1].homeBound = true }),
        ("coat swap", { $0.cats[1].swapping = true }),
        ("baton", { $0.cats[1].wheelBound = true }),
        ("hop out", { $0.beginHop(1, from: 680, to: 500, entering: false) })
    ]
    for (name, block) in blockers {
        let blocked = make(); held(blocked); block(blocked)
        let old = blocked.wheel
        expect(!blocked.wheelDropReady, "wheel drop: no waiting signal while " + name)
        expect(!blocked.dropped(0) && blocked.wheel == old && !blocked.cats[0].wheelBound,
               "wheel drop: ignored while " + name)
        if name != "walking home" && name != "shuffle" {
            expect(settled(blocked) && blocked.wheel == old, "wheel drop: back on free space while " + name)
        }
    }
    let fixed = make(); held(fixed)
    expect(!fixed.dropped(0, wheelAllowed: false) && !fixed.cats[0].wheelBound && settled(fixed),
           "wheel drop: fixed lineup settles back on free space")

    // Tower drop (drag 2/3): in through the tower, and the same slot comes back out as another cat.
    do {
        var seed: UInt64 = 5
        let t = make()
        t.random = { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        let old = t.cats[0].appearance, wheelCoat = t.wheel!.coat, other = t.cats[1].coat
        var swaps = 0
        t.swapped = { swaps += 1 }
        held(t, at: 702)
        expect(t.towerDropReady && !t.wheelDropReady, "tower drop: held over the tower, the door opens (not the wheel's signal)")
        expect(t.dropped(0) && t.cats[0].action == .hopping && t.cats[0].hopIn && t.cats[0].hopFrom == 702 && t.cats[0].hopTo == 700
               && t.cats[0].swapping && !t.cats[0].wheelBound, "tower drop: hops in from where it was let go")
        var wentIn = false, insideFor = 0.0, steps = 0, shownInside = 0
        while (t.cats[0].home || !wentIn) && steps < 30 * 20 {
            t.step(1.0 / 30); steps += 1
            if t.cats[0].home { wentIn = true; insideFor += 1.0 / 30; shownInside = max(shownInside, t.homeCount) }
        }
        expect(wentIn && shownInside == 1 && insideFor >= 1 && insideFor <= 2.2, "tower drop: shown in the tower icon for 1-2 s: \(insideFor)")
        expect(t.cats.count == 2 && t.cats[0].coat != old.coat && t.cats[0].coat != other && t.cats[0].coat != wheelCoat && swaps == 1,
               "tower drop: same slot, new coat unlike the others and the wheel cat: \(old.coat) -> \(t.cats[0].coat)")
        expect(t.swapGap > Colony.swapSpacing - 1, "tower drop: auto rotation pushed back a full spacing")
        expect(settled(t) && !t.cats[0].swapping && !t.cats[0].handSwap, "tower drop: trots out onto the free space")
        // Again right away: allowed during the swap spacing, and never back into the coat just worn.
        let second = t.cats[0].coat
        held(t, at: 700)
        expect(t.swapGap > 0 && t.dropped(0), "tower drop: allowed during swap spacing")
        for _ in 0..<(30 * 6) { t.step(1.0 / 30) }
        expect(!t.cats[0].home && t.cats[0].coat != second && t.cats[0].coat != old.coat, "tower drop: not the coat it just wore, nor the one before")
    }
    // Auto rotation off: a swap by hand still changes the cat.
    let manual = make(); manual.rotation = nil; held(manual, at: 700)
    let manualOld = manual.cats[0].coat
    expect(manual.dropped(0), "tower drop: works with auto rotation off")
    for _ in 0..<(30 * 6) { manual.step(1.0 / 30) }
    expect(!manual.cats[0].home && manual.cats[0].coat != manualOld, "tower drop: a new cat even with auto rotation off")
    // Busy: ignored, back on the free space as the same cat.
    let towerBlockers: [(String, (Colony) -> Void)] = [
        ("shuffle", { $0.shuffling = true }), ("walking home", { $0.callHome(at: 700) }),
        ("coat swap", { $0.cats[1].swapping = true }), ("baton", { $0.cats[1].wheelBound = true }),
        ("quiet", { $0.quiet = true }), ("offstage", { $0.onStage = false }), ("no tower", { $0.homeX = nil })
    ]
    for (name, block) in towerBlockers {
        let blocked = make(); held(blocked, at: 700); block(blocked)
        let look = blocked.cats[0].appearance
        expect(!blocked.towerDropReady, "tower drop: no open door while " + name)
        expect(!blocked.dropped(0) && !blocked.cats[0].swapping && blocked.cats[0].appearance == look, "tower drop: ignored while " + name)
        if name != "walking home" && name != "shuffle" {
            expect(settled(blocked) && blocked.cats[0].appearance == look, "tower drop: back on free space while " + name)
        }
    }
    let moving = make(); held(moving, at: 700)
    let movingLook = moving.cats[0].appearance
    expect(!moving.dropped(0, towerAllowed: false) && settled(moving) && moving.cats[0].appearance == movingLook,
           "tower drop: app veto (paused, moving displays) settles back as the same cat")
    let byCode = make(); held(byCode, at: 700)
    let byCodeLook = byCode.cats[0].appearance
    byCode.release(0)
    expect(!byCode.cats[0].swapping && settled(byCode) && byCode.cats[0].appearance == byCodeLook && byCode.homeCount == 0,
           "tower drop: programmatic release never swaps")
    // Called home while it waits inside: it stays in as itself.
    let recalled = make(); held(recalled, at: 700)
    let recalledLook = recalled.cats[0].appearance
    _ = recalled.dropped(0)
    for _ in 0..<20 { recalled.step(1.0 / 30) }
    recalled.callHome(at: 700)
    for _ in 0..<(30 * 20) { recalled.step(1.0 / 30) }
    expect(recalled.cats.allSatisfy(\.home) && recalled.cats[0].appearance == recalledLook, "tower drop: callHome keeps it in as itself")

    // Exercise the view's actual mouse handlers with isolated preferences and no visible windows.
    _ = NSApplication.shared
    let suite = "CatsInMenubar.selftest.wheelDrop"
    let prefs = UserDefaults(suiteName: suite)!
    prefs.removePersistentDomain(forName: suite)
    defer { prefs.removePersistentDomain(forName: suite) }
    prefs.set(true, forKey: Pref.allowDrag)
    for mode in 0..<3 {
        let model = make()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 24),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = HabitatView(colony: model, frame: NSRect(x: 0, y: 0, width: 800, height: 24), defaults: prefs)
        window.contentView = view
        view.wheelDropAllowed = { mode != 2 }
        var ended = 0
        view.interactionEnded = { ended += 1 }
        func event(_ type: NSEvent.EventType, _ x: Double, _ time: Double) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 12), modifierFlags: [],
                               timestamp: time, windowNumber: window.windowNumber, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        let old = model.wheel
        view.mouseDown(with: event(.leftMouseDown, model.cats[0].x, 1))
        view.mouseDragged(with: event(.leftMouseDragged, 682, 2))
        expect(view.dragging == 0, "wheel drop view: grabbed and dragged")
        if mode == 1 { view.endDrag() }
        else { view.mouseUp(with: event(.leftMouseUp, 682, 3)) }
        expect(view.dragging == nil && ended == 1, "wheel drop view: ends interaction once")
        if mode == 0 {
            expect(model.cats[0].wheelBound && model.cats[0].action == .hopping, "wheel drop view: mouseUp starts baton")
            finish(model)
            expect(model.wheel != old, "wheel drop view: mouseUp completes exchange")
        } else {
            expect(model.wheel == old && !model.cats[0].wheelBound && model.cats[0].action == .grooming,
                   "wheel drop view: endDrag or app veto settles without swapping")
            expect(settled(model) && model.wheel == old, "wheel drop view: endDrag or app veto over the wheel goes back to free space")
        }
    }
    // The same through the view for the tower: mouseUp trades the cat, endDrag never does.
    for viaMouse in [true, false] {
        let model = make()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 24),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = HabitatView(colony: model, frame: NSRect(x: 0, y: 0, width: 800, height: 24), defaults: prefs)
        window.contentView = view
        view.wheelDropAllowed = { true }; view.towerDropAllowed = { true }
        func event(_ type: NSEvent.EventType, _ x: Double, _ time: Double) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 12), modifierFlags: [],
                               timestamp: time, windowNumber: window.windowNumber, context: nil,
                               eventNumber: 0, clickCount: 1, pressure: 0)!
        }
        let look = model.cats[0].appearance
        view.mouseDown(with: event(.leftMouseDown, model.cats[0].x, 1))
        view.mouseDragged(with: event(.leftMouseDragged, 700, 2))
        if viaMouse { view.mouseUp(with: event(.leftMouseUp, 700, 3)) } else { view.endDrag() }
        if viaMouse {
            expect(model.cats[0].swapping && model.cats[0].action == .hopping, "tower drop view: mouseUp sends it in")
            for _ in 0..<(30 * 6) { model.step(1.0 / 30) }
            expect(!model.cats[0].home && model.cats[0].coat != look.coat, "tower drop view: comes back out as another cat")
        } else {
            expect(!model.cats[0].swapping && settled(model) && model.cats[0].appearance == look, "tower drop view: endDrag settles as the same cat")
        }
    }

}

func testMenuBarTidy(_ expect: (@autoclosure () -> Bool, String) -> Void) {
    expect(FileManager.default.fileExists(atPath: Bundle.main.resourceURL!.appendingPathComponent("MIT-HiddenBar.txt").path),
           "Hidden Bar's MIT license ships inside the app with the code taken from it")
    // Every running app stays allowed except the hidden ones; this app is always allowed.
    let allowed = MenuBarTidy.allowList(running: ["a", "b", "c", "b"], hidden: ["b", "x"], own: "me")
    expect(allowed == ["a", "c", "me"], "allow-list: running minus hidden plus own, each once")
    expect(MenuBarTidy.allowList(running: ["me"], hidden: ["me"], own: "me") == ["me"], "this app can never hide itself")
    expect(MenuBarTidy.systemItems == Array(0..<64), "macOS's own items always stay")
    // Two rows of seven; past fourteen the last spot is a +N menu.
    expect(!CaptureActivity.counts(["com.apple.CoreSpeech"]), "the Siri listener does not count as recording")
    expect(CaptureActivity.counts(["com.apple.CoreSpeech", "us.zoom.xos"]), "an app recording beside it still counts")
    expect(CaptureActivity.counts([nil]), "a recorder of unknown bundle counts")
    expect(!CaptureActivity.counts([]), "no recorder, nothing in use")
    expect(PanelGrid.layout(count: 0) == (0, 0) && PanelGrid.layout(count: 3) == (3, 0), "a few apps show as they are")
    expect(PanelGrid.layout(count: 14) == (14, 0), "fourteen apps fill both rows")
    expect(PanelGrid.layout(count: 15) == (13, 2), "fifteen: thirteen icons and +2")
    expect(PanelGrid.layout(count: 40) == (13, 27), "many: the menu holds the rest")
    // Only an Applications folder counts; macOS hides an app run from elsewhere even when allowed.
    expect(MenuBarTidy.inApplications(URL(fileURLWithPath: "/Applications/Cats in Menubar.app")), "/Applications counts")
    expect(MenuBarTidy.inApplications(URL(fileURLWithPath: "/Applications/Setapp/X.app")), "folders inside /Applications count")
    expect(!MenuBarTidy.inApplications(URL(fileURLWithPath: "/Users/me/Downloads/Cats in Menubar.app")), "Downloads does not count")
    expect(!MenuBarTidy.inApplications(URL(fileURLWithPath: "/Users/me/Applications/Cats in Menubar.app")), "~/Applications does not count")
    // Icons left of the tower on its own menu bar, ignoring hidden apps' stale frames and this app.
    let band = CGRect(x: 0, y: 0, width: 1512, height: 37)
    let own = NSRect(x: 1100, y: 945, width: 24, height: 37)
    let extras = [StatusExtra(pid: 1, bundle: "left", frames: [CGRect(x: 1000, y: 0, width: 24, height: 37)]),
                  StatusExtra(pid: 2, bundle: "right", frames: [CGRect(x: 1200, y: 0, width: 24, height: 37)]),
                  StatusExtra(pid: 3, bundle: "hidden", frames: [CGRect(x: 900, y: 0, width: 24, height: 37)]),
                  StatusExtra(pid: 4, bundle: "otherScreen", frames: [CGRect(x: 1000, y: -900, width: 24, height: 37)]),
                  StatusExtra(pid: 9, bundle: "me", frames: [CGRect(x: 1100, y: 0, width: 24, height: 37)])]
    let left = MenuBarTidy.itemsLeft(of: own, extras: extras, skip: ["hidden"], ownPid: 9, band: band)
    expect(left == [CGRect(x: 1000, y: 0, width: 24, height: 37)], "only a visible icon left of the tower on its menu bar counts")
    expect(MenuBarTidy.itemsLeft(of: own, extras: Array(extras.dropFirst()), skip: ["hidden"], ownPid: 9, band: band).isEmpty, "leftmost tower: nothing to move")
}

/// The panel's opening, details and closing with a stand-in pointer and clock, on real windows.
func runPanelTests() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    UserDefaults.standard.register(defaults: Pref.defaults)
    var checks = 0
    func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { fputs("FAIL: \(message)\n", stderr); exit(1) }
    }
    guard let screen = NSScreen.main else { print("Panel tests: no screen"); return }
    let model = AppModel()
    model.catSummary = "3 cats · 840 pt of room"
    let system = SystemMonitor()
    system.sample()
    let panel = DashboardPanel(model: model, system: system, openSettings: {}, play: {})
    let bar = max(24, screen.frame.maxY - screen.visibleFrame.maxY)
    let icon = NSRect(x: screen.frame.maxX - 320, y: screen.frame.maxY - bar, width: 30, height: bar)
    var mouse = NSPoint(x: icon.midX, y: icon.midY), now = 1000.0
    panel.icon = { icon }
    panel.pointer = { mouse }
    panel.clock = { now }
    func step(_ seconds: Double, every: Double = 0.05) {
        var left = seconds
        while left > 0.0001 {
            now += every; left -= every
            panel.tick()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }
    func settle() { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3)) }
    func far() -> NSPoint { NSPoint(x: screen.visibleFrame.minX + 5, y: screen.visibleFrame.minY + 5) }
    func center(_ r: NSRect) -> NSPoint { NSPoint(x: r.midX, y: r.midY) }
    func open() {
        mouse = center(icon)
        step(0.4)
        settle()
        expect(panel.isShown && panel.mode == .hover, "resting on the icon opens the panel")
    }
    func showRow(_ stat: DashboardStat) {
        guard let row = panel.rowOnScreen(stat) else { expect(false, "the summary reports where the \(stat) row is"); return }
        mouse = center(row)
        step(0.2)
        settle()
        expect(panel.detailShown == stat, "resting on the \(stat) row shows its details (shown: \(String(describing: panel.detailShown)))")
    }

    // Open, see a row's details, go away.
    open()
    step(0.3)
    expect(panel.isShown, "the panel stays while the pointer is on the icon")
    showRow(.cpu)
    showRow(.memory)
    if let detail = panel.frames.detail {
        mouse = center(detail); step(1)
        expect(panel.isShown && panel.detailShown == .memory, "the details stay while the pointer is on them")
        mouse = NSPoint(x: detail.midX, y: detail.minY - 60); step(0.3)
        expect(panel.isShown, "a moment away is forgiven")
        step(0.4)
        expect(!panel.isShown, "away from the details for half a second closes the panel")
    } else { expect(false, "the details have a window") }
    step(0.5)

    // Back on the icon only after leaving it; then away straight from a row.
    open()
    showRow(.memory)
    mouse = far(); step(0.7)
    expect(!panel.isShown, "away from the summary closes the panel, details and all")
    step(0.5)

    // Crossing rows on the way to the details does not swap them.
    open()
    showRow(.cpu)
    if let memory = panel.rowOnScreen(.memory), let detail = panel.frames.detail {
        mouse = center(memory); step(0.05)
        mouse = center(detail); step(0.3)
        expect(panel.detailShown == .cpu, "passing over another row on the way keeps the details")
    }
    mouse = far(); step(0.7)
    expect(!panel.isShown, "and the panel still closes after")
    step(0.5)

    // The header has no details; the pointer back on the icon keeps the panel.
    open()
    showRow(.memory)
    mouse = NSPoint(x: panel.frames.summary.midX, y: panel.frames.summary.maxY - 20); step(0.3); settle()
    expect(panel.isShown && panel.detailShown == nil, "the header hides the details")
    mouse = center(icon); step(1)
    expect(panel.isShown, "back on the icon keeps the panel")
    mouse = far(); step(0.7)
    expect(!panel.isShown, "then away closes it")
    step(0.5)

    // Many rows in a row, then away: never stuck open.
    for round in 0..<20 {
        open()
        for stat in [DashboardStat.cpu, .memory, .disk, .network, .gpu, .memory] where panel.rowOnScreen(stat) != nil {
            mouse = center(panel.rowOnScreen(stat)!); step(Double(round % 4) * 0.05 + 0.05)
        }
        if round % 2 == 0, let detail = panel.frames.detail { mouse = center(detail); step(0.2) }
        mouse = far(); step(0.7)
        expect(!panel.isShown, "round \(round): the panel closes once the pointer has left")
        step(0.5)
    }

    // A click just after the rest opened it changes nothing: it still closes when the pointer leaves.
    open()
    panel.click()
    expect(panel.mode == .hover, "a click on the icon of a panel opened by resting keeps it as it is")
    showRow(.memory)
    mouse = far(); step(0.7)
    expect(!panel.isShown, "and it closes once the pointer has left")
    step(0.5)
    // A click before the rest delay opens it the same way.
    mouse = center(icon)
    panel.click(); settle()
    expect(panel.mode == .hover, "with Open on hover, a click opens the same panel at once")
    mouse = far(); step(0.7)
    expect(!panel.isShown, "which also closes once the pointer has left")
    step(0.5)
    // With Open on hover off, a click opens it to stay.
    panel.hoverOn = { false }
    mouse = center(icon)
    panel.click(); settle()
    expect(panel.mode == .click, "with Open on hover off, a click opens the panel to stay")
    mouse = far(); step(1)
    expect(panel.isShown, "a clicked panel stays when the pointer leaves")
    mouse = center(icon)
    panel.click()
    expect(!panel.isShown, "a second click closes it")
    print("Panel tests: \(checks) checks")
}
