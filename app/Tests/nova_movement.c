#include "NovaMovementBudget.h"
#include <assert.h>
#include <stdio.h>
int main(void){
 PGNovaMovement s={.distanceMeters=80,.reserveBytes=192ull<<20,.targetBytes=1024ull<<20};
 pg_nova_move_sample(&s,1000,true,0,0,0,false);pg_nova_move_sample(&s,1250,true,79,0,0,false);assert(!atomic_load(&s.permitUntilMS));
 pg_nova_move_sample(&s,1500,true,80,0,0,false);assert(atomic_load(&s.movementEvents)==1);
 assert(pg_nova_move_budget(&s,1500,2000ll<<20,1500ull<<20)>0); // Ample room: no gratuitous eviction.
 assert(pg_nova_move_budget(&s,1501,2000ll<<20,729ull<<20)==-(16ll<<20));
 assert(pg_nova_move_budget(&s,1600,2000ll<<20,729ull<<20)>0); // No per-poll reclaim storm.
 assert(atomic_load(&s.requestedBytes)==16ull<<20);
 assert(pg_nova_move_budget(&s,9502,-5,100ull<<20)==-5); // Engine negative budget is preserved.
 assert(pg_nova_move_budget(&s,9502,2000ll<<20,729ull<<20)>0); // Stationary, noncritical: no reclaim.
 pg_nova_move_sample(&s,10000,false,0,0,0,false);assert(!s.anchorValid);
 pg_nova_move_sample(&s,10250,true,800,0,0,false);assert(atomic_load(&s.movementEvents)==1);
 assert(pg_nova_move_budget(&s,12000,100ll<<20,40ull<<20)<0); // Critical pressure bypasses movement.
 atomic_store(&s.pressureUntilMS,15000);assert(pg_nova_move_budget(&s,13000,100ll<<20,1600ull<<20)<0);
 pg_nova_move_sample(&s,16000,true,NAN,0,0,false);assert(!s.anchorValid);
 assert(pg_nova_move_reserve_for_limit(512,4096)==256ull<<20);
 assert(pg_nova_move_reserve_for_limit(192,4096)==192ull<<20);
 assert(pg_nova_move_target(192ull<<20,4096)==1024ull<<20);
 assert(atomic_load(&s.emergencyRequests)==2);
 puts("PASS: movement, pressure, cooldown, pause reset, invalid positions, reserve cap, preserved engine lifetime budgets");
}
