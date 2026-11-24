#import <UIKit/UIKit.h>
#import <GameController/GameController.h>

NS_ASSUME_NONNULL_BEGIN
@class AKGamepadLayout;
enum { AKTouchDragThreshold = 8 };
// Ability circles and the Camera pad hand drags to the host.
@protocol AKTouchDragHost <NSObject>
- (BOOL)ak_beginTouchDrag:(UITouch *)touch origin:(CGPoint)origin;
- (void)ak_moveTouchDrag:(UITouch *)touch;
- (void)ak_endTouchDrag:(UITouch *)touch cancelled:(BOOL)cancelled;
@optional
- (BOOL)ak_beginCameraDrag:(UITouch *)touch origin:(CGPoint)origin rightButton:(BOOL)rightButton;
- (void)ak_sendKeyCode:(unsigned short)keyCode characters:(nullable NSString *)characters modifiers:(NSUInteger)modifiers pressed:(BOOL)pressed;
- (void)ak_sendMouseClick:(unsigned)button pressed:(BOOL)pressed;
@end
// Radial analog mapping with a small dead zone and clamped magnitude.
CGPoint AKTouchGamepadStickPosition(CGPoint point, CGSize size);
// Owns only our virtual device. Physical controllers and their handlers stay
// with GameController/the guest. No game events or memory are inspected.
@interface AKTouchGamepad : NSObject
- (instancetype)initWithHostView:(UIView *)host;
@property(nonatomic) BOOL enabled;
/// Layout only: keeps the same connected controller and saved control positions.
@property(nonatomic) BOOL simple;
@property(nonatomic) BOOL keyboardVisible;
@property(nonatomic, readonly) BOOL visible;
@property(nonatomic, readonly) BOOL configuring;
@property(nonatomic, readonly) BOOL editing;
@property(nonatomic, readonly) BOOL editingAbilities;
@property(nonatomic, readonly) BOOL mobileEditing;
/// Shared with the toolbar so a settings save cannot overwrite moved buttons.
@property(nonatomic, readonly) AKGamepadLayout *layout;
@property(nonatomic, copy, nullable) void (^visibilityChanged)(BOOL visible);
/// Keep Done and the settings sheet reachable even when a toolbar button overlaps.
- (BOOL)configurationContainsPoint:(CGPoint)point inView:(UIView *)view;
- (void)refresh;
- (void)toggleSettings;
- (void)invalidate;
@end
NS_ASSUME_NONNULL_END
