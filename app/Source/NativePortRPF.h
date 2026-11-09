#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <unistd.h>
#include <zlib.h>
#include <sys/stat.h>
#include <pthread.h>

// Direct Port RPF data loader & resolver: allows Mugoat Nova to boot directly from
// standard GTA V Port / PC RPF datasets (common.rpf, x64a.rpf ... x64w.rpf, update/update.rpf).
// Child RPF archives (vehicles.rpf, clipmax.rpf, dlc.rpf) are read directly from top-level RPFs
// via zero-copy pread() without decompressing 21 GB of data. Metadata archives (common.rpf & x64a.rpf)
// are cached locally on first launch (~66 MB).

typedef struct {
    char archiveRel[128];
    uint64_t blockOffset;
    uint64_t uncompSize;
} PGPortRPFChildEntry;

static BOOL isLocalPortRPF = NO;
static NSString *portRPFRoot = nil;
static NSString *portRPFCacheDir = nil;
static NSMutableDictionary<NSString *, NSValue *> *portRPFChildMap = nil;
static pthread_mutex_t portRPFLock = PTHREAD_MUTEX_INITIALIZER;

// Persistent file descriptor cache for top-level RPF archives to eliminate open()/close() syscall churn.
typedef struct {
    char relPath[128];
    int fd;
} PGPortArchiveFD;
static PGPortArchiveFD portArchiveFDs[128];
static int portArchiveFDCount = 0;
static pthread_mutex_t portArchiveFDLock = PTHREAD_MUTEX_INITIALIZER;

static int PGGetPortArchiveFD(const char *relPath) {
    if (!portRPFRoot || !relPath || !*relPath) return -1;
    pthread_mutex_lock(&portArchiveFDLock);
    for (int i = 0; i < portArchiveFDCount; i++) {
        if (strcmp(portArchiveFDs[i].relPath, relPath) == 0) {
            int fd = portArchiveFDs[i].fd;
            pthread_mutex_unlock(&portArchiveFDLock);
            return fd;
        }
    }
    if (portArchiveFDCount < 128) {
        NSString *archPath = [portRPFRoot stringByAppendingPathComponent:@(relPath)];
        int fd = open(archPath.fileSystemRepresentation, O_RDONLY);
        if (fd >= 0) {
            fcntl(fd, F_SETFD, FD_CLOEXEC);
            strncpy(portArchiveFDs[portArchiveFDCount].relPath, relPath, sizeof(portArchiveFDs[portArchiveFDCount].relPath) - 1);
            portArchiveFDs[portArchiveFDCount].fd = fd;
            portArchiveFDCount++;
            pthread_mutex_unlock(&portArchiveFDLock);
            return fd;
        }
    }
    pthread_mutex_unlock(&portArchiveFDLock);
    return -1;
}

// Lightweight RAM cache for frequently-read small metadata / header blocks (<= 32 KB).
#define PG_BLOCK_CACHE_LINES 256
#define PG_BLOCK_CACHE_MAX_LEN 32768

typedef struct {
    uint32_t pathHash;
    uint64_t offset;
    uint32_t length;
    uint8_t data[PG_BLOCK_CACHE_MAX_LEN];
    pthread_mutex_t lock;
} PGBlockCacheLine;

static PGBlockCacheLine portBlockCache[PG_BLOCK_CACHE_LINES];
static pthread_once_t portBlockCacheOnce = PTHREAD_ONCE_INIT;

static void PGInitBlockCacheOnce(void) {
    for (int i = 0; i < PG_BLOCK_CACHE_LINES; i++) {
        pthread_mutex_init(&portBlockCache[i].lock, NULL);
    }
}

static inline uint32_t pg_hash_path_offset(const char *path, uint64_t offset) {
    uint32_t h = 2166136261u;
    while (*path) { h ^= (uint8_t)*path++; h *= 16777619u; }
    h ^= (uint32_t)offset; h *= 16777619u;
    h ^= (uint32_t)(offset >> 32); h *= 16777619u;
    return h;
}

