import Cocoa

/// How fast the wheel cat runs for a given CPU use. Like RunCat: the busier the Mac, the faster the cat.
/// Under 5 % it loafs, up to 20 % it walks, above that it gallops faster and faster.
struct WheelPace {
    enum Gait { case rest, walk, run }
    private(set) var cpu = 0.0
    private(set) var gait = Gait.rest
    private var started = false

    /// Averages two samples and keeps a gap between up and down thresholds, so a value
    /// near a boundary does not flip the gait back and forth.
    mutating func update(cpu sample: Double) {
        let value = min(1, max(0, sample))
        cpu = started ? cpu * 0.5 + value * 0.5 : value
        started = true
        switch gait {
        case .rest: if cpu > 0.22 { gait = .run } else if cpu > 0.06 { gait = .walk }
        case .walk: if cpu > 0.22 { gait = .run } else if cpu < 0.04 { gait = .rest }
        case .run: if cpu < 0.04 { gait = .rest } else if cpu < 0.18 { gait = .walk }
        }
    }
    /// Cells per second the cat steps through (0 = holds still) and how fast the teeth turn.
    /// Low Power Mode caps the frame rate at 12 fps and slows the wheel with it, so each frame turns
    /// the same angle and the teeth never seem to spin backwards.
    struct Motion: Equatable { var frameRate: Double; var degreesPerSecond: Double }
    func motion(lowPower: Bool = false) -> Motion { motion(maxFrameRate: lowPower ? Self.lowPowerFPS : .infinity) }
    /// The same motion at no more than `maxFrameRate` cells a second, the wheel slowed with it
    /// (Low Power Mode, or the AI Face board, which shows only so many pictures a second).
    func motion(maxFrameRate: Double) -> Motion {
        let full: Motion
        switch gait {
        case .rest: full = Motion(frameRate: 0, degreesPerSecond: 0)
        case .walk:
            let t = min(1, max(0, (cpu - 0.05) / 0.15))
            full = Motion(frameRate: 6 + 4 * t, degreesPerSecond: 25 + 15 * t)
        case .run:
            // Gallop 1 → 3 strides a second (8 cells each), wheel 60 → 180°/s.
            let t = min(1, max(0, (cpu - 0.2) / 0.8))
            full = Motion(frameRate: 8 * (1 + 2 * t), degreesPerSecond: 60 + 120 * t)
        }
        guard full.frameRate > maxFrameRate else { return full }
        let slow = maxFrameRate / full.frameRate
        return Motion(frameRate: maxFrameRate, degreesPerSecond: full.degreesPerSecond * slow)
    }
    static let lowPowerFPS = 12.0
}

/// The wheel's band as a battery gauge. It does not turn, so it stays readable: two thin rims run all the way
/// around and the charge fills the track between them clockwise from 12 o'clock. Color follows the charge alone, also while
/// charging: green above 20 %, red at 20 % or less. Mono draws the green share in the menu bar's own color
/// (template tint) but keeps red as a warning. Off, or a Mac without a battery: the plain solid band.
struct WheelBattery: Equatable {
    enum Ink: Equatable { case template, green, red }
    /// Whole percent shown, so a change under 1 % does not redraw anything.
    var percent = 100
    var ink = Ink.template
    var rims = false
    var share: Double { Double(percent) / 100 }
    static let plain = WheelBattery()
    static let lowPercent = 20
    static func gauge(hasBattery: Bool, level: Double, enabled: Bool, mono: Bool) -> WheelBattery {
        guard enabled, hasBattery else { return .plain }
        let level = min(1, max(0, level)), percent = Int((level * 100).rounded())
        // Color from the real charge, so 20.4 % is still green even though its arc shows 20 %.
        let ink: Ink = level <= Double(lowPercent) / 100 ? .red : mono ? .template : .green
        return WheelBattery(percent: percent, ink: ink, rims: true)
    }
    /// Arc length of the filled share in degrees.
    var degrees: Double { share * 360 }
    /// The color the overlay draws, nil when the template image carries the fill.
    var color: NSColor? {
        switch ink { case .template: return nil; case .green: return .systemGreen; case .red: return .systemRed }
    }
}

