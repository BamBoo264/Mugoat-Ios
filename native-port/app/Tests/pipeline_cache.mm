#include "../Source/MetalRenderer/MRPipelineCache.mm"
#include <cassert>
#include <cstdarg>
namespace mr {
void logf(const char *f,...){va_list a;va_start(a,f);vfprintf(stdout,f,a);puts("");va_end(a);}
void logOnce(const std::string &,const char *f,...){va_list a;va_start(a,f);vfprintf(stdout,f,a);puts("");va_end(a);}
}
int main(){@autoreleasepool{
 id<MTLDevice> device=MTLCreateSystemDefaultDevice();
 if(!device){puts("SKIP: Metal device unavailable; device cache test requires actual GPU");return 0;}
 mr::PipelineCache::shared().initialize(device);
 dispatch_sync(mr::worker,^{});
 NSError *error=nil;
 id<MTLLibrary> library=[device newLibraryWithSource:@"#include <metal_stdlib>\nusing namespace metal; vertex float4 test_vertex(uint i [[vertex_id]]) {return float4(0,0,0,1);} fragment float4 test_fragment(){return float4(1,0,0,1);}" options:nil error:&error];
 assert(library);mr::functions=library;
 auto *d=[MTLRenderPipelineDescriptor new];d.vertexFunction=[library newFunctionWithName:@"test_vertex"];d.fragmentFunction=[library newFunctionWithName:@"test_fragment"];
 d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];d.colorAttachments[0].pixelFormat=MTLPixelFormatBGRA8Unorm;
 d.colorAttachments[0].blendingEnabled=YES;d.colorAttachments[0].sourceRGBBlendFactor=MTLBlendFactorSourceAlpha;d.colorAttachments[0].destinationRGBBlendFactor=MTLBlendFactorOneMinusSourceAlpha;
 d.inputPrimitiveTopology=MTLPrimitiveTopologyClassTriangle;
 NSDictionary *recipe=mr::encode(d);assert(recipe);auto *copy=mr::decode(recipe);assert(copy);
 assert([mr::keyFor(recipe) isEqualToString:mr::keyFor(mr::encode(copy))]);
 dispatch_semaphore_t ready=dispatch_semaphore_create(0);__block id<MTLRenderPipelineState> first=nil;
 mr::PipelineCache::shared().compile(d,^(id<MTLRenderPipelineState> s,NSError *e){first=s;dispatch_semaphore_signal(ready);});
 assert(dispatch_semaphore_wait(ready,dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC))==0 && first);
 // A warm hit must return immediately, even while the worker queue is unavailable.
 dispatch_suspend(mr::worker);__block bool hit=false;
 mr::PipelineCache::shared().compile(copy,^(id<MTLRenderPipelineState> s,NSError *e){assert(s==first);hit=true;});
 assert(hit);dispatch_resume(mr::worker);
 dispatch_sync(mr::worker,^{mr::save();});
 assert(!mr::writeFailed);
 MTLBinaryArchiveDescriptor *ad=[MTLBinaryArchiveDescriptor new];ad.url=mr::archiveURL;
 id<MTLBinaryArchive> archive=[device newBinaryArchiveWithDescriptor:ad error:&error];assert(archive);
 copy.binaryArchives=@[archive];
 id<MTLRenderPipelineState> restored=[device newRenderPipelineStateWithDescriptor:copy options:MTLPipelineOptionFailOnBinaryArchiveMiss reflection:nil error:&error];assert(restored);
 puts("PASS: full descriptor roundtrip, Metal pipeline compile, immediate warm hit, archive save/reload and fail-on-miss validation");
 return 0;
}}
