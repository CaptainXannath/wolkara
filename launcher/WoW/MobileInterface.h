#import <Foundation/Foundation.h>
// Caller holds the edition's update lock and must not call while its guest is running.
BOOL TKWoWPrepareMobileInterface(NSString *editionDirectory, NSString *sourceDirectory, BOOL enabled, NSError **error);
