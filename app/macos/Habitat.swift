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
    static let catRadius = 17.0
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

enum CatAction: String, CaseIterable { case sitting, walking, sleeping, grooming, playing, chasing }
struct Cat {
    var x: Double
    var destination: Double
    var direction = 1.0
    var velocity = 0.0
    var gait = 0.0          // distance walked, drives leg motion so feet never slide
    var turnCooldown = 0.0  // a cat must stand a moment before facing the other way
    var pounceCooldown = 0.0
    var action: CatAction = .sitting
    var remaining = 5.0
    var phase = 0.0
    var hiddenFor = 0.0
    var visible = false
    let coat: Int
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
    var random: () -> Double
    init(count: Int = 3, random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.random = random
        setCount(count)
    }
    func setCount(_ count: Int) {
        let count = max(1, min(3, count))
        while cats.count > count { cats.removeLast() }
        while cats.count < count {
            cats.append(Cat(x: -100, destination: -100, remaining: 2 + random() * 8, coat: cats.count))
        }
        reconcile()
    }
    func updateLanes(_ newLanes: [Lane]) {
        lanes = newLanes
        reconcile()
    }
    func reconcile() {
        for i in cats.indices {
            // Existing positions stay stable when space grows; never walk across an obstacle.
            if let lane = lanes.first(where: { $0.contains(cats[i].x, margin: Habitat.catRadius) }) {
                cats[i].destination = min(lane.upper - Habitat.catRadius, max(lane.lower + Habitat.catRadius, cats[i].destination))
                cats[i].visible = true
            } else if !lanes.isEmpty {
                let lane = lanes[i % lanes.count]
                cats[i].x = lane.lower + Habitat.catRadius + (lane.width - 2 * Habitat.catRadius) * (Double(i + 1) / Double(cats.count + 1))
                cats[i].destination = cats[i].x
                cats[i].hiddenFor = 0.45
                cats[i].velocity = 0
                cats[i].visible = true
                cats[i].action = .sitting
                cats[i].remaining = 2 + random() * 4
            } else { cats[i].visible = false }
        }
        if let toy = ball, !lanes.contains(where: { $0.lower <= toy.lane.lower && $0.upper >= toy.lane.upper }) {
            ball = nil
            for i in cats.indices where cats[i].action == .playing { cats[i].action = .sitting; cats[i].remaining = 1 }
        }
    }
    func choose(_ i: Int, lane: Lane) {
        let r = random()
        if quiet || r < 0.32 { cats[i].action = .sleeping; cats[i].remaining = 18 + random() * 50 }
        else if r < 0.54 { cats[i].action = .sitting; cats[i].remaining = 5 + random() * 12 }
        else if r < 0.70 { cats[i].action = .grooming; cats[i].remaining = 4 + random() * 7 }
        else if r < 0.88 || lane.width < 150 {
            cats[i].action = .walking
            cats[i].destination = lane.lower + Habitat.catRadius + random() * (lane.width - 2 * Habitat.catRadius)
            cats[i].remaining = 12
        } else {
            if ball == nil { ball = ToyBall(x: cats[i].x, velocity: cats[i].direction * 34, lane: lane) }
            if let toy = ball, lane.contains(toy.x, margin: 5) {
                cats[i].action = .playing; cats[i].remaining = 10 + random() * 8
            } else { cats[i].action = .sitting; cats[i].remaining = 4 }
        }
        // A rare short chase, only within the same connected free interval.
        if !quiet, cats[i].action == .walking, random() < 0.22,
           let friend = cats.indices.first(where: { $0 != i && cats[$0].visible && lane.contains(cats[$0].x, margin: Habitat.catRadius) && cats[$0].action == .walking }) {
            cats[i].action = .chasing
            cats[i].destination = cats[friend].x
            cats[i].remaining = 3
        }
    }
    func step(_ dt: Double) {
        let dt = min(max(dt, 0), 0.1)
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
            guard cats[i].visible, let lane = lanes.first(where: { $0.contains(cats[i].x, margin: Habitat.catRadius) }) else { continue }
            cats[i].hiddenFor = max(0, cats[i].hiddenFor - dt)
            cats[i].phase += dt
            cats[i].remaining -= dt
            if quiet && cats[i].action != .sleeping { cats[i].action = .sleeping; cats[i].remaining = 30 }
            if cats[i].remaining <= 0 { choose(i, lane: lane) }
            cats[i].turnCooldown = max(0, cats[i].turnCooldown - dt)
            cats[i].pounceCooldown = max(0, cats[i].pounceCooldown - dt)
            if cats[i].action == .playing {
                if var toy = ball, lane.contains(toy.x, margin: 5) {
                    // Side is taken from where the ball is, not where the cat faces, so it cannot oscillate.
                    let side = toy.x >= cats[i].x ? 1.0 : -1.0
                    if cats[i].pounceCooldown > 0 {
                        cats[i].destination = cats[i].x
                    } else if abs(toy.x - cats[i].x) < 14 && abs(cats[i].velocity) < 12 {
                        toy.velocity = side * (40 + random() * 35)
                        ball = toy
                        cats[i].pounceCooldown = 0.9 + random() * 1.4
                        cats[i].destination = cats[i].x
                    } else {
                        cats[i].destination = min(lane.upper - Habitat.catRadius, max(lane.lower + Habitat.catRadius, toy.x - side * 11))
                    }
                } else { cats[i].action = .sitting; cats[i].remaining = 3 }
            }
            let moving = [.walking, .chasing, .playing].contains(cats[i].action)
            let delta = moving ? cats[i].destination - cats[i].x : 0
            let maxSpeed = cats[i].action == .chasing ? 42.0 : (cats[i].action == .playing ? 30 : 15)
            let accel = cats[i].action == .walking ? 30.0 : 70  // idle actions also stop quickly
            var desired = 0.0
            if abs(delta) > 0.5 {
                let wanted = delta > 0 ? 1.0 : -1.0
                if wanted != cats[i].direction {
                    // Slow down, pause, then turn around.
                    if abs(cats[i].velocity) < 0.5 && cats[i].turnCooldown <= 0 { cats[i].direction = wanted; cats[i].turnCooldown = 0.6 }
                } else {
                    // Ease in and brake smoothly before the destination.
                    desired = wanted * min(maxSpeed, sqrt(2 * accel * abs(delta)))
                }
            } else if moving && cats[i].action != .playing && abs(cats[i].velocity) < 0.5 { cats[i].remaining = 0 }
            let change = desired - cats[i].velocity
            cats[i].velocity += max(-accel * dt, min(accel * dt, change))
            let before = cats[i].x
            cats[i].x += cats[i].velocity * dt
            cats[i].x = min(lane.upper - Habitat.catRadius, max(lane.lower + Habitat.catRadius, cats[i].x))
            if cats[i].x == lane.lower + Habitat.catRadius || cats[i].x == lane.upper - Habitat.catRadius { cats[i].velocity = 0 }
            cats[i].gait += abs(cats[i].x - before)
        }
    }
    func play() {
        guard !quiet, let i = cats.indices.first(where: { index in cats[index].visible && lanes.contains(where: { $0.contains(cats[index].x, margin: Habitat.catRadius) && $0.width >= 150 }) }),
              let lane = lanes.first(where: { $0.contains(cats[i].x, margin: Habitat.catRadius) }) else { return }
        ball = ToyBall(x: min(lane.upper - 5, cats[i].x + 12), velocity: 45, lane: lane)
        cats[i].action = .playing; cats[i].remaining = 20
    }
}
