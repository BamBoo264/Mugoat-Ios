#import "MRPipelineCache.h"
#import "MRInternal.h"
#include <TargetConditionals.h>
#if TARGET_OS_IOS
#import <UIKit/UIKit.h>
#endif
#include <mutex>
#include <cstdio>
namespace mr {
static dispatch_queue_t worker;
static dispatch_source_t timer;
static id<MTLDevice> gpu;
static id<MTLLibrary> functions;
static id<MTLBinaryArchive> loaded, writer;
static NSURL *archiveURL, *recipeURL;
static NSMutableDictionary<NSString *, NSDictionary *> *recipes;
static NSMutableDictionary<NSString *, id<MTLRenderPipelineState>> *states;
static std::mutex statesLock;
static bool dirty=false, archiveDirty=false, writeFailed=false;
static unsigned failures=0, compiled=0, warmed=0;
static NSDictionary *encode(MTLRenderPipelineDescriptor *d) {
 if(!d.vertexFunction)return nil;
 NSMutableArray *attrs=[NSMutableArray array],*layouts=[NSMutableArray array],*colors=[NSMutableArray array];
 for(NSUInteger i=0;i<31;i++){
  auto *a=d.vertexDescriptor.attributes[i];auto *l=d.vertexDescriptor.layouts[i];
  [attrs addObject:@[@(a.format),@(a.offset),@(a.bufferIndex)]];
  [layouts addObject:@[@(l.stride),@(l.stepFunction),@(l.stepRate)]];
 }
 for(NSUInteger i=0;i<8;i++){
  auto *c=d.colorAttachments[i];[colors addObject:@[@(c.pixelFormat),@(c.writeMask),@(c.blendingEnabled),@(c.sourceRGBBlendFactor),@(c.destinationRGBBlendFactor),@(c.rgbBlendOperation),@(c.sourceAlphaBlendFactor),@(c.destinationAlphaBlendFactor),@(c.alphaBlendOperation)]];
 }
 return @{@"v":d.vertexFunction.name,@"f":d.fragmentFunction.name?:@"",@"a":attrs,@"l":layouts,@"c":colors,@"depth":@(d.depthAttachmentPixelFormat),@"stencil":@(d.stencilAttachmentPixelFormat),@"samples":@(d.rasterSampleCount),@"coverage":@(d.alphaToCoverageEnabled),@"alphaOne":@(d.alphaToOneEnabled),@"raster":@(d.rasterizationEnabled),@"topology":@(d.inputPrimitiveTopology)};
}
static NSString *keyFor(NSDictionary *r){return [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:r options:NSJSONWritingSortedKeys error:nil] encoding:NSUTF8StringEncoding];}
static MTLRenderPipelineDescriptor *decode(NSDictionary *r){
 if(![r isKindOfClass:NSDictionary.class]||[r[@"a"] count]!=31||[r[@"l"] count]!=31||[r[@"c"] count]!=8)return nil;
 auto *d=[MTLRenderPipelineDescriptor new];d.vertexFunction=[functions newFunctionWithName:r[@"v"]];
 if([r[@"f"] length])d.fragmentFunction=[functions newFunctionWithName:r[@"f"]];
 if(!d.vertexFunction||([r[@"f"] length]&&!d.fragmentFunction))return nil;
 d.vertexDescriptor=[MTLVertexDescriptor vertexDescriptor];
 for(NSUInteger i=0;i<31;i++){
  NSArray *a=r[@"a"][i],*l=r[@"l"][i];if(a.count!=3||l.count!=3)return nil;
  d.vertexDescriptor.attributes[i].format=(MTLVertexFormat)[a[0] unsignedIntegerValue];d.vertexDescriptor.attributes[i].offset=[a[1] unsignedIntegerValue];d.vertexDescriptor.attributes[i].bufferIndex=[a[2] unsignedIntegerValue];
  d.vertexDescriptor.layouts[i].stride=[l[0] unsignedIntegerValue];d.vertexDescriptor.layouts[i].stepFunction=(MTLVertexStepFunction)[l[1] unsignedIntegerValue];d.vertexDescriptor.layouts[i].stepRate=[l[2] unsignedIntegerValue];
 }
 for(NSUInteger i=0;i<8;i++){
  NSArray *a=r[@"c"][i];if(a.count!=9)return nil;auto *c=d.colorAttachments[i];
  c.pixelFormat=(MTLPixelFormat)[a[0] unsignedIntegerValue];c.writeMask=(MTLColorWriteMask)[a[1] unsignedIntegerValue];c.blendingEnabled=[a[2] boolValue];c.sourceRGBBlendFactor=(MTLBlendFactor)[a[3] unsignedIntegerValue];c.destinationRGBBlendFactor=(MTLBlendFactor)[a[4] unsignedIntegerValue];c.rgbBlendOperation=(MTLBlendOperation)[a[5] unsignedIntegerValue];c.sourceAlphaBlendFactor=(MTLBlendFactor)[a[6] unsignedIntegerValue];c.destinationAlphaBlendFactor=(MTLBlendFactor)[a[7] unsignedIntegerValue];c.alphaBlendOperation=(MTLBlendOperation)[a[8] unsignedIntegerValue];
 }
 d.depthAttachmentPixelFormat=(MTLPixelFormat)[r[@"depth"] unsignedIntegerValue];d.stencilAttachmentPixelFormat=(MTLPixelFormat)[r[@"stencil"] unsignedIntegerValue];d.rasterSampleCount=[r[@"samples"] unsignedIntegerValue];d.alphaToCoverageEnabled=[r[@"coverage"] boolValue];d.alphaToOneEnabled=[r[@"alphaOne"] boolValue];d.rasterizationEnabled=[r[@"raster"] boolValue];d.inputPrimitiveTopology=(MTLPrimitiveTopologyClass)[r[@"topology"] unsignedIntegerValue];return d;
}
static void save(){
 if(dirty){NSData *data=[NSJSONSerialization dataWithJSONObject:recipes.allValues options:0 error:nil];if([data writeToURL:recipeURL options:NSDataWritingAtomic error:nil])dirty=false;}
 if(!archiveDirty||!writer||writeFailed)return;
 NSURL *temp=[archiveURL URLByAppendingPathExtension:@"tmp"];NSError *error=nil;
 if(![writer serializeToURL:temp error:&error]){writeFailed=true;logf("[cache-v3] archive save disabled this session: %s; recipes retained",error.localizedDescription.UTF8String?:"unknown");return;}
 if(rename(temp.fileSystemRepresentation,archiveURL.fileSystemRepresentation)==0){archiveDirty=false;logf("[cache-v3] saved %lu full recipes, %u compiled, %u warmed",(unsigned long)recipes.count,compiled,warmed);}
}
static id<MTLRenderPipelineState> build(MTLRenderPipelineDescriptor *d,NSError **error){
 if(loaded)d.binaryArchives=@[loaded];
 id<MTLRenderPipelineState> state=[gpu newRenderPipelineStateWithDescriptor:d error:error];
 if(!state&&loaded){d.binaryArchives=@[];state=[gpu newRenderPipelineStateWithDescriptor:d error:error];}
 if(state&&writer&&!writeFailed){MTLRenderPipelineDescriptor *record=[d copy];record.binaryArchives=@[];NSError *e=nil;
  if([writer addRenderPipelineFunctionsWithDescriptor:record error:&e])archiveDirty=true;
  else if(++failures==1)logf("[cache-v3] archive add failed; rendering retained: %s",e.localizedDescription.UTF8String?:"unknown");
 }return state;
}
PipelineCache &PipelineCache::shared(){static PipelineCache *c=new PipelineCache;return *c;}
void PipelineCache::initialize(id<MTLDevice> device){
 static std::once_flag once;std::call_once(once,[device]{
  gpu=device;recipes=[NSMutableDictionary dictionary];states=[NSMutableDictionary dictionary];
  worker=dispatch_queue_create("mugoat.pipeline-cache-v3",dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,QOS_CLASS_UTILITY,0));
  NSURL *revisionURL=[NSBundle.mainBundle URLForResource:@"iosvn-pipeline-revision" withExtension:@"txt"];
  NSString *revision=revisionURL?[NSString stringWithContentsOfURL:revisionURL encoding:NSUTF8StringEncoding error:nil]:@"local";
  NSString *identity=[NSString stringWithFormat:@"%@|%@|%@|schema3",gpu.name,NSProcessInfo.processInfo.operatingSystemVersionString,revision];
  uint64_t hash=1469598103934665603ull;for(NSUInteger i=0;i<identity.length;i++){hash^=[identity characterAtIndex:i];hash*=1099511628211ull;}
  NSURL *dir=[[NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask].firstObject URLByAppendingPathComponent:@"PipelineCache-v3"];
  [NSFileManager.defaultManager createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
  NSString *stem=[NSString stringWithFormat:@"%016llx",(unsigned long long)hash];archiveURL=[dir URLByAppendingPathComponent:[stem stringByAppendingString:@".archive"]];recipeURL=[dir URLByAppendingPathComponent:[stem stringByAppendingString:@".json"]];
  dispatch_async(worker,^{@autoreleasepool{
   NSError *error=nil;auto *ad=[MTLBinaryArchiveDescriptor new];if([NSFileManager.defaultManager fileExistsAtPath:archiveURL.path])ad.url=archiveURL;
   loaded=ad.url?[gpu newBinaryArchiveWithDescriptor:ad error:&error]:nil;writer=[gpu newBinaryArchiveWithDescriptor:ad error:&error];if(!writer){ad.url=nil;writer=[gpu newBinaryArchiveWithDescriptor:ad error:nil];}
   NSURL *libraryURL=[NSBundle.mainBundle URLForResource:@"shaders-iphoneos" withExtension:@"metallib"];
   functions=libraryURL?[gpu newLibraryWithURL:libraryURL error:nil]:nil;
   NSData *data=[NSData dataWithContentsOfURL:recipeURL];NSArray *stored=data.length<=16*1024*1024?[NSJSONSerialization JSONObjectWithData:data?:[NSData data] options:0 error:nil]:nil;
   if([stored isKindOfClass:NSArray.class]&&stored.count<=2048)for(NSDictionary *r in stored){@try{
    auto *d=decode(r);if(!d)continue;NSString *key=keyFor(r);NSError *e=nil;id<MTLRenderPipelineState> state=build(d,&e);if(state){{std::lock_guard<std::mutex> lock(statesLock);states[key]=state;}recipes[key]=r;warmed++;}
   }@catch(NSException *e){logOnce("bad-cache-recipe","[cache-v3] invalid recipe ignored");}}
   logf("[cache-v3] archive %s; prewarmed %u complete PSOs on serial utility queue",loaded?"loaded":"new",warmed);
  }});
  timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,worker);dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),30*NSEC_PER_SEC,NSEC_PER_SEC);dispatch_source_set_event_handler(timer,^{@autoreleasepool{save();}});dispatch_resume(timer);
