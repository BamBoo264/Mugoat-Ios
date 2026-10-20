import Foundation

enum PerformanceMode: String, CaseIterable {
    case stable60, potato, custom
    var title: String { switch self { case .stable60: return "Mượt 60"; case .potato: return "Potato · FPS tối đa"; case .custom: return "Tùy chỉnh" } }
    var height: Int { self == .potato ? 432 : 540 }
    var automatic: Bool { self != .custom }
    func options(_ original: [String]) -> [String] {
        guard automatic else { return original }
        return ["-shaderQuality=1", "-textureQuality=0", "-shadowQuality=-1", "-reflectionQuality=0", "-particleQuality=0", "-grassQuality=0", "-cityDensity=0", "-lodScale=0", "-pedLodBias=0", "-vehicleLodBias=0", "-pedVariety=0", "-vehicleVariety=0"]
    }
}

/// Same values feed both CLI and settings.xml; the saved file cannot silently raise quality.
enum SafeGraphicsSettings {
    static func xml(options: [String], lean: Bool) -> String {
        var values: [String:String] = [:]
        for option in options { let p=option.dropFirst().split(separator:"=",maxSplits:1);if p.count==2 {values[String(p[0])]=String(p[1])} }
        func v(_ name:String,_ fallback:String)->String { values[name] ?? fallback }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <Settings><version value="27"/><configSource>SMC_AUTO</configSource><graphics>
        <TextureQuality value="\(v("textureQuality","0"))"/><ShaderQuality value="1"/>
        <ShadowQuality value="\(v("shadowQuality","0"))"/><ReflectionQuality value="\(v("reflectionQuality","0"))"/>
        <ParticleQuality value="\(v("particleQuality","0"))"/><GrassQuality value="\(v("grassQuality","0"))"/>
        <LodScale value="\(v("lodScale","0"))"/><PedLodBias value="\(v("pedLodBias","0"))"/><VehicleLodBias value="\(v("vehicleLodBias","0"))"/>
        <CityDensity value="\(v("cityDensity","0"))"/><PedVarietyMultiplier value="\(v("pedVariety","0"))"/><VehicleVarietyMultiplier value="\(v("vehicleVariety","0"))"/>
        <Shadow_Distance value="\(lean ? "0.15":"1.0")"/><Shadow_SoftShadows value="0"/><Shadow_ParticleShadows value="false"/>
        <ReflectionMSAA value="0"/><Reflection_MipBlur value="false"/><SSAO value="0"/><AnisotropicFiltering value="0"/>
        <MSAA value="0"/><MSAAFragments value="0"/><MSAAPostProcess value="0"/><WaterQuality value="0"/>
        <DeepSurfaceQuality value="0"/><FXAA value="\(lean ? "false":"true")"/><TXAA value="false"/>
        <Lighting_FogVolumes value="false"/><Shader_SSA value="false"/><DX_Version value="2"/>
        <PostFX value="0"/><DoF value="false"/><HdStreamingInFlight value="false"/><MaxLodScale value="0"/><MotionBlurStrength value="0"/>
        </graphics><system><Windowed value="2"/></system><video><Windowed value="2"/><VSync value="1"/></video></Settings>
        """
    }
}

/// Slow, bounded changes. A single streaming hitch never triggers a resize.
struct AdaptiveResolution {
    private(set) var currentHeight = 0
    private var maximum = 0, lastSample = -Double.infinity, lastChange = -Double.infinity
    private var low = 0, high = 0
    mutating func reset(maximum: Int) {
        self = AdaptiveResolution(); self.maximum=max(360,maximum); currentHeight=self.maximum
    }
    mutating func sample(now: Double, fps: Double, thermal: Int, active: Bool) -> Int? {
        guard maximum>0,now.isFinite else {return nil}
        if !active {low=0;high=0;lastSample=now;return nil}
        guard now-lastSample>=2 else {return nil};lastSample=now
        guard fps.isFinite,fps>=5,fps<=125 else {low=0;high=0;return nil}
        if fps<54 || thermal>=2 {low+=1;high=0}
        else if fps>=59 && thermal==0 {high+=1;low=0}
        else {low=0;high=0}
        guard now-lastChange>=15 else {return nil}
        let next: Int
        if low>=3 {next=max(360,currentHeight-54)}
        else if high>=10 {next=min(maximum,currentHeight+54)}
        else {return nil}
        low=0;high=0
        guard next != currentHeight else {return nil}
        currentHeight=next;lastChange=now;return next
    }
}
