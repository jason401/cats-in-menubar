import Foundation

struct Lane: Equatable {
    var lower: Double
    var upper: Double
    var width: Double { upper - lower }
    func contains(_ x: Double, margin: Double = 0) -> Bool {
        x >= lower + margin && x <= upper - margin
    }
}

// Coordinates are screen-local points. Occupied rectangles are expanded before subtraction.
enum Habitat {
    static let catRadius = 24.0
    static func freeLanes(width: Double, obstacles: [Lane], padding: Double = 8) -> [Lane] {
        guard width > 0 else { return [] }
        let blocked = obstacles.map { Lane(lower: max(0, $0.lower - padding), upper: min(width, $0.upper + padding)) }
            .filter { $0.upper > $0.lower }.sorted { $0.lower < $1.lower }
        var cursor = 0.0
        var result: [Lane] = []
        for obstacle in blocked {
            if obstacle.lower > cursor { result.append(Lane(lower: cursor, upper: obstacle.lower)) }
            cursor = max(cursor, obstacle.upper)
        }
        if cursor < width { result.append(Lane(lower: cursor, upper: width)) }
        return result.filter { $0.width >= catRadius * 2 + 6 }
    }
}

enum CatAction: String, CaseIterable {
    case sitting, walking, sleeping, grooming, playing, chasing
    case running, stalking, pouncing, stretching, loafing, held
    case goingHome, hopping
}
enum CatSize: Int, CaseIterable, Codable {
    case kitten, young, adult
    var scale: Double { switch self { case .kitten: 0.64; case .young: 0.82; case .adult: 1 } }
    var label: String { switch self { case .kitten: "Kitten"; case .young: "Young"; case .adult: "Adult" } }
}
struct CatAppearance: Codable, Equatable {
    var coat: Int
    var size: CatSize
    static let names = ["Orange tabby", "Black", "White", "Silver tabby", "Cream tabby", "Tuxedo", "Calico", "Siamese"]
}
struct Cat {
    var x: Double
    var destination: Double
    var direction = 1.0
    var velocity = 0.0
    var gait = 0.0          // distance walked, drives leg motion so feet never slide
    var turnCooldown = 0.0  // a cat must stand a moment before facing the other way
    var turnHold = 0.0      // stays put while the turn-around frames play
    var batAt = -10.0       // phase of the last paw swipe at the ball
    var pounceCooldown = 0.0
    var elapsed = 0.0       // time in the current action, drives one-shot poses like stretching
    var target = 0.0        // where a hunt ends
    var wiggle = 0.0        // butt wiggle before a pounce
    var stuck = 0.0         // time spent playing without moving or batting
    var heldLean = 0.0
    var heldLeanVelocity = 0.0
    var swing = 0.0         // horizontal speed while carried by the mouse
    var escaping = false    // covered by a menu or icon, hurrying to the nearest free space
    var homeBound = false   // called back to the cat tower
    var tunnelBound = false // walking to the notch to cross to the other side
    var inTunnel = false    // passing behind the notch, unseen in the middle
    var home = false        // inside the cat tower icon, not drawn
    var outDelay = 0.0      // staggered exit from the tower
    var hopFrom = 0.0, hopTo = 0.0
    var hopIn = true
    var action: CatAction = .sitting
    var remaining = 5.0
    var phase = 0.0
    var hiddenFor = 0.0
    var visible = false
    var coat: Int
    var size: CatSize = .adult
    var radius: Double { Habitat.catRadius * size.scale }
    var appearance: CatAppearance {
        get { CatAppearance(coat: coat, size: size) }
        set { coat = max(0, min(7, newValue.coat)); size = newValue.size }
    }
}
struct ToyBall {
    var x: Double
    var velocity: Double
    var phase = 0.0
    var lifetime = 16.0
    var lane: Lane
}

