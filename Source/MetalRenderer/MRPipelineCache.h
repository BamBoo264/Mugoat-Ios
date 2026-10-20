//
//  MRPipelineCache.h
//  Mugoat iOS - Metal Pipeline State Cache ("Pipecache")
//
//  Provides persistent pipeline archiving (MTLBinaryArchive) and
//  offline/startup pipeline pre-warming to eliminate runtime shader compilation
//  stutter and prevent skipped draw calls (missing textures / FPS drops).
//

#pragma once
#import <Metal/Metal.h>
#include <stdint.h>
#include <string>
#include <vector>
#include <unordered_map>
#include <memory>
#include <functional>

namespace mr {

struct PipeRecipe {
    std::string vsHash;
    std::string psHash;
    uint32_t layoutOid = 0;
    uint32_t topo = 4;
    uint64_t passKey = 0;
    uint64_t blendHash = 0;
    uint64_t key = 0;
};

class PipelineCache {
public:
    static PipelineCache &shared();

    // Initialize with the active Metal device and setup cache directories
    void initialize(id<MTLDevice> device);

    // Attach the persistent MTLBinaryArchive to a render pipeline descriptor
    void attachToDescriptor(MTLRenderPipelineDescriptor *desc);

    // Record a compiled pipeline function into the binary archive
    void recordPipeline(MTLRenderPipelineDescriptor *desc, uint64_t key);

    // Save binary archive to disk (called on background / intervals / pause)
    void serializeToDisk();

    // Load pre-recorded pipeline recipes from bundle and documents
    void loadRecipes();

    // Record a recipe to pipelines-v1.jsonl
    void recordRecipe(const PipeRecipe &recipe);

    // Pre-warm a batch of pipelines asynchronously during loading
    void warmPipelines(std::function<void(const PipeRecipe &)> compileCallback);

    bool isInitialized() const { return m_initialized; }
    id<MTLBinaryArchive> binaryArchive() const { return m_binaryArchive; }

    uint64_t hits() const { return m_hits; }
    uint64_t misses() const { return m_misses; }
    uint32_t warmedCount() const { return m_warmed; }

private:
    PipelineCache();
    ~PipelineCache();

    bool m_initialized = false;
    id<MTLDevice> m_device = nil;
    id<MTLBinaryArchive> m_binaryArchive = nil;
    NSURL *m_archiveURL = nil;
    NSURL *m_recipesURL = nil;

    std::vector<PipeRecipe> m_recipes;
    std::unordered_map<uint64_t, bool> m_recordedKeys;
    uint64_t m_hits = 0;
    uint64_t m_misses = 0;
    uint32_t m_warmed = 0;
    bool m_dirty = false;
};

} // namespace mr
