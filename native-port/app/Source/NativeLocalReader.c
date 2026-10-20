#include "NativeLocalReader.h"
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <limits.h>

// Four handles per I/O thread. No global read lock and no unbounded FD growth.
// Game/mod files are immutable for the lifetime of the running engine.
typedef struct {char *path;int fd;uint64_t used;} Slot;
typedef struct {Slot slots[4];uint64_t tick;} Reader;
static pthread_key_t key;static pthread_once_t once=PTHREAD_ONCE_INIT;
static int keyError;
static void destroy(void *ptr){Reader *r=ptr;if(!r)return;for(int i=0;i<4;i++){if(r->slots[i].path){close(r->slots[i].fd);free(r->slots[i].path);}}free(r);}
static void initialize(void){keyError=pthread_key_create(&key,destroy);}
void pg_local_reader_close_thread(void){pthread_once(&once,initialize);if(keyError)return;void *r=pthread_getspecific(key);pthread_setspecific(key,NULL);destroy(r);}
int64_t pg_local_read(const char *path,uint64_t offset,void *buffer,uint32_t length){
 if(!length)return 0;if(offset>INT64_MAX || length>(uint64_t)INT64_MAX-offset){errno=EINVAL;return -1;}
 pthread_once(&once,initialize);Reader *r=keyError?NULL:pthread_getspecific(key);
 if(!r&&!keyError){r=calloc(1,sizeof *r);if(r&&pthread_setspecific(key,r)!=0){free(r);r=NULL;}}
 int fd=-1;int temporary=0;
 if(r){
  int selected=-1;uint64_t oldest=UINT64_MAX;
  for(int i=0;i<4;i++){Slot *s=&r->slots[i];if(s->path&&!strcmp(s->path,path)){selected=i;fd=s->fd;break;}if(!s->path){oldest=0;selected=i;}else if(s->used<oldest){oldest=s->used;selected=i;}}
  Slot *s=&r->slots[selected];
  if(fd<0){fd=open(path,O_RDONLY|O_CLOEXEC);if(fd<0)return -1;char *copy=strdup(path);if(!copy){close(fd);errno=ENOMEM;return -1;}if(s->path){close(s->fd);free(s->path);}s->fd=fd;s->path=copy;}
  s->used=++r->tick;
 }else {fd=open(path,O_RDONLY|O_CLOEXEC);if(fd<0)return -1;temporary=1;}
 uint64_t done=0;while(done<length){ssize_t n=pread(fd,(char *)buffer+done,length-done,(off_t)(offset+done));if(n<0&&errno==EINTR)continue;if(n<0){if(temporary)close(fd);return -1;}if(!n)break;done+=(uint64_t)n;}
 if(temporary)close(fd);return (int64_t)done;
}
