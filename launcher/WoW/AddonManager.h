#import <UIKit/UIKit.h>
#import "AddonStore.h"

NS_ASSUME_NONNULL_BEGIN

// A data-only description of one user-supplied add-on folder. The launcher
// never interprets or modifies the add-on's Lua or game files.
@interface TKWoWAddon : NSObject
@property(nonatomic, readonly, copy) NSString *folder;
@property(nonatomic, readonly, copy) NSString *title;
@property(nonatomic, readonly, copy, nullable) NSString *version;
@property(nonatomic, readonly) NSUInteger fileCount;
@end

// Lists direct child folders of Interface/AddOns. Invalid or unreadable
// folders are skipped so a damaged add-on cannot prevent the manager opening.
NSArray<TKWoWAddon *> *TKWoWAddonsAtDirectory(NSString *directory);

@interface TKWoWAddonManagerViewController : UITableViewController
- (instancetype)initWithAddOnsDirectory:(NSString *)directory edition:(NSString *)edition;
- (instancetype)initWithAddOnsDirectory:(NSString *)directory edition:(NSString *)edition
                                product:(NSString *)product gameVersion:(NSString *)version;
// The actions a managed package offers: disable/restore, pin/unpin, remove, cancel. Exposed so
// the device self-test can assert that removal is reachable without a second pair of hands on
// the iPad; the page presents this same sheet when a row is tapped.
- (UIAlertController *)manageSheetForRecord:(TKAddonRecord *)record;
@end

NS_ASSUME_NONNULL_END
