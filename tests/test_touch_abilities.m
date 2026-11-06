#import "TouchActionInput.h"
#import "TouchActionLayout.h"
#include <assert.h>
#include <math.h>

static void InputTests(void) {
    AKTouchActionInput *input=[AKTouchActionInput new]; NSMutableArray *events=[NSMutableArray new];
    input.changed=^(NSString *button,BOOL down) { [events addObject:[NSString stringWithFormat:@"%@%c",button,down?'+':'-']]; };
    assert([input beginAction:@"one" button:@"X" modifiers:3]);
    assert(([events isEqual:@[@"LT+",@"RT+",@"X+"]]));
    [input endAction:@"one"]; assert(([events isEqual:@[@"LT+",@"RT+",@"X+",@"X-",@"LT-",@"RT-"]]));
    [events removeAllObjects];
    [input setManualButton:@"LT" pressed:YES];
    assert([input beginAction:@"one" button:@"A" modifiers:1]);
    assert([input beginAction:@"two" button:@"B" modifiers:1]);
    [input endAction:@"one"]; assert([input.pressedButtons containsObject:@"B"] && [input.pressedButtons containsObject:@"LT"]);
    [input endAction:@"two"]; assert(([input.pressedButtons isEqual:[NSSet setWithObject:@"LT"]]));
    [input setManualButton:@"LT" pressed:NO]; assert(input.pressedButtons.count==0);
    [input setManualButton:@"RT" pressed:YES];
    NSUInteger count=events.count; assert(![input beginAction:@"bad" button:@"X" modifiers:1]); assert(events.count==count);
    [input releaseAll]; assert([input beginAction:@"one" button:@"X" modifiers:1]);
    assert(![input beginAction:@"bad" button:@"A" modifiers:2]);
    assert(![input beginAction:@"duplicate" button:@"X" modifiers:1]);
    assert(![input beginAction:@"one" button:@"B" modifiers:1]);
    [events removeAllObjects]; [input setManualButton:@"RT" pressed:YES];
    assert(([events isEqual:@[@"X-",@"LT-",@"RT+"]]));
    [input endAction:@"one"]; assert(([input.pressedButtons isEqual:[NSSet setWithObject:@"RT"]]));
    [input releaseAll]; [input setManualButton:@"A" pressed:YES];
    assert(![input beginAction:@"bad" button:@"B" modifiers:1]); // Never change an already-held button's modifier context.
    [input releaseAll]; assert([input beginAction:@"one" button:@"X" modifiers:1]);
    [input setManualButton:@"X" pressed:YES]; [input endAction:@"one"];
    assert(([input.pressedButtons isEqual:[NSSet setWithObject:@"X"]]));
    [input releaseAll]; [input releaseAll]; [input endAction:@"unknown"]; assert(input.pressedButtons.count==0);
    for (NSUInteger mod=0;mod<4;mod++) for (NSString *button in @[@"A",@"B",@"X",@"Y",@"up",@"right",@"down",@"left"]) {
        assert([input beginAction:@"one" button:button modifiers:mod]);
        assert([input.pressedButtons containsObject:button]);
        assert([input.pressedButtons containsObject:@"LT"]==!!(mod&1));
        assert([input.pressedButtons containsObject:@"RT"]==!!(mod&2));
        [input releaseAll]; assert(!input.pressedButtons.count);
    }
    assert(![input beginAction:@"bad" button:@"unknown" modifiers:0]);
    assert(![input beginAction:@"bad" button:@"A" modifiers:4]);
    puts("TOUCH_ABILITIES_INPUT_PASS: modifier order, 32 chords, shared ownership, conflicting chords, cancellation, duplicate suppression and neutral reset.");
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
