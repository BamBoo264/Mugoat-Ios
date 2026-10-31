#include "GameInstallerShim.h"
#include <stdbool.h>
bool PGModFileProblem(const char *,char *,size_t);

#include <stdint.h>
#include <stdbool.h>
void PGEnableSoundMods(bool enabled);
bool PGRegisterStockVehicleSound(uint32_t model,const char *profile);
bool PGSelectVehicleSound(uint32_t model,const char *profile);

int gi_inflate_raw(const void *,uint32_t,void *,uint32_t);
int gi_inflate_resource(const void *,uint32_t,void *,uint32_t);
uint32_t gi_deflate_raw(const void *,uint32_t,void *,uint32_t);
