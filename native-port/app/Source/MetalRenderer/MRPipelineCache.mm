//
//  MRPipelineCache.mm
//  Mugoat iOS - Metal Pipeline State Cache ("Pipecache") Implementation
//

#import "MRPipelineCache.h"
#import "MRInternal.h"
#import <Foundation/Foundation.h>
#include <mutex>
#include <fstream>
#include <sstream>

namespace mr {

static std::mutex gCacheMutex;

PipelineCache::PipelineCache() {}

PipelineCache::~PipelineCache() {
    serializeToDisk();
}

PipelineCache &PipelineCache::shared() {
    static PipelineCache instance;
    return instance;
}

void PipelineCache::initialize(id<MTLDevice> device) {
    std::lock_guard<std::mutex> lock(gCacheMutex);
    if (m_initialized) return;
    m_device = device;

    // Use Caches directory for the compiled binary archive (OS handles eviction if under extreme pressure, but keeps across launches)
    NSArray *cachePaths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cacheDir = cachePaths.firstObject;
    NSString *archivePath = [cacheDir stringByAppendingPathComponent:@"pipecache.metallib"];
    m_archiveURL = [NSURL fileURLWithPath:archivePath];

    // Documents/Mugoat/pipelines-v1.jsonl for persistent recipe text
    NSArray *docPaths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *docDir = docPaths.firstObject;
    NSString *recipePath = [docDir stringByAppendingPathComponent:@"pipelines-v1.jsonl"];
    m_recipesURL = [NSURL fileURLWithPath:recipePath];

    if (@available(iOS 14.0, *)) {
        MTLBinaryArchiveDescriptor *desc = [MTLBinaryArchiveDescriptor new];
        if ([[NSFileManager defaultManager] fileExistsAtPath:archivePath]) {
            desc.url = m_archiveURL;
            NSError *err = nil;
            m_binaryArchive = [m_device newBinaryArchiveWithDescriptor:desc error:&err];
            if (m_binaryArchive) {
                logf("Metal pipecache: loaded persistent binary archive from disk (%s)", archivePath.UTF8String);
            } else {
                logf("Metal pipecache: existing archive invalid (%s), creating fresh", err.localizedDescription.UTF8String ?: "unknown");
                desc.url = nil;
                m_binaryArchive = [m_device newBinaryArchiveWithDescriptor:desc error:&err];
            }
        } else {
            desc.url = nil;
            NSError *err = nil;
            m_binaryArchive = [m_device newBinaryArchiveWithDescriptor:desc error:&err];
            logf("Metal pipecache: initialized fresh binary archive");
        }
    }

    loadRecipes();
    m_initialized = true;
}

void PipelineCache::attachToDescriptor(MTLRenderPipelineDescriptor *desc) {
    if (!desc) return;
    if (@available(iOS 14.0, *)) {
        if (m_binaryArchive) {
            desc.binaryArchives = @[ m_binaryArchive ];
        }
    }
}

void PipelineCache::recordPipeline(MTLRenderPipelineDescriptor *desc, uint64_t key) {
    if (!desc) return;
    std::lock_guard<std::mutex> lock(gCacheMutex);
    if (m_recordedKeys.find(key) != m_recordedKeys.end()) {
        m_hits++;
        return;
    }
    m_misses++;
    m_recordedKeys[key] = true;

    if (@available(iOS 14.0, *)) {
        if (m_binaryArchive) {
            NSError *err = nil;
            if ([m_binaryArchive addRenderPipelineFunctionsWithDescriptor:desc error:&err]) {
                m_dirty = true;
            } else if (err) {
                // Ignore duplicate function warnings
            }
        }
    }

    // Periodically flush archive to disk every 50 new pipelines
    if (m_dirty && (m_recordedKeys.size() % 50 == 0)) {
        serializeToDisk();
    }
}

void PipelineCache::serializeToDisk() {
    if (!m_dirty || !m_binaryArchive || !m_archiveURL) return;
    if (@available(iOS 14.0, *)) {
        NSError *err = nil;
        if ([m_binaryArchive serializeToURL:m_archiveURL error:&err]) {
            m_dirty = false;
            logf("Metal pipecache: serialized %zu pipelines to disk (%s)", m_recordedKeys.size(), m_archiveURL.path.UTF8String);
        } else if (err) {
            logf("Metal pipecache: serialization failed: %s", err.localizedDescription.UTF8String ?: "unknown");
        }
    }
}

void PipelineCache::loadRecipes() {
    // 1. Check bundle for bundled pre-baked recipes
    NSString *bundlePath = [NSBundle.mainBundle pathForResource:@"pipelines-v1" ofType:@"jsonl"];
    std::vector<NSString *> paths;
    if (bundlePath) paths.push_back(bundlePath);
    if (m_recipesURL && [[NSFileManager defaultManager] fileExistsAtPath:m_recipesURL.path]) {
        paths.push_back(m_recipesURL.path);
    }

    for (NSString *p : paths) {
        std::ifstream file(p.fileSystemRepresentation);
        if (!file.is_open()) continue;
        std::string line;
        while (std::getline(file, line)) {
            if (line.empty() || line[0] != '{') continue;
            // Parse lightweight recipe line
            PipeRecipe r;
            // Extract key if present
            size_t keyPos = line.find("\"key\":");
            if (keyPos != std::string::npos) {
                r.key = std::strtoull(line.c_str() + keyPos + 6, nullptr, 10);
            }
            size_t vsPos = line.find("\"vs\":\"");
            if (vsPos != std::string::npos) {
                size_t end = line.find("\"", vsPos + 6);
                if (end != std::string::npos) r.vsHash = line.substr(vsPos + 6, end - vsPos - 6);
            }
            size_t psPos = line.find("\"ps\":\"");
            if (psPos != std::string::npos) {
                size_t end = line.find("\"", psPos + 6);
                if (end != std::string::npos) r.psHash = line.substr(psPos + 6, end - psPos - 6);
            }
            if (!r.vsHash.empty()) {
                m_recipes.push_back(r);
            }
        }
    }

    if (!m_recipes.empty()) {
        logf("Metal pipecache: loaded %zu recipes to warm before gameplay", m_recipes.size());
    }
}

void PipelineCache::recordRecipe(const PipeRecipe &recipe) {
    if (!m_recipesURL) return;
    std::string line = "{\"key\":" + std::to_string(recipe.key) +
                       ",\"vs\":\"" + recipe.vsHash + "\"" +
                       ",\"ps\":\"" + recipe.psHash + "\"" +
                       ",\"lay\":" + std::to_string(recipe.layoutOid) +
                       ",\"topo\":" + std::to_string(recipe.topo) +
                       ",\"pass\":" + std::to_string(recipe.passKey) +
                       ",\"blend\":" + std::to_string(recipe.blendHash) + "}\n";

    std::ofstream out(m_recipesURL.path.fileSystemRepresentation, std::ios::app);
    if (out.is_open()) {
        out << line;
    }
}

void PipelineCache::warmPipelines(std::function<void(const PipeRecipe &)> compileCallback) {
    if (m_recipes.empty() || !compileCallback) return;
    logf("Metal pipecache: pre-warming %zu pipelines in background...", m_recipes.size());
    dispatch_queue_t queue = dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0);
    for (const auto &recipe : m_recipes) {
        dispatch_async(queue, ^{
            compileCallback(recipe);
        });
    }
}

} // namespace mr
