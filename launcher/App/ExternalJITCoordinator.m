#import "ExternalJITCoordinator.h"
#if TOLKARA_EXTERNAL_JIT_PROTOTYPE
#import <UIKit/UIKit.h>
#import <Security/Security.h>
#import "ExternalJITRequest.h"
#include "DebuggerArena.h"
#include "ExternalJITProbe.h"
#include "NativeGuest.h"
#include <unistd.h>

// Security exposes these on iOS but does not ship its SecTask header in the SDK.
// Query only this process's signed development entitlement.
typedef struct __SecTask *SecTaskRef;
extern SecTaskRef SecTaskCreateFromSelf(CFAllocatorRef allocator);
extern CFTypeRef SecTaskCopyValueForEntitlement(SecTaskRef task, CFStringRef entitlement, CFErrorRef *error);
static BOOL DevelopmentPermission(void) {
    SecTaskRef task=SecTaskCreateFromSelf(kCFAllocatorDefault);
    if (!task) return NO;
    CFTypeRef value=SecTaskCopyValueForEntitlement(task,CFSTR("get-task-allow"),NULL);
    BOOL allowed=value && CFGetTypeID(value)==CFBooleanGetTypeID() && CFBooleanGetValue((CFBooleanRef)value);
    if (value) CFRelease(value);
    CFRelease(task);
    return allowed;
}

@implementation TKExternalJITCoordinator {
    TKExternalJITRequest *_request;
    NSTimer *_timer;
    NSString *_path;
    BOOL _probe;
    BOOL _workerStarted;
    NSString *_lastMessage;
    void (^_status)(NSString *);
    void (^_completion)(BOOL,BOOL,NSString *);
}
- (void)startProbe:(BOOL)probe logPath:(NSString *)path
           status:(void (^)(NSString *))status
       completion:(void (^)(BOOL,BOOL,NSString *))completion {
    NSAssert(NSThread.isMainThread,@"Start on the UI thread");
    if (_request && (_request.state!=TKExternalJITFailed || _request.restartRequired)) {
        completion(NO,YES,@"A JIT request already used this session. Close and reopen Wolkara JIT."); return;
    }
    _probe=probe; _path=[path copy]; _status=[status copy]; _completion=[completion copy];
    _request=[TKExternalJITRequest new]; _workerStarted=NO;
    _lastMessage=nil;
    NSURL *url=[_request beginForBundle:NSBundle.mainBundle.bundleIdentifier?:@"" process:getpid()
        debuggingPermission:DevelopmentPermission()
        helperInstalled:[UIApplication.sharedApplication canOpenURL:[NSURL URLWithString:@"stikdebug://"]]
        alreadyAttached:da_debugger_present() atTime:NSProcessInfo.processInfo.systemUptime];
    [self update];
    if (!url) return;
    __weak TKExternalJITCoordinator *weakSelf=self;
    _timer=[NSTimer timerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) {
        (void)timer; [weakSelf tick];
    }];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL success) {
        TKExternalJITCoordinator *host=weakSelf;
        if (!host) return;
        [host->_request opened:success]; [host tick];
    }];
}
- (void)tick {
    // Never read the arena while the worker owns it. Only its completion checks
    // executable protection; the debugger flag alone is insufficient.
    BOOL prepare=[_request pollAtTime:NSProcessInfo.processInfo.systemUptime
        attached:da_debugger_present() prepared:NO];
    [self update];
    if (!prepare || _workerStarted) return;
    _workerStarted=YES;
    NSString *path=_path; BOOL probe=_probe;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        FILE *log=fopen(path.fileSystemRepresentation,"a");
        if (log) { setvbuf(log,NULL,_IOLBF,0); fprintf(log,"[external-jit] begin %s; no game has entered\n",probe?"synthetic probe":"arena preparation"); }
        BOOL success=log && (probe ? da_synthetic_probe(log) : ng_reserve_arena(log));
        BOOL detached=da_external_wait_for_detachment();
        if (!probe) success=success && detached && ng_external_arena_ready();
        if (log) { fprintf(log,"[external-jit] result=%s detached=%s\n",success?"PASS":"FAIL",detached?"yes":"no"); fclose(log); }
        dispatch_async(dispatch_get_main_queue(),^{
            // Apply the deadline before processing a delayed completion. Timeout
            // invalidates this request; a late worker can never enter a game.
            (void)[self->_request pollAtTime:NSProcessInfo.processInfo.systemUptime attached:!detached prepared:NO];
            [self->_request prepared:success detached:detached];
            [self update];
        });
    });
}
- (void)update {
    if (_status) _status(_request.message);
    if (![_lastMessage isEqualToString:_request.message]) {
        _lastMessage=_request.message;
        [_lastMessage writeToFile:[_path stringByAppendingString:@".status.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
    if (_request.state!=TKExternalJITReady && _request.state!=TKExternalJITFailed) return;
    [_timer invalidate]; _timer=nil;
    void (^completion)(BOOL,BOOL,NSString *)=_completion;
    _completion=nil; _status=nil;
    if (!completion) return;
    BOOL ready=_request.state==TKExternalJITReady;
    NSString *message=ready && _probe ? @"JIT test passed: our sample ran and was rewritten after debugger detachment. No game was loaded. Close and reopen Wolkara JIT before playing." : _request.message;
    // The worker owns the log until it finishes; use a separate small status file.
    [message writeToFile:[_path stringByAppendingString:@".status.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    completion(ready,_request.restartRequired,message);
}
- (void)dealloc { [_timer invalidate]; }
@end
#endif
