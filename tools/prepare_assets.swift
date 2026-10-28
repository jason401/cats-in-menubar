import Cocoa

struct Layout: Codable { var rect: [Double]; var ground: Double; var head: [Double] }
struct SpriteInfo: Codable { var headX: Double; var footLift: Double; var width: Int; var height: Int }
let names = ["orange", "black", "white", "silver", "cream", "tuxedo", "calico", "siamese"]
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let input = root.appendingPathComponent("app/macos/Resources/Cats")
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let layout = try JSONDecoder().decode([Layout].self, from: Data(contentsOf: input.appendingPathComponent("layout.json")))
let held = NSBitmapImageRep(data: try Data(contentsOf: root.appendingPathComponent("design/held-cats-v1.png")))!.cgImage!
func largest(_ image: CGImage, in rect: CGRect) -> CGRect {
    let bounds = rect.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height)).integral
    let cut = image.cropping(to: bounds)!
    let w = cut.width, h = cut.height
    let rep = NSBitmapImageRep(cgImage: cut)
    var mask = [UInt8](repeating: 0, count: w * h)
    for y in 0..<h { for x in 0..<w { if rep.colorAt(x: x, y: y)!.alphaComponent > 0.12 { mask[y * w + x] = 1 } } }
    var biggest = 0, best = CGRect.zero
    for start in mask.indices where mask[start] == 1 {
        var queue = [start], cursor = 0, minX = w, minY = h, maxX = 0, maxY = 0
        mask[start] = 0
        while cursor < queue.count {
            let p = queue[cursor]; cursor += 1
            let x = p % w, y = p / w
            minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
            for (xx, yy) in [(x-1,y), (x+1,y), (x,y-1), (x,y+1)] where xx >= 0 && yy >= 0 && xx < w && yy < h {
                let next = yy * w + xx
                if mask[next] != 0 { mask[next] = 0; queue.append(next) }
            }
        }
        if queue.count > biggest {
            biggest = queue.count
            best = CGRect(x: bounds.minX + CGFloat(minX), y: bounds.minY + CGFloat(minY), width: CGFloat(maxX - minX + 1), height: CGFloat(maxY - minY + 1))
        }
    }
    precondition(biggest > 400, "Missing sprite in \(bounds)")
    return best.insetBy(dx: -1, dy: -1).intersection(bounds).integral
}
var metadata: [[SpriteInfo]] = []
for (coat, name) in names.enumerated() {
    let folder = output.appendingPathComponent(name)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let source = NSBitmapImageRep(data: try Data(contentsOf: input.appendingPathComponent(name + ".png")))!.cgImage!
    precondition(source.width == 1536 && source.height == 1024, "Unexpected source dimensions for \(name)")
    var frames: [SpriteInfo] = []
    for index in 0..<21 {
        let sourceImage: CGImage, crop: CGRect, anchor: Double, lift: Double
        if index < 18 {
            let spec = layout[index]
            sourceImage = source
            let original = CGRect(x: spec.rect[0], y: spec.rect[1], width: spec.rect[2], height: spec.rect[3])
            crop = largest(source, in: original.insetBy(dx: -10, dy: -8))
            anchor = original.minX + spec.head[0] - crop.minX
            lift = index < 6 ? 0 : spec.ground - crop.maxY
        } else {
            sourceImage = held
            let cellW = Double(held.width) / 3, cellH = Double(held.height) / 8
            crop = largest(held, in: CGRect(x: Double(index-18)*cellW, y: Double(coat)*cellH, width: cellW, height: cellH).insetBy(dx: -5, dy: -5))
            // Head/grab point stays stationary while the body changes sway pose.
            let rep = NSBitmapImageRep(cgImage: held.cropping(to: crop)!)
            var weightedX = 0.0, weight = 0.0
            for y in 0..<max(1, Int(Double(rep.pixelsHigh) * 0.28)) { for x in 0..<rep.pixelsWide {
                let a = rep.colorAt(x: x, y: y)!.alphaComponent
                if a > 0.12 { weightedX += Double(x) * a; weight += a }
            }}
            anchor = weightedX / max(1, weight)
            lift = 0
        }
        let image = sourceImage.cropping(to: crop)!
        let rep = NSBitmapImageRep(cgImage: image)
        try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("\(index).png"))
        frames.append(SpriteInfo(headX: anchor, footLift: lift, width: image.width, height: image.height))
    }
    metadata.append(frames)
}
try JSONEncoder().encode(metadata).write(to: output.appendingPathComponent("metadata.json"))
print("Prepared 8 independent cats × 21 sprite frames, including three held poses each")
