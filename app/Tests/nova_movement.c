#include "NovaMovementBudget.h"
#include <assert.h>
int main(void){PGNovaMovement s={.distanceMeters=80,.reserveBytes=128ull<<20};
 pg_nova_move_sample(&s,1000,true,0,0,0,false);pg_nova_move_sample(&s,1250,true,79,0,0,false);assert(!atomic_load(&s.permitUntilMS));
 pg_nova_move_sample(&s,1500,true,80,0,0,false);assert(atomic_load(&s.permitUntilMS)==3500);
 assert(pg_nova_move_budget(&s,1500,100ll<<20,160ull<<20)==-(16ll<<20));assert(pg_nova_move_budget(&s,1501,100ll<<20,160ull<<20)>=0);
 assert(pg_nova_move_budget(&s,2001,-5,100ull<<20)==-5);
 pg_nova_move_sample(&s,2500,false,0,0,0,true);assert(!s.anchorValid);assert(atomic_load(&s.permitUntilMS)>2500);
 assert(pg_nova_move_budget(&s,5000,100ll<<20,40ull<<20)<0);return 0;}
