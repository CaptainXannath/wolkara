#import "../translation/AppKit/TouchGamepad.h"
#import "../translation/AppKit/TouchActionOverlay.h"
#include <assert.h>
#include <math.h>
static UIView *Find(UIView *view,NSString *identifier) {
    if ([view.accessibilityIdentifier isEqual:identifier]) return view;
    for (UIView *v in view.subviews) { UIView *found=Find(v,identifier); if (found) return found; } return nil;
}
static void Drain(void) { CFRunLoopRunInMode(kCFRunLoopDefaultMode,.03,false); }
static void Tap(UIView *host,NSString *identifier) {
    UIControl *control=(id)Find(host,identifier); assert(control); [control sendActionsForControlEvents:UIControlEventTouchUpInside];
}
@interface AKAbilityTestPan : UIPanGestureRecognizer
@property CGPoint movement;
@property UIGestureRecognizerState phase;
@end
@implementation AKAbilityTestPan
- (CGPoint)translationInView:(UIView *)view { (void)view; return self.movement; }
- (void)setTranslation:(CGPoint)p inView:(UIView *)view { (void)view; self.movement=p; }
- (UIGestureRecognizerState)state { return self.phase; }
@end
@interface AKTouchActionOverlay (Fixture)
- (void)drag:(UIPanGestureRecognizer *)pan;
- (void)resetLayout;
@end
static void Capture(UIView *host,NSString *name) {
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat]; format.scale=1;
    UIImage *image=[[[UIGraphicsImageRenderer alloc] initWithSize:host.bounds.size format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [host.layer renderInContext:ctx.CGContext];
    }];
    NSString *documents=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject;
    [UIImagePNGRepresentation(image) writeToFile:[documents stringByAppendingPathComponent:name] atomically:YES];
}
void TestTouchAbilitiesUI(UIView *host,AKTouchGamepad *manager,GCVirtualController *controller) {
    [NSUserDefaults.standardUserDefaults removeObjectForKey:@"WolkaraTouchAbilitiesV1"];
    [manager toggleSettings]; Tap(host,@"wolkara.controls.abilities");
    assert(manager.configuring && manager.editing);
    UIView *first=Find(host,@"wolkara.ability.0.up"); assert(first);
    AKTouchActionOverlay *overlay=(id)first.superview;
    Tap(host,@"wolkara.abilities.reset"); first=Find(host,@"wolkara.ability.0.up"); [overlay layoutIfNeeded];
    UISwitch *enabled=(id)Find(host,@"wolkara.abilities.enabled"); enabled.on=YES;
    [enabled sendActionsForControlEvents:UIControlEventValueChanged];
    GCExtendedGamepad *pad=controller.controller.extendedGamepad;
    [(UIControl *)first sendActionsForControlEvents:UIControlEventTouchDown]; Drain(); assert(!pad.dpad.up.pressed);
    UISlider *size=(id)Find(host,@"wolkara.abilities.size");
    CGRect before=first.frame; size.value=1.3; [size sendActionsForControlEvents:UIControlEventValueChanged]; [overlay layoutIfNeeded];
    assert(fabs(first.frame.size.width/before.size.width-1.3)<.01);
    AKAbilityTestPan *pan=[AKAbilityTestPan new]; [first addGestureRecognizer:pan]; pan.phase=UIGestureRecognizerStateBegan;
    pan.movement=CGPointMake(12,-10); CGPoint old=overlay.layout.center; [overlay drag:pan];
    assert(overlay.layout.center.x>old.x && overlay.layout.center.y<old.y);
    UISegmentedControl *mode=(id)Find(host,@"wolkara.abilities.mode"); mode.selectedSegmentIndex=1;
    [mode sendActionsForControlEvents:UIControlEventValueChanged];
    CGPoint other=overlay.layout.actions[1].position,position=overlay.layout.actions[0].position;
    pan.movement=CGPointMake(10,5); [overlay drag:pan];
    assert(!CGPointEqualToPoint(position,overlay.layout.actions[0].position)); assert(CGPointEqualToPoint(other,overlay.layout.actions[1].position));
    size.value=65; [size sendActionsForControlEvents:UIControlEventValueChanged]; assert(overlay.layout.actions[0].diameter==65);
    [first removeGestureRecognizer:pan];
    Capture(host,@"abilities-editor.png");
    Tap(host,@"wolkara.abilities.done"); assert(!manager.configuring && !manager.editing);
    AKTouchActionLayout *saved=[[AKTouchActionLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
    assert(saved.enabled && saved.actions[0].diameter==65);
    // Actual GCVirtualController input, all 32 default combinations.
    for (AKTouchAction *action in overlay.layout.actions) {
        UIControl *circle=(id)Find(host,[@"wolkara.ability." stringByAppendingString:action.identifier]);
        assert(circle && !circle.hidden && !overlay.hidden);
        [circle sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
        assert(pad.leftTrigger.pressed==!!(action.modifiers&1)); assert(pad.rightTrigger.pressed==!!(action.modifiers&2));
        NSDictionary *buttons=@{@"A":pad.buttonA,@"B":pad.buttonB,@"X":pad.buttonX,@"Y":pad.buttonY,
            @"up":pad.dpad.up,@"right":pad.dpad.right,@"down":pad.dpad.down,@"left":pad.dpad.left};
        assert(((GCControllerButtonInput *)buttons[action.button]).pressed);
        [circle sendActionsForControlEvents:UIControlEventTouchCancel]; Drain();
        assert(!pad.leftTrigger.pressed&&!pad.rightTrigger.pressed&&!((GCControllerButtonInput *)buttons[action.button]).pressed);
    }
    UIControl *lt=(id)Find(host,[@"tolkara.gamepad." stringByAppendingString:GCInputLeftTrigger]);
    UIControl *rt=(id)Find(host,[@"tolkara.gamepad." stringByAppendingString:GCInputRightTrigger]);
    UIControl *x=(id)Find(host,@"wolkara.ability.1.X");
    [lt sendActionsForControlEvents:UIControlEventTouchDown]; [x sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
    assert(pad.leftTrigger.pressed&&pad.buttonX.pressed); [x sendActionsForControlEvents:UIControlEventTouchUpInside]; Drain();
    assert(pad.leftTrigger.pressed&&!pad.buttonX.pressed); [lt sendActionsForControlEvents:UIControlEventTouchUpInside];
    [rt sendActionsForControlEvents:UIControlEventTouchDown]; [x sendActionsForControlEvents:UIControlEventTouchDown]; Drain();
    assert(pad.rightTrigger.pressed&&!pad.leftTrigger.pressed&&!pad.buttonX.pressed);
    [x sendActionsForControlEvents:UIControlEventTouchUpInside]; [rt sendActionsForControlEvents:UIControlEventTouchUpInside];
    [x sendActionsForControlEvents:UIControlEventTouchDown]; Drain(); assert(pad.buttonX.pressed);
    [manager toggleSettings]; Drain(); assert(!pad.buttonX.pressed&&!pad.leftTrigger.pressed);
    Tap(host,@"wolkara.controls.abilities");
    Tap(host,@"wolkara.abilities.done");
    // Reference preview stays local to this synthetic fixture, never in the app/repository.
    AKTouchActionOverlay *preview=[[AKTouchActionOverlay alloc] initWithFrame:CGRectMake(0,0,1280,900)];
    [preview resetLayout]; preview.layout.enabled=YES; preview.layout.borderOpacity=.7; preview.active=YES; [preview layoutIfNeeded];
    UIView *canvas=[[UIView alloc] initWithFrame:preview.bounds];
    NSString *reference=[NSBundle.mainBundle pathForResource:@"Reference" ofType:@"jpg"];
    if (reference) { UIImageView *background=[[UIImageView alloc] initWithImage:[UIImage imageWithContentsOfFile:reference]]; background.frame=canvas.bounds; [canvas addSubview:background]; }
    [canvas addSubview:preview]; Capture(canvas,@"abilities-reference.png");
    overlay.layout.enabled=NO; [overlay.layout save]; overlay.active=NO;
    puts("TOUCH_ABILITIES_UI_PASS: editor, whole/individual adjustments, persistence, 32 real controller chords, held modifiers, incompatible chord rejection and settings cancellation.");
}