extension TowerIcon {
    /// Wheel on the left, tower on the right: 20 + 2 + 18 pt.
    static let wheelSize = NSSize(width: 40, height: 20)
    /// Where the tower's 18 pt box starts in the wheel image.
    static let towerOffset: CGFloat = 22
    /// Center of the wheel inside the 40 x 20 image, low enough that the teeth stay inside it.
    static let wheelCenter = NSPoint(x: 10, y: 10.25)
    /// Inner and outer radius of the solid band; the cat runs on the inner edge (14 pt across).
    static let wheelInner: CGFloat = 7.0
    static let wheelOuter: CGFloat = 9.0
    /// Height of the 12 teeth outside the band. Only the teeth turn, so the band can later show a level.
    static let wheelTooth: CGFloat = 0.75
    /// Width of the thin rims that outline a battery gauge's track.
    static let wheelRim: CGFloat = 0.5
    /// The wheel: a fixed band, teeth turned by `angle` degrees, and a low stand. With a battery gauge the
    /// template keeps the two rims all around plus the Mono share between them; a green or red share is drawn
    /// between the rims in color by `WheelOverlayView`.
    static func drawWheel(angle: Double, tooth: CGFloat = wheelTooth, battery: WheelBattery = .plain) {
        let c = wheelCenter
        if battery.ink == .template { battery.rims ? drawShare(level: battery.share) : drawBand(level: battery.share) }
        if battery.rims { drawRims() }
        // Teeth about 10° wide, 30° apart, a little narrower at the tip. They start just inside the
        // band so no seam shows where they join it.
        let teeth = NSBezierPath()
        let root = wheelOuter - 0.2, tip = wheelOuter + tooth
        func point(_ r: CGFloat, _ degrees: Double) -> NSPoint {
            let a = degrees * .pi / 180
            return NSPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
        }
        for i in 0..<12 {
            let a = angle + Double(i) * 30
            teeth.move(to: point(root, a - 5)); teeth.line(to: point(tip, a - 4)); teeth.line(to: point(tip, a + 4)); teeth.line(to: point(root, a + 5))
            teeth.close()
        }
        teeth.fill()
        NSBezierPath(ovalIn: NSRect(x: c.x - 0.9, y: c.y - 0.9, width: 1.8, height: 1.8)).fill()
        // A thin base the lowest teeth brush past.
        NSBezierPath(roundedRect: NSRect(x: c.x - 5.5, y: 0, width: 11, height: 0.6), xRadius: 0.3, yRadius: 0.3).fill()
    }
    /// Degrees (0 = 3 o'clock, counterclockwise) where a share filled clockwise from 12 o'clock ends.
    static func gaugeEnd(share: Double) -> Double { 90 - min(1, max(0, share)) * 360 }
    /// The ring between radii `inner` and `outer` from 12 o'clock clockwise over `from`...`to` (shares of a turn).
    private static func ring(inner: CGFloat, outer: CGFloat, from: Double, to: Double) {
        let c = wheelCenter, a = min(1, max(0, from)), b = min(1, max(a, to))
        guard b > a else { return }
        let band = NSBezierPath()
        band.windingRule = .evenOdd
        if b - a >= 1 {
            band.appendOval(in: NSRect(x: c.x - outer, y: c.y - outer, width: outer * 2, height: outer * 2))
            band.appendOval(in: NSRect(x: c.x - inner, y: c.y - inner, width: inner * 2, height: inner * 2))
        } else {
            let start = CGFloat(gaugeEnd(share: a)), end = CGFloat(gaugeEnd(share: b))
            band.appendArc(withCenter: c, radius: outer, startAngle: start, endAngle: end, clockwise: true)
            band.appendArc(withCenter: c, radius: inner, startAngle: end, endAngle: start, clockwise: false)
            band.close()
        }
        band.fill()
    }
    /// The band between `wheelInner` and `wheelOuter`. `level` 0...1 fills that share clockwise from
    /// the top; 1 is the whole ring.
    static func drawBand(level: Double) { ring(inner: wheelInner, outer: wheelOuter, from: 0, to: level) }
    /// A gauge's filled `level` in the track between the rims, so the rims stay visible over it.
    static func drawShare(level: Double) { ring(inner: wheelInner + wheelRim, outer: wheelOuter - wheelRim, from: 0, to: level) }
    /// Thin inner and outer rims all the way around a battery gauge.
    static func drawRims() {
        ring(inner: wheelOuter - wheelRim, outer: wheelOuter, from: 0, to: 1)
        ring(inner: wheelInner, outer: wheelInner + wheelRim, from: 0, to: 1)
    }
    /// Center x of the tower inside a status button `rect` that holds the image centered.
    static func towerCenterX(in rect: NSRect, wheel: Bool) -> Double {
        wheel ? rect.minX + (rect.width - wheelSize.width) / 2 + towerOffset + 9 : rect.midX
    }
    /// Center x of the wheel inside a status button `rect` that holds the wheel image centered.
    static func wheelCenterX(in rect: NSRect) -> Double { rect.minX + (rect.width - wheelSize.width) / 2 + wheelCenter.x }
}

/// The colored layer over the wheel: a green or red battery share, then the cat on top. It sits over the
/// template icon as its own view, so the tower and wheel keep the menu bar's automatic tinting and only these
/// are drawn in color. Clicks pass through.
/// When the next cat takes its turn: a fresh uniform random wait inside the chosen range at every swap.
/// Presets (the wheelSwapRange pref): 0 Off, 1 2–6 min, 2 5–15 min (default), 3 15–30 min.
enum WheelShift {
    static let ranges: [ClosedRange<Double>?] = [nil, 2...6, 5...15, 15...30]   // minutes
    static let defaultRange = 2

