import Cocoa

// Each artwork set is one authored sheet, `sheets/<coat>.png`, with its table of contents in `sheets/<coat>.json`:
// 128 equal cells (8 x 16), unused cells transparent. Coats without their own sheet use orange.
// The build measures each pose and writes the menu bar copies; it never crops, fits or rescales a single pose.
// Every behavior's cells in play order. The app finds poses only by these names.
let poseNames = ["stand", "idle", "walk", "run", "turn", "sitDown", "sit", "loafDown", "loaf", "sleepDown", "sleep",
                 "groom", "stretch", "yawn", "crouch", "creep", "wiggle", "pounce", "bat", "held"]
struct AtlasSource: Decodable {
    var cellWidth: Int; var cellHeight: Int; var headX: Double; var ground: Double
    var pixelsPerPoint: Double; var frameCount: Int; var walkStride: Double
    var animations: [String: [Int]]
}
struct SheetFrame: Codable { var lift: Double; var left: Double; var right: Double }
struct SheetInfo: Codable {
    var columns = 8, rows = 16, cellWidth: Int, cellHeight: Int
    var headX: Double, ground: Double
    var pixelsPerPoint: Double, walkStride: Double
    var animations: [String: [Int]]
    var frames: [SheetFrame]
    var variants: [String: [Int]]   // "<density>x-<size>": cell width and height in screen pixels
}
// Menu bar copies are shrunk here once, for 1x and 2x screens and every cat size (CatSize.scale).
let sizeScales = [0.64, 0.82, 1.0]
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
func writeSheet(_ frames: [CGImage], to folder: URL, source: AtlasSource) throws {
    precondition(source.pixelsPerPoint > 0 && source.walkStride > 0)
    let info0 = SheetInfo(cellWidth: source.cellWidth, cellHeight: source.cellHeight, headX: source.headX, ground: source.ground,
                          pixelsPerPoint: source.pixelsPerPoint, walkStride: source.walkStride, animations: source.animations,
                          frames: [], variants: [:])
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
let input = root.appendingPathComponent("app/macos/Resources/Cats/sheets")
let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
var prepared = Set<String>()
var resolved: [String] = []
for name in names {
    let coat = FileManager.default.fileExists(atPath: input.appendingPathComponent("\(name).png").path) ? name : "orange"
    resolved.append(coat)
    if prepared.contains(coat) { continue }
    let folder = output.appendingPathComponent(coat)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let atlasURL = input.appendingPathComponent("\(coat).png")
    guard let atlas = NSBitmapImageRep(data: try Data(contentsOf: atlasURL))?.cgImage else { fatalError("Cannot decode \(atlasURL.path)") }
    let source = try JSONDecoder().decode(AtlasSource.self, from: Data(contentsOf: input.appendingPathComponent("\(coat).json")))
    let w = source.cellWidth, h = source.cellHeight, count = source.frameCount
    precondition(w > 0 && h > 0 && count > 0 && count <= 128)
    precondition(atlas.width == w * 8 && atlas.height == h * 16, "\(coat) sheet must be 8 columns x 16 rows of \(w) x \(h)")
    let frames = (0..<count).map { index in
        atlas.cropping(to: CGRect(x: index % 8 * w, y: index / 8 * h, width: w, height: h))!
    }
    precondition(frames.allSatisfy { extent($0).right > extent($0).left }, "\(coat) sheet has an empty pose")
    for index in count..<128 {
        let empty = atlas.cropping(to: CGRect(x: index % 8 * w, y: index / 8 * h, width: w, height: h))!
        precondition(extent(empty).right == 0, "Reserved \(coat) cell \(index) must be empty")
    }
    try writeSheet(frames, to: folder, source: source)
    prepared.insert(coat)
}
try JSONEncoder().encode(resolved).write(to: output.appendingPathComponent("coats.json"))
print("Prepared 128-cell sheets (8 x 16); coat fallback: \(resolved)")
