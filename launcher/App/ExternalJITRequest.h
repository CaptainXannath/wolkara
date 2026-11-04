#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
typedef NS_ENUM(NSUInteger, TKExternalJITState) {
    TKExternalJITIdle, TKExternalJITOpening, TKExternalJITWaiting,
    TKExternalJITPreparing, TKExternalJITReady, TKExternalJITFailed
};

// Main-thread state machine. URL acceptance is not executable-memory readiness.
// A request is single-use: stale helper replies must never start a later game.
@interface TKExternalJITRequest : NSObject
@property(nonatomic, readonly) TKExternalJITState state;
@property(nonatomic, copy, readonly) NSString *message;
@property(nonatomic, readonly) BOOL restartRequired;
- (nullable NSURL *)beginForBundle:(NSString *)bundle process:(int)pid
              debuggingPermission:(BOOL)permission helperInstalled:(BOOL)installed
                 alreadyAttached:(BOOL)attached atTime:(NSTimeInterval)now;
- (void)opened:(BOOL)accepted;
// YES requests one preparation on the host's serial worker, never on the UI thread.
- (BOOL)pollAtTime:(NSTimeInterval)now attached:(BOOL)attached prepared:(BOOL)prepared;
- (void)prepared:(BOOL)success detached:(BOOL)detached;
- (void)cancel;
@end
NS_ASSUME_NONNULL_END
