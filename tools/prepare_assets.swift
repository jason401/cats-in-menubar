import Cocoa

struct Registration: Decodable { var eyeX: Double; var eyeY: Double; var scale: Double; var baselineEye: Double?; var rootX: Double? }
// One sheet per artwork set: 128 equal cells (8 x 16), unused cells transparent.
// The sheet's table of contents: each behavior's cells in play order. The app finds poses only by these names.
let poseNames = ["stand", "idle", "walk", "run", "turn", "sitDown", "sit", "loafDown", "loaf", "sleepDown", "sleep",
                 "groom", "stretch", "yawn", "crouch", "creep", "wiggle", "pounce", "bat", "held"]
// Cell order of the older 62-frame strip artwork.
let stripAnimations: [String: [Int]] = [
    "stand": [0], "idle": [1, 2, 3], "walk": Array(4...11), "run": Array(12...19), "turn": Array(20...23),
    "sitDown": [24, 25], "sit": [26], "loafDown": [27, 28], "loaf": [29], "sleepDown": [30, 31, 32], "sleep": [33, 34],
    "groom": Array(35...38), "stretch": Array(39...43), "yawn": [44, 45], "crouch": [46, 47], "creep": Array(48...51),
    "wiggle": [52, 53], "pounce": Array(54...57), "bat": [58, 59], "held": [60, 61]]
