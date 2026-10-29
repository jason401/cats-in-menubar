import Cocoa
// Usage: xcrun swift tools/walk_sample.swift <stand frame png> <output folder> [frames]
// Makes a motion reference (design/walk-sample-claude/): leg columns are cut from the standing frame and
// rotated about shoulder/hip in the cat walk order (left hind, left fore, right hind, right fore).
// Planted paws move back exactly as far as the body moves forward. Leg column positions fit the v5 orange stand frame.
// Cut-out walk prototype: legs cut from the standing frame, rotated about shoulder/hip.
let src = CommandLine.arguments[1], out = CommandLine.arguments[2]
let frames = Int(CommandLine.arguments[3]) ?? 8
let size = 256
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let info = CGImageAlphaInfo.premultipliedLast.rawValue
func context() -> CGContext { CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: space, bitmapInfo: info)! }
let base = context()
base.draw(NSImage(contentsOfFile: src)!.cgImage(forProposedRect: nil, context: nil, hints: nil)!, in: CGRect(x: 0, y: 0, width: size, height: size))
let pixels = base.data!.assumingMemoryBound(to: UInt8.self)   // row 0 = top

// Leg columns (source px from the left) and where legs leave the body (rows from the top).
struct Leg { var x0: Int; var x1: Int; var phase: Double; var near: Bool; var front: Bool }
let legs = [Leg(x0: 85, x1: 118, phase: 0.50, near: false, front: false),  // right hind (far)
            Leg(x0: 150, x1: 176, phase: 0.75, near: false, front: true),  // right fore (far)
            Leg(x0: 46, x1: 85, phase: 0.00, near: true, front: false),    // left hind (near)
            Leg(x0: 176, x1: 204, phase: 0.25, near: true, front: true)]   // left fore (near)
let hidden = 164, feather = 178, cut = 182, pivotTop = 178, groundTop = 231
func piece(_ keep: (Int, Int) -> Double) -> CGImage {
    let c = context(); let p = c.data!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<size { for x in 0..<size {
        let a = keep(x, y); guard a > 0 else { continue }
        for k in 0..<4 { p[(y * size + x) * 4 + k] = UInt8(Double(pixels[(y * size + x) * 4 + k]) * a) }   // premultiplied
    } }
    return c.makeImage()!
}
// Legs start a little inside the body with a soft top edge, so drawn over the body the joint blends in.
let legImages = legs.map { leg in piece { x, y in
    guard x >= leg.x0 && x < leg.x1 && y >= hidden else { return 0 }
    return min(1, Double(y - hidden) / Double(feather - hidden))
} }
// The original thighs just below the cut, fading out downward: shows through if adjacent legs part.
let underlay = piece { x, y in
    guard y >= cut, y < cut + 20, legs.contains(where: { x >= $0.x0 && x < $0.x1 }) else { return 0 }
    return 1 - Double(y - cut) / 20
}
let body = piece { x, y in y >= cut && legs.contains { x >= $0.x0 && x < $0.x1 } ? 0 : 1 }

// Gait: stance 62 % of the cycle, planted paw moves back exactly as far as the body moves forward.
let legLength = Double(groundTop - pivotTop)
let reach = 20.0                                 // paw travel either side of the hip, source px
let stance = 0.62
let cycle = 2 * reach / stance                   // body travel per cycle, source px
func pawX(_ t: Double) -> (x: Double, lift: Double) {
    if t < stance { return (reach - 2 * reach * t / stance, 0) }       // planted: forward → back, linear
    let s = (t - stance) / (1 - stance)                                 // swing: back → forward, lifted
    let eased = s * s * (3 - 2 * s)
    return (-reach + 2 * reach * eased, sin(s * .pi) * 9)
}
let pivotUp = Double(size - pivotTop), groundUp = Double(size - groundTop)
for f in 0..<frames {
    let t = Double(f) / Double(frames)
    let poses = legs.map { leg -> (angle: Double, lift: Double, planted: Bool) in
        let p = pawX((t + leg.phase).truncatingRemainder(dividingBy: 1))
        return (asin(p.x / legLength), p.lift, p.lift == 0)
    }
    // Body drops a little while planted legs are spread, so planted paws reach the ground.
    let planted = poses.filter(\.planted)
    let reachDown = planted.map { legLength * cos($0.angle) }.reduce(0, +) / Double(max(1, planted.count))
    let drop = legLength - reachDown
    let c = context()
    c.interpolationQuality = .high
    c.translateBy(x: 0, y: -drop)
    c.draw(underlay, in: CGRect(x: 0, y: 0, width: size, height: size))
    c.draw(body, in: CGRect(x: 0, y: 0, width: size, height: size))
    for pass in [false, true] {                  // body, then far legs, then near legs on top
        for (i, leg) in legs.enumerated() where leg.near == pass {
            let pose = poses[i]
            let pivotX = Double(leg.x0 + leg.x1) / 2
            // Planted legs stretch or squash a hair so the paw sits exactly on the ground; swinging legs fold to lift the paw.
            let target = pose.planted ? (pivotUp - drop - groundUp) / (legLength * cos(pose.angle)) : (legLength - pose.lift) / legLength
            c.saveGState()
            c.translateBy(x: pivotX, y: pivotUp)
            c.rotate(by: pose.angle)
            c.scaleBy(x: 1, y: target)
            c.translateBy(x: -pivotX, y: -pivotUp)
            c.draw(legImages[i], in: CGRect(x: 0, y: 0, width: size, height: size))
            c.restoreGState()
        }
    }
    let rep = NSBitmapImageRep(cgImage: c.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/walk\(f).png"))
}
print(String(format: "cycle %.1f source px = %.2f pt per cycle", cycle, cycle * 24 / 180))
