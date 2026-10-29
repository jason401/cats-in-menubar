import Cocoa
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let folder = root.appendingPathComponent("app/macos/Resources/Cats/sheets")
let source = NSImage(contentsOf: folder.appendingPathComponent("orange.png"))!.cgImage(forProposedRect:nil,context:nil,hints:nil)!
let w=source.width,h=source.height,space=CGColorSpaceCreateDeviceRGB()
var original=[UInt8](repeating:0,count:w*h*4)
original.withUnsafeMutableBytes { p in
 let c=CGContext(data:p.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
 c.draw(source,in:CGRect(x:0,y:0,width:w,height:h))
}
func clamp(_ x:Double)->Double { min(1,max(0,x)) }
// Hand-reviewed anatomical landmarks for every occupied frame, in original cell pixels.
// hx,hy=head center; bx,by=torso center; rx,ry=torso radii.
let landmarks:[[Double]] = [
[77,36,55,44,17,9], [79,39,56,46,17,9], [79,39,56,46,17,9], [79,39,56,46,17,9],
[79,40,56,46,17,9],[79,40,56,46,17,9],[79,40,56,46,17,9],[79,40,56,46,17,9],
[79,40,56,46,17,9],[79,40,56,46,17,9],[79,40,56,46,17,9],[79,40,56,46,17,9],
[79,40,56,46,17,9],[79,40,56,46,17,9],[79,40,56,46,17,9],[79,40,56,46,17,9],
[79,40,56,46,17,9],[79,40,56,46,17,9],[79,40,56,46,17,9],[79,40,56,46,17,9],
[79,38,58,46,15,10],[79,38,55,42,20,8],[79,37,54,41,22,7],[79,38,56,44,17,8],
[79,38,56,44,17,9],[79,38,56,45,16,10],[79,38,56,45,16,10],[79,38,56,45,16,10],
[79,39,57,47,17,9],[79,39,60,48,15,9],[76,36,76,50,9,11],[20,38,42,47,17,9],
[79,39,57,47,17,9],[79,39,60,48,16,9],[79,38,66,49,13,12],[79,38,66,50,14,11],
[79,45,59,52,18,9],[79,45,59,52,18,9],[79,45,59,52,18,9],[82,51,61,52,20,9],
[79,53,65,51,20,10],[79,53,65,51,20,10],[79,53,65,51,20,10],[79,37,66,49,13,12],
[79,36,66,49,13,12],[79,36,66,49,13,12],[79,37,66,49,13,12],[79,38,58,46,17,9],
[77,47,55,45,17,9],[79,54,54,45,17,9],[79,43,56,45,17,9],[79,38,56,46,17,9],
[76,34,65,49,13,13],[76,34,65,49,13,13],[79,46,56,46,19,9],[81,54,58,53,21,8],
[79,45,55,47,20,8],[79,45,55,47,20,8],[79,45,55,47,20,8],[79,45,55,47,20,8],
[79,50,56,49,20,9],[79,50,56,49,20,9],[79,36,58,43,17,9],[83,43,54,43,22,8],
[80,50,55,48,20,8],[79,38,56,46,17,9],[79,36,66,49,13,12],[79,36,66,49,13,12],
[75,23,68,43,9,17],[76,23,68,43,9,17]
]
func ellipse(_ x:Double,_ y:Double,_ cx:Double,_ cy:Double,_ rx:Double,_ ry:Double)->Bool {pow((x-cx)/rx,2)+pow((y-cy)/ry,2)<1}
for name in ["tuxedo","calico","siamese"] {
 var out=original
 for i in stride(from:0,to:out.count,by:4) {
  let alpha=Double(original[i+3])/255
  if alpha==0 {continue}
  let px=i/4,x=Double(px%w%102),y=Double(px/w%68),frame=(px/w/68)*8+(px%w/102),a=landmarks[min(frame,69)]
  let r=Double(original[i])/alpha,g=Double(original[i+1])/alpha,b=Double(original[i+2])/alpha
  let warm=r>=g && g>=b && r-g>5 && g-b>(r-g)*0.2
  let pale=r>190 && g>170 && b>145
  if !warm && !pale {continue}
  let hx=a[0],hy=a[1],bx=a[2],by=a[3],rx=a[4],ry=a[5]
  let flip=frame==31,front=frame==30,dir:Double=flip ? -1:1
  let head=ellipse(x,y,hx,hy-2,12.5,16)
  let muzzle=ellipse(x,y,hx+dir*5,hy+5,8,5)
  let chest=ellipse(x,y,hx-dir*4,hy+13,5.5,9)
  let body=ellipse(x,y,bx,by,rx+3,ry+3)
  let tail = !head && (( !body && (flip ? x>bx+rx-1 : x<bx-rx+2) && y<by+3) || (y<by-ry+1 && (flip ? x>hx+13 : x<hx-13)))
  let sock = pale && !head && !tail && y>by+4
  let shade=clamp((g/max(r,1)-0.4)/0.55)
  var target=[Double](),line=[Double]()
  if name=="tuxedo" {
   let belly=ellipse(x,y,bx+2,by+ry,rx*0.65,3)
   let white=muzzle || chest || sock || belly || (front && ellipse(x,y,hx,hy+9,5,10))
   target=white ? [247,244,236]:[49+shade*9,51+shade*9,57+shade*9]
   line=[28,26,27]
  } else if name=="calico" {
   let rump=ellipse(x,y,bx-dir*rx*0.45,by,rx*0.48,ry*0.9)
   let shoulder=ellipse(x,y,bx+dir*rx*0.42,by-ry*0.35,rx*0.45,ry*0.85)
   let rearEar=ellipse(x,y,hx-dir*8,hy-10,4.5,8)
   let blackPatch=(rump && !head) || (rearEar && !muzzle)
   let orangePatch=(shoulder && !head) || (head && !muzzle && !rearEar) || tail
   if blackPatch {target=[52+shade*8,53+shade*8,58+shade*8]}
   else if orangePatch {target=[246,170+shade*20,86+shade*20]}
   else {target=[248,245,237]}
   if front && (muzzle || y>hy+8) {target=[248,245,237]}
   line=[60,42,33]
  } else {
   let paw = sock || (!head && !body && !tail && y>by+ry*0.5)
   let point=head || tail || paw
   target=point ? [78+shade*12,53+shade*10,43+shade*9]:[246,230,203]
   line=[49,32,28]
  }
  let blend=clamp((r-85)/145)
  for k in 0..<3 {out[i+k]=UInt8(max(0,min(255,((line[k]*(1-blend)+target[k]*blend)*alpha).rounded())))}
 }
 // Recolor isolated eye components, never mouth or outer contours.
 for frame in 0..<70 {
  var seen=Set<Int>()
  func eyePixel(_ p:Int)->Bool {
   let x=p%102,y=p/102
   if x<0 || x>=102 || y<0 || y>=68 {return false}
   let i=((frame/8*68+y)*w+frame%8*102+x)*4
   return original[i+3]>220 && original[i]<110 && original[i+1]<80 && original[i+2]<70
  }
  for y in 0..<68 {for x in 0..<102 {
   let p=y*102+x
   if seen.contains(p) || !eyePixel(p) {continue}
   var q=[p];seen.insert(p);var j=0
   while j<q.count {
    let p=q[j];j+=1
    for n in [p-102,p+102,p-1,p+1] {
     if n<0 || n>=6936 || abs(n%102-p%102)>1 || seen.contains(n) || !eyePixel(n) {continue}
     seen.insert(n);q.append(n)
    }
   }
   let xx=q.map{$0%102},yy=q.map{$0/102},xmin=xx.min()!,xmax=xx.max()!,ymin=yy.min()!,ymax=yy.max()!
   let bw=xmax-xmin+1,bh=ymax-ymin+1
   let a=landmarks[frame]
   if q.count<3 || q.count>24 || bw<2 || bw>6 || bh<2 || bh>7 || Double(bh)/Double(bw)<0.7 || Double(q.count)/Double(bw*bh)<0.5 || abs(Double(xmin)-a[0])>15 || abs(Double(ymin)-a[1])>12 {continue}
   for p in q {
    let i=((frame/8*68+p/102)*w+frame%8*102+p%102)*4
    let color:[UInt8]=name=="siamese" ? [91,165,212]:[215,164,67]
    if p%102==xmin || p/102==ymin {out[i]=color[0];out[i+1]=color[1];out[i+2]=color[2]}
   }
  }}
 }
 for i in stride(from:3,to:out.count,by:4) {precondition(out[i]==original[i])}
 out.withUnsafeMutableBytes { p in
  let c=CGContext(data:p.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
  let rep=NSBitmapImageRep(cgImage:c.makeImage()!)
  try! rep.representation(using:.png,properties:[:])!.write(to:folder.appendingPathComponent("\(name).png"))
 }
 try! Data(contentsOf:folder.appendingPathComponent("orange.json")).write(to:folder.appendingPathComponent("\(name).json"))
 print("\(name): \(w)x\(h), original alpha retained at every pixel; metadata copied")
}
