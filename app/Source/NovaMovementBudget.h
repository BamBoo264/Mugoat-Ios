#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stdatomic.h>
#include <math.h>
// Anchor is owned by the script thread. Permits, pressure and counters cross threads atomically.
typedef struct {
 bool anchorValid,wasScene;
 float x,y,z;
 uint64_t nextSceneMS,reserveBytes,targetBytes;
 uint32_t distanceMeters;
 _Atomic uint64_t nextReclaimMS,permitUntilMS,pressureUntilMS;
 _Atomic uint64_t movementEvents,reclaimRequests,requestedBytes,emergencyRequests;
} PGNovaMovement;
static inline uint64_t pg_nova_move_reserve_for_limit(uint64_t requestedMB,uint64_t limitMB){
 uint64_t cap=limitMB?((limitMB/16)/16)*16:requestedMB;
 if(limitMB&&cap<64)cap=64;
 return (requestedMB<cap?requestedMB:cap)<<20;
}
static inline uint64_t pg_nova_move_target(uint64_t reserveBytes,uint64_t limitMB){
 uint64_t target=reserveBytes+(256ull<<20),quarter=(limitMB/4)<<20;
 return target>quarter?target:quarter;
}
static inline uint64_t pg_nova_move_available(const PGNovaMovement *s,uint64_t engine,uint64_t available){
 uint64_t growth=available>s->reserveBytes?available-s->reserveBytes:0;
 return engine<growth?engine:growth;
}
static inline void pg_nova_move_sample(PGNovaMovement *s,uint64_t now,bool valid,float x,float y,float z,bool scene){
 if(scene){
  if(!s->wasScene||now>=s->nextSceneMS){atomic_store(&s->permitUntilMS,now+2000);s->nextSceneMS=now+1000;}
  s->anchorValid=false;
 }else if(valid&&isfinite(x)&&isfinite(y)&&isfinite(z)){
  if(s->anchorValid){
   double dx=(double)x-s->x,dy=(double)y-s->y,dz=(double)z-s->z;
   double distance=s->distanceMeters?s->distanceMeters:80;
   if(dx*dx+dy*dy+dz*dz>=distance*distance){
    atomic_store(&s->permitUntilMS,now+2000);atomic_fetch_add(&s->movementEvents,1);s->x=x;s->y=y;s->z=z;
   }
  }else{s->anchorValid=true;s->x=x;s->y=y;s->z=z;}
 }else{s->anchorValid=false;atomic_store(&s->permitUntilMS,0);} // A pause/loading gap cannot create a false distance jump.
 s->wasScene=scene;
}
static inline int64_t pg_nova_move_budget(PGNovaMovement *s,uint64_t now,int64_t engine,uint64_t available){
 if(engine<0)return engine; // Never suppress the engine's own lifetime/budget decision.
 uint64_t growth=pg_nova_move_available(s,(uint64_t)engine,available);
 int64_t result=growth>INT64_MAX?INT64_MAX:(int64_t)growth;
 uint64_t target=s->targetBytes?s->targetBytes:s->reserveBytes+(256ull<<20);
 uint64_t until=atomic_load(&s->permitUntilMS);
 bool permit=until&&now<=until;
 uint64_t pressureUntil=atomic_load(&s->pressureUntilMS);
 bool pressure=pressureUntil&&now<=pressureUntil;
 bool critical=available<s->reserveBytes;
 if((available>=target&&!pressure)||(!critical&&!pressure&&!permit))return result;
 uint64_t next=atomic_load(&s->nextReclaimMS),interval=pressure||available<s->reserveBytes/2?500:critical?2000:8000;
 if(now<next||!atomic_compare_exchange_strong(&s->nextReclaimMS,&next,now+interval))return result;
 if(permit)atomic_compare_exchange_strong(&s->permitUntilMS,&until,0);
 uint64_t deficit=available<target?target-available:(16ull<<20),bytes=deficit<(16ull<<20)?deficit:(16ull<<20);
 atomic_fetch_add(&s->reclaimRequests,1);atomic_fetch_add(&s->requestedBytes,bytes);
 if(critical||pressure)atomic_fetch_add(&s->emergencyRequests,1);
 return -(int64_t)bytes; // Request only: streamer selects unused assets; no entity deletion.
}
