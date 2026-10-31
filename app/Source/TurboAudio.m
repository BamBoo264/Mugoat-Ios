#import <AVFAudio/AVFAudio.h>
#import <Foundation/Foundation.h>
#include <stdbool.h>

// The game owns the audio session. Never reset its category/mixer here.
static NSMutableArray<AVAudioPlayer *> *turboPops,*turboSubs,*turboActive;
static BOOL turboAudioEnabled;
static unsigned turboAudioSet=~0u, turboSubIndex;
void PGTurboAudioEnable(bool enabled,unsigned soundSet){
    dispatch_async(dispatch_get_main_queue(), ^{
        turboAudioEnabled=enabled;
        if(!enabled||soundSet!=turboAudioSet){
            for(AVAudioPlayer *p in turboActive)[p stop];
            for(AVAudioPlayer *p in turboSubs)[p stop];
            turboActive=[NSMutableArray array];turboPops=nil;turboSubs=nil;
        }
        if(!enabled)return;
        if(turboPops)return;
        turboAudioSet=soundSet;
        NSString *name=@[@"backfire",@"Default",@"Default-Old"][MIN(soundSet,2u)];
        NSURL *root=[NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:[@"TurboSounds" stringByAppendingPathComponent:name] isDirectory:YES];
        turboPops=[NSMutableArray array];turboSubs=[NSMutableArray array];
        // Enumerate existing names: Default deliberately has no EX_POP_34.
        NSArray<NSURL *> *files=[[NSFileManager defaultManager] contentsOfDirectoryAtURL:root includingPropertiesForKeys:nil options:0 error:nil];
        for(NSURL *url in files){
            NSString *file=url.lastPathComponent;
            if(![file hasPrefix:@"EX_POP_"]||![file.pathExtension.lowercaseString isEqualToString:@"wav"])continue;
            unsigned copies=[file isEqualToString:@"EX_POP_SUB.wav"]?3:1;
            for(unsigned i=0;i<copies;i++){
                AVAudioPlayer *p=[[AVAudioPlayer alloc] initWithContentsOfURL:url error:nil];
                if(!p)continue;[p prepareToPlay];
                if(copies==3)[turboSubs addObject:p];else [turboPops addObject:p];
            }
        }
        NSLog(@"Turbo audio: %@, %lu pops, %lu sub voices",name,(unsigned long)turboPops.count,(unsigned long)turboSubs.count);
    });
}
void PGTurboPlayPop(float volume,bool loud){
    dispatch_async(dispatch_get_main_queue(), ^{
        if(!turboAudioEnabled)return;
        NSIndexSet *finished=[turboActive indexesOfObjectsPassingTest:^BOOL(AVAudioPlayer *p,NSUInteger index,BOOL *stop){return !p.playing;}];
        [turboActive removeObjectsAtIndexes:finished];
        if(loud&&turboPops.count){
            AVAudioPlayer *p=turboPops[arc4random_uniform((uint32_t)turboPops.count)];
            [turboActive removeObject:p];
            if(turboActive.count>=4){[turboActive.firstObject stop];[turboActive removeObjectAtIndex:0];}
            p.currentTime=0;p.volume=volume;[p play];[turboActive addObject:p];
        }
        if(turboSubs.count){AVAudioPlayer *p=turboSubs[turboSubIndex++%turboSubs.count];p.currentTime=0;p.volume=volume;[p play];}
    });
}
