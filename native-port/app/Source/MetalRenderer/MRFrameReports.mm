// Bounded local frame-time measurements. No network uploads or per-frame file writes.
#include "MRFrameReports.h"
#include "NativeFrameMetrics.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#include <TargetConditionals.h>
#include <atomic>
#include <cstdio>
#include <mach/mach.h>
#include <os/proc.h>
extern "C" void pg_log(const char *);
namespace mr {
static PGFrameMetricsWindow window;
static double windowStart;
static std::atomic<bool> inFlight{false}, resetPending{false}, active{true};
static id<MTLDevice> device;
void frameReportsInstall(id<MTLDevice> d){
 device=d;
 dispatch_async(dispatch_get_main_queue(),^{
  [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationWillResignActiveNotification object:nil queue:nil usingBlock:^(NSNotification *n){active=false;resetPending=true;}];
  [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification *n){resetPending=true;active=true;}];
 });
 pg_log("Local frame reports enabled: 15-second aggregates, no network telemetry.");
}
static void save(PGFrameMetricsSnapshot s){
 bool expected=false;if(!inFlight.compare_exchange_strong(expected,true))return;
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{@autoreleasepool{
  task_vm_info_data_t memory={};mach_msg_type_number_t count=TASK_VM_INFO_COUNT;
  bool valid=task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&memory,&count)==KERN_SUCCESS;
  double frames=std::max(1.0,(double)s.frames);
  NSDictionary *r=@{@"schema":@3,@"timestamp":@(NSDate.date.timeIntervalSince1970),@"frames":@(s.frames),@"fps":@(s.fps()),@"p95Ms":@(s.p95Ms),@"p99Ms":@(s.p99Ms),@"maxMs":@(s.maxMs),@"over50":@(s.over50),@"over100":@(s.over100),@"pipelineMs":@(s.work.pipeline/frames),@"gpuWaitMs":@(s.work.gpuWait/frames),@"submitMs":@(s.work.submit/frames),@"idleMs":@(s.work.idle/frames),@"draws":@(s.draws/frames),@"footprintMB":@(valid?memory.phys_footprint/1048576.0:0),@"metalMB":@(device.currentAllocatedSize/1048576.0),@"thermal":@(NSProcessInfo.processInfo.thermalState)};
  NSURL *dir=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
  NSData *data=[NSJSONSerialization dataWithJSONObject:r options:0 error:nil];
  [data writeToURL:[dir URLByAppendingPathComponent:@"performance-latest.json"] options:NSDataWritingAtomic error:nil];
  NSURL *history=[dir URLByAppendingPathComponent:@"performance-windows.jsonl"];
  NSNumber *size=nil;[history getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
  if(size.unsignedLongLongValue>2*1024*1024)[[NSData data] writeToURL:history options:NSDataWritingAtomic error:nil];
  if(![NSFileManager.defaultManager fileExistsAtPath:history.path])[NSFileManager.defaultManager createFileAtPath:history.path contents:nil attributes:nil];
  NSFileHandle *file=[NSFileHandle fileHandleForWritingToURL:history error:nil];
  @try{[file seekToEndOfFile];[file writeData:data];[file writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];[file closeFile];}@catch(NSException *e){}
  char line[256];snprintf(line,sizeof line,"[performance] %.1f FPS, p95 %.0f ms, p99 %.0f ms, max %.0f ms; pipeline %.2f, gpu-wait %.2f, submit %.2f ms/frame",s.fps(),s.p95Ms,s.p99Ms,s.maxMs,s.work.pipeline/frames,s.work.gpuWait/frames,s.work.submit/frames);pg_log(line);
  inFlight=false;
 }});
}
void frameReportsRecord(double timeMs,double frameMs,uint64_t draws,bool world,const FrameWork &w){
 if(resetPending.exchange(false)){window.reset();windowStart=0;return;}
 if(!active||!world||draws<100)return;
 PGFrameWork work{w.idle,w.pipeline,0,w.uploads,w.uploadBytes,w.gpuWait,w.submit};
 if(!window.record(frameMs,draws,work))return;
 if(!windowStart)windowStart=timeMs;
 if(timeMs-windowStart>=15000){save(window.snapshot());window.reset();windowStart=timeMs;}
}
}
