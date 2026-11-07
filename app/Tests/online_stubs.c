#include "online_bridge.h"
void PGRemoveRemotePeer(const char *s){}
bool PGGetPlayerPosition(float p[3]){p[0]=100;p[1]=200;p[2]=30;return true;}
float PGGetPlayerHeading(void){return 0;}
void PGUpdateRemotePeer(const char *s,float x,float y,float z,float h,uint32_t m){}
uint32_t PGGameStatus(void){return 0;}
void PGTeleportPlayer(float x,float y,float z){}
PGControlHints PGReadControlHints(uint32_t c){PGControlHints h={0};return h;}
uint32_t PGCurrentTouchContext(void){return 0;}

void PGSetOnlinePvP(bool enabled){}
unsigned PGTakeOnlineHit(const char *peerId){return 0;}
void PGQueueOnlineHit(unsigned damage){}

void PGUpdateRemotePeerState(const char *id,float x,float y,float z,float h,uint32_t m,uint32_t w,const char *o,int32_t seat,uint32_t shot,uint32_t epoch,uint32_t windows,uint32_t pedModel,uint32_t shotWeapon){}
uint32_t PGReadOnlinePlayerModel(void){return 0;}
bool PGReadOnlineEffect(PGOnlineEffect *effect){return false;}
void PGUpdateRemoteEffect(const char *id, PGOnlineEffect effect){}
void PGSetOnlineSession(bool enabled){}
uint32_t PGReadOnlineLoadout(char owner[32],int32_t *seat,uint32_t *shot,uint32_t *vehicle,uint32_t *windows,uint32_t *impact,uint32_t *shotWeapon){owner[0]=0;*seat=-1;*shot=0;*vehicle=0;*windows=0;*impact=0;return 0;}

void PGRequestOnlinePassenger(void){}

uint32_t PGReadOnlinePeerGlass(const char *id,uint32_t *epoch){*epoch=0;return 0;}
void PGQueueOnlineGlass(uint32_t epoch,uint32_t mask){}
