#include "NativeVehicleAudio.h"
#include <assert.h>
#include <string.h>
static bool exists(const char *name,void *ctx){return !strcmp(name,ctx);}
int main(void){
 PGVehicleAudioPolicy p={0,"custombike","vc_motorcycle_scooter"};
 assert(!strcmp(PGChooseVehicleAudio(&p,exists,"custombike"),"custombike"));
 assert(!strcmp(PGChooseVehicleAudio(&p,exists,"faggio2"),"faggio2"));
 assert(!strcmp(PGChooseVehicleAudio(&p,exists,"sanchez"),"sanchez"));
 assert(!PGChooseVehicleAudio(&p,exists,"missing"));
 strcpy(p.kind,"vc_motorcycle");assert(!strcmp(PGChooseVehicleAudio(&p,exists,"bati"),"bati"));assert(!PGChooseVehicleAudio(&p,exists,"faggio2"));
 strcpy(p.kind,"vc_super");assert(!strcmp(PGChooseVehicleAudio(&p,exists,"adder"),"adder"));
 strcpy(p.kind,"vc_boat");assert(!PGChooseVehicleAudio(&p,exists,"adder"));
 PGRegisterVehicleAudioPolicy("adder","","vc_super");assert(PGFindVehicleAudioPolicy(0xb779a091));uint32_t revision=PGVehicleAudioRevision();PGRegisterVehicleAudioPolicy("adder","turismor","vc_super");assert(PGVehicleAudioRevision()>revision);assert(!strcmp(PGFindVehicleAudioPolicy(0xb779a091)->profile,"turismor"));
 PGRegisterVehicleAudioOverride("adder","turismor","vc_super");assert(PGFindVehicleAudioPolicy(0xb779a091)->forced);
 PGRegisterVehicleAudioPolicy("adder","turismor","vc_super");assert(!PGFindVehicleAudioPolicy(0xb779a091)->forced);
}
