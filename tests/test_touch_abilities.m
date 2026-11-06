#import "TouchActionInput.h"
#import "TouchActionLayout.h"
#include <assert.h>
#include <math.h>

// Deterministic clock: exercise deadlines without sleeping or loading a game.
@interface AKTouchActionInput (TimingFixture)
- (NSTimeInterval)now;
- (void)publish;
- (void)scheduleAt:(NSTimeInterval)deadline;
@end
@interface AKTimedActionInput : AKTouchActionInput
@property NSTimeInterval time, deadline;
@end
@implementation AKTimedActionInput
- (NSTimeInterval)now { return self.time; }
- (void)scheduleAt:(NSTimeInterval)deadline { self.deadline=deadline; }
@end
static void Advance(AKTimedActionInput *input,NSTimeInterval elapsed) { input.time+=elapsed; [input publish]; }
static void InputTests(void) {
    AKTimedActionInput *input=[AKTimedActionInput new]; input.time=100;
    NSMutableArray *events=[NSMutableArray new];
    input.changed=^(NSString *button,BOOL down) { [events addObject:[NSString stringWithFormat:@"%@%c",button,down?'+':'-']]; };
    assert([input beginAction:@"one" button:@"X" modifiers:3]);
    assert(([events isEqual:@[@"LT+",@"RT+"]]));
    Advance(input,.01); assert(events.count==2);
    Advance(input,.03); assert(([events isEqual:@[@"LT+",@"RT+",@"X+"]]));
    Advance(input,1); assert(events.count==3); // Holding never repeats.
    [input endAction:@"one"]; assert(([events isEqual:@[@"LT+",@"RT+",@"X+",@"X-"]]));
    assert(input.pressedButtons.count==2);
    Advance(input,.04); assert(([events isEqual:@[@"LT+",@"RT+",@"X+",@"X-",@"LT-",@"RT-"]]));
    assert(!isfinite(input.deadline));
    // Even a complete tap within one delivery phase becomes exactly one chord.
    [events removeAllObjects]; Advance(input,.04);
    assert([input beginAction:@"quick" button:@"A" modifiers:1]); [input endAction:@"quick"];
    assert(([events isEqual:@[@"LT+"]]));
    Advance(input,.04); assert(([events isEqual:@[@"LT+",@"A+"]]));
    Advance(input,.01); assert(events.count==2);
    Advance(input,.03); assert(([events isEqual:@[@"LT+",@"A+",@"A-"]]));
    Advance(input,.04); assert(([events isEqual:@[@"LT+",@"A+",@"A-",@"LT-"]]));
    Advance(input,2); assert(events.count==4 && !input.pressedButtons.count);
    // Manual modifiers have independent ownership; shared circles keep them.
    [input setManualButton:@"LT" pressed:YES]; Advance(input,.04);
    assert([input beginAction:@"one" button:@"A" modifiers:1]);
    assert([input beginAction:@"two" button:@"B" modifiers:1]); Advance(input,.04);
    [input endAction:@"one"]; assert([input.pressedButtons containsObject:@"B"] && [input.pressedButtons containsObject:@"LT"]);
    [input endAction:@"two"]; Advance(input,.04);
    assert(([input.pressedButtons isEqual:[NSSet setWithObject:@"LT"]]));
    [input setManualButton:@"LT" pressed:NO]; assert(!input.pressedButtons.count);
    [input setManualButton:@"RT" pressed:YES];
    NSUInteger count=events.count; assert(![input beginAction:@"bad" button:@"X" modifiers:1]); assert(events.count==count);
    [input releaseAll]; assert([input beginAction:@"one" button:@"X" modifiers:1]);
    assert(![input beginAction:@"bad" button:@"A" modifiers:2]);
    assert(![input beginAction:@"duplicate" button:@"X" modifiers:1]); // Reserved before its delayed press.
    assert(![input beginAction:@"one" button:@"B" modifiers:1]);
    [events removeAllObjects]; [input setManualButton:@"RT" pressed:YES];
    assert(([events isEqual:@[@"LT-",@"RT+"]])); Advance(input,1); assert(events.count==2);
    [input endAction:@"one"]; assert(([input.pressedButtons isEqual:[NSSet setWithObject:@"RT"]]));
    [input releaseAll]; [input setManualButton:@"A" pressed:YES];
    assert(![input beginAction:@"bad" button:@"B" modifiers:1]);
    [input releaseAll]; assert([input beginAction:@"one" button:@"X" modifiers:1]); Advance(input,.04);
    [input setManualButton:@"X" pressed:YES]; [input endAction:@"one"]; Advance(input,.04); Advance(input,.04);
    assert(([input.pressedButtons isEqual:[NSSet setWithObject:@"X"]]));
    // Cancellation before/after lift must never deliver a late ability.
    for (NSUInteger cancel=0;cancel<3;cancel++) {
        [input releaseAll]; Advance(input,.04); [events removeAllObjects];
        assert([input beginAction:@"cancel" button:@"Y" modifiers:2]);
        if (cancel==1) [input endAction:@"cancel"];
        if (cancel==2) [input releaseAll]; else [input cancelAction:@"cancel"];
        Advance(input,1); assert(![events containsObject:@"Y+"] && !input.pressedButtons.count);
    }
    // Cancelling a delivered button releases it before dropping its modifier.
    [events removeAllObjects];
    [input setManualButton:@"LT" pressed:YES]; Advance(input,.04);
    [input cancelAllActions]; assert(([input.pressedButtons isEqual:[NSSet setWithObject:@"LT"]]));
    [input releaseAll];
    assert([input beginAction:@"first" button:@"A" modifiers:1]);
    assert([input beginAction:@"second" button:@"B" modifiers:1]);
    [input endAction:@"first"]; [input endAction:@"second"];
    input.time+=.1; // Deadlines are due, but the run loop has not delivered them.
    [input cancelAllActions]; Advance(input,1);
    assert(![events containsObject:@"A+"] && ![events containsObject:@"B+"] && !input.pressedButtons.count);
    assert([input beginAction:@"cancel" button:@"Y" modifiers:2]); Advance(input,.04);
    [events removeAllObjects]; [input cancelAction:@"cancel"];
    assert(([events isEqual:@[@"Y-"]])); Advance(input,.04); assert(([events isEqual:@[@"Y-",@"RT-"]]));
    [input releaseAll]; [input releaseAll]; [input endAction:@"unknown"]; assert(!input.pressedButtons.count);
    for (NSUInteger mod=0;mod<4;mod++) for (NSString *button in @[@"A",@"B",@"X",@"Y",@"up",@"right",@"down",@"left"]) {
        Advance(input,.04); assert([input beginAction:@"one" button:button modifiers:mod]);
        assert([input.pressedButtons containsObject:button]==(mod==0));
        [input endAction:@"one"]; Advance(input,.04);
        if (mod) {
            assert([input.pressedButtons containsObject:button]);
            assert([input.pressedButtons containsObject:@"LT"]==!!(mod&1));
            assert([input.pressedButtons containsObject:@"RT"]==!!(mod&2));
        }
        Advance(input,.04); assert(![input.pressedButtons containsObject:button]);
        Advance(input,.04); assert(!input.pressedButtons.count);
    }
    assert(![input beginAction:@"bad" button:@"unknown" modifiers:0]);
    assert(![input beginAction:@"bad" button:@"A" modifiers:4]);
    puts("TOUCH_ABILITIES_INPUT_PASS: phased delivery, 32 quick taps, no hold repetition, shared/manual ownership, conflicts, cancellation and no late input.");
}
static void LayoutTests(void) {
    NSString *suite=[@"org.wolkara.tests.abilities." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults=[[NSUserDefaults alloc] initWithSuiteName:suite];
    AKTouchActionLayout *layout=[[AKTouchActionLayout alloc] initWithDefaults:defaults];
    assert(layout.actions.count==32 && !layout.enabled);
    CGRect reference=CGRectMake(0,0,1280,900);
    // Pixel centers independently taken from the screenshot's four modifier labels.
    const CGPoint expected[]={{565,608},{388,671},{777,671},{582,729}};
    for (NSUInteger group=0;group<4;group++) {
        AKTouchAction *a=layout.actions[group*8]; CGRect f=[layout frameForAction:a inBounds:reference];
        assert(a.modifiers==group && [a.button isEqual:@"up"]);
        assert(fabs(CGRectGetMidX(f)-expected[group].x)<.01 && fabs(CGRectGetMidY(f)-expected[group].y)<.01);
        assert([layout.actions[group*8+4].button isEqual:@"Y"] && [layout.actions[group*8+6].button isEqual:@"A"]);
    }
    AKTouchAction *first=layout.actions[0],*last=layout.actions.lastObject;
    CGRect before=[layout frameForAction:first inBounds:reference],lastBefore=[layout frameForAction:last inBounds:reference];
    [layout moveGroupBy:CGPointMake(80,-60) inBounds:reference];
    CGRect moved=[layout frameForAction:first inBounds:reference],lastMoved=[layout frameForAction:last inBounds:reference];
    assert(CGRectEqualToRect(moved,CGRectOffset(before,80,-60)));
    assert(CGRectEqualToRect(lastMoved,CGRectOffset(lastBefore,80,-60)));
    layout.scale=1.4;
    CGRect scaled=[layout frameForAction:first inBounds:reference],lastScaled=[layout frameForAction:last inBounds:reference];
    assert(fabs(scaled.size.width/before.size.width-1.4)<.001);
    assert(fabs((CGRectGetMidX(lastScaled)-CGRectGetMidX(scaled))/(CGRectGetMidX(lastMoved)-CGRectGetMidX(moved))-1.4)<.001);
    CGPoint lastPosition=last.position;
    [layout moveAction:first by:CGPointMake(20,10) inBounds:reference]; assert(CGPointEqualToPoint(last.position,lastPosition));
    first.diameter=80; first.button=@"B"; first.modifiers=2; first.enabled=NO; layout.enabled=YES; [layout save];
    layout=[[AKTouchActionLayout alloc] initWithDefaults:defaults];
    assert(layout.enabled && layout.actions[0].diameter==80 && !layout.actions[0].enabled);
    assert([layout.actions[0].button isEqual:@"B"] && layout.actions[0].modifiers==2);
    CGRect wide=[layout frameForAction:layout.actions[4] inBounds:reference];
    for (NSValue *bounds in @[[NSValue valueWithCGRect:CGRectMake(0,0,852,393)], [NSValue valueWithCGRect:CGRectMake(0,0,956,440)], [NSValue valueWithCGRect:CGRectMake(0,0,1280,900)], [NSValue valueWithCGRect:CGRectMake(20,10,500,300)]]) {
        for (AKTouchAction *a in layout.actions) assert(CGRectContainsRect(bounds.CGRectValue,[layout frameForAction:a inBounds:bounds.CGRectValue]));
    }
    assert(CGRectEqualToRect(wide,[layout frameForAction:layout.actions[4] inBounds:reference]));
    layout.scale=4; [layout moveGroupBy:CGPointMake(10000,10000) inBounds:CGRectMake(0,0,390,280)];
    for (AKTouchAction *a in layout.actions) assert(CGRectContainsRect(CGRectMake(0,0,390,280),[layout frameForAction:a inBounds:CGRectMake(0,0,390,280)]));
    AKTouchAction *added=[layout addAction]; assert(added && layout.actions.count==33); [layout removeAction:added];
    layout.scale=NAN; layout.center=CGPointMake(INFINITY,NAN); assert(isfinite(layout.scale)&&isfinite(layout.center.x)&&isfinite(layout.center.y));
    [layout reset]; [layout save]; assert(layout.actions.count==32&&!layout.enabled);
    [defaults setObject:@{@"actions":@[@{},@"bad",@{@"id":@"bad",@"button":@"unknown"}],@"scale":@"bad"} forKey:@"WolkaraTouchAbilitiesV1"];
    layout=[[AKTouchActionLayout alloc] initWithDefaults:defaults]; assert(layout.actions.count==0 && layout.scale==1);
    [defaults removePersistentDomainForName:suite];
    puts("TOUCH_ABILITIES_LAYOUT_PASS: screenshot mapping, block translation/scaling, individual edits, persistence, phone sizes, clamping and malformed preferences.");
}
int main(void) { @autoreleasepool { InputTests(); LayoutTests(); } return 0; }
