#pragma once
#include <math.h>
#include <stdbool.h>

// Original implementation for the pinned native engine. No Windows offsets or
// upstream TurboFix source are embedded here. Boost is an engine multiplier,
// not a physical pressure in bar/PSI.
typedef struct {
    bool enabled, forceTurbo, antiLag, effects, sound, gearBoost, dial;
    float spoolStart, spoolEnd, minBoost, maxBoost, spoolRate, unspoolRate;
    float falloffRPM, falloffBoost, minRPM, volume;
    float gears[10];
    unsigned periodMS, randomMS, loudIntervalMS;
    bool loudOffThrottle;
    unsigned soundSet;
} PGTurboConfig;

static inline PGTurboConfig pg_turbo_defaults(void) {
    PGTurboConfig c = {.spoolStart=.2f,.spoolEnd=.5f,.minBoost=-.8f,
        .maxBoost=1,.spoolRate=.999f,.unspoolRate=.97f,.falloffRPM=1,
        .minRPM=.65f,.volume=.3f,.periodMS=100,.randomMS=150,
        .loudIntervalMS=1000,.antiLag=true,.effects=true,.sound=true,
        .loudOffThrottle=true};
    for(unsigned i=0;i<10;i++)c.gears[i]=1;
    return c;
}
static inline float pg_turbo_clamp(float x,float lo,float hi) {
    return fminf(hi,fmaxf(lo,x));
}
static inline bool pg_turbo_valid(const PGTurboConfig *c) {
    if(!c||c->soundSet>2)return false;
    const float v[]={c->spoolStart,c->spoolEnd,c->minBoost,c->maxBoost,
        c->spoolRate,c->unspoolRate,c->falloffRPM,c->falloffBoost,c->minRPM,c->volume};
    for(unsigned i=0;i<sizeof(v)/sizeof(*v);i++)if(!isfinite(v[i]))return false;
    if(c->spoolStart<0||c->spoolEnd<=c->spoolStart||c->spoolEnd>1||
       c->minBoost<-.95f||c->minBoost>0||c->maxBoost<=0||c->maxBoost>5||
       c->spoolRate<=0||c->spoolRate>=1||c->unspoolRate<=0||c->unspoolRate>=1||
       c->falloffRPM<c->spoolEnd||c->falloffRPM>1||c->falloffBoost<0||c->falloffBoost>5||
       c->minRPM<0||c->minRPM>1||c->volume<0||c->volume>1||
       c->periodMS<100||c->periodMS>10000||c->randomMS>10000||
       c->loudIntervalMS<100||c->loudIntervalMS>10000)return false;
    for(unsigned i=0;i<10;i++)if(!isfinite(c->gears[i])||c->gears[i]<0||c->gears[i]>5)return false;
    return true;
}
static inline float pg_turbo_step(const PGTurboConfig *c,float previous,
                                  float rpm,float throttle,unsigned gear,float dt) {
    if(!isfinite(previous)||!isfinite(rpm)||!isfinite(throttle)||!isfinite(dt)||dt<=0)return previous;
    // Ignore a long suspension interval, rather than emitting catch-up work.
    dt=fminf(dt,.1f);rpm=pg_turbo_clamp(rpm,0,1);throttle=pg_turbo_clamp(fabsf(throttle),0,1);
    float maximum=c->gearBoost?c->gears[gear==0?0:(gear>10?9:gear-1)]:c->maxBoost;
    if(c->falloffRPM<1&&rpm>c->falloffRPM)
        maximum+=(c->falloffBoost-maximum)*(rpm-c->falloffRPM)/(1-c->falloffRPM);
    float vacuum=c->minBoost*pg_turbo_clamp((rpm-.2f)/.8f,0,1);
    float target=vacuum*(1-throttle)+maximum*pg_turbo_clamp((rpm-c->spoolStart)/(c->spoolEnd-c->spoolStart),0,1)*throttle;
    if(c->antiLag&&throttle<.1f&&rpm>=c->minRPM)target=maximum;
    float rate=target>previous?c->spoolRate:c->unspoolRate;
    float result=previous+(target-previous)*(-expm1f(log1pf(-rate)*dt));
    return pg_turbo_clamp(result,c->minBoost,5);
}
