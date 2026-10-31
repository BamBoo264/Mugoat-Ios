#import <Foundation/Foundation.h>
#include <assert.h>
extern NSArray *PGNovaPackCandidates(NSString *);
int main(int argc,char **argv){@autoreleasepool{
 assert(argc==2);NSString *root=@(argv[1]);
 for(NSString *kind in @[@"Accented",@"Plain"]){
  NSString *path=[root stringByAppendingFormat:@"/Vietnamese%@.nvp",kind];
  NSArray *rows=PGNovaPackCandidates(path);assert(rows.count>1000);
  NSFileHandle *f=[NSFileHandle fileHandleForReadingAtPath:path];
  for(NSArray *r in rows){[f seekToFileOffset:[r[3] unsignedLongLongValue]];NSData *b=[f readDataOfLength:[r[2] unsignedIntegerValue]];assert(b.length==[r[2] unsignedIntegerValue]);}
  [f closeFile];
  NSMutableData *broken=[[NSData dataWithContentsOfFile:path] mutableCopy];((uint8_t*)broken.mutableBytes)[0]^=1;
  NSString *bad=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];[broken writeToFile:bad atomically:YES];assert(PGNovaPackCandidates(bad)==nil);[NSFileManager.defaultManager removeItemAtPath:bad error:nil];
 }
 puts("PASS production Nova pack reader: both complete packs, all slice bounds, malformed header rejected.");return 0;
}}
