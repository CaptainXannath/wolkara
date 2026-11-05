#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN
// Each instance is bound to the selected installation, never a global Forever path.
@interface TKGameToolsViewController : UITableViewController
- (instancetype)initWithWorkingDirectory:(NSString *)directory product:(NSString *)product
                                edition:(NSString *)edition version:(NSString *)version;
@end
NS_ASSUME_NONNULL_END
