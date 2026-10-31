#import <Foundation/Foundation.h>
#include <stdint.h>
#include <string.h>
extern void pg_log(const char *);
// One immutable pack, no loose-file extraction and no work on the frame loop.
NSArray *PGNovaPackCandidates(NSString *path) {
 @autoreleasepool {
  NSFileHandle *file=[NSFileHandle fileHandleForReadingAtPath:path];if(!file)return nil;
  @try {
   unsigned long long total=[file seekToEndOfFile];[file seekToFileOffset:0];
   if(total<16||total>64ull*1024*1024)return nil;
   NSData *header=[file readDataOfLength:16];uint64_t indexSize=0;
   if(header.length!=16||memcmp(header.bytes,"NOVAPAK1",8))return nil;
   memcpy(&indexSize,(const uint8_t *)header.bytes+8,8);
   if(indexSize<2||indexSize>1024*1024||indexSize>total-16)return nil;
   NSData *index=[file readDataOfLength:(NSUInteger)indexSize];
   id rows=[NSJSONSerialization JSONObjectWithData:index options:0 error:nil];
   if(![rows isKindOfClass:NSArray.class]||[rows count]>4096)return nil;
   NSMutableArray *result=[NSMutableArray array];NSMutableSet *paths=[NSMutableSet set];
   uint64_t base=16+indexSize,end=0;
   for(id row in rows){
    if(![row isKindOfClass:NSArray.class]||[row count]!=3)return nil;
    id name=row[0],start=row[1],size=row[2];
    if(![name isKindOfClass:NSString.class]||![start isKindOfClass:NSNumber.class]||![size isKindOfClass:NSNumber.class])return nil;
    NSString *key=[name lowercaseString];
    BOOL permitted=[key isEqualToString:@"common/data/ui/fontmap.xml"]||[key hasPrefix:@"x64/data/lang/american.rpf/"]||[key hasPrefix:@"x64/data/lang/american_rel.rpf/"]||[key hasPrefix:@"x64/data/cdimages/scaleform_frontend.rpf/"]||[key hasPrefix:@"x64/data/cdimages/scaleform_platform_pc.rpf/"];
    if(!permitted||[name length]>500||[name containsString:@"\\"]||[[name pathComponents] containsObject:@".."]||[paths containsObject:key])return nil;
    uint64_t at=[start unsignedLongLongValue],length=[size unsignedLongLongValue];
    if([start doubleValue]!=(double)at||[size doubleValue]!=(double)length||at!=end||at>total-base||length>total-base-at)return nil;
    end=at+length;[paths addObject:key];[result addObject:@[name,path,@(length),@(base+at)]];
   }
   if(base+end!=total)return nil;
   return result;
  } @catch(NSException *e){return nil;} @finally {[file closeFile];}
 }
}
NSString *PGNovaVietnamesePath(void){
 NSUserDefaults *d=NSUserDefaults.standardUserDefaults;
 NSInteger mode=[d objectForKey:@"NewGenVietnameseMode"]?[d integerForKey:@"NewGenVietnameseMode"]:1;
 if(mode!=1&&mode!=2)return nil;
 return [NSBundle.mainBundle pathForResource:mode==1?@"VietnameseAccented":@"VietnamesePlain" ofType:@"nvp"];
}
