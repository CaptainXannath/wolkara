#import <Foundation/Foundation.h>
#import "ExternalJITRequest.h"

NS_ASSUME_NONNULL_BEGIN
// Retain for the lifetime of the scene. One helper request per process after handoff.
@interface TKExternalJITCoordinator : NSObject
- (void)startProbe:(BOOL)probe logPath:(NSString *)path
           status:(void (^)(NSString *message, TKExternalJITState state))status
       completion:(void (^)(BOOL ready, BOOL restartRequired, NSString *message))completion;
@end
NS_ASSUME_NONNULL_END
