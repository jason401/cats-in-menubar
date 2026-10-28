import Cocoa

// Checks an animation strip (see design/ART_GUIDE.md): draws each cell side by side, an onion skin of all
// cells on top of each other, and the frames at actual menu bar size (1x) in the bottom row.
// Usage: xcrun swift tools/onion_strip.swift <out.png> <strip.png> <frame count> [cell size, default 256]
let args = CommandLine.arguments
guard args.count >= 4, let count = Int(args[3]), count > 0 else {
    print("usage: onion_strip.swift <out.png> <strip.png> <frame count> [cell size]"); exit(1)
}
let cellSize = args.count > 4 ? Int(args[4]) ?? 256 : 256
guard let strip = NSImage(contentsOfFile: args[2])?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("cannot read \(args[2])"); exit(1)
}
let cells = (0..<count).map { strip.cropping(to: CGRect(x: $0 * cellSize, y: 0, width: cellSize, height: min(cellSize, strip.height)))! }
let actual = 24.0 / 180.0                       // source px to menu bar pt, as in SpriteAtlas.sourceScale
let small = Int((Double(cellSize) * actual).rounded())
let width = cellSize * (count + 1), height = cellSize + small * 3 + 30
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setFillColor(CGColor(gray: 0.15, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
let top = CGFloat(small * 3 + 30)
// Ground line at 232 px from the top of each cell.
context.setFillColor(CGColor(gray: 1, alpha: 0.25))
context.fill(CGRect(x: 0, y: top + CGFloat(cellSize - 232), width: CGFloat(width), height: 1))
context.interpolationQuality = .high
for (i, cell) in cells.enumerated() {
    context.draw(cell, in: CGRect(x: CGFloat(i * cellSize), y: top, width: CGFloat(cellSize), height: CGFloat(cellSize)))
}
context.setAlpha(0.25)
for cell in cells { context.draw(cell, in: CGRect(x: CGFloat(count * cellSize), y: top, width: CGFloat(cellSize), height: CGFloat(cellSize))) }
context.setAlpha(1)
// Actual size, enlarged 3x with hard pixels so the real menu bar look is visible.
for (i, cell) in cells.enumerated() {
    let tiny = CGContext(data: nil, width: small, height: small, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    tiny.interpolationQuality = .high
    tiny.draw(cell, in: CGRect(x: 0, y: 0, width: small, height: small))
    context.interpolationQuality = .none
    context.draw(tiny.makeImage()!, in: CGRect(x: 10 + i * (small * 3 + 10), y: 10, width: small * 3, height: small * 3))
}
let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
print("Wrote \(args[1])")
