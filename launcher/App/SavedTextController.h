#import <UIKit/UIKit.h>
#import "SavedTextStore.h"

NS_ASSUME_NONNULL_BEGIN
@interface WKSavedTextController : NSObject
@property (nonatomic, weak, nullable) UIView *gameTextTarget;
- (instancetype)initWithStore:(id<WKSavedTextStorage>)store;
@end
NS_ASSUME_NONNULL_END