    /// Seconds until the next swap for a roll in 0...1, or nil when taking turns is off.
    static func interval(range: Int, roll: Double) -> Double? {
        guard ranges.indices.contains(range), let minutes = ranges[range] else { return nil }
        let t = min(1, max(0, roll))
        return (minutes.lowerBound + t * (minutes.upperBound - minutes.lowerBound)) * 60
    }

    /// The preset nearest an old fixed interval in minutes (by range midpoint); 0 or less is Off.
    static func preset(forMinutes old: Double) -> Int {
        guard old > 0 else { return 0 }
        return ranges.indices.dropFirst().min { abs(mid($0) - old) < abs(mid($1) - old) } ?? defaultRange
    }
    private static func mid(_ i: Int) -> Double { ranges[i].map { ($0.lowerBound + $0.upperBound) / 2 } ?? 0 }

    /// Once: a fixed wheelSwap value from an older version becomes the nearest range preset. Only the
    /// saved values in `domain` count, not registered defaults (which always answer wheelSwapRange = 2).
    static func migrate(_ defaults: UserDefaults, domain: String) {
        let saved = defaults.persistentDomain(forName: domain) ?? [:]
        guard let old = saved[Pref.wheelSwap] else { return }
        if saved[Pref.wheelSwapRange] == nil {
            defaults.set(preset(forMinutes: (old as? NSNumber)?.doubleValue ?? 15), forKey: Pref.wheelSwapRange)
        }
        defaults.removeObject(forKey: Pref.wheelSwap)
    }
}

final class WheelOverlayView: NSView {
    var coat = 0
    var cell = 0 { didSet { if cell != oldValue { needsDisplay = true } } }
    var battery = WheelBattery.plain { didSet { if battery != oldValue { needsDisplay = true } } }
    /// systemGreen and systemRed differ between dark and light menu bars.
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    /// Body length about 12 pt, so a galloping cat fits the 14 pt inside of the band.
    static let scale: CGFloat = 0.4
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The coat for the next shift in the wheel: never the same cat again, and one no cat of the colony
    /// wears now when there is one, so the same cat does not show twice.
    static func nextCoat(after current: Int, outside: Set<Int>, roll: Double) -> Int {
        let others = (0..<8).filter { $0 != current }
        let free = others.filter { !outside.contains($0) }
        let pool = free.isEmpty ? others : free
        return pool[min(pool.count - 1, max(0, Int(roll * Double(pool.count))))]
    }

    /// The cell for a gait and step: loaf still, walk and run loop through their cells.
    static func cell(_ gait: WheelPace.Gait, step: Int, coat: Int) -> Int {
        switch gait {
        case .rest: return SpriteAtlas.cell(.loaf, 0, coat: coat)
        case .walk: return SpriteAtlas.cell(.walk, step, coat: coat)
        case .run: return SpriteAtlas.cell(.run, step, coat: coat)
        }
    }
    /// Draws one cell with its paws on the band's inner edge and its body centered on the hub.
    /// `origin` is where the wheel image's (0, 0) lands, so previews can reuse the same placement.
    static func draw(cell index: Int, coat: Int, origin: NSPoint = .zero) {
        guard let name = SpriteAtlas.artworkName(for: coat), let sheet = SpriteAtlas.sheet(name),
              sheet.frames.indices.contains(index), let image = SpriteAtlas.cell(index, coat: coat) else { return }
        let factor = scale / CGFloat(sheet.pixelsPerPoint)
        // Center on the pose's first cell so the body does not jitter from cell to cell.
        let pose = SpriteAtlas.pose(of: index, coat: coat)
        let anchor = pose.map { SpriteAtlas.cell($0.pose, 0, coat: coat) } ?? index
        let frame = sheet.frames[sheet.frames.indices.contains(anchor) ? anchor : index]
        let middle = CGFloat(frame.left + frame.right) / 2
        let ground = NSPoint(x: origin.x + TowerIcon.wheelCenter.x, y: origin.y + TowerIcon.wheelCenter.y - TowerIcon.wheelInner + 0.4)
        let rect = NSRect(x: ground.x - middle * factor,
                          y: ground.y + CGFloat(sheet.ground - Double(sheet.cellHeight) + sheet.frames[index].lift) * factor,
                          width: CGFloat(sheet.cellWidth) * factor, height: CGFloat(sheet.cellHeight) * factor)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }
    /// The colored battery share between the rims, drawn under the cat.
    static func draw(battery: WheelBattery) {
        guard let color = battery.color else { return }
        color.setFill(); TowerIcon.drawShare(level: battery.share)
    }
    override func draw(_ dirtyRect: NSRect) { Self.draw(battery: battery); Self.draw(cell: cell, coat: coat) }
}
