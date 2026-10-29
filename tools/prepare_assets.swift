import Cocoa

struct Registration: Decodable { var eyeX: Double; var eyeY: Double; var scale: Double; var baselineEye: Double?; var rootX: Double? }
struct SpriteInfo: Codable { var headX: Double; var footLift: Double; var width: Int; var height: Int }
let names = ["orange", "black", "white", "silver", "cream", "tuxedo", "calico", "siamese"]
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let input = root.appendingPathComponent("app/macos/Resources/Cats")
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
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
// Cropping a component's bounding box alone can retain a detached speck inside that box.
func isolated(_ source: CGImage) -> CGImage {
    let w=source.width, h=source.height
    let ctx=CGContext(data:nil,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,
        space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(source,in:CGRect(x:0,y:0,width:w,height:h))
    let pixels=ctx.data!.assumingMemoryBound(to:UInt8.self)
    var seen=[Bool](repeating:false,count:w*h), biggest:[Int]=[]
    for start in seen.indices where !seen[start] && pixels[start*4+3]>8 {
        var q=[start], cursor=0;seen[start]=true
        while cursor<q.count {
            let p=q[cursor];cursor+=1;let x=p%w,y=p/w
            for (xx,yy) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] where xx>=0 && yy>=0 && xx<w && yy<h {
                let n=yy*w+xx
                if !seen[n] && pixels[n*4+3]>8 {seen[n]=true;q.append(n)}
            }
        }
        if q.count>biggest.count {biggest=q}
    }
    var keep=[Bool](repeating:false,count:w*h)
    for p in biggest {keep[p]=true}
    for p in keep.indices where !keep[p] {for c in 0..<4 {pixels[p*4+c]=0}}
    return ctx.makeImage()!
}
// V3 sheets are kept per coat. Missing complete coat sets deliberately use orange.
let sheets: [(String, Int, Int, Double)] = [
    ("01-stand",1,1,180), ("02-idle",3,3,180), ("03-walk",8,4,180),
    ("04-run",8,4,175), ("05-turn",4,4,180), ("06-stand-to-sit",3,3,180),
    ("07-sit-to-loaf",3,3,160), ("08-loaf-to-sleep",3,3,115), ("09-sleep-breathe",2,2,95),
    ("10-groom",4,4,160), ("11-stretch",5,5,180), ("12-yawn",2,2,160),
    ("13-crouch",2,2,145), ("14-stalk",4,4,125), ("15-wiggle",2,2,125),
    ("16-pounce",4,4,160), ("17-bat",2,2,160), ("18-held-kick",2,2,180)
]
let v3 = input.appendingPathComponent("v3")
var metadata: [[SpriteInfo]] = []
var prepared: [String: [SpriteInfo]] = [:]
var resolved: [String] = []
for name in names {
    let own = v3.appendingPathComponent(name)
    let coat = sheets.allSatisfy { FileManager.default.fileExists(atPath: own.appendingPathComponent($0.0 + ".png").path) } ? name : "orange"
    resolved.append(coat)
    if let cached = prepared[coat] { metadata.append(cached); continue }
    let folder = output.appendingPathComponent(coat)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let registrationURL = v3.appendingPathComponent(coat).appendingPathComponent("registration.json")
    let registration = FileManager.default.fileExists(atPath: registrationURL.path)
        ? try JSONDecoder().decode([String: [Registration]].self, from: Data(contentsOf: registrationURL)) : [:]
    var frames: [SpriteInfo] = []
    for (sheet, count, columns, targetHeight) in sheets {
        let data = try Data(contentsOf: v3.appendingPathComponent(coat).appendingPathComponent(sheet + ".png"))
        let decoded = NSBitmapImageRep(data: data)!.cgImage!
        let rgba = CGContext(data: nil, width: decoded.width, height: decoded.height, bitsPerComponent: 8, bytesPerRow: decoded.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        rgba.draw(decoded, in: CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height))
        let bytes = rgba.data!.assumingMemoryBound(to: UInt8.self)
        // Suppress the generated stand's diffuse halo, and near-transparent colored specks elsewhere.
        for i in 0..<(decoded.width * decoded.height) {
            if bytes[i * 4 + 3] < (sheet == "01-stand" ? 217 : 9) {
                for channel in 0..<4 { bytes[i * 4 + channel] = 0 }
            }
        }
        let source = rgba.makeImage()!
        let rows = (count + columns - 1) / columns
        let crops = (0..<count).map { i -> CGRect in
            // Rounded boundaries support the generated sheets whose widths aren't divisible by column count.
            let x0 = (Double(i % columns) * Double(source.width) / Double(columns)).rounded()
            let x1 = (Double(i % columns + 1) * Double(source.width) / Double(columns)).rounded()
            let y0 = (Double(i / columns) * Double(source.height) / Double(rows)).rounded()
            let y1 = (Double(i / columns + 1) * Double(source.height) / Double(rows)).rounded()
            return largest(source, in: CGRect(x: x0, y: y0, width: x1-x0, height: y1-y0))
        }
        // One scale per cycle preserves leg movement; never resize every pose to its own bounding box.
        let factor = min(targetHeight / Double(crops.map(\.height).max()!), 240 / Double(crops.map(\.width).max()!))
        if let entries = registration[sheet] { precondition(entries.count == count, "Missing authored landmarks for \(sheet)") }
        for (index, crop) in crops.enumerated() {
            let authored = registration[sheet]?[index]
            // Wider transparent canvas accommodates extension without shrinking the cat to its tail-inclusive width.
            let canvasWidth = authored == nil ? 256 : 384
            let context = CGContext(data: nil, width: canvasWidth, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            let scale = authored?.scale ?? factor
            let w = crop.width * scale, h = crop.height * scale
            let cellX = (Double(index % columns) * Double(source.width) / Double(columns)).rounded()
            let cellY = (Double(index / columns) * Double(source.height) / Double(rows)).rounded()
            let anchor = authored.map { ($0.eyeX + cellX - crop.minX) * scale } ?? w * (sheet == "18-held-kick" ? 0.72 : 0.87)
            let headX = authored == nil ? 216.0 : 300.0
            // Walk/run hold the actual eye height; airborne foot lift survives. Stretch anchors its planted hind paw.
            var x = headX - anchor
            if let root = authored?.rootX { x = 165 - (root + cellX - crop.minX) * scale }
            let y = authored.flatMap { entry in entry.baselineEye.map {
                24 + $0 - (crop.maxY - cellY - entry.eyeY) * scale
            }} ?? 24
            precondition(x >= -1 && x + w <= Double(canvasWidth) + 1 && y >= 0 && y + h <= 256,
                         "Authored pose exceeds canvas: \(sheet) frame \(index)")
            context.interpolationQuality = .high
            context.draw(isolated(source.cropping(to: crop)!), in: CGRect(x: x, y: y, width: w, height: h))
            let out = NSBitmapImageRep(cgImage: context.makeImage()!)
            try out.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("\(frames.count).png"))
            frames.append(SpriteInfo(headX: headX, footLift: -24, width: canvasWidth, height: 256))
        }
    }
    precondition(frames.count == 62)
    prepared[coat] = frames; metadata.append(frames)
}
try JSONEncoder().encode(metadata).write(to: output.appendingPathComponent("metadata.json"))
try JSONEncoder().encode(resolved).write(to: output.appendingPathComponent("coats.json"))
print("Prepared v3: 62 frames per artwork set; coat fallback: \(resolved)")
