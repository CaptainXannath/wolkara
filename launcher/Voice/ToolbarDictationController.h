#import "Dictation.h"

NS_ASSUME_NONNULL_BEGIN
/// The touch adapter sends explicit start/confirm/cancel actions by notification.
/// This owner opens chat with Enter, streams only to a visible draft, and sends
/// only the exact displayed text provided by an explicit confirmation.
@interface AKToolbarDictationController : NSObject
- (instancetype)initWithDictation:(AKDictation *)dictation;
@end
NS_ASSUME_NONNULL_END
