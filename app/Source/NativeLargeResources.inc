// Extended compressed sizes are mod-only and fingerprinted against the mounted entry.
// Ordinary resources take the sentinel comparison only, with no table lock.
extern bool pg_mods_large_archive_known(const char*);
extern uint32_t pg_mods_large_resource_size(const char*,const char*,uint32_t,uint32_t);
#define PG_LARGE_SLOTS 4096u
static struct {uint64_t address,low,high,table;uint32_t size;} largeEntries[PG_LARGE_SLOTS];
static _Atomic uint32_t largeEntryCount;
static pthread_mutex_t largeEntryLock=PTHREAD_MUTEX_INITIALIZER;
u32 pg_large_rpf_size(w2c_game *instance,u64 entry,u32 encoded){
 (void)instance;if(encoded!=0xffffffu||!entry)return encoded;
 const uint64_t *words=pg_pointer(&env,entry,16);uint64_t low=words[0],high=words[1];
 unsigned start=(unsigned)((entry>>4)*2654435761u)&(PG_LARGE_SLOTS-1);
 pthread_mutex_lock(&largeEntryLock);
 uint32_t size=encoded;
 for(unsigned k=0,i=start;k<PG_LARGE_SLOTS;k++,i=(i+1)&(PG_LARGE_SLOTS-1)){
  if(!largeEntries[i].address)break;
  if(largeEntries[i].address==entry){if(largeEntries[i].low==low&&largeEntries[i].high==high)size=largeEntries[i].size;break;}
 }
 pthread_mutex_unlock(&largeEntryLock);return size;
}
static void pg_large_register(uint64_t address,uint64_t table,uint32_t size){
 const uint64_t *words=pg_pointer(&env,address,16);
 unsigned start=(unsigned)((address>>4)*2654435761u)&(PG_LARGE_SLOTS-1);int slot=-1;
 pthread_mutex_lock(&largeEntryLock);
 for(unsigned k=0,i=start;k<PG_LARGE_SLOTS;k++,i=(i+1)&(PG_LARGE_SLOTS-1)){
  if(largeEntries[i].address==address){slot=(int)i;break;}
  if(largeEntries[i].address==UINT64_MAX&&slot<0)slot=(int)i;
  if(!largeEntries[i].address){if(slot<0)slot=(int)i;break;}
 }
 if(slot>=0){
  if(!largeEntries[slot].address||largeEntries[slot].address==UINT64_MAX)atomic_fetch_add(&largeEntryCount,1);
  largeEntries[slot].address=address;largeEntries[slot].table=table;largeEntries[slot].low=words[0];largeEntries[slot].high=words[1];largeEntries[slot].size=size;
 }
 pthread_mutex_unlock(&largeEntryLock);
}
void pg_large_archive_unmount(w2c_game *instance,u64 packfile){
 (void)instance;if(!atomic_load(&largeEntryCount))return;
 uint64_t table=*(uint64_t*)pg_pointer(&env,packfile+32,8);if(!table)return;
 pthread_mutex_lock(&largeEntryLock);
 for(unsigned k=0;k<PG_LARGE_SLOTS;k++)if(largeEntries[k].address&&largeEntries[k].address!=UINT64_MAX&&largeEntries[k].table==table){largeEntries[k].address=UINT64_MAX;atomic_fetch_sub(&largeEntryCount,1);}
 pthread_mutex_unlock(&largeEntryLock);
}
static void pg_large_walk(const char *archive,uint64_t entries,uint64_t names,unsigned shift,uint32_t index,char path[512],size_t length,int depth){
 if(depth>24)return;
 const uint64_t *e=pg_pointer(&env,entries+16ull*index,16);
 const char *name=pg_string(&env,names+((e[0]&0xffff)<<shift));
 size_t n=length;
 if(index){int add=snprintf(path+length,512-length,"%s%s",length?"/":"",name);if(add<0||(size_t)add>=512-length)return;n+=add;}
 if(((e[0]>>40)&0x7fffff)==0x7fffff){
  uint32_t first=(uint32_t)e[1],count=(uint32_t)(e[1]>>32);
  if(count<200000)for(uint32_t k=0;k<count;k++)pg_large_walk(archive,entries,names,shift,first+k,path,n,depth+1);
 }else if((e[0]>>63)&&((e[0]>>16)&0xffffff)==0xffffff){
  uint32_t size=pg_mods_large_resource_size(archive,path,(uint32_t)e[1],(uint32_t)(e[1]>>32));
  pg_large_register(entries+16ull*index,entries,size?size:0xffffffu); // invalidate even an identical entry reused by an unindexed archive
  if(size){char line[700];snprintf(line,sizeof line,"Extended resource ready: %.250s/%.250s = %u bytes (24-bit sentinel expanded).",archive,path,size);pg_log(line);}
 }
 path[length]=0;
}
static void pg_large_archive_mounted(uint64_t packfile,const char *label){
 if(!pg_mods_large_archive_known(label))return;
 uint64_t entries=*(uint64_t*)pg_pointer(&env,packfile+32,8),names=*(uint64_t*)pg_pointer(&env,packfile+16,8);
 unsigned shift=*(uint8_t*)pg_pointer(&env,packfile+184,1);if(!entries||!names||shift>4)return;
 char path[512]={0};pg_large_walk(label,entries,names,shift,0,path,0,0);
}
