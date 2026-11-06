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