#if TARGET_OS_IOS
  [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidEnterBackgroundNotification object:nil queue:nil usingBlock:^(NSNotification *n){PipelineCache::shared().serializeToDisk();}];
#endif
 });
}
void PipelineCache::compile(MTLRenderPipelineDescriptor *descriptor,void (^completion)(id<MTLRenderPipelineState>,NSError *)){
 MTLRenderPipelineDescriptor *snapshot=[descriptor copy];NSDictionary *r=encode(snapshot);NSString *key=r?keyFor(r):nil;
 id<MTLRenderPipelineState> cached=nil;{std::lock_guard<std::mutex> lock(statesLock);if(key)cached=states[key];}
 if(cached){completion(cached,nil);return;} // a warmed hit never waits behind archive disk I/O
 dispatch_async(worker,^{@autoreleasepool{
  NSError *error=nil;id<MTLRenderPipelineState> state=nil;
  {std::lock_guard<std::mutex> lock(statesLock);if(key)state=states[key];}
  if(!state){state=build(snapshot,&error);compiled++;if(state&&key&&recipes.count<2048){{std::lock_guard<std::mutex> lock(statesLock);states[key]=state;}recipes[key]=r;dirty=true;}}
  completion(state,error);
 }});
}
void PipelineCache::serializeToDisk(){if(worker)dispatch_async(worker,^{@autoreleasepool{save();}});}
}