struct AtlasSource: Decodable {
    var cellWidth: Int; var cellHeight: Int; var headX: Double; var ground: Double
    var pixelsPerPoint: Double; var frameCount: Int; var walkStride: Double
    var animations: [String: [Int]]
}
struct SheetFrame: Codable { var lift: Double; var left: Double; var right: Double }
struct SheetInfo: Codable {
    var columns = 8, rows = 16, cellWidth = 384, cellHeight = 256
    var headX = 300.0, ground = 232.0
    var pixelsPerPoint = 7.5, walkStride = 12.0
    var animations = stripAnimations
    var frames: [SheetFrame]
    var variants: [String: [Int]]   // "<density>x-<size>": cell width and height in screen pixels
}
// Menu bar copies are shrunk here once, for 1x and 2x screens and every cat size (CatSize.scale).
let sizeScales = [0.64, 0.82, 1.0]
let sourceScale = 24.0 / 180.0
let cell = (width: 384, height: 256)
func rgbaContext(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func resample(_ image: CGImage, _ width: Int, _ height: Int) -> CGImage {
    let context = rgbaContext(width, height)
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage()!
}
/// Halving step by step keeps thin outlines clean instead of losing them in one big jump.
func shrink(_ image: CGImage, _ width: Int, _ height: Int) -> CGImage {
    var current = image
    while current.width / 2 >= width * 2 && current.height / 2 >= height * 2 { current = resample(current, current.width / 2, current.height / 2) }
    return resample(current, width, height)
}
/// Lowest solid row (from the top) and left/right edges of a cell, in source pixels.
func extent(_ image: CGImage) -> (bottom: Double, left: Double, right: Double) {
    let context = rgbaContext(image.width, image.height)
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixels = context.data!.assumingMemoryBound(to: UInt8.self), stride = context.bytesPerRow
    var bottom = 0, left = image.width, right = 0
    for row in 0..<image.height { for x in 0..<image.width where pixels[row * stride + x * 4 + 3] > 100 {
        bottom = max(bottom, row); left = min(left, x); right = max(right, x)
    }}
    return (Double(bottom), Double(left), Double(right))
}
func writePNG(_ image: CGImage, _ url: URL) throws {
    try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: url)
}
func writeSheet(_ frames: [CGImage], to folder: URL, source: AtlasSource? = nil) throws {
    var info0 = SheetInfo(frames: [], variants: [:])
    if let source {
        precondition(source.pixelsPerPoint > 0 && source.walkStride > 0)
        info0.cellWidth = source.cellWidth; info0.cellHeight = source.cellHeight
        info0.headX = source.headX; info0.ground = source.ground
        info0.pixelsPerPoint = source.pixelsPerPoint; info0.walkStride = source.walkStride
        info0.animations = source.animations
    }
    let named = poseNames.map { info0.animations[$0] ?? [] }
    precondition(named.allSatisfy { !$0.isEmpty && $0.allSatisfy(frames.indices.contains) }, "Every pose needs cells inside the sheet")
    precondition(Set(named.joined()).count == named.joined().count, "A cell belongs to one pose")
    precondition(frames.count <= info0.columns * info0.rows, "More frames than sheet cells")
    // Paws go on the ground line per frame; a gallop or pounce moves as a whole, so only true flight frames leave the ground.
    let extents = frames.map(extent)
    func lowest(_ cells: [Int]) -> Double { cells.map { extents[$0].bottom }.max()! }
    let run = info0.animations["run"]!, pounce = info0.animations["pounce"]!, held = info0.animations["held"]!
    let frameInfo = extents.enumerated().map { index, e -> SheetFrame in
        let lift = switch index {
        case _ where run.contains(index): lowest(run) - info0.ground
        case _ where pounce.contains(index): lowest(pounce) - info0.ground
        case _ where held.contains(index): 0.0
        default: e.bottom - info0.ground
        }
        return SheetFrame(lift: lift, left: e.left, right: e.right)
    }
    var variants: [String: [Int]] = [:]
    for density in [0, 1, 2] {   // 0 = the original, high quality
        for (size, scale) in sizeScales.enumerated() where density > 0 || size == 0 {
            let factor = density == 0 ? 1 : scale * Double(density) / info0.pixelsPerPoint
            let w = Int((Double(info0.cellWidth) * factor).rounded()), h = Int((Double(info0.cellHeight) * factor).rounded())
            let sheet = rgbaContext(w * info0.columns, h * info0.rows)
            for (index, frame) in frames.enumerated() {
                let column = index % info0.columns, row = index / info0.columns
                let image = density == 0 ? frame : shrink(frame, w, h)
                sheet.draw(image, in: CGRect(x: column * w, y: (info0.rows - 1 - row) * h, width: w, height: h))
            }
            let name = density == 0 ? "sheet.png" : "sheet-\(density)x-\(size).png"
            try writePNG(sheet.makeImage()!, folder.appendingPathComponent(name))
            if density > 0 { variants["\(density)x-\(size)"] = [w, h] }
        }
    }
    var info = info0; info.frames = frameInfo; info.variants = variants
    try JSONEncoder().encode(info).write(to: folder.appendingPathComponent("sheet.json"))
}
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
var prepared = Set<String>()
var resolved: [String] = []
for name in names {
    let own = v3.appendingPathComponent(name)
    let single = input.appendingPathComponent("sheets/\(name).png")
    let hasSingle = FileManager.default.fileExists(atPath: single.path)
    let coat = hasSingle || sheets.allSatisfy { FileManager.default.fileExists(atPath: own.appendingPathComponent($0.0 + ".png").path) } ? name : "orange"
    resolved.append(coat)
    if prepared.contains(coat) { continue }
    let folder = output.appendingPathComponent(coat)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    // A registered atlas is already authored in runtime coordinates. Never crop, fit or rescale
    // its individual poses: that would change head size, limb length and animation endpoints.
    let atlasURL = input.appendingPathComponent("sheets/\(coat).png")
    if FileManager.default.fileExists(atPath: atlasURL.path) {
        guard let atlas = NSBitmapImageRep(data: try Data(contentsOf: atlasURL))?.cgImage else {
            fatalError("Cannot decode \(atlasURL.path)")
        }
        let manifestURL = input.appendingPathComponent("sheets/\(coat).json")
        let source = FileManager.default.fileExists(atPath: manifestURL.path)
            ? try JSONDecoder().decode(AtlasSource.self, from: Data(contentsOf: manifestURL)) : nil
        let w = source?.cellWidth ?? cell.width, h = source?.cellHeight ?? cell.height
        let count = source?.frameCount ?? 62
        precondition(w > 0 && h > 0 && count >= 62 && count <= 128)
        precondition(atlas.width == w * 8 && (atlas.height == h * 16 || source == nil && atlas.height == h * 8),
                     "Atlas must have 8 columns x 16 rows; legacy 64-cell sources remain readable")
        let frames = (0..<count).map { index in
            atlas.cropping(to: CGRect(x: index % 8 * w, y: index / 8 * h, width: w, height: h))!
        }
        precondition(frames.allSatisfy { extent($0).right > extent($0).left }, "Atlas has an empty pose")
        for index in count..<(8 * atlas.height / h) {
            let empty = atlas.cropping(to: CGRect(x: index % 8 * w, y: index / 8 * h, width: w, height: h))!
            precondition(extent(empty).right == 0, "Reserved atlas cell \(index) must be empty")
        }
        try writeSheet(frames, to: folder, source: source)
        prepared.insert(coat)
        continue
    }
    let registrationURL = v3.appendingPathComponent(coat).appendingPathComponent("registration.json")
    let registration = FileManager.default.fileExists(atPath: registrationURL.path)
        ? try JSONDecoder().decode([String: [Registration]].self, from: Data(contentsOf: registrationURL)) : [:]
    var frames: [CGImage] = []
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
            // Every frame goes into the same 384 x 256 cell with the head anchor at x = 300.
            let padded = rgbaContext(cell.width, cell.height)
            padded.draw(context.makeImage()!, in: CGRect(x: 300 - Int(headX), y: 0, width: canvasWidth, height: 256))
            frames.append(padded.makeImage()!)
        }
    }
    precondition(frames.count == 62)
    try writeSheet(frames, to: folder)
    prepared.insert(coat)
}
try JSONEncoder().encode(resolved).write(to: output.appendingPathComponent("coats.json"))
print("Prepared 128-cell sheets (8 x 16); coat fallback: \(resolved)")