final class Colony {
    var cats: [Cat] = []
    var ball: ToyBall?
    var lanes: [Lane] = []
    var quiet = false
    var mood = 0.0          // from the power level: negative = more naps, positive = livelier
    var activity = 1        // 0 calm, 1 normal, 2 playful
    var homeX: Double?      // overlay x of the cat tower icon
    var tunnel: Lane?       // the camera notch: nothing can be seen there, but cats may walk through it
    static let hopTime = 0.55
    static let turnTime = 0.36  // four turn-around frames at 0.09 s
    var random: () -> Double
    init(count: Int = 3, random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.random = random
        setCount(count)
    }
    func setCount(_ count: Int) {
        let count = max(1, min(3, count))
        while cats.count > count { cats.removeLast() }
        while cats.count < count {
            let unused = (0..<8).filter { coat in !cats.contains { $0.coat == coat } }
            let coat = unused[min(unused.count - 1, Int(random() * Double(unused.count)))]
            let size = CatSize.allCases[min(2, Int(random() * 3))]
            cats.append(Cat(x: -100, destination: -100, remaining: 2 + random() * 8, coat: coat, size: size))
        }
        reconcile()
    }
    func updateLanes(_ newLanes: [Lane]) {
        lanes = newLanes
        reconcile()
    }
    func reconcile() {
        for i in cats.indices {
            if cats[i].home || cats[i].action == .hopping || cats[i].inTunnel { continue }
            if cats[i].action == .held, carryLane(for: i) != nil, !lanes.contains(where: { $0.contains(cats[i].x, margin: cats[i].radius) }) { continue }
            // Existing positions stay stable when space grows; never walk across an obstacle.
            if let lane = lanes.first(where: { $0.contains(cats[i].x, margin: cats[i].radius) }) {
                cats[i].destination = clamp(cats[i].destination, to: lane, for: i)
                cats[i].visible = true
            } else if !lanes.isEmpty && cats[i].visible && cats[i].hiddenFor <= 0 {
                // Space was taken over the cat: it stays visible and scurries out instead of vanishing.
                if cats[i].action == .held { start(i, .sitting, for: 1) }
            } else if !lanes.isEmpty {
                // Weight connected intervals by usable length, then spread initial cats apart if possible.
                let total = lanes.reduce(0.0) { $0 + max(0, $1.width - 2 * cats[i].radius) }
                var draw = random() * total
                let lane = lanes.first { lane in draw -= max(0, lane.width - 2 * cats[i].radius); return draw <= 0 } ?? lanes.last!
                var spot = lane.lower + cats[i].radius
                for _ in 0..<12 {
                    spot = lane.lower + cats[i].radius + random() * (lane.width - 2 * cats[i].radius)
                    if !cats.indices.contains(where: { $0 != i && cats[$0].visible && abs(cats[$0].x - spot) < cats[$0].radius + cats[i].radius + 6 }) { break }
                }
                cats[i].x = spot
                cats[i].destination = cats[i].x
                cats[i].hiddenFor = 0.45
                cats[i].velocity = 0
                cats[i].visible = true
                start(i, .sitting, for: 2 + random() * 4)
            } else { cats[i].visible = false }
        }
        if let toy = ball, !lanes.contains(where: { $0.lower <= toy.lane.lower && $0.upper >= toy.lane.upper }) {
            ball = nil
            for i in cats.indices where cats[i].action == .playing { cats[i].action = .sitting; cats[i].remaining = 1 }
        }
    }
    static let stretchTime = 3.2
    func start(_ i: Int, _ action: CatAction, for duration: Double) {
        cats[i].action = action; cats[i].remaining = duration; cats[i].elapsed = 0; cats[i].wiggle = 0; cats[i].tunnelBound = false
    }
    func clamp(_ x: Double, to lane: Lane, for i: Int) -> Double {
        min(lane.upper - cats[i].radius, max(lane.lower + cats[i].radius, x))
    }
    func applyAppearances(_ appearances: [CatAppearance]) {
        for i in cats.indices where appearances.indices.contains(i) { cats[i].appearance = appearances[i] }
        reconcile()
    }
    func shuffle() {
        var unused = Array(0..<8)
        for i in cats.indices {
            cats[i].coat = unused.remove(at: min(unused.count - 1, Int(random() * Double(unused.count))))
            cats[i].size = CatSize.allCases[min(2, Int(random() * 3))]
            cats[i].home = false; cats[i].homeBound = false; cats[i].visible = false
            cats[i].x = -100; cats[i].velocity = 0; cats[i].escaping = false; cats[i].inTunnel = false
            start(i, .sitting, for: 2)
        }
        ball = nil
        reconcile()
    }
    func choose(_ i: Int, lane: Lane) {
        let previous = cats[i].action
        if cats[i].homeBound { start(i, .goingHome, for: .infinity); return }
        // The Calm/Playful setting and the power level shift the choice between naps and running or hunting.
        let r = min(0.999, max(0, random() + Double(activity - 1) * 0.12 + mood))
        if quiet { start(i, .sleeping, for: 18 + random() * 50); return }
        if previous == .pouncing { start(i, .sitting, for: 3 + random() * 4); return }
        // Waking up usually comes with a good stretch.
        if (previous == .sleeping || previous == .loafing) && r < 0.65 { start(i, .stretching, for: Colony.stretchTime); return }
        if r < 0.22 { start(i, .sleeping, for: 18 + random() * 45) }
        else if r < 0.34 { start(i, .sitting, for: 4 + random() * 8) }
        else if r < 0.44 { start(i, .loafing, for: 8 + random() * 12) }
        else if r < 0.53 { start(i, .grooming, for: 4 + random() * 5) }
        else if r < 0.58 { start(i, .stretching, for: Colony.stretchTime) }
        else if r < 0.76 || lane.width < 120 {
            start(i, .walking, for: 14)
            cats[i].destination = clamp(lane.lower + random() * lane.width, to: lane, for: i)
        } else if r < 0.85 {
            // A sudden zoomie to the far side of the free space.
            start(i, .running, for: 10)
            let middle = (lane.lower + lane.upper) / 2
            cats[i].destination = clamp(cats[i].x < middle ? lane.upper - random() * lane.width * 0.25 : lane.lower + random() * lane.width * 0.25, to: lane, for: i)
        } else if r < 0.93 {
            // Hunt an imaginary bug: creep, wiggle, pounce.
            let side = random() < 0.5 ? -1.0 : 1.0
            let prey = clamp(cats[i].x + side * (45 + random() * 40), to: lane, for: i)
            if abs(prey - cats[i].x) < 35 { start(i, .sitting, for: 4) }
            else {
                start(i, .stalking, for: 15)
                cats[i].target = prey
                cats[i].destination = prey - (prey > cats[i].x ? 1 : -1) * 20
            }
        } else {
            if ball == nil { ball = ToyBall(x: cats[i].x, velocity: cats[i].direction * 34, lane: lane) }
            if let toy = ball, lane.contains(toy.x, margin: 5) { start(i, .playing, for: 10 + random() * 8) }
            else { start(i, .sitting, for: 4) }
        }
        // A rare short chase, only within the same connected free interval.
        if !quiet, cats[i].action == .walking, random() < 0.22,
           let friend = cats.indices.first(where: { $0 != i && cats[$0].visible && lane.contains(cats[$0].x, margin: cats[$0].radius) && cats[$0].action == .walking }) {
            start(i, .chasing, for: 4)
            cats[i].destination = clamp(cats[friend].x, to: lane, for: i)
        }
        // Sometimes a walk heads into the notch and comes out on the other side.
        if !quiet, cats[i].action == .walking, random() < 0.25, let ends = tunnelEnds(), lane == ends.left || lane == ends.right {
            cats[i].tunnelBound = true
            cats[i].destination = lane == ends.left ? lane.upper - cats[i].radius : lane.lower + cats[i].radius
        }
    }
    /// The free spaces directly on both sides of the notch, with nothing else in between.
    func tunnelEnds() -> (left: Lane, right: Lane)? {
        guard let tunnel else { return nil }
        // Lanes stop 8 pt (the obstacle padding) short of the notch.
        let gap = 0.0...9.0
        guard let left = lanes.first(where: { gap.contains(tunnel.lower - $0.upper) }),
              let right = lanes.first(where: { gap.contains($0.lower - tunnel.upper) }) else { return nil }
        return (left, right)
    }
    private func crossTunnel(_ i: Int, _ dt: Double) {
        guard let tunnel, let ends = tunnelEnds() else {
            // The notch or the far side went away: come back out like any covered cat.
            cats[i].inTunnel = false; escape(i, dt); return
        }
        let exitLane = cats[i].direction > 0 ? ends.right : ends.left
        let exit = cats[i].direction > 0 ? exitLane.lower + cats[i].radius : exitLane.upper - cats[i].radius
        let walk = 15 * cats[i].size.scale
        if cats[i].x - cats[i].radius >= tunnel.lower && cats[i].x + cats[i].radius <= tunnel.upper {
            // Out of sight it hurries, so the notch is a short wait rather than a long walk.
            cats[i].velocity = cats[i].direction * 120 * cats[i].size.scale
        } else {
            // Going in and coming out it walks, like any other walk.
            let speed = min(walk, abs(cats[i].velocity) + 30 * cats[i].size.scale * dt)
            cats[i].velocity = cats[i].direction * speed
        }
        let step = min(abs(exit - cats[i].x), abs(cats[i].velocity) * dt)
        cats[i].x += cats[i].direction * step
        cats[i].gait += step; cats[i].phase += dt; cats[i].elapsed += dt
        cats[i].destination = cats[i].x
        guard abs(exit - cats[i].x) < 0.01 else { return }
        cats[i].x = exit; cats[i].inTunnel = false
        if cats[i].homeBound { start(i, .goingHome, for: .infinity); return }
        start(i, .walking, for: 14)
        cats[i].destination = clamp(exit + cats[i].direction * (30 + random() * 60), to: exitLane, for: i)
    }
    func step(_ elapsed: Double) {
        // Drawing can slow to 8 fps (2 fps at rest), but movement and sway still advance in real time.
        var remaining = min(max(elapsed, 0), 0.5)
        while remaining > 0.000000001 {
            let dt = min(remaining, 1.0 / 30)
            advance(dt)
            remaining -= dt
        }
    }
    private func advance(_ dt: Double) {
        if quiet { ball = nil }
        if var toy = ball {
            toy.lifetime -= dt
            toy.x += toy.velocity * dt
            toy.velocity *= pow(0.94, dt * 30)
            if toy.x < toy.lane.lower + 5 { toy.x = toy.lane.lower + 5; toy.velocity = abs(toy.velocity) }
            if toy.x > toy.lane.upper - 5 { toy.x = toy.lane.upper - 5; toy.velocity = -abs(toy.velocity) }
            toy.phase += toy.velocity * dt / 4
            ball = toy.lifetime > 0 ? toy : nil
        }
        for i in cats.indices {
            if cats[i].home { comeOut(i, dt); continue }
            guard cats[i].visible else { continue }
            if cats[i].action == .hopping { hop(i, dt); continue }
            if cats[i].inTunnel { crossTunnel(i, dt); continue }
            guard let lane = lanes.first(where: { $0.contains(cats[i].x, margin: cats[i].radius) }) ?? (cats[i].action == .held ? carryLane(for: i) : nil) else { escape(i, dt); continue }
            cats[i].escaping = false
            cats[i].hiddenFor = max(0, cats[i].hiddenFor - dt)
            cats[i].phase += dt
            cats[i].elapsed += dt
            if cats[i].action == .held {
                let target = -max(-1, min(1, cats[i].swing / 100))
                cats[i].heldLeanVelocity += ((target - cats[i].heldLean) * 80 - cats[i].heldLeanVelocity * 8) * dt
                cats[i].heldLean = max(-1.1, min(1.1, cats[i].heldLean + cats[i].heldLeanVelocity * dt))
                cats[i].swing *= exp(-6 * dt)
                continue
            }
            cats[i].remaining -= dt
            if quiet && !cats[i].homeBound && cats[i].action != .sleeping { start(i, .sleeping, for: 30) }
            if cats[i].remaining <= 0 { choose(i, lane: lane) }
            cats[i].turnCooldown = max(0, cats[i].turnCooldown - dt)
            cats[i].turnHold = max(0, cats[i].turnHold - dt)
            cats[i].pounceCooldown = max(0, cats[i].pounceCooldown - dt)
            if cats[i].action == .playing {
                if var toy = ball, lane.contains(toy.x, margin: 5) {
                    // Side is taken from where the ball is, not where the cat faces, so it cannot oscillate.
                    let side = toy.x >= cats[i].x ? 1.0 : -1.0
                    let spot = clamp(toy.x - side * 11 * cats[i].size.scale, to: lane, for: i)
                    // Near the end of the free space the cat cannot get closer than its own body allows;
                    // once it is as close as it can be, it bats from there.
                    let reach = abs(spot - cats[i].x) < 0.5 ? cats[i].radius + 10 : 14 * cats[i].size.scale
                    if cats[i].pounceCooldown > 0 {
                        cats[i].destination = cats[i].x
                    } else if abs(toy.x - cats[i].x) < reach && abs(cats[i].velocity) < 12 {
                        toy.velocity = side * (40 + random() * 35)
                        ball = toy
                        cats[i].pounceCooldown = 0.9 + random() * 1.4
                        cats[i].batAt = cats[i].phase
                        cats[i].destination = cats[i].x
                        cats[i].stuck = 0
                    } else {
                        cats[i].destination = spot
                    }
                    // Never hold a pose forever: a cat that can neither move nor bat loses interest.
                    if abs(cats[i].velocity) < 0.5 && cats[i].pounceCooldown <= 0 { cats[i].stuck += dt } else { cats[i].stuck = 0 }
                    if cats[i].stuck > 2.5 { start(i, .sitting, for: 3 + random() * 3); cats[i].stuck = 0 }
                } else { cats[i].action = .sitting; cats[i].remaining = 3 }
            }
            if cats[i].action == .goingHome, let homeX {
                cats[i].destination = clamp(homeX, to: lane, for: i)
                // One cat at a time hops from the edge of the free space into the tower.
                if abs(cats[i].destination - cats[i].x) < 0.5 && abs(cats[i].velocity) < 0.5 && !cats.contains(where: { $0.action == .hopping && $0.hopIn }) {
                    beginHop(i, from: cats[i].x, to: homeX, entering: true)
                    continue
                }
            }
            if cats[i].action == .stalking && cats[i].wiggle > 0 {
                cats[i].wiggle -= dt
                if cats[i].wiggle <= 0 {
                    let prey = clamp(cats[i].target, to: lane, for: i)
                    start(i, .pouncing, for: 1.5)
                    cats[i].destination = prey
                }
            }
            let moving: Set<CatAction> = [.walking, .running, .chasing, .playing, .stalking, .pouncing, .goingHome]
            let holding = cats[i].action == .stalking && cats[i].wiggle > 0
            let delta = moving.contains(cats[i].action) && !holding ? cats[i].destination - cats[i].x : 0
            let (baseSpeed, baseAccel): (Double, Double) = switch cats[i].action {
            case .walking: (15, 30)
            case .goingHome: (55, 90)
            case .running: (58, 90)
            case .chasing: (50, 90)
            case .playing: (30, 70)
            case .stalking: (6, 20)
            case .pouncing: (75, 400)
            default: (0, 70)  // idle actions also stop quickly
            }
            let maxSpeed = baseSpeed * cats[i].size.scale
            let accel = baseAccel * cats[i].size.scale
            var desired = 0.0
            if abs(delta) > 0.5 {
                let wanted = delta > 0 ? 1.0 : -1.0
                if wanted != cats[i].direction {
                    // Slow down, pause, then turn around.
                    if abs(cats[i].velocity) < 0.5 && cats[i].turnCooldown <= 0 {
                        cats[i].direction = wanted; cats[i].turnCooldown = 0.6; cats[i].turnHold = Colony.turnTime
                    }
                } else if cats[i].turnHold <= 0 {
                    // Ease in and brake smoothly before the destination.
                    desired = wanted * min(maxSpeed, sqrt(2 * accel * abs(delta)))
                }
            } else if moving.contains(cats[i].action) && abs(cats[i].velocity) < 0.5 {
                switch cats[i].action {
                case .playing, .goingHome: break
                case .stalking: if cats[i].wiggle <= 0 { cats[i].wiggle = 0.7 + random() * 0.7 }
                case .walking where cats[i].tunnelBound && tunnelEnds() != nil:
                    cats[i].tunnelBound = false; cats[i].inTunnel = true
                default: cats[i].remaining = 0
                }
            }
            let change = desired - cats[i].velocity
            cats[i].velocity += max(-accel * dt, min(accel * dt, change))
            let before = cats[i].x
            cats[i].x += cats[i].velocity * dt
            cats[i].x = clamp(cats[i].x, to: lane, for: i)
            if cats[i].x == lane.lower + cats[i].radius || cats[i].x == lane.upper - cats[i].radius { cats[i].velocity = 0 }
            cats[i].gait += abs(cats[i].x - before)
        }
    }
    /// Runs straight to the closest free spot; only used while the cat is already covered.
    func escape(_ i: Int, _ dt: Double) {
        guard !lanes.isEmpty else { cats[i].visible = false; return }
        let x = cats[i].x
        let spots = lanes.map { clamp(x, to: $0, for: i) }
        guard let spot = spots.min(by: { abs($0 - x) < abs($1 - x) }) else { return }
        if cats[i].action != .running { start(i, .running, for: 3) }
        let fresh = !cats[i].escaping
        cats[i].escaping = true
        cats[i].direction = spot > x ? 1 : -1
        if fresh { cats[i].velocity = 0 }
        // Farther escapes are quicker dashes, so a covered cat is always out within about a second.
        if !cats[i].escaping || cats[i].velocity == 0 { cats[i].velocity = cats[i].direction * max(90, abs(spot - x)) }
        let step = min(abs(spot - x), abs(cats[i].velocity) * dt)
        cats[i].x += cats[i].direction * step
        cats[i].gait += step
        cats[i].phase += dt
        if abs(spot - cats[i].x) < 0.01 { cats[i].x = spot; cats[i].velocity = 0; start(i, .sitting, for: 1 + random() * 2) }
        cats[i].destination = cats[i].x
    }
    // MARK: Cat tower
    var homeCount: Int { cats.filter(\.home).count }
    var anyHomeBound: Bool { cats.contains { $0.homeBound || $0.home } }
    /// Everyone runs toward the tower icon and hops in, one by one.
    func callHome(at x: Double) {
        homeX = x
        ball = nil
        for i in cats.indices where !cats[i].home {
            cats[i].homeBound = true
            if !cats[i].visible { cats[i].home = true; continue }
            if cats[i].action != .hopping && !cats[i].inTunnel { start(i, .goingHome, for: .infinity) }
        }
    }
    /// Cats hop back out of the tower, a moment apart.
    func letOut(at x: Double) {
        homeX = x
        var order = 0.0
        for i in cats.indices {
            cats[i].homeBound = false
            if cats[i].home { cats[i].outDelay = order; order += 0.7 }
            else if cats[i].action == .goingHome { start(i, .sitting, for: 1 + random()) }
        }
    }
    func beginHop(_ i: Int, from: Double, to: Double, entering: Bool) {
        start(i, .hopping, for: .infinity)
        cats[i].hopFrom = from; cats[i].hopTo = to; cats[i].hopIn = entering
        cats[i].direction = to >= from ? 1 : -1
        cats[i].velocity = 0; cats[i].escaping = false
    }
    private func hop(_ i: Int, _ dt: Double) {
        cats[i].phase += dt; cats[i].elapsed += dt
        let q = min(1, cats[i].elapsed / Colony.hopTime)
        cats[i].x = cats[i].hopFrom + (cats[i].hopTo - cats[i].hopFrom) * q
        cats[i].destination = cats[i].x
        guard q >= 1 else { return }
        if cats[i].hopIn { cats[i].home = true; cats[i].visible = false; start(i, .sitting, for: 2) }
        else {
            // Out of the tower: trot a little way into the free space.
            start(i, .running, for: 6)
            if let lane = lanes.first(where: { $0.contains(cats[i].x, margin: cats[i].radius) }) {
                cats[i].destination = clamp(cats[i].x + cats[i].direction * (40 + random() * 80), to: lane, for: i)
            }
        }
    }
    private func comeOut(_ i: Int, _ dt: Double) {
        guard !cats[i].homeBound, let homeX, !lanes.isEmpty else { return }
        cats[i].outDelay -= dt
        guard cats[i].outDelay <= 0 else { return }
        let spot = lanes.map { clamp(homeX, to: $0, for: i) }.min { abs($0 - homeX) < abs($1 - homeX) }!
        cats[i].home = false; cats[i].visible = true; cats[i].hiddenFor = 0; cats[i].x = homeX
        beginHop(i, from: homeX, to: spot, entering: false)
    }
    // Mouse handling: a held cat stays inside its own free interval and is never carried over menus or icons.
    /// Where a held cat can be carried: its own free space, or both sides of the notch joined through it.
    func carryLane(for i: Int) -> Lane? {
        if let ends = tunnelEnds() {
            let joined = Lane(lower: ends.left.lower, upper: ends.right.upper)
            if joined.contains(cats[i].x, margin: cats[i].radius) { return joined }
        }
        return lanes.first { $0.contains(cats[i].x, margin: cats[i].radius) }
    }
    func catIndex(at x: Double) -> Int? {
        cats.indices.filter { cats[$0].visible && cats[$0].hiddenFor <= 0 && cats[$0].action != .hopping && !cats[$0].inTunnel && abs(cats[$0].x - x) < 13 * cats[$0].size.scale }
            .min { abs(cats[$0].x - x) < abs(cats[$1].x - x) }
    }
    func grab(_ i: Int) {
        guard cats.indices.contains(i), cats[i].visible else { return }
        start(i, .held, for: .infinity); cats[i].velocity = 0; cats[i].swing = 0; cats[i].heldLean = 0; cats[i].heldLeanVelocity = 0
    }
    func drag(_ i: Int, to x: Double, dt: Double) {
        guard cats.indices.contains(i), cats[i].action == .held, let lane = carryLane(for: i) else { return }
        let next = clamp(x, to: lane, for: i)
        cats[i].swing += ((next - cats[i].x) / max(dt, 0.001) - cats[i].swing) * min(1, dt * 12)
        cats[i].x = next; cats[i].destination = next
    }
    func release(_ i: Int) {
        guard cats.indices.contains(i), cats[i].action == .held else { return }
        start(i, .grooming, for: 2 + random() * 2); cats[i].swing = 0
        // Let go behind the notch: it walks out of the nearer side.
        if !lanes.contains(where: { $0.contains(cats[i].x, margin: cats[i].radius) }), let ends = tunnelEnds() {
            start(i, .walking, for: 14)
            cats[i].direction = cats[i].x < (ends.left.upper + ends.right.lower) / 2 ? -1 : 1
            cats[i].velocity = 0; cats[i].inTunnel = true
        }
    }
    /// A ball drops at a random spot; every cat sharing that free space goes for it.
    func play() {
        guard !quiet else { return }
        let wide = lanes.filter { $0.width >= 120 }
        func eligible(_ i: Int, _ lane: Lane) -> Bool {
            cats[i].visible && !cats[i].homeBound && ![.held, .hopping].contains(cats[i].action) && lane.contains(cats[i].x, margin: cats[i].radius)
        }
        let withCats = wide.filter { lane in cats.indices.contains { eligible($0, lane) } }
        let pool = withCats.isEmpty ? wide : withCats
        guard !pool.isEmpty else { return }
        let lane = pool[min(pool.count - 1, Int(random() * Double(pool.count)))]
        ball = ToyBall(x: lane.lower + 10 + random() * (lane.width - 20), velocity: (random() - 0.5) * 60, lifetime: 22, lane: lane)
        for i in cats.indices where eligible(i, lane) {
            start(i, .playing, for: 14 + random() * 8)
            cats[i].pounceCooldown = random() * 0.8   // not everyone reacts at the same instant
        }
    }

}
