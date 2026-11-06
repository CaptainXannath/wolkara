#import "TouchActionInput.h"
#include <math.h>

// Setters called in one turn produce callbacks that see the final profile,
// not snapshots. Separate modifier, button and release delivery phases.
static const NSTimeInterval PhaseInterval = 1.0 / 30.0;
@interface AKHeldTouchAction : NSObject
@property(nonatomic, copy) NSString *button;
@property NSUInteger modifiers;
@property BOOL pressed, released;
@property NSTimeInterval pressedAt;
@end
@implementation AKHeldTouchAction
@end

@implementation AKTouchActionInput {
    NSMutableSet<NSString *> *_manual, *_output;
    NSMutableDictionary<NSString *,AKHeldTouchAction *> *_actions;
    NSTimer *_timer;
    NSTimeInterval _modifiersReadyAt, _tailUntil;
    NSUInteger _tailModifiers;
}
- (instancetype)init {
    if ((self=[super init])) { _manual=[NSMutableSet new]; _output=[NSMutableSet new]; _actions=[NSMutableDictionary new]; }
    return self;
}
- (NSTimeInterval)now { return NSProcessInfo.processInfo.systemUptime; }
- (NSSet<NSString *> *)pressedButtons { return _output.copy; }
- (NSUInteger)modifiersIn:(NSSet *)buttons { return ([buttons containsObject:@"LT"]?1:0) | ([buttons containsObject:@"RT"]?2:0); }
- (void)emit:(NSString *)button pressed:(BOOL)pressed {
    if ([_output containsObject:button]==pressed) return;
    if (pressed) [_output addObject:button]; else [_output removeObject:button];
    if (self.changed) self.changed(button,pressed);
}
- (void)scheduleAt:(NSTimeInterval)deadline {
    [_timer invalidate]; _timer=nil;
    if (!isfinite(deadline)) return;
    __weak AKTouchActionInput *weakSelf=self;
    _timer=[NSTimer timerWithTimeInterval:MAX(.001,deadline-[self now]) repeats:NO block:^(NSTimer *timer) {
        (void)timer; [weakSelf publish];
    }];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
}
- (void)retainModifiersAfter:(AKHeldTouchAction *)action now:(NSTimeInterval)now {
    if (!action.pressed || !action.modifiers) return;
    _tailModifiers |= action.modifiers;
    _tailUntil=now+PhaseInterval;
}
- (void)publish {
    NSTimeInterval now=[self now];
    if (now>=_tailUntil) _tailModifiers=0;
    for (NSString *owner in _actions.allKeys) {
        AKHeldTouchAction *action=_actions[owner];
        if (action.pressed && action.released && now>=action.pressedAt+PhaseInterval) {
            [self retainModifiersAfter:action now:now]; [_actions removeObjectForKey:owner];
        }
    }
    NSUInteger modifiers=[self modifiersIn:_manual] | _tailModifiers;
    for (AKHeldTouchAction *action in _actions.allValues) modifiers |= action.modifiers;
    if (modifiers!=[self modifiersIn:_output]) _modifiersReadyAt=now+PhaseInterval;
    NSMutableSet *desired=_manual.mutableCopy;
    if (modifiers&1) [desired addObject:@"LT"];
    if (modifiers&2) [desired addObject:@"RT"];
    NSTimeInterval next=_tailModifiers?_tailUntil:INFINITY;
    for (AKHeldTouchAction *action in _actions.allValues) {
        if (!action.pressed && now>=_modifiersReadyAt) { action.pressed=YES; action.pressedAt=now; }
        if (action.pressed) {
            [desired addObject:action.button];
            if (action.released) next=MIN(next,action.pressedAt+PhaseInterval);
        } else next=MIN(next,_modifiersReadyAt);
    }
    // On normal release, keep modifiers held for a phase after button-up.
    for (NSString *key in _output.copy)
        if (![key isEqual:@"LT"] && ![key isEqual:@"RT"] && ![desired containsObject:key]) [self emit:key pressed:NO];
    for (NSString *key in @[@"LT",@"RT"]) [self emit:key pressed:[desired containsObject:key]];
    for (NSString *key in desired) if (![_output containsObject:key]) [self emit:key pressed:YES];
    [self scheduleAt:next];
}
- (void)setManualButton:(NSString *)button pressed:(BOOL)pressed {
    if ([_manual containsObject:button]==pressed) return;
    if (pressed && ([button isEqual:@"LT"] || [button isEqual:@"RT"])) {
        NSUInteger next=[self modifiersIn:_manual] | ([button isEqual:@"LT"]?1:2);
        BOOL conflict=(_tailModifiers && (next & ~_tailModifiers));
        for (AKHeldTouchAction *action in _actions.allValues) conflict |= (next & ~action.modifiers)!=0;
        if (conflict) {
            // Explicit manual input wins and cancels pending circle presses.
            [_actions removeAllObjects]; _tailModifiers=0; [self publish];
        }
    }
    if (pressed) [_manual addObject:button]; else [_manual removeObject:button];
    [self publish];
}
- (BOOL)beginAction:(NSString *)owner button:(NSString *)button modifiers:(NSUInteger)modifiers {
    [self publish];
    if (!owner.length || _actions[owner] || modifiers>3 ||
        ![@[@"A",@"B",@"X",@"Y",@"LB",@"RB",@"up",@"right",@"down",@"left"] containsObject:button]) return NO;
    NSUInteger manual=[self modifiersIn:_manual];
    if ((manual & ~modifiers) || [_output containsObject:button] || (_tailModifiers && _tailModifiers!=modifiers)) return NO;
    if (modifiers!=manual) {
        for (NSString *held in _manual)
            if (![@[@"LT",@"RT"] containsObject:held]) return NO;
    }
    for (AKHeldTouchAction *action in _actions.allValues)
        if (action.modifiers!=modifiers || [action.button isEqual:button]) return NO;
    AKHeldTouchAction *action=[AKHeldTouchAction new]; action.button=button; action.modifiers=modifiers;
    _actions[owner]=action; [self publish]; return YES;
}
- (void)endAction:(NSString *)owner {
    // A normal lift completes one tap, even before modifier delivery. A hold
    // never repeats. Cancellation discards the pending press instead.
    _actions[owner].released=YES; [self publish];
}
- (void)cancelAction:(NSString *)owner {
    AKHeldTouchAction *action=_actions[owner];
    if (!action) return;
    [self retainModifiersAfter:action now:[self now]];
    [_actions removeObjectForKey:owner]; [self publish];
}
- (void)cancelAllActions {
    [_timer invalidate]; _timer=nil;
    // Remove every pending owner before publishing: cancelling one by one
    // could advance another owner's now-due press during the cleanup itself.
    [_actions removeAllObjects]; _tailModifiers=0; [self publish];
}
- (void)releaseAll { [_manual removeAllObjects]; [self cancelAllActions]; }
- (void)dealloc { [_timer invalidate]; }
@end
