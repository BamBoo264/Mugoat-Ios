from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1];out=Path(sys.argv[1]);s=(root/'app/Source/NativeASI.c').read_text(encoding='utf-8');a=s.index('static uint64_t k_CreateDirectoryW(');b=s.index('// Settings files (.ini)',a)
source=r"""#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>
#include <assert.h>
static unsigned char mem[65536];static uint64_t args[8],lastError;
#define G(a) (mem+(a))
#define ARG(i) (args[i])
static void setError(uint64_t e){lastError=e;}
static void wr16(uint64_t p,uint16_t n){memcpy(G(p),&n,2);}static void wr32(uint64_t p,uint32_t n){memcpy(G(p),&n,4);}static void wr64(uint64_t p,uint64_t n){memcpy(G(p),&n,8);}
static uint64_t galloc(uint64_t n){assert(n<1000);return 32768;}static void release(uint64_t p){assert(p==32768);}static struct{void(*free)(uint64_t);}H={release};
static void wToUtf8(uint64_t p,long n,char *o,size_t cap){size_t i=0;while(i+1<cap&&mem[p+2*i]){o[i]=mem[p+2*i];i++;}o[i]=0;}
static char base[1024];static void hostPath(const char *s,char *o,size_t cap){snprintf(o,cap,"%s/%s",base,strrchr(s,'\\')?strrchr(s,'\\')+1:s);}
static uint64_t findFirst(const char *p,uint64_t out,bool wide){return 123;}
"""
source+=s[a:b]+r"""
int main(void){strcpy(base,"/tmp/nova-abi-XXXXXX");assert(mkdtemp(base));const char *name="config";for(size_t i=0;i<=strlen(name);i++)wr16(100+2*i,name[i]);args[0]=100;
assert(k_CreateDirectoryW()==1);assert(k_CreateDirectoryW()==0&&lastError==183);assert(k_GetFileAttributesW()==0x10);
args[1]=0;args[2]=200;assert(k_GetFileAttributesExW()==1);uint32_t attr;memcpy(&attr,G(200),4);assert(attr==0x10);
args[3]=300;memset(G(400),0,16);args[0]=400;assert(k_SHGetKnownFolderPath()!=0);uint64_t ptr;memcpy(&ptr,G(300),8);assert(ptr==0);
unsigned char id[16]={0x85,0x27,0xb3,0xf1,0xba,0x6f,0xcf,0x4f,0x9d,0x55,0x7b,0x8e,0x7f,0x15,0x70,0x91};memcpy(G(400),id,16);assert(k_SHGetKnownFolderPath()==0);memcpy(&ptr,G(300),8);assert(ptr==32768);args[0]=ptr;k_CoTaskMemFree();
char p[1200];snprintf(p,sizeof p,"%s/config",base);rmdir(p);snprintf(p,sizeof p,"%s/LocalAppData",base);rmdir(p);rmdir(base);puts("PASS production camera filesystem ABI: UTF16 paths, attributes, honest HRESULT and owned output memory");}
"""
p=out/'camera-filesystem.c';p.write_text(source);binary=out/'camera-filesystem';subprocess.run(['clang','-fsanitize=address,undefined',str(p),'-o',str(binary)],check=True);subprocess.run([str(binary)],check=True)
