#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
typedef struct { uint32_t model; char profile[64], kind[64]; } PGVehicleAudioPolicy;
void PGRegisterVehicleAudioPolicy(const char *model, const char *profile, const char *kind);
uint32_t PGVehicleAudioRevision(void);
const PGVehicleAudioPolicy *PGFindVehicleAudioPolicy(uint32_t model);
const char *PGChooseVehicleAudio(const PGVehicleAudioPolicy *, bool (*exists)(const char *,void *),void *);
