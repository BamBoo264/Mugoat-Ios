#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stdatomic.h>
#include <math.h>
// Main-script thread owns the anchor; only the short-lived permit crosses threads.
typedef struct {
 bool anchorValid, wasScene;
 float x,y,z;
 uint64_t nextSceneMS, reserveBytes;
 uint32_t distanceMeters;
 _Atomic uint64_t nextReclaimMS;
 _Atomic uint64_t permitUntilMS;
} PGNovaMovement;
// Keep profiles small relative to a restricted process, regardless of hardware RAM.
static inline uint64_t pg_nova_move_reserve_for_limit(uint64_t requestedMB,uint64_t limitMB){
 uint64_t cap=limitMB?((limitMB/16)/16)*16:requestedMB;
 if(requestedMB&&limitMB&&cap<64)cap=64;
 return (requestedMB<cap?requestedMB:cap)<<20;
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
   double metres=s->distanceMeters?s->distanceMeters:80;
   if(dx*dx+dy*dy+dz*dz>=metres*metres){
    atomic_store(&s->permitUntilMS,now+2000);s->x=x;s->y=y;s->z=z;
   }
  }else{s->anchorValid=true;s->x=x;s->y=y;s->z=z;}
 }
 s->wasScene=scene;
}
static inline int64_t pg_nova_move_budget(PGNovaMovement *s,uint64_t now,int64_t engine,uint64_t available){
 // Preserve the engine's own signed budget and object-lifetime rules.
 if(engine<0)return engine;
 uint64_t growth=pg_nova_move_available(s,(uint64_t)engine,available);
 int64_t result=growth>INT64_MAX?INT64_MAX:(int64_t)growth;
 uint64_t target=s->reserveBytes?s->reserveBytes+(64ull<<20):(256ull<<20);
 if(available>=target)return result;
 // Only critical headroom can bypass movement; never loop a negative answer per poll.
 bool emergency=s->reserveBytes&&available<s->reserveBytes/2;
 uint64_t until=atomic_load(&s->permitUntilMS);
 bool permit=until&&now<=until;
 if(!emergency&&!permit)return result;
 uint64_t next=atomic_load(&s->nextReclaimMS);
 if(now<next||!atomic_compare_exchange_strong(&s->nextReclaimMS,&next,now+500))return result;
 if(permit)atomic_compare_exchange_strong(&s->permitUntilMS,&until,0);
 uint64_t deficit=target-available;
 return -(int64_t)(deficit<(16ull<<20)?deficit:(16ull<<20));
}
