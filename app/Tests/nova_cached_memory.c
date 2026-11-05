#include "SharedSIMD.h"
#include "NovaNativeMemoryBase.h"
#include <assert.h>
#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
static jmp_buf recovery;
static int expecting_trap;
void wasm_rt_trap(wasm_rt_trap_t code){if(expecting_trap){expecting_trap=0;longjmp(recovery,1);}abort();}
static _Atomic volatile uint8_t storage[8192];
static wasm_rt_shared_memory_t memory;
static _Atomic unsigned sequence,acknowledged;
static void *worker(void *arg){
 uint8_t *base=arg;
 for(unsigned i=1;i<=20000;i++){
  while(atomic_load_explicit(&sequence,memory_order_acquire)!=i){}
  unsigned char bytes[16];simde_wasm_v128_store(bytes,v128_load_shared(base,0,&memory,128));
  for(unsigned j=0;j<16;j++)assert(bytes[j]==(unsigned char)(i+j));
  atomic_store_explicit(&acknowledged,i,memory_order_release);
 }
 return NULL;
}
int main(void){
 memory.data=storage;memory.size=sizeof storage;
 uint8_t *base=(uint8_t *)(void *)storage;
 for(unsigned i=0;i<sizeof storage;i++)atomic_store(&storage[i],(uint8_t)(i*17));
 for(unsigned offset=0;offset<128;offset++){
  unsigned char a[16],b[16];
  simde_wasm_v128_store(a,v128_load_shared(NULL,0,&memory,offset));simde_wasm_v128_store(b,v128_load_shared(base,0,&memory,offset));assert(!memcmp(a,b,16));
  v128_store_shared(base,0,&memory,2048+offset,simde_wasm_v128_load(a));
  for(unsigned j=0;j<16;j++)assert(atomic_load(&storage[2048+offset+j])==a[j]);
 }
 for(unsigned i=0;i<3;i++){
  uint64_t at=i==0?sizeof storage-15:i==1?sizeof storage:UINT64_MAX;
  if(!setjmp(recovery)){expecting_trap=1;(void)v128_load_shared(base,0,&memory,at);abort();}
 }
 memory.size=4096;v128_store_shared(base,0,&memory,4080,simde_wasm_i32x4_splat(7));memory.size=8192;
 assert(memory.data==storage); // Growth changes the accessible size, not the base.
 pthread_t thread;assert(!pthread_create(&thread,NULL,worker,base));
 for(unsigned i=1;i<=20000;i++){
  unsigned char bytes[16];for(unsigned j=0;j<16;j++)bytes[j]=(uint8_t)(i+j);
  v128_store_shared(base,0,&memory,128,simde_wasm_v128_load(bytes));atomic_store_explicit(&sequence,i,memory_order_release);
  while(atomic_load_explicit(&acknowledged,memory_order_acquire)!=i){}
 }
 assert(!pthread_join(thread,NULL));
 puts("PASS: production cached/uncached SIMD, unaligned access, overflow traps, fixed-base growth, 20000 threaded handoffs");
}
