#import "MemoryDiagnostics.h"
#import "AKSupport.h"
#import <UIKit/UIKit.h>
#include <mach/mach.h>
#include <os/proc.h>

// At most one hour at 30-second intervals, plus lifetime extrema. A previous
// session is kept separately; no text, app memory, endpoints or identifiers.
@interface AKMemoryJournal : NSObject
@property NSURL *url;
@property NSMutableArray<NSDictionary *> *samples;
@property uint64_t peakFootprint, lowestAvailable;
@property unsigned warnings;
- (instancetype)initWithURL:(NSURL *)url;
- (void)append:(NSDictionary *)sample;
@end
@implementation AKMemoryJournal
- (instancetype)initWithURL:(NSURL *)url {
    if ((self=[super init])) { _url=url; _samples=[NSMutableArray new]; _lowestAvailable=UINT64_MAX; }
    return self;
}
- (void)append:(NSDictionary *)sample {
    if (sample[@"footprint_bytes"]) _peakFootprint=MAX(_peakFootprint,[sample[@"footprint_bytes"] unsignedLongLongValue]);
    if (sample[@"available_bytes"]) _lowestAvailable=MIN(_lowestAvailable,[sample[@"available_bytes"] unsignedLongLongValue]);
    if ([sample[@"event"] isEqual:@"memory_warning"]) _warnings++;
    [_samples addObject:sample];
    if (_samples.count>120) [_samples removeObjectAtIndex:0];
    NSMutableDictionary *report=[@{@"version":@1, @"samples":_samples,
        @"peak_footprint_bytes":@(_peakFootprint), @"memory_warnings":@(_warnings)} mutableCopy];
    if (_lowestAvailable!=UINT64_MAX) report[@"lowest_available_bytes"]=@(_lowestAvailable);
    NSData *data=[NSJSONSerialization dataWithJSONObject:report options:0 error:nil];
    if (data && ![data writeToURL:_url options:NSDataWritingAtomic error:nil])
        AKLog(@"memory diagnostic: could not persist sample");
}
@end

static NSDictionary *memorySample(NSString *event, BOOL foreground) {
    NSMutableDictionary *sample=[@{@"time":@(NSDate.date.timeIntervalSince1970),
        @"uptime_s":@(NSProcessInfo.processInfo.systemUptime), @"event":event,
        @"foreground":@(foreground), @"available_bytes":@(os_proc_available_memory())} mutableCopy];
    task_vm_info_data_t info={0}; mach_msg_type_number_t count=TASK_VM_INFO_COUNT;
    kern_return_t result=task_info(mach_task_self(),TASK_VM_INFO,(task_info_t)&info,&count);
    if (result==KERN_SUCCESS && count>=TASK_VM_INFO_REV1_COUNT) {
        sample[@"footprint_bytes"]=@(info.phys_footprint);
        sample[@"resident_bytes"]=@(info.resident_size);
        sample[@"compressed_bytes"]=@(info.compressed);
    } else sample[@"query_error"]=@(result);
    return sample;
}
void AKStartMemoryDiagnostics(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        dispatch_queue_t queue=dispatch_queue_create("local.wolkara.memory-counters",DISPATCH_QUEUE_SERIAL);
        NSURL *directory=[NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]];
        NSURL *url=[directory URLByAppendingPathComponent:@"memory-health.json"];
        __block BOOL foreground=UIApplication.sharedApplication.applicationState==UIApplicationStateActive;
        AKMemoryJournal *journal=[[AKMemoryJournal alloc] initWithURL:url];
        dispatch_async(queue,^{ @autoreleasepool {
            NSFileManager *files=NSFileManager.defaultManager;
            NSURL *previous=[directory URLByAppendingPathComponent:@"memory-health-previous.json"];
            if ([files fileExistsAtPath:url.path]) {
                [files removeItemAtURL:previous error:nil];
                [files moveItemAtURL:url toURL:previous error:nil];
            }
            [journal append:memorySample(@"start",foreground)];
        } });
        NSDictionary *notifications=@{UIApplicationDidReceiveMemoryWarningNotification:@"memory_warning",
            UIApplicationDidEnterBackgroundNotification:@"background", UIApplicationDidBecomeActiveNotification:@"foreground"};
        for (NSString *name in notifications) {
            NSString *event=notifications[name];
            [NSNotificationCenter.defaultCenter addObserverForName:name object:nil queue:nil
                usingBlock:^(__unused NSNotification *note) {
                    dispatch_async(queue,^{ @autoreleasepool {
                        if ([event isEqual:@"background"]) foreground=NO;
                        if ([event isEqual:@"foreground"]) foreground=YES;
                        [journal append:memorySample(event,foreground)];
                    } });
                }];
        }
        static dispatch_source_t timer;
        timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,queue);
        dispatch_source_set_timer(timer,dispatch_time(DISPATCH_TIME_NOW,30*NSEC_PER_SEC),30*NSEC_PER_SEC,3*NSEC_PER_SEC);
        dispatch_source_set_event_handler(timer,^{ @autoreleasepool { [journal append:memorySample(@"sample",foreground)]; } });
        dispatch_resume(timer);
    });
}
