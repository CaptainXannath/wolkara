#import <UIKit/UIKit.h>

// Posted after saving; the object is the defaults store that changed.
FOUNDATION_EXPORT NSNotificationName const AKGamepadLayoutDidChangeNotification;

// Preferences contain only UI appearance/feedback; never controller or game state.
@interface AKGamepadLayout : NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
@property(nonatomic) CGFloat opacity;
@property(nonatomic) CGFloat rearScale;
@property(nonatomic) CGFloat frontScale;
@property(nonatomic) BOOL hapticsEnabled;
// Swap the visual shoulder slots only; controller element identities are unchanged.
@property(nonatomic) BOOL swapShoulders;
// Whether the optional performance HUD is shown. Off by default; the in-game
// settings page and the launcher's Performance & UI row both write it, so the
// preference has one home and one meaning.
@property(nonatomic) BOOL performanceOverlayEnabled;
// Photo HUD action bindings, right-stick look mode, and external-hardware auto-hide.
@property(nonatomic, copy) NSString *targetBinding;
@property(nonatomic, copy) NSString *interactBinding;
@property(nonatomic, copy) NSString *jumpBinding;
@property(nonatomic) BOOL cameraRightDrag;
@property(nonatomic) CGFloat cameraSensitivity;
@property(nonatomic) BOOL leftStickWASD;
@property(nonatomic) BOOL autoHideExternalInput;
@property(nonatomic) BOOL showHudTarget;
@property(nonatomic) BOOL showHudInteract;
@property(nonatomic) BOOL showHudJump;
@property(nonatomic) BOOL showHudCamera;

+ (NSArray<NSString *> *)allowedTargetBindings;
+ (NSArray<NSString *> *)allowedInteractBindings;
+ (NSArray<NSString *> *)allowedJumpBindings;

- (NSDictionary *)positionsSnapshot;
- (void)restorePositions:(NSDictionary *)snapshot;
- (void)resetPositions;
- (CGRect)frameForItem:(NSString *)item defaultFrame:(CGRect)frame inBounds:(CGRect)bounds;
- (void)moveItem:(NSString *)item toFrame:(CGRect)frame inBounds:(CGRect)bounds;
- (void)save;
- (void)reset;
@end
