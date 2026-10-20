#include "NativeVehicleAudio.h"
#include <string.h>
#include <ctype.h>
#include <stdio.h>
static PGVehicleAudioPolicy policies[512];static unsigned count;
void PGRegisterVehicleAudioPolicy(const char *model,const char *profile,const char *kind){
 if(!model||!profile||!kind||strlen(model)>63||strlen(profile)>63||strlen(kind)>63||count==512)return;
 uint32_t hash=0;for(const unsigned char *p=(const unsigned char *)model;*p;p++){hash+=(unsigned char)tolower(*p);hash+=hash<<10;hash^=hash>>6;}hash+=hash<<3;hash^=hash>>11;hash+=hash<<15;
 PGVehicleAudioPolicy *p=&policies[count++];p->model=hash;
 snprintf(p->profile,64,"%s",*profile?profile:model);snprintf(p->kind,64,"%s",kind);
}
const PGVehicleAudioPolicy *PGFindVehicleAudioPolicy(uint32_t model){for(unsigned i=0;i<count;i++)if(policies[i].model==model)return &policies[i];return NULL;}
const char *PGChooseVehicleAudio(const PGVehicleAudioPolicy *p,bool (*exists)(const char *,void *),void *context){
 if(!p)return NULL;
 if(exists(p->profile,context))return p->profile;
 const char *a=NULL,*b=NULL;
 if(!strcmp(p->kind,"vc_motorcycle")){a="faggio2";b="sanchez";}
 else if(!strcmp(p->kind,"vc_super")||!strcmp(p->kind,"vc_sport")||!strcmp(p->kind,"vc_sports")){a="turismor";b="adder";}
 else if(!strcmp(p->kind,"vc_muscle")){a="dominator";b="adder";}
 else if(!strcmp(p->kind,"vc_suv")||!strcmp(p->kind,"vc_suvs")||!strcmp(p->kind,"vc_off_road")){a="granger";b="adder";}
 else if(!strcmp(p->kind,"vc_sedan")||!strcmp(p->kind,"vc_sedans")||!strcmp(p->kind,"vc_compact")||!strcmp(p->kind,"vc_compacts")||!strcmp(p->kind,"vc_coupe")||!strcmp(p->kind,"vc_coupes")){a="asea";b="adder";}
 else if(!strcmp(p->kind,"vc_van")||!strcmp(p->kind,"vc_vans")||!strcmp(p->kind,"vc_industrial")||!strcmp(p->kind,"vc_commercial")){a="speedo";b="pounder";}
 if(a&&exists(a,context))return a;if(b&&exists(b,context))return b;return NULL;
}
