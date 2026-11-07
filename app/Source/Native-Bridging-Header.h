#include "MugoatOnline.h"
#include "EngineHost.h"
#include "NativeAssetPreload.h"

#include "NativeGraphics.h"
#include "GameInstallerShim.h"

int gi_inflate_raw(const void *,uint32_t,void *,uint32_t);
int gi_inflate_resource(const void *,uint32_t,void *,uint32_t);
uint32_t gi_deflate_raw(const void *,uint32_t,void *,uint32_t);