static bool PGTryReadBlockCache(const char *relPath, uint64_t offset, uint8_t *dest, uint32_t length) {
    if (length > PG_BLOCK_CACHE_MAX_LEN) return false;
    pthread_once(&portBlockCacheOnce, PGInitBlockCacheOnce);
    uint32_t h = pg_hash_path_offset(relPath, offset);
    size_t idx = h % PG_BLOCK_CACHE_LINES;
    PGBlockCacheLine *line = &portBlockCache[idx];
    pthread_mutex_lock(&line->lock);
    if (line->length == length && line->offset == offset && line->pathHash == h) {
        memcpy(dest, line->data, length);
        pthread_mutex_unlock(&line->lock);
        return true;
    }
    pthread_mutex_unlock(&line->lock);
    return false;
}

static void PGStoreBlockCache(const char *relPath, uint64_t offset, const uint8_t *src, uint32_t length) {
    if (length > PG_BLOCK_CACHE_MAX_LEN) return;
    pthread_once(&portBlockCacheOnce, PGInitBlockCacheOnce);
    uint32_t h = pg_hash_path_offset(relPath, offset);
    size_t idx = h % PG_BLOCK_CACHE_LINES;
    PGBlockCacheLine *line = &portBlockCache[idx];
    pthread_mutex_lock(&line->lock);
    line->pathHash = h;
    line->offset = offset;
    line->length = length;
    memcpy(line->data, src, length);
    pthread_mutex_unlock(&line->lock);
}

static void PGIndexRPFChildren(NSString *rpfFullPath, NSString *relPath) {
    int fd = open(rpfFullPath.fileSystemRepresentation, O_RDONLY);
    if (fd < 0) return;
    uint32_t header[4];
    if (read(fd, header, 16) != 16 || header[0] != 0x52504637) { close(fd); return; }
    uint32_t count = header[1];
    uint32_t names_len = header[2];
    if (count > 200000 || names_len > 10 * 1024 * 1024) { close(fd); return; }
    
    uint64_t *entries = malloc(count * 16);
    char *names = malloc(names_len);
    if (!entries || !names) { close(fd); free(entries); free(names); return; }
    
    if (read(fd, entries, count * 16) == (ssize_t)(count * 16) && read(fd, names, names_len) == (ssize_t)names_len) {
        for (uint32_t i = 0; i < count; i++) {
            uint64_t e0 = entries[i * 2];
            uint64_t e1 = entries[i * 2 + 1];
            uint64_t block = (e0 >> 40) & 0x7FFFFF;
            if (block == 0x7FFFFF) continue; // directory
            uint32_t name_offset = e0 & 0xFFFF;
            if (name_offset >= names_len) continue;
            const char *name = names + name_offset;
            size_t nlen = strlen(name);
            if (nlen > 4 && !strcasecmp(name + nlen - 4, ".rpf")) {
                NSString *key = [@(name) lowercaseString];
                if (!portRPFChildMap[key]) {
                    PGPortRPFChildEntry entry;
                    memset(&entry, 0, sizeof entry);
                    snprintf(entry.archiveRel, sizeof entry.archiveRel, "%s", relPath.UTF8String);
                    entry.blockOffset = block;
                    entry.uncompSize = e1 & 0xFFFFFFFF;
                    portRPFChildMap[key] = [NSValue valueWithBytes:&entry objCType:@encode(PGPortRPFChildEntry)];
                }
            }
        }
    }
    free(entries);
    free(names);
    close(fd);
}

