#include <stdbool.h>
#include <stdint.h>
#include <assert.h>
#include "NovaLogFilter.h"
int main(void){
 assert(pg_nova_noise_kind("Fatal Error: out of memory")==-1);
 assert(pg_nova_noise_kind("Error: missing game resource")==-1);
 assert(pg_nova_noise_kind("Warning: [Parser] Array indices is a fixed size and needs exactly 6 elements")==0);
 assert(pg_nova_noise_emit(1)&&pg_nova_noise_emit(4)&&!pg_nova_noise_emit(5)&&pg_nova_noise_emit(1024));
 unsigned kept=0;for(uint64_t i=1;i<=10000;i++)kept+=pg_nova_noise_emit(i);assert(kept==13);
 return 0;
}
