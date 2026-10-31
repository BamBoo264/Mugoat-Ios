// Script-thread only; display FoW bypass, not world streaming or save exploration.
void PG_FN_HIDE_MAP_FOW(w2c_game*,u32);
static void pg_sandbox_map_tick(w2c_game *instance){
 if(configuredStartMode!=2||PGPauseMenuActive()||PGGameStatus()!=0||PGLoadSceneActive())return;
 static double next;double now=timeMS(CLOCK_MONOTONIC);if(now<next)return;next=now+1000;
 if(env.memory.size<=19520605)return;
 const _Atomic unsigned char *hidden=(const _Atomic unsigned char *)((const unsigned char *)(void *)env.memory.data+19520605);
 if(atomic_load_explicit(hidden,memory_order_relaxed))return;
 u64 previous=pg_asi_enter_script(instance);PG_FN_HIDE_MAP_FOW(instance,1);pg_asi_leave_script(instance,previous);
 static bool told;if(!told){pg_log("Sandbox map: exploration fog hidden; save discovery and world streaming unchanged.");told=true;}
}
