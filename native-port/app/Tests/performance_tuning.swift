import Foundation
@main struct PerformanceTests {
 static func main() {
  let options=PerformanceMode.stable60.options(["-shaderQuality=2","-lodScale=1"])
  let xml=SafeGraphicsSettings.xml(options:options,lean:true)
  precondition(xml.contains("<ShadowQuality value=\"-1\"/>") && xml.contains("<ReflectionQuality value=\"0\"/>") && xml.contains("<LodScale value=\"0\"/>") && xml.contains("<FXAA value=\"false\"/>") && xml.contains("<ShaderQuality value=\"1\"/>"))
  precondition(PerformanceMode.custom.options(["-lodScale=0.4"]) == ["-lodScale=0.4"])
  var c=AdaptiveResolution();c.reset(maximum:540)
  precondition(c.sample(now:0,fps:60,thermal:0,active:true)==nil)
  precondition(c.sample(now:2,fps:20,thermal:0,active:true)==nil)
  precondition(c.sample(now:4,fps:60,thermal:0,active:true)==nil)
  for t in [6.0,8] {precondition(c.sample(now:t,fps:40,thermal:0,active:true)==nil)}
  precondition(c.sample(now:10,fps:40,thermal:0,active:true)==486)
  for t in stride(from:12.0,through:24,by:2) {precondition(c.sample(now:t,fps:40,thermal:0,active:true)==nil)}
  precondition(c.sample(now:26,fps:40,thermal:0,active:true)==432)
  _=c.sample(now:28,fps:40,thermal:0,active:false)
  precondition(c.sample(now:30,fps:40,thermal:0,active:true)==nil)
  precondition(c.sample(now:32,fps:0,thermal:0,active:true)==nil)
  for t in stride(from:34.0,through:50,by:2) {precondition(c.sample(now:t,fps:60,thermal:0,active:true)==nil)}
  precondition(c.sample(now:52,fps:60,thermal:0,active:true)==486)
  for t in stride(from:54.0,through:500,by:2) {_=c.sample(now:t,fps:40,thermal:3,active:true)}
  precondition(c.currentHeight==360)
  print("PASS: graphics CLI/XML agree; single hitch, pause and loading ignored; sustained load, cooldown, slow recovery and thermal floor")
 }
}
