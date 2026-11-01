#pragma once
#include <string.h>
#include <stdatomic.h>
// Only proven repetitive, non-fatal families from N001 logs; unknown errors pass.
static inline int pg_nova_noise_kind(const char *s){
 if(strstr(s,"Warning: [Parser] Array indices is a fixed size"))return 0;
 if(strstr(s,"Warning: [Parser] Array liveries is a fixed size"))return 1;
 if(strstr(s,"Error: [Parser] Couldn't set the array size for node indices,"))return 2;
 if(strstr(s,"Error: [Parser] Couldn't set the array size for node liveries,"))return 3;
 if(strstr(s,"Warning: <ClothInstanc> [Graphics] grcBuffer_d3d11::Unlock_Internal()"))return 4;
 return -1;
}
static inline bool pg_nova_noise_emit(uint64_t count){return count<=4 || count%1024==0;}
