#import <Foundation/Foundation.h>

// One chord per deliberate touch, with separate modifier/button delivery phases.
// No repetition or game-state access; cancellation discards pending presses.
@interface AKTouchActionInput : NSObject
@property(nonatomic, copy) void (^changed)(NSString *button, BOOL pressed);
@property(nonatomic, readonly) NSSet<NSString *> *pressedButtons;
- (void)setManualButton:(NSString *)button pressed:(BOOL)pressed;
- (BOOL)beginAction:(NSString *)owner button:(NSString *)button modifiers:(NSUInteger)modifiers;
- (void)endAction:(NSString *)owner;
- (void)cancelAction:(NSString *)owner;
- (void)cancelAllActions;
- (void)releaseAll;
@end
