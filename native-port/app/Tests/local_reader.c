#include "NativeLocalReader.h"
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
static char folder[1024];
static void *run(void *unused){(void)unused;for(int n=0;n<400;n++){int i=n%20;char path[1200],bytes[16];snprintf(path,sizeof path,"%s/%d",folder,i);assert(pg_local_read(path,10,bytes,16)==16);for(int j=0;j<16;j++)assert(bytes[j]==(char)i);}pg_local_reader_close_thread();return NULL;}
int main(void){strcpy(folder,"/tmp/mugoat-reader-XXXXXX");assert(mkdtemp(folder));for(int i=0;i<20;i++){char path[1200],bytes[64];memset(bytes,i,64);snprintf(path,sizeof path,"%s/%d",folder,i);FILE *f=fopen(path,"wb");assert(f);assert(fwrite(bytes,1,64,f)==64);fclose(f);}
 pthread_t threads[4];for(int i=0;i<4;i++)assert(!pthread_create(&threads[i],NULL,run,NULL));for(int i=0;i<4;i++)pthread_join(threads[i],NULL);
 char path[1200],b[16];snprintf(path,sizeof path,"%s/3",folder);assert(pg_local_read(path,60,b,16)==4);assert(pg_local_read(path,64,b,16)==0);assert(pg_local_read(path,UINT64_MAX,b,1)==-1);assert(pg_local_read("/no/such/game/file",0,b,1)==-1);pg_local_reader_close_thread();
 for(int i=0;i<20;i++){snprintf(path,sizeof path,"%s/%d",folder,i);unlink(path);}rmdir(folder);puts("PASS: bounded local reader concurrent bytes, eviction, EOF, errors and thread cleanup");}
