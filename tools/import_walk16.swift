import Cocoa

// Import a 4x4 authored walk into a native 2x, 128-cell master. No per-pose fitting or anatomy changes.
// Usage: swift import_walk16.swift <walk4x4.png> <previous-2x-sheet.png> <out-master.png> <out-walk.png>
// History only: this produced the first native master (walk at cells 4–11 + 62–69, `walkFrames` manifest).
// The master has since been reordered and now lists every pose by name in `animations`; see ART_GUIDE.
let args = CommandLine.arguments
precondition(args.count == 5)
func context(_ w: Int, _ h: Int) -> CGContext {
    CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}
func read(_ path: String) -> CGImage { NSBitmapImageRep(data: try! Data(contentsOf: URL(fileURLWithPath: path)))!.cgImage! }
func write(_ image: CGImage, _ path: String) {
    try! FileManager.default.createDirectory(at: URL(fileURLWithPath: path).deletingLastPathComponent(), withIntermediateDirectories: true)
    try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
struct Eye: Codable { var x: Double; var y: Double; var height: Int }
func eye(_ image: CGImage) -> Eye {
    let w=image.width,h=image.height,c=context(w,h);c.draw(image,in:CGRect(x:0,y:0,width:w,height:h))
    let p=c.data!.assumingMemoryBound(to:UInt8.self)
    var seen=[Bool](repeating:false,count:w*h), best:[Int]=[]
    func dark(_ n:Int)->Bool { p[n*4+3]>200 && max(p[n*4],p[n*4+1],p[n*4+2])<55 }
    for y in 0..<Int(Double(h)*0.75) { for x in Int(Double(w)*0.6)..<w {
        let start=y*w+x; if seen[start] || !dark(start) {continue}
        var q=[start],j=0;seen[start]=true
        while j<q.count {let n=q[j];j+=1;let xx=n%w,yy=n/w
            for (nx,ny) in [(xx-1,yy),(xx+1,yy),(xx,yy-1),(xx,yy+1)] where nx>=0 && nx<w && ny>=0 && ny<h {
                let next=ny*w+nx;if !seen[next] && dark(next) {seen[next]=true;q.append(next)}
            }
        }
        let xs=q.map{$0%w},ys=q.map{$0/w},bw=xs.max()!-xs.min()!+1,bh=ys.max()!-ys.min()!+1
        let cy=Double(ys.reduce(0,+))/Double(ys.count)
        if q.count>10 && cy>Double(h)*0.25 && cy<Double(h)*0.65 && bh<h/4 && bw<h/4 && Double(q.count)/Double(bw*bh)>0.45 && Double(bw)/Double(bh)>0.35 && Double(bw)/Double(bh)<1.3 && q.count>best.count {best=q}
    }}
    precondition(!best.isEmpty,"No isolated side-profile eye; inspect source manually")
    return Eye(x:Double(best.map{$0%w}.reduce(0,+))/Double(best.count),y:Double(best.map{$0/w}.reduce(0,+))/Double(best.count),height:best.map{$0/w}.max()!-best.map{$0/w}.min()!+1)
}
let source=read(args[1]), previous=read(args[2])
precondition(source.width>=408 && source.height>=272)
precondition(previous.width==816 && previous.height>=544,"Previous sheet must be the actual adult 2x sheet")
let originals=(0..<16).map { i -> CGImage in
    let x0=Int((Double(i%4)*Double(source.width)/4).rounded()),x1=Int((Double(i%4+1)*Double(source.width)/4).rounded())
    let y0=Int((Double(i/4)*Double(source.height)/4).rounded()),y1=Int((Double(i/4+1)*Double(source.height)/4).rounded())
    return source.cropping(to:CGRect(x:x0,y:y0,width:x1-x0,height:y1-y0))!
}
let eyes=originals.map(eye), heights=eyes.map(\.height).sorted()
let scale=(13.0*2/7.5)/(Double(heights[7]+heights[8])/2)
let atlas=context(816,1088),walk=context(408,272)
for i in 0..<62 {
    let frame=previous.cropping(to:CGRect(x:i%8*102,y:i/8*68,width:102,height:68))!
    atlas.draw(frame,in:CGRect(x:i%8*102,y:(15-i/8)*68,width:102,height:68))
}
var registrations:[[String:Double]]=[]
for i in 0..<16 {
    let original=originals[i],sw=original.width,sh=original.height
    let clean=context(sw,sh)
    clean.draw(original,in:CGRect(x:0,y:0,width:sw,height:sh))
    let p=clean.data!.assumingMemoryBound(to:UInt8.self)
    // Remove diffuse generation halos before native-size resampling, without painting or changing poses.
    for n in 0..<(sw*sh) where p[n*4+3]<200 {for k in 0..<4 {p[n*4+k]=0}}
    let frame=context(102,68)
    let x=80-eyes[i].x*scale,y=68-36-(Double(sh)-eyes[i].y)*scale
    frame.interpolationQuality = .high
    frame.draw(clean.makeImage()!,in:CGRect(x:x,y:y,width:Double(sw)*scale,height:Double(sh)*scale))
    let image=frame.makeImage()!,index=i<8 ? 4+i : 62+i-8
    atlas.clear(CGRect(x:index%8*102,y:(15-index/8)*68,width:102,height:68))
    atlas.draw(image,in:CGRect(x:index%8*102,y:(15-index/8)*68,width:102,height:68))
    walk.draw(image,in:CGRect(x:i%4*102,y:(3-i/4)*68,width:102,height:68))
    registrations.append(["frame":Double(i+1),"eyeX":eyes[i].x,"eyeY":eyes[i].y,"eyeHeight":Double(eyes[i].height),"globalScale":scale])
}
write(atlas.makeImage()!,args[3]);write(walk.makeImage()!,args[4])
let manifest:[String:Any] = ["cellWidth":102,"cellHeight":68,"headX":80,"ground":62,"pixelsPerPoint":2,"frameCount":70,"walkFrames":Array(4...11)+Array(62...69),"walkStride":9.6]
try! JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:args[3]).deletingPathExtension().appendingPathExtension("json"))
try! JSONSerialization.data(withJSONObject:registrations,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:args[4]).deletingPathExtension().appendingPathExtension("json"))
print("Imported 16 walk frames at native 2x; 70 occupied / 128 cells; one global scale \(scale)")
