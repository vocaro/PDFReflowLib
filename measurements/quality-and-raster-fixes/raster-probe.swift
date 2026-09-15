import Foundation
import PDFKit
@main struct Probe {
 static func main() throws {
  let doc = PDFDocument(url: URL(fileURLWithPath: CommandLine.arguments[1]))!
  let page = doc.page(at: 120)!
  print("PDFKit",page.bounds(for: .cropBox),"CG",page.pageRef!.getBoxRect(.cropBox))
  print("transform",page.pageRef!.getDrawingTransform(.cropBox,rect:CGRect(x:0,y:0,width:1485,height:1935),rotate:0,preserveAspectRatio:true))
  for rotate in [false, true] {
   let img = try PageRasterizer.image(page:page,rect:page.bounds(for:.cropBox),options:.init(),applyRotation:rotate)
   try PageRasterizer.write(img,to:URL(fileURLWithPath:"/tmp/faa-raster-\(rotate).png"))
   print(rotate,img.width,img.height)
  }
 }
}
