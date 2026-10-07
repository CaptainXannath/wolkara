#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
// Installs only our bundled addon before guest entry. Preserves other addons,
// game files and saved variables; refuses to overwrite manually edited code.
BOOL TKWoWInstallTouchAddon(NSString *source, NSString *editionDirectory, NSError **error);
NS_ASSUME_NONNULL_END
