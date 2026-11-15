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
    /// Cells per second the cat steps through (0 = holds still) and how fast the tread turns.
    /// Low Power Mode caps the frame rate at 12 fps and slows the tread with it, so each frame turns
    /// the same angle and the rungs never seem to spin backwards.
    struct Motion: Equatable { var frameRate: Double; var degreesPerSecond: Double }
    func motion(lowPower: Bool = false) -> Motion {
        let full: Motion
        switch gait {
        case .rest: full = Motion(frameRate: 0, degreesPerSecond: 0)
        case .walk:
            let t = min(1, max(0, (cpu - 0.05) / 0.15))
            full = Motion(frameRate: 6 + 4 * t, degreesPerSecond: 25 + 15 * t)
        case .run:
            // Gallop 1 → 3 strides a second (8 cells each), tread 60 → 180°/s.
            let t = min(1, max(0, (cpu - 0.2) / 0.8))
            full = Motion(frameRate: 8 * (1 + 2 * t), degreesPerSecond: 60 + 120 * t)
        }
        guard lowPower, full.frameRate > Self.lowPowerFPS else { return full }
        let slow = Self.lowPowerFPS / full.frameRate
        return Motion(frameRate: Self.lowPowerFPS, degreesPerSecond: full.degreesPerSecond * slow)
    }
    static let lowPowerFPS = 12.0
}

extension TowerIcon {
    /// Tower on the left, wheel on the right: 18 + 2 + 20 pt.
    static let wheelSize = NSSize(width: 40, height: 20)
    /// Center and inner tread radius of the wheel inside the 40 x 20 image.
    static let wheelCenter = NSPoint(x: 30, y: 10.6)
    static let wheelInner: CGFloat = 6.9
    /// Outer rim radius. With the strokes, the band from `wheelInner` out is about 3 pt (6 px on Retina).
    static let wheelOuter: CGFloat = 9.0
    /// The wheel's frame (rim, rungs and stand). Rungs turn with `angle` degrees.
    static func drawWheel(angle: Double) {
        let c = wheelCenter
        // A ladder band: a bold outer rim and a thin tread ring, joined by rungs across the whole band,
        // so the rungs and the gaps between them read as turning even at actual size.
        let rim = NSBezierPath(ovalIn: NSRect(x: c.x - wheelOuter, y: c.y - wheelOuter, width: wheelOuter * 2, height: wheelOuter * 2))
        rim.lineWidth = 1.3
        rim.stroke()
        let tread = NSBezierPath(ovalIn: NSRect(x: c.x - wheelInner, y: c.y - wheelInner, width: wheelInner * 2, height: wheelInner * 2))
        tread.lineWidth = 0.6
        tread.stroke()
        let rungs = NSBezierPath()
        rungs.lineWidth = 1.1
        rungs.lineCapStyle = .butt
        for i in 0..<12 {
            let a = (angle + Double(i) * 30) * .pi / 180
            rungs.move(to: NSPoint(x: c.x + wheelInner * cos(a), y: c.y + wheelInner * sin(a)))
            rungs.line(to: NSPoint(x: c.x + wheelOuter * cos(a), y: c.y + wheelOuter * sin(a)))
        }
        rungs.stroke()
        NSBezierPath(ovalIn: NSRect(x: c.x - 0.9, y: c.y - 0.9, width: 1.8, height: 1.8)).fill()
        // A short stand under the rim.
        let strut = NSBezierPath()
        strut.move(to: NSPoint(x: c.x - 2.6, y: 0.8)); strut.line(to: NSPoint(x: c.x + 2.6, y: 0.8))
        strut.line(to: NSPoint(x: c.x + 1.3, y: 2.1)); strut.line(to: NSPoint(x: c.x - 1.3, y: 2.1)); strut.close()
        strut.fill()
        NSBezierPath(roundedRect: NSRect(x: c.x - 6.2, y: 0, width: 12.4, height: 1.2), xRadius: 0.6, yRadius: 0.6).fill()
    }
}

/// The colored cat inside the wheel. It sits over the template icon as its own layer, so the tower and
/// wheel keep the menu bar's automatic tinting and only the cat is drawn in color. Clicks pass through.
final class WheelCatView: NSView {
    var coat = 0
    var cell = 0 { didSet { if cell != oldValue { needsDisplay = true } } }
    /// Body length about 12 pt, so a galloping cat fits the 13.8 pt tread.
    static let scale: CGFloat = 0.4
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The coat for the next shift in the wheel: never the same cat again, and one that is not out
    /// playing right now when there is one, so the same cat does not show twice.
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
    /// Draws one cell with its paws on the lowest rung and its body centered on the hub.
    /// `origin` is where the wheel image's (20, 0) lands, so previews can reuse the same placement.
    static func draw(cell index: Int, coat: Int, origin: NSPoint = .zero) {
        guard let name = SpriteAtlas.artworkName(for: coat), let sheet = SpriteAtlas.sheet(name),
              sheet.frames.indices.contains(index), let image = SpriteAtlas.cell(index, coat: coat) else { return }
        let factor = scale / CGFloat(sheet.pixelsPerPoint)
        // Center on the pose's first cell so the body does not jitter from cell to cell.
        let pose = SpriteAtlas.pose(of: index, coat: coat)
        let anchor = pose.map { SpriteAtlas.cell($0.pose, 0, coat: coat) } ?? index
        let frame = sheet.frames[sheet.frames.indices.contains(anchor) ? anchor : index]
        let middle = CGFloat(frame.left + frame.right) / 2
        let ground = NSPoint(x: origin.x + TowerIcon.wheelCenter.x - 20, y: origin.y + TowerIcon.wheelCenter.y - TowerIcon.wheelInner + 0.4)
        let rect = NSRect(x: ground.x - middle * factor,
                          y: ground.y + CGFloat(sheet.ground - Double(sheet.cellHeight) + sheet.frames[index].lift) * factor,
                          width: CGFloat(sheet.cellWidth) * factor, height: CGFloat(sheet.cellHeight) * factor)
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
    }
    override func draw(_ dirtyRect: NSRect) { Self.draw(cell: cell, coat: coat) }
}