static void PGExtractRPFArchive(NSString *rpfFullPath, NSString *targetDir) {
    int fd = open(rpfFullPath.fileSystemRepresentation, O_RDONLY);
    if (fd < 0) return;
    uint32_t header[4];
    if (read(fd, header, 16) != 16 || header[0] != 0x52504637) { close(fd); return; }
    uint32_t count = header[1];
    uint32_t names_len = header[2];
    if (count > 200000 || names_len > 10 * 1024 * 1024) { close(fd); return; }
    
    uint64_t *entries = malloc(count * 16);
    char *names = malloc(names_len);
    if (!entries || !names) { close(fd); free(entries); free(names); return; }
    if (read(fd, entries, count * 16) != (ssize_t)(count * 16) || read(fd, names, names_len) != (ssize_t)names_len) {
        free(entries); free(names); close(fd); return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:targetDir withIntermediateDirectories:YES attributes:nil error:nil];

    typedef struct { uint32_t index; char path[512]; } StackItem;
    StackItem *stack = malloc(sizeof(StackItem) * (count + 1));
    if (!stack) { free(entries); free(names); close(fd); return; }
    int stackTop = 0;
    stack[0].index = 0;
    stack[0].path[0] = 0;

    while (stackTop >= 0) {
        StackItem item = stack[stackTop--];
        uint32_t idx = item.index;
        if (idx >= count) continue;
        uint64_t e0 = entries[idx * 2];
        uint64_t e1 = entries[idx * 2 + 1];
        uint32_t name_offset = e0 & 0xFFFF;
        if (name_offset >= names_len) continue;
        const char *name = names + name_offset;

        char currentPath[512];
        if (item.path[0] && name[0]) {
            snprintf(currentPath, sizeof currentPath, "%s/%s", item.path, name);
        } else if (name[0]) {
            snprintf(currentPath, sizeof currentPath, "%s", name);
        } else {
            currentPath[0] = 0;
        }

        uint64_t block = (e0 >> 40) & 0x7FFFFF;
        BOOL isDir = (block == 0x7FFFFF);

        if (isDir) {
            uint32_t first = (uint32_t)(e1 & 0xFFFFFFFF);
            uint32_t childCount = (uint32_t)((e1 >> 32) & 0xFFFFFFFF);
            if (currentPath[0]) {
                NSString *dirPath = [targetDir stringByAppendingPathComponent:@(currentPath)];
                [fm createDirectoryAtPath:dirPath withIntermediateDirectories:YES attributes:nil error:nil];
            }
            if (childCount < count) {
                for (uint32_t c = 0; c < childCount; c++) {
                    if (stackTop + 1 < (int)count) {
                        stack[++stackTop].index = first + c;
                        snprintf(stack[stackTop].path, sizeof stack[stackTop].path, "%s", currentPath);
                    }
                }
            }
        } else {
            uint32_t stored = (uint32_t)((e0 >> 16) & 0xFFFFFF);
            uint32_t uncomp = (uint32_t)(e1 & 0xFFFFFFFF);
            uint32_t toRead = (stored > 0 && stored != uncomp) ? stored : uncomp;
            if (toRead > 0 && toRead < 50 * 1024 * 1024) {
                uint8_t *rawBuf = malloc(toRead);
                if (rawBuf) {
                    if (pread(fd, rawBuf, toRead, (off_t)(block * 512)) == (ssize_t)toRead) {
                        NSString *outFilePath = [targetDir stringByAppendingPathComponent:@(currentPath)];
                        [fm createDirectoryAtPath:[outFilePath stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:nil error:nil];
                        if (stored > 0 && stored != uncomp) {
                            uint8_t *decompBuf = malloc(uncomp);
                            if (decompBuf) {
                                z_stream strm;
                                memset(&strm, 0, sizeof(strm));
                                strm.next_in = (Bytef *)rawBuf;
                                strm.avail_in = (uInt)toRead;
                                strm.next_out = (Bytef *)decompBuf;
                                strm.avail_out = (uInt)uncomp;
                                int zres = inflateInit2(&strm, -15);
                                if (zres != Z_OK) zres = inflateInit(&strm);
                                if (zres == Z_OK) {
                                    if (inflate(&strm, Z_FINISH) == Z_STREAM_END || strm.total_out == uncomp) {
                                        int outFd = open(outFilePath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0644);
                                        if (outFd >= 0) {
                                            write(outFd, decompBuf, uncomp);
                                            close(outFd);
                                        }
                                    }
                                    inflateEnd(&strm);
                                }
                                free(decompBuf);
                            }
                        } else {
                            int outFd = open(outFilePath.fileSystemRepresentation, O_WRONLY | O_CREAT | O_TRUNC, 0644);
                            if (outFd >= 0) {
                                write(outFd, rawBuf, toRead);
                                close(outFd);
                            }
                        }
                    }
                    free(rawBuf);
                }
            }
        }
    }
    free(stack);
    free(entries);
    free(names);
    close(fd);
}

static void PGInitPortRPF(NSString *dataPath, NSString *cacheDir) {
    pthread_mutex_lock(&portRPFLock);
    portRPFRoot = dataPath;
    portRPFCacheDir = [cacheDir stringByAppendingPathComponent:@"rpf_cache"];
    isLocalPortRPF = YES;

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:portRPFCacheDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *marker = [portRPFCacheDir stringByAppendingPathComponent:@".extracted_v1"];
    if (![fm fileExistsAtPath:marker]) {
        pg_log("[NativeAssets] Unpacking common.rpf and x64a.rpf into fast SSD cache...");
        NSString *commonRpf = [dataPath stringByAppendingPathComponent:@"common.rpf"];
        if ([fm fileExistsAtPath:commonRpf]) {
            PGExtractRPFArchive(commonRpf, [portRPFCacheDir stringByAppendingPathComponent:@"common"]);
        }
        NSString *x64aRpf = [dataPath stringByAppendingPathComponent:@"x64a.rpf"];
        if ([fm fileExistsAtPath:x64aRpf]) {
            PGExtractRPFArchive(x64aRpf, [portRPFCacheDir stringByAppendingPathComponent:@"x64"]);
        }
        [@"ready" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
        pg_log("[NativeAssets] Metadata cache extraction complete.");
    }

    portRPFChildMap = [NSMutableDictionary dictionaryWithCapacity:1600];
    for (char c = 'a'; c <= 'w'; c++) {
        NSString *rel = [NSString stringWithFormat:@"x64%c.rpf", c];
        NSString *full = [dataPath stringByAppendingPathComponent:rel];
        if ([fm fileExistsAtPath:full]) {
            PGIndexRPFChildren(full, rel);
        }
    }
    NSString *updateRpf = [dataPath stringByAppendingPathComponent:@"update/update.rpf"];
    if ([fm fileExistsAtPath:updateRpf]) {
        PGIndexRPFChildren(updateRpf, @"update/update.rpf");
    }
    NSString *dlcDir = [dataPath stringByAppendingPathComponent:@"update/x64/dlcpacks"];
    NSArray *dlcs = [fm contentsOfDirectoryAtPath:dlcDir error:nil];
    for (NSString *pack in dlcs) {
        NSString *rel = [NSString stringWithFormat:@"update/x64/dlcpacks/%@/dlc.rpf", pack];
        NSString *full = [dataPath stringByAppendingPathComponent:rel];
        if ([fm fileExistsAtPath:full]) {
            PGIndexRPFChildren(full, rel);
        }
    }
    char line[160];
    snprintf(line, sizeof line, "[NativeAssets] Indexed %lu child RPF archives from GTA V Port data.", (unsigned long)portRPFChildMap.count);
    pg_log(line);
    pthread_mutex_unlock(&portRPFLock);
}

static inline void PGPatchRPFEncryptionHeader(NSString *relPath, uint64_t offset, uint8_t *destination, int64_t length) {
    if (!destination || length <= 0) return;
    if (offset <= 12 && (offset + (uint64_t)length) >= 16) {
        size_t encIdx = 12 - (size_t)offset;
        if (encIdx + 4 <= (size_t)length) {
            uint32_t enc = 0;
            memcpy(&enc, destination + encIdx, 4);
            if (enc == 0) {
                if (offset == 0) {
                    uint32_t magic = 0;
                    memcpy(&magic, destination, 4);
                    if (magic == 0x52504637) { // 'RPF7'
                        uint32_t openVal = 0x4E45504F; // 'OPEN'
                        memcpy(destination + encIdx, &openVal, 4);
                    }
                } else if (relPath && [relPath.lowercaseString hasSuffix:@".rpf"]) {
                    uint32_t openVal = 0x4E45504F; // 'OPEN'
                    memcpy(destination + encIdx, &openVal, 4);
                }
            }
        }
    }
}

static int64_t PGReadPortRPFAsset(NSString *relPath, uint64_t offset, uint8_t *destination, uint32_t length) {
    if (!portRPFRoot || !length) return -1;

    const char *relCStr = relPath.UTF8String;
    if (relCStr && PGTryReadBlockCache(relCStr, offset, destination, length)) {
        PGPatchRPFEncryptionHeader(relPath, offset, destination, (int64_t)length);
        return (int64_t)length;
    }

    // 1. Fast path: check child RPF map FIRST
    NSString *baseName = [relPath lastPathComponent].lowercaseString;
    NSValue *val = [portRPFChildMap objectForKey:baseName];
    if (val) {
        PGPortRPFChildEntry child;
        [val getValue:&child];
        int afd = PGGetPortArchiveFD(child.archiveRel);
        if (afd >= 0) {
            ssize_t n = pread(afd, destination, length, (off_t)(child.blockOffset * 512 + offset));
            if (n >= 0) {
                PGPatchRPFEncryptionHeader(relPath, offset, destination, (int64_t)n);
                if (n == (ssize_t)length && relCStr) PGStoreBlockCache(relCStr, offset, destination, length);
                return (int64_t)n;
            }
        }
    }

    // 2. Audio fallback
    if ([relPath isEqualToString:@"x64/audio/audio.rpf"]) {
        int afd = PGGetPortArchiveFD("x64/audio/audio_rel.rpf");
        if (afd >= 0) {
            ssize_t n = pread(afd, destination, length, (off_t)offset);
            if (n >= 0) {
                PGPatchRPFEncryptionHeader(relPath, offset, destination, (int64_t)n);
                if (n == (ssize_t)length && relCStr) PGStoreBlockCache(relCStr, offset, destination, length);
                return (int64_t)n;
            }
        }
    }

    // 3. Check extracted metadata cache (<cacheRoot>/rpf_cache/<relPath>)
    if (portRPFCacheDir) {
        NSString *cachePath = [portRPFCacheDir stringByAppendingPathComponent:relPath];
        int cfd = open(cachePath.fileSystemRepresentation, O_RDONLY);
        if (cfd >= 0) {
            ssize_t n = pread(cfd, destination, length, (off_t)offset);
            close(cfd);
            if (n >= 0) {
                PGPatchRPFEncryptionHeader(relPath, offset, destination, (int64_t)n);
                if (n == (ssize_t)length && relCStr) PGStoreBlockCache(relCStr, offset, destination, length);
                return (int64_t)n;
            }
        }
    }

    // 4. Check loose file in port folder (<localDataRoot>/<relPath>)
    NSString *loosePath = [portRPFRoot stringByAppendingPathComponent:relPath];
    int lfd = open(loosePath.fileSystemRepresentation, O_RDONLY);
    if (lfd >= 0) {
        ssize_t n = pread(lfd, destination, length, (off_t)offset);
        close(lfd);
        if (n >= 0) {
            PGPatchRPFEncryptionHeader(relPath, offset, destination, (int64_t)n);
            if (n == (ssize_t)length && relCStr) PGStoreBlockCache(relCStr, offset, destination, length);
            return (int64_t)n;
        }
    }

    return -1;
}
