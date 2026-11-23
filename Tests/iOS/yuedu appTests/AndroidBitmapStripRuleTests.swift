import Foundation
import Testing
import UIKit
@testable import yuedu_app

@Suite("Actual Android bitmap strip rule", .serialized)
@MainActor
struct AndroidBitmapStripRuleTests {
    @Test("exact rule restores all rows, including remainder, and honours raw bypass")
    func exactUserRule() throws {
        var source = BookSource(bookSourceUrl: "https://bitmap-\(UUID()).test", bookSourceName: "synthetic bitmap rule")
        source.ruleContent.imageDecode = Self.rule
        let bridge = ModernParserBridge(source: source)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let png = UIGraphicsImageRenderer(size: CGSize(width: 11, height: 23), format: format).pngData { ctx in
            for y in 0..<23 {
                UIColor(red: CGFloat(y + 1) / 25, green: 0.3, blue: 0.7, alpha: 1).setFill()
                ctx.fill(CGRect(x: 0, y: y, width: 11, height: 1))
            }
        }
        let src = "https://cdn.example.test/media/photos/220981/grid.png"
        // The old namespace dispatcher threw here. The supplied rule catches that error,
        // returns a perfectly valid scrambled PNG and only leaves the failure in jmdl.
        _ = bridge.evaluateSourceScript("var factory = Packages.android.graphics.BitmapFactory; factory.savedDecode = factory.decodeByteArray; factory.decodeByteArray = function(){ throw new Error('UnsupportedLegadoAPIError: BitmapFactory'); };")
        #expect(bridge.decodeImageBytes(png, src: src, ruleJs: Self.rule) == png)
        #expect(bridge.evaluateSourceScript("source.get('jmdl')")?.hasPrefix("FAIL:") == true)
        _ = bridge.evaluateSourceScript("var factory = Packages.android.graphics.BitmapFactory; factory.decodeByteArray = factory.savedDecode;")
        #expect(FixedPageImageDecoder(source: source)?.cacheKeyPrefix.hasPrefix("imageDecode.bitmap-v1|") == true)
        let decoded = try #require(bridge.decodeImageBytes(png, src: src, ruleJs: Self.rule))
        #expect(decoded != png)
        let image = try #require(UIImage(data: decoded))
        let original = try #require(UIImage(data: png))
        #expect(image.cgImage?.width == 11)
        #expect(image.cgImage?.height == 23)
        let rows = [18,19,20,21,22,16,17,14,15,12,13,10,11,8,9,6,7,4,5,2,3,0,1]
        for (y, oldY) in rows.enumerated() {
            let expected = try #require(Self.pixel(original, y: oldY))
            #expect(Self.pixel(image, y: y) == expected)
        }
        #expect(bridge.evaluateSourceScript("source.get('jmdl')")?.hasPrefix("ok r10") == true)
        _ = bridge.evaluateSourceScript("source.put('jmraw','1')")
        #expect(bridge.decodeImageBytes(png, src: src, ruleJs: Self.rule) == png)
    }
    private static func pixel(_ image: UIImage, y: Int) -> [UInt8]? {
        guard let image = image.cgImage?.cropping(to: CGRect(x: 0, y: y, width: 1, height: 1)),
              let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        defer { withExtendedLifetime(ctx) {} }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Array(UnsafeBufferPointer(start: data, count: 4))
    }
    // Verbatim supplied rule, with synthetic image URLs used only by the test above.
    private static let rule = #"""
(function(){
 try{
  var U=String(src||'');
  var i=U.indexOf('/media/photos/');
  if(i<0)return result;
  var t=U.substring(i+14);var ps=t.split('/');
  if(ps.length<2)return result;
  var pidStr=ps[0].split('?')[0];
  var pid=parseInt(pidStr,10)||0;
  var f=ps[1];if(f==null)return result;
  var fn=f.split('?')[0].split('.')[0];
  var ext='';
  if(f.indexOf('.')>=0)ext=f.split('?')[0].split('.').pop();
  ext=String(ext).toLowerCase();
  if(ext==='gif')return result;
  var n=0;
  if(pid<220980){n=0;}
  else if(pid<268850){n=10;}
  else{var x=pid<421926?10:8;var h=String(java.md5Encode(String(pid)+String(fn)));var c=h.charCodeAt(h.length-1);n=(c%x)*2+2;}
  if(n<=0)return result;
  var raw=null;
  try{raw=source.get('jmraw');}catch(e2){raw=null;}
  if(String(raw)==='1'){return result;}
  if(n<=1)return result;
  var BF=Packages.android.graphics.BitmapFactory;
  var bmp=BF.decodeByteArray(result,0,result.length);
  if(bmp==null){try{source.put('jmdl','null len='+result.length+' hdr='+result[0]+','+result[1]+','+result[2]+','+result[3]);}catch(e3){}return result;}
  var w=bmp.getWidth(),h=bmp.getHeight();
  if(w<4||h<4){try{source.put('jmdl','tiny '+w+'x'+h);}catch(e4){}return result;}
  var dst=Packages.android.graphics.Bitmap.createBitmap(w,h,Packages.android.graphics.Bitmap.Config.ARGB_8888);
  var cv=new Packages.android.graphics.Canvas(dst);
  var pt=new Packages.android.graphics.Paint();
  var over=h%n;var move=Math.floor(h/n);
  for(var ii=0;ii<n;ii++){
   var m2=move;var ys=h-move*(ii+1)-over;var yd=move*ii;
   if(ii===0){m2+=over;}else{yd+=over;}
   if(ys<0)ys=0;if(ys+m2>h)m2=h-ys;
   if(yd<0)yd=0;if(yd+m2>h)m2=h-yd;
   cv.drawBitmap(bmp,new Packages.android.graphics.Rect(0,ys,w,ys+m2),new Packages.android.graphics.Rect(0,yd,w,yd+m2),pt);
  }
  var bos=new Packages.java.io.ByteArrayOutputStream();
  dst.compress(Packages.android.graphics.Bitmap.CompressFormat.PNG,100,bos);
  var out2=bos.toByteArray();
  try{source.put('jmdl','ok r'+n+' '+pid+'/'+fn+' '+out2.length);}catch(e5){}
  return out2;
 }catch(e){
  try{java.longToast('🖼 图解码失败: '+String(e).substring(0,90));}catch(e6){}
  try{source.put('jmdl','FAIL: '+String(e).substring(0,90));}catch(e7){}
  return result;
 }
})()
"""#
}
