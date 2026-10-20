#pragma once
#import <Metal/Metal.h>
namespace mr {
class PipelineCache {
public:
 static PipelineCache &shared();
 void initialize(id<MTLDevice> device);
 void compile(MTLRenderPipelineDescriptor *, void (^)(id<MTLRenderPipelineState>, NSError *));
 void serializeToDisk();
};
}
