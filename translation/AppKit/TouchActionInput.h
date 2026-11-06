#import <Foundation/Foundation.h>

// One owner per deliberate touch. No timers, repetition or game-state access.
@interface AKTouchActionInput : NSObject
@property(nonatomic, copy) void (^changed)(NSString *button, BOOL pressed);
@property(nonatomic, readonly) NSSet<NSString *> *pressedButtons;
- (void)setManualButton:(NSString *)button pressed:(BOOL)pressed;
- (BOOL)beginAction:(NSString *)owner button:(NSString *)button modifiers:(NSUInteger)modifiers;
- (void)endAction:(NSString *)owner;
- (void)releaseAll;
@end
