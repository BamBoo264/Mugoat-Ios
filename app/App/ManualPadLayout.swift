import Foundation
import CoreGraphics
/// Fixed, independent layout for the optional complete controller. Ignores custom
/// gameplay positions/scales so the temporary controls cannot overlap them.
enum ManualPadLayout {
 static func frames(in safe:CGRect,utilityOnly:Bool=false)->[String:CGRect] {
  var result:[String:CGRect]=[:]
  func put(_ name:String,_ x:CGFloat,_ y:CGFloat,_ d:CGFloat=44){result[name]=CGRect(x:safe.minX+x-d/2,y:safe.minY+y-d/2,width:d,height:d)}
  let bar=utilityOnly ? ["settings","mods"] : ["camera","phone","pause","settings","mods","manualPad"]
  for (i,n) in bar.enumerated(){put(n,safe.width/2+(CGFloat(i)-CGFloat(bar.count-1)/2)*54,24)}
  if utilityOnly{return result}
  for (i,n) in ["script_lb","script_lt","manualL3","manualR3","script_rt","script_rb"].enumerated(){put(n,safe.width * (0.12+CGFloat(i)*0.152),80)}
  for (i,n) in ["script_y","script_x","script_a","script_b"].enumerated(){put(n,safe.width * [0.20,0.40,0.60,0.80][i],136)}
  put("up",safe.width/2,safe.height-134);put("down",safe.width/2,safe.height-26)
  put("left",safe.width/2-54,safe.height-80);put("right",safe.width/2+54,safe.height-80)
  put("leftStick",safe.width*0.14,safe.height-72,108);put("lookStick",safe.width*0.86,safe.height-72,108)
  return result
 }
 static func valid(_ frames:[String:CGRect],in safe:CGRect)->Bool {
  for (name,a) in frames {
   guard a.minX.isFinite,a.minY.isFinite,a.width.isFinite,a.height.isFinite,safe.contains(a) else{return false}
   for (other,b) in frames where name<other {
    if a.insetBy(dx:-4,dy:-4).intersects(b.insetBy(dx:-4,dy:-4)){return false}
   }
  }
  return true
 }
 static func overlayVisible(available:Bool,stopped:Bool)->Bool {available && !stopped}
 static func utilityOnly(external:Bool,hide:Bool,preview:Bool)->Bool {external && hide && !preview}
}
