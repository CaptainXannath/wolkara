#import <Foundation/Foundation.h>

// Companion commands use modified F6/F7 chords (see Bridge.lua).
// They originate only in explicit control actions or their individual touch gestures.
typedef NS_ENUM(NSUInteger, AKMobileCommand) {
    AKMobileEnable, AKMobileDisable, AKMobileEdit, AKMobileDone,
    AKMobileTap, AKMobileHold, AKMobileClear, AKMobileDrag
};
static NSString * const AKMobileEnabledKey = @"WolkaraMobileEnabled";
static NSString * const AKMobileAvailableKey = @"WolkaraMobileAvailable";
static inline BOOL AKMobileInterfaceEnabled(void) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    return [defaults boolForKey:AKMobileAvailableKey] && [defaults boolForKey:AKMobileEnabledKey];
}
@protocol AKMobileInterfaceHost <NSObject>
- (void)ak_mobileCommand:(AKMobileCommand)command;
@end
