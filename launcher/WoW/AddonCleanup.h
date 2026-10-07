#import <Foundation/Foundation.h>

// Retires only the abandoned experimental addon, outside WoW's AddOns folder.
// Preserves its files, saved variables, other addons and all game data.
BOOL TKWoWRetireTouchAddon(NSString *editionDirectory, NSError **error);
