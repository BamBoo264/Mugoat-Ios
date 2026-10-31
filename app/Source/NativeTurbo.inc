// Included after script context helpers and pg_f32_arg. Only the player's
// driven vehicle is opted in. Fixed storage; no nearby-vehicle scans.
u64 PG_FN_TURBO_ENTITY_ADDRESS(w2c_game*,u32);
extern void PGTurboAudioEnable(bool enabled,unsigned soundSet);
extern void PGTurboPlayPop(float volume,bool loud);
static pthread_mutex_t turboLock=PTHREAD_MUTEX_INITIALIZER;
static _Atomic bool turboEnabled;
static _Atomic uint64_t turboVehicle;
static PGTurboConfig turboConfig;
static struct {float rpm,throttle,boost;unsigned gear;double at;} turboTelemetry;
PGTurboConfig PGTurboDefaultConfig(void){return pg_turbo_defaults();}
bool PGSetTurboConfig(PGTurboConfig c){
    if(!pg_turbo_valid(&c))return false;
    atomic_store(&turboEnabled,false);
    pthread_mutex_lock(&turboLock);turboConfig=c;pthread_mutex_unlock(&turboLock);
    if(!c.enabled)atomic_store(&turboVehicle,0);
    PGTurboAudioEnable(c.enabled&&c.sound,c.soundSet);
    atomic_store(&turboEnabled,c.enabled);return true;
}
bool PGTurboTelemetry(float *rpm,float *boost,unsigned *gear){
    pthread_mutex_lock(&turboLock);
    bool valid=atomic_load(&turboEnabled)&&atomic_load(&turboVehicle)&&timeMS(CLOCK_MONOTONIC)-turboTelemetry.at<500;
    if(rpm)*rpm=turboTelemetry.rpm;
    if(boost)*boost=turboTelemetry.boost;
    if(gear)*gear=turboTelemetry.gear;
    pthread_mutex_unlock(&turboLock);return valid;
}
float pg_native_turbo_boost(uint64_t vehicle,float previous,float rpm,float throttle,uint32_t gear,float dt,float stock){
    if(!atomic_load(&turboEnabled)||vehicle!=atomic_load(&turboVehicle))return stock;
    // Physics never waits on UIKit or invokes game natives/audio.
    if(pthread_mutex_trylock(&turboLock))return stock;
    float result=pg_turbo_step(&turboConfig,previous,rpm,throttle,gear,dt);
    if(!isfinite(result)){pthread_mutex_unlock(&turboLock);return stock;}
    turboTelemetry.rpm=rpm;turboTelemetry.throttle=throttle;turboTelemetry.boost=result;
    turboTelemetry.gear=gear;turboTelemetry.at=timeMS(CLOCK_MONOTONIC);
    pthread_mutex_unlock(&turboLock);return result;
}
static void pg_turbo_tick(w2c_game *instance){
    static u32 lastVehicle;static int bones[16];static unsigned boneCount;
    static bool reportedTelemetry,reportedFX;
    static double nextFX,nextRequest;static unsigned requestAttempts;static uint64_t asset,effect,boneName;
    if(!atomic_load(&turboEnabled)||PGPauseMenuActive()||PGGameStatus()!=0||PGLoadSceneActive()){
        atomic_store(&turboVehicle,0);lastVehicle=0;return;
    }
    PGTurboConfig c;float rpm,throttle;double sampled;
    pthread_mutex_lock(&turboLock);c=turboConfig;rpm=turboTelemetry.rpm;throttle=turboTelemetry.throttle;sampled=turboTelemetry.at;pthread_mutex_unlock(&turboLock);
    u64 previous=pg_asi_enter_script(instance);
    u32 ped=PG_FN_PLAYER_PED_ID(instance),vehicle=ped?PG_FN_PED_VEHICLE(instance,ped,0):0;
    if(vehicle&&pg_test_call(instance,0xbb40dd2270b65366ull,3,(uint64_t[]){vehicle,(uint32_t)-1,0})!=ped)vehicle=0;
    if(vehicle!=lastVehicle){
        atomic_store(&turboVehicle,0);lastVehicle=vehicle;boneCount=0;requestAttempts=0;reportedTelemetry=false;reportedFX=false;nextFX=timeMS(CLOCK_MONOTONIC)+200;
        pthread_mutex_lock(&turboLock);turboTelemetry.at=0;pthread_mutex_unlock(&turboLock);
        if(vehicle){
            if(c.forceTurbo){
                pg_test_call(instance,0x1f2aa07f00b3217aull,2,(uint64_t[]){vehicle,0});
                pg_test_call(instance,0x2a1f4f37f95bad08ull,3,(uint64_t[]){vehicle,18,1});
            }
            // Cache only bones that actually exist, once on entry.
            if(!boneName)boneName=pg_asi_alloc(32);
            if(boneName)for(unsigned i=0;i<16;i++){
                char name[32];if(i==0)snprintf(name,sizeof name,"exhaust");else snprintf(name,sizeof name,"exhaust_%u",i+1);
                memcpy(pg_pointer(&env,boneName,32),name,strlen(name)+1);
                int bone=(int)pg_test_call(instance,0xfb71170b7e76acbaull,2,(uint64_t[]){vehicle,boneName});
                if(bone>=0)bones[boneCount++]=bone;
            }
        }
    }
    atomic_store(&turboVehicle,vehicle?PG_FN_TURBO_ENTITY_ADDRESS(instance,vehicle):0);
    double now=timeMS(CLOCK_MONOTONIC);
    if(vehicle&&sampled>0&&now-sampled<250&&!reportedTelemetry){
        reportedTelemetry=true;pg_log("Turbo native: transmission telemetry active for player vehicle.");
    }
    if(!vehicle||sampled<=0||now-sampled>250||!c.antiLag||rpm<c.minRPM||fabsf(throttle)>=.1f||now<nextFX)goto done;
    // At most ten bursts per second, no catch-up after pause/loading.
    nextFX=now+c.periodMS+(c.randomMS?arc4random_uniform(c.randomMS+1):0);
    if(c.effects&&boneCount){
        u64 core=pg_wasm_text(&asset,"core"),fx=pg_wasm_text(&effect,"veh_backfire");
        if(!core||!fx)goto done;
        if(!(pg_test_call(instance,0x8702416e512ec454ull,1,(uint64_t[]){core})&1)){
            if(now>=nextRequest&&requestAttempts<10){pg_test_call(instance,0xb80d8756b4668ab6ull,1,(uint64_t[]){core});nextRequest=now+1000;requestAttempts++;}
        }else{
        // Hard cap four visible exhausts per burst, preserving predictable cost.
        for(unsigned i=0;i<boneCount&&i<4;i++){
            pg_test_call(instance,0x6c38af3693a69a91ull,1,(uint64_t[]){core});
            uint64_t result=pg_test_call(instance,0x02b1f2a72e0f5325ull,14,(uint64_t[]){fx,vehicle,0,0,0,0,0,0,(uint32_t)bones[i],pg_f32_arg(1),0,0,0,0});
            if(!reportedFX){reportedFX=true;pg_log(result==1?"Turbo native: exhaust FX native accepted first burst.":"Turbo native: exhaust FX native did not confirm first burst; check particle asset and vehicle bones.");}
        }
        }
    }
    if(c.sound&&boneCount){static double lastLoud;bool loud=c.loudOffThrottle&&now-lastLoud>=c.loudIntervalMS;
        PGTurboPlayPop(c.volume,loud);if(loud)lastLoud=now;}
done:
    pg_asi_leave_script(instance,previous);
}
