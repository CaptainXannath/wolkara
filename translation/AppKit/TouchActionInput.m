#import "TouchActionInput.h"

@implementation AKTouchActionInput {
    NSMutableSet<NSString *> *_manual, *_output;
    NSMutableDictionary<NSString *,NSDictionary *> *_actions;
}
- (instancetype)init {
    if ((self=[super init])) { _manual=[NSMutableSet new]; _output=[NSMutableSet new]; _actions=[NSMutableDictionary new]; }
    return self;
}
- (NSSet<NSString *> *)pressedButtons { return _output.copy; }
- (NSUInteger)manualModifiers { return ([_manual containsObject:@"LT"]?1:0) | ([_manual containsObject:@"RT"]?2:0); }
- (void)emit:(NSString *)button pressed:(BOOL)pressed {
    if ([_output containsObject:button]==pressed) return;
    if (pressed) [_output addObject:button]; else [_output removeObject:button];
    if (self.changed) self.changed(button,pressed);
}
- (void)publish {
    NSMutableSet *desired=_manual.mutableCopy;
    for (NSDictionary *action in _actions.allValues) {
        [desired addObject:action[@"button"]];
        NSUInteger modifiers=[action[@"modifiers"] unsignedIntegerValue];
        if (modifiers&1) [desired addObject:@"LT"];
        if (modifiers&2) [desired addObject:@"RT"];
    }
    // Release action buttons before their modifiers; press modifiers first.
    for (NSString *key in _output.copy)
        if (![key isEqual:@"LT"] && ![key isEqual:@"RT"] && ![desired containsObject:key]) [self emit:key pressed:NO];
    for (NSString *key in @[@"LT",@"RT"]) [self emit:key pressed:[desired containsObject:key]];
    for (NSString *key in desired) if (![_output containsObject:key]) [self emit:key pressed:YES];
}
- (void)setManualButton:(NSString *)button pressed:(BOOL)pressed {
    if ([_manual containsObject:button]==pressed) return;
    if (pressed && ([button isEqual:@"LT"] || [button isEqual:@"RT"])) {
        NSUInteger next=[self manualModifiers] | ([button isEqual:@"LT"]?1:2);
        for (NSDictionary *action in _actions.allValues) {
            if (next & ~[action[@"modifiers"] unsignedIntegerValue]) {
                // A newly pressed manual modifier takes priority. End the old
                // chord before changing its modifiers; never reinterpret it.
                [_actions removeAllObjects]; [self publish]; break;
            }
        }
    }
    if (pressed) [_manual addObject:button]; else [_manual removeObject:button];
    [self publish];
}
- (BOOL)beginAction:(NSString *)owner button:(NSString *)button modifiers:(NSUInteger)modifiers {
    if (!owner.length || _actions[owner] || modifiers>3 ||
        ![@[@"A",@"B",@"X",@"Y",@"up",@"right",@"down",@"left"] containsObject:button]) return NO;
    if (([self manualModifiers] & ~modifiers) || [_output containsObject:button]) return NO;
    if (modifiers!=[self manualModifiers]) {
        for (NSString *held in _manual)
            if (![@[@"LT",@"RT"] containsObject:held]) return NO;
    }
    for (NSDictionary *action in _actions.allValues)
        if ([action[@"modifiers"] unsignedIntegerValue]!=modifiers) return NO;
    _actions[owner]=@{@"button":button,@"modifiers":@(modifiers)};
    [self publish]; return YES;
}
- (void)endAction:(NSString *)owner { [_actions removeObjectForKey:owner]; [self publish]; }
- (void)releaseAll { [_actions removeAllObjects]; [_manual removeAllObjects]; [self publish]; }
@end
