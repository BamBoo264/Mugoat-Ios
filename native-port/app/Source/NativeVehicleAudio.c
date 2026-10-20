#include "NativeVehicleAudio.h"
#include <string.h>
#include <ctype.h>
#include <stdio.h>
#include <pthread.h>
#include <stdatomic.h>
static PGVehicleAudioPolicy policies[512];static unsigned count;
static pthread_mutex_t lock=PTHREAD_MUTEX_INITIALIZER;static _Atomic uint32_t revision;
uint32_t PGVehicleAudioRevision(void){return atomic_load(&revision);}
void PGRegisterVehicleAudioPolicy(const char *model,const char *profile,const char *kind){
 if(!model||!profile||!kind||strlen(model)>63||strlen(profile)>63||strlen(kind)>63)return;
 uint32_t hash=0;for(const unsigned char *p=(const unsigned char *)model;*p;p++){hash+=(unsigned char)tolower(*p);hash+=hash<<10;hash^=hash>>6;}hash+=hash<<3;hash^=hash>>11;hash+=hash<<15;
 pthread_mutex_lock(&lock);PGVehicleAudioPolicy *p=NULL;
 for(unsigned i=0;i<count;i++)if(policies[i].model==hash){p=&policies[i];break;}
 if(!p){if(count==512){pthread_mutex_unlock(&lock);return;}p=&policies[count++];}p->model=hash;p->forced=false;
 snprintf(p->profile,64,"%s",*profile?profile:model);snprintf(p->kind,64,"%s",kind);atomic_fetch_add(&revision,1);pthread_mutex_unlock(&lock);
}
const PGVehicleAudioPolicy *PGFindVehicleAudioPolicy(uint32_t model){static _Thread_local PGVehicleAudioPolicy snapshot;bool found=false;pthread_mutex_lock(&lock);for(unsigned i=0;i<count;i++)if(policies[i].model==model){snapshot=policies[i];found=true;break;}pthread_mutex_unlock(&lock);return found?&snapshot:NULL;}
const char *PGChooseVehicleAudio(const PGVehicleAudioPolicy *p,bool (*exists)(const char *,void *),void *context){
 if(!p)return NULL;
 if(exists(p->profile,context))return p->profile;
 const char *a=NULL,*b=NULL;
 if(!strcmp(p->kind,"vc_motorcycle_scooter")){a="faggio2";b="sanchez";}
 else if(!strcmp(p->kind,"vc_motorcycle")){a="bati";b="akuma";}
 else if(!strcmp(p->kind,"vc_super")||!strcmp(p->kind,"vc_sport")||!strcmp(p->kind,"vc_sports")){a="turismor";b="adder";}
 else if(!strcmp(p->kind,"vc_muscle")){a="dominator";b="adder";}
 else if(!strcmp(p->kind,"vc_suv")||!strcmp(p->kind,"vc_suvs")||!strcmp(p->kind,"vc_off_road")){a="granger";b="adder";}
 else if(!strcmp(p->kind,"vc_sedan")||!strcmp(p->kind,"vc_sedans")||!strcmp(p->kind,"vc_compact")||!strcmp(p->kind,"vc_compacts")||!strcmp(p->kind,"vc_coupe")||!strcmp(p->kind,"vc_coupes")){a="asea";b="adder";}
 else if(!strcmp(p->kind,"vc_van")||!strcmp(p->kind,"vc_vans")||!strcmp(p->kind,"vc_industrial")||!strcmp(p->kind,"vc_commercial")){a="speedo";b="pounder";}
 if(a&&exists(a,context))return a;if(b&&exists(b,context))return b;return NULL;
}

void PGRegisterVehicleAudioOverride(const char *model,const char *profile,const char *kind){
 PGRegisterVehicleAudioPolicy(model,profile,kind);
 pthread_mutex_lock(&lock);for(unsigned i=0;i<count;i++)if(!strcmp(policies[i].profile,profile)&&!strcmp(policies[i].kind,kind)){
  uint32_t hash=0;for(const unsigned char *p=(const unsigned char *)model;*p;p++){hash+=(unsigned char)tolower(*p);hash+=hash<<10;hash^=hash>>6;}hash+=hash<<3;hash^=hash>>11;hash+=hash<<15;
  if(policies[i].model==hash)policies[i].forced=true;
 }pthread_mutex_unlock(&lock);
}
