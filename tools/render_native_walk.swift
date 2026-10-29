import Cocoa
import ImageIO

// Exact baked cells, enlarged with integer pixels for a shareable animation preview.
let folder=URL(fileURLWithPath:CommandLine.arguments[1]),out=URL(fileURLWithPath:CommandLine.arguments[2])
let meta=try! JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("sheet.json"))) as! [String:Any]
let ids=(meta["animations"] as! [String:[Int]])["walk"]!, frames=meta["frames"] as! [[String:Double]]
func read(_ name:String)->CGImage {NSBitmapImageRep(data:try! Data(contentsOf:folder.appendingPathComponent(name)))!.cgImage!}
let two=read("sheet-2x-2.png"),one=read("sheet-1x-2.png")
let dest=CGImageDestinationCreateWithURL(out as CFURL,"com.compuserve.gif" as CFString,ids.count,nil)!
CGImageDestinationSetProperties(dest,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFLoopCount:0]] as CFDictionary)
for (phase,id) in ids.enumerated(){
    let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:900,pixelsHigh:390,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:bitmap)
    NSColor(calibratedRed:0.13,green:0.15,blue:0.18,alpha:1).setFill();NSRect(x:0,y:0,width:900,height:390).fill()
    let title:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:18,weight:.semibold),.foregroundColor:NSColor.white]
    let small:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:13),.foregroundColor:NSColor.lightGray]
    ("2x source · 4x zoom" as NSString).draw(at:NSPoint(x:25,y:350),withAttributes:title)
    ("1x · 8x zoom" as NSString).draw(at:NSPoint(x:470,y:350),withAttributes:title)
    NSGraphicsContext.current?.imageInterpolation = .none
    let lift=frames[id]["lift"]!
    for (sheet,w,h,zoom,x) in [(two,102,68,4.0,25.0),(one,51,34,8.0,470.0)] {
        let crop=sheet.cropping(to:CGRect(x:id%8*w,y:id/8*h,width:w,height:h))!
        let im=NSImage(cgImage:crop,size:NSSize(width:w,height:h))
        let density=Double(w)/102
        im.draw(in:NSRect(x:x,y:65+lift*density*zoom,width:Double(w)*zoom,height:Double(h)*zoom),from:.zero,operation:.sourceOver,fraction:1)
    }
    let native=one.cropping(to:CGRect(x:id%8*51,y:id/8*34,width:51,height:34))!
    NSImage(cgImage:native,size:NSSize(width:51,height:34)).draw(in:NSRect(x:25,y:12+lift/2,width:51,height:34))
    ("Actual 1x size" as NSString).draw(at:NSPoint(x:90,y:24),withAttributes:small)
    ("\(phase+1)/16 · 1.6 sec / cycle · 6 pt/s" as NSString).draw(at:NSPoint(x:470,y:24),withAttributes:small)
    NSGraphicsContext.restoreGraphicsState()
    CGImageDestinationAddImage(dest,bitmap.cgImage!,[kCGImagePropertyGIFDictionary:[kCGImagePropertyGIFDelayTime:0.1]] as CFDictionary)
}
precondition(CGImageDestinationFinalize(dest))
print(out.path)
