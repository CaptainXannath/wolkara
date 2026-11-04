#import "ExternalJITRequest.h"
#include <math.h>

@implementation TKExternalJITRequest {
    NSTimeInterval _deadline;
}
- (instancetype)init {
    if ((self=[super init])) _message=@"Ready to prepare.";
    return self;
}
- (void)fail:(NSString *)message {
    _state=TKExternalJITFailed; _message=[message copy];
}
- (NSURL *)beginForBundle:(NSString *)bundle process:(int)pid
      debuggingPermission:(BOOL)permission helperInstalled:(BOOL)installed
          alreadyAttached:(BOOL)attached atTime:(NSTimeInterval)now {
    if (_state!=TKExternalJITIdle) return nil;
    if (!permission) {
        [self fail:@"This installation lacks development permission. Select a Personal Team in Xcode and rebuild the WolkaraExternalJIT scheme."]; return nil;
    }
    if (attached) {
        [self fail:@"A debugger is already attached. Stop the Xcode run and open Wolkara JIT from the Home Screen. Debug executable must be off."]; return nil;
    }
    if (!installed) {
        [self fail:@"Install StikDebug and complete its pairing setup. Connect LocalDevVPN, then try again. See the External JIT setup guide."]; return nil;
    }
    NSCharacterSet *invalid=[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-"] invertedSet];
    if (!bundle.length || bundle.length>255 || [bundle rangeOfCharacterFromSet:invalid].location!=NSNotFound || pid<=0 || !isfinite(now)) {
        [self fail:@"Cannot identify this app process for JIT preparation."]; return nil;
    }
    NSURLComponents *url=[NSURLComponents new]; url.scheme=@"stikdebug"; url.host=@"enable-jit";
    // Our existing iOS 26+ allocator implements this fixed protocol. No user scripts.
    url.queryItems=@[[NSURLQueryItem queryItemWithName:@"bundle-id" value:bundle],
        [NSURLQueryItem queryItemWithName:@"pid" value:@(pid).stringValue],
        [NSURLQueryItem queryItemWithName:@"script-name" value:@"universal.js"]];
    _state=TKExternalJITOpening; _deadline=now+300;
    _restartRequired=YES; // The URL completion itself can be delayed.
    _message=@"Opening StikDebug to prepare this session…";
    return url.URL;
}
- (void)opened:(BOOL)accepted {
    if (_state!=TKExternalJITOpening) return;
    if (!accepted) { _restartRequired=NO; [self fail:@"Could not open StikDebug. Check that it is installed and set up, then try again."]; return; }
    _restartRequired=YES; // A helper may attach later, even after cancellation.
    _state=TKExternalJITWaiting;
    _message=@"Waiting for StikDebug. Complete its setup if requested, then return here. Keep LocalDevVPN connected.";
}
- (BOOL)pollAtTime:(NSTimeInterval)now attached:(BOOL)attached prepared:(BOOL)prepared {
    if (_state!=TKExternalJITOpening && _state!=TKExternalJITWaiting && _state!=TKExternalJITPreparing) return NO;
    if (!isfinite(now) || now>=_deadline) {
        [self fail:@"JIT preparation timed out. Check StikDebug and LocalDevVPN, then close and reopen Wolkara JIT to retry."]; return NO;
    }
    if (_state!=TKExternalJITWaiting) return NO;
    if (prepared && !attached) { _state=TKExternalJITReady; _message=@"Execution memory is ready."; return NO; }
    if (!attached) return NO;
    _state=TKExternalJITPreparing; _message=@"Preparing execution memory. Keep this app open…";
    return YES;
}
- (void)prepared:(BOOL)success detached:(BOOL)detached {
    if (_state!=TKExternalJITPreparing) return;
    if (!success || !detached) {
        [self fail:detached?@"StikDebug could not prepare executable memory. Close and reopen Wolkara JIT; see Diagnostics and logs.":
            @"Preparation did not detach the debugger. Game startup is blocked. Close and reopen Wolkara JIT."]; return;
    }
    _state=TKExternalJITReady; _message=@"Execution memory is ready.";
}
- (void)cancel {
    if (_state==TKExternalJITFailed || _state==TKExternalJITReady) return;
    if (_state==TKExternalJITOpening) _restartRequired=YES;
    [self fail:@"Preparation cancelled. Close and reopen Wolkara JIT before trying again."];
}
@end
