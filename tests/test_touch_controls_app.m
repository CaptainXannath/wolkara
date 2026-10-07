// Original UIKit/AppKit fixture for manual touch/keyboard testing. No guest.
#import "AppKit.h"
#import "TouchControls.h"
#import "TouchGamepad.h"
#import "TouchAdventure.h"
#import <objc/runtime.h>
#include <assert.h>

@interface AKInputFixtureView : NSView
@property CATextLayer *heading, *instructions, *result;
@property NSMutableString *text;
@property NSString *lastAction;
@property NSRange selection;
@property NSUInteger replacements;
@end
@implementation AKInputFixtureView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.wantsLayer = YES;
        self.layer.backgroundColor = [UIColor colorWithRed:0.06 green:0.10 blue:0.16 alpha:1].CGColor;
        _text = [NSMutableString new];
        _lastAction = @"Ready";
        for (NSString *key in @[@"heading", @"instructions", @"result"]) {
            CATextLayer *label = [CATextLayer new];
            label.contentsScale = UIScreen.mainScreen.scale;
            label.foregroundColor = UIColor.whiteColor.CGColor;
            label.wrapped = YES;
            [self.layer addSublayer:label];
            [self setValue:label forKey:key];
        }
        _heading.fontSize = 24; _instructions.fontSize = 15; _result.fontSize = 18;
        _heading.string = @"Tolkara · Touch input fixture";
        _instructions.string = @"Slide: move • Tap: left click • Two fingers: scroll / right click\nThree-finger tap: middle click • Hold then slide: drag\nUse the keyboard button at the top center. This is an original test screen.";
        [self setFrame:frame];
    }
    return self;
}
- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    CGFloat width = MAX(100, frame.size.width - 96);
    _heading.frame = CGRectMake(48, 32, width, 32);
    _instructions.frame = CGRectMake(48, 76, width, 78);
    _result.frame = CGRectMake(48, 170, width, 100);
    [self refresh];
}
- (void)refresh {
    self.result.string = [NSString stringWithFormat:@"%@\nText: %@", self.lastAction, self.text];
}
- (BOOL)acceptsFirstResponder { return YES; }
- (void)keyDown:(NSEvent *)event {
    if (event.keyCode == 0 && (event.modifierFlags & NSEventModifierFlagCommand)) {
        self.selection = NSMakeRange(0, self.text.length);
        self.replacements++;
        return;
    }
    NSRange range = self.selection;
    assert(NSMaxRange(range) <= self.text.length);
    if (event.keyCode == 51) {
        if (!range.length && range.location) range = [self.text rangeOfComposedCharacterSequenceAtIndex:range.location - 1];
        [self.text deleteCharactersInRange:range];
        self.selection = NSMakeRange(range.location, 0);
    } else if (event.keyCode == 53) {
        [self.text setString:@""]; self.selection = NSMakeRange(0, 0);
    } else if (event.characters.length) {
        [self.text replaceCharactersInRange:range withString:event.characters];
        self.selection = NSMakeRange(range.location + event.characters.length, 0);
    }
    self.lastAction = @"Keyboard input received";
    [self refresh];
}
- (void)mouseMoved:(NSEvent *)event {
    self.lastAction = [NSString stringWithFormat:@"Pointer %.0f, %.0f", event.locationInWindow.x, event.locationInWindow.y];
    [self refresh];
}
- (void)mouseDown:(NSEvent *)event { self.lastAction = event.clickCount == 2 ? @"Double click" : @"Left click / hold"; [self refresh]; }
- (void)rightMouseDown:(NSEvent *)event { (void)event; self.lastAction = @"Right click / hold"; [self refresh]; }
- (void)otherMouseDown:(NSEvent *)event { (void)event; self.lastAction = @"Middle click"; [self refresh]; }
- (void)mouseDragged:(NSEvent *)event { (void)event; self.lastAction = @"Left drag"; [self refresh]; }
- (void)rightMouseDragged:(NSEvent *)event { (void)event; self.lastAction = @"Right drag"; [self refresh]; }
- (void)scrollWheel:(NSEvent *)event {
    self.lastAction = [NSString stringWithFormat:@"Scroll %.0f, %.0f", event.deltaX, event.deltaY];
    [self refresh];
}
@end

static void AKDrainFixtureEvents(void) {
    // Let UIKit finish its asynchronous text transaction before observing the
    // translated events. The fixture is entered from a timer, like the guest.
    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.02, false);
    NSEvent *event;
    while ((event = [NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES])) [NSApp sendEvent:event];
}

static UIView *AKFindInputView(UIView *root, NSString *identifier) {
    if ([root.accessibilityIdentifier isEqual:identifier]) return root;
    for (UIView *child in root.subviews) {
        UIView *found = AKFindInputView(child, identifier);
        if (found) return found;
    }
    return nil;
}

static void AKFixtureInputSource(void *context) {
    (void)context;
    NSEvent *event = [NSEvent new]; event.type = NSEventTypeMouseMoved;
    [NSApp postEvent:event atStart:NO];
}

@interface AKTouchGamepad (InputModeFixture)
- (NSArray<GCController *> *)connectedControllers;
- (BOOL)wantsController;
@end
@interface UIView (InputModeFixture)
- (void)updateTouchMode;
- (void)touchAdventureTapAt:(CGPoint)point;
@end
@interface AKBridgeFixtureTouch : UITouch
@property CGPoint point;
@property NSTimeInterval time;
@property UITouchPhase fixturePhase;
@end
@implementation AKBridgeFixtureTouch
- (CGPoint)locationInView:(UIView *)view { (void)view; return self.point; }
- (NSTimeInterval)timestamp { return self.time; }
- (UITouchType)type { return UITouchTypeDirect; }
- (UITouchPhase)phase { return self.fixturePhase; }
@end
@interface AKBridgeFixtureController : NSObject
@property BOOL isSnapshot;
@property id extendedGamepad;
@property id microGamepad;
@end
@implementation AKBridgeFixtureController
@end
static NSArray<GCController *> *AKBridgeFixtureControllers;
static NSArray<GCController *> *AKBridgeConnectedControllers(id object, SEL selector) {
    (void)object; (void)selector; return AKBridgeFixtureControllers ?: @[];
}
static BOOL AKBridgeNeverConnect(id object, SEL selector) {
    (void)object; (void)selector; return NO;
}
static AKBridgeFixtureTouch *AKBridgeTouch(CGPoint point, NSTimeInterval time) {
    AKBridgeFixtureTouch *touch=[AKBridgeFixtureTouch new];
    touch.point=point; touch.time=time; touch.fixturePhase=UITouchPhaseBegan; return touch;
}
static NSArray<NSEvent *> *AKTakeBridgeEvents(void) {
    // Inspect our synthetic queue instead of dispatching movement letters into
    // the fixture's text field. The caller pauses its normal event pump.
    NSMutableArray<NSEvent *> *events=[NSMutableArray new]; NSEvent *event;
    while ((event=[NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast
        inMode:NSDefaultRunLoopMode dequeue:YES])) [events addObject:event];
    return events;
}
static void AKTestAdventureBridge(NSWindow *guest) {
    UIView *host=[guest valueForKey:@"_host"];
    AKTouchControls *controls=[host valueForKey:@"_touchControls"];
    AKTouchGamepad *gamepad=[host valueForKey:@"_touchGamepad"];
    AKTouchAdventure *adventure=[host valueForKey:@"_touchAdventure"];
    [host layoutIfNeeded];
    assert(fabs(controls.bounds.size.width-148)<0.1);
    assert(!AKFindInputView(controls,@"tolkara.trackpad"));
    NSUInteger buttons=0;
    for (UIView *view in controls.subviews) if ([view isKindOfClass:UIButton.class]) buttons++;
    assert(buttons==3 && AKFindInputView(controls,@"tolkara.keyboard") &&
        AKFindInputView(controls,@"tolkara.gamepad") && AKFindInputView(controls,@"wolkara.controlSettings"));
    // Substitute discovery/transport only inside our own fixture process. This
    // tests real mode callbacks without connecting a virtual pad or touching a
    // physical controller paired to the test Mac.
    Method discover=class_getInstanceMethod(AKTouchGamepad.class,@selector(connectedControllers));
    Method connect=class_getInstanceMethod(AKTouchGamepad.class,@selector(wantsController));
    IMP originalDiscover=method_setImplementation(discover,(IMP)AKBridgeConnectedControllers);
    IMP originalConnect=method_setImplementation(connect,(IMP)AKBridgeNeverConnect);
    gamepad.enabled=NO; [host updateTouchMode];
    assert(!controls.trackpadEnabled && adventure.enabled);
    gamepad.enabled=YES;
    assert(gamepad.controllerModeActive && controls.trackpadEnabled && !adventure.enabled);
    gamepad.enabled=NO;
    assert(!controls.trackpadEnabled && adventure.enabled);
    AKBridgeFixtureController *physical=[AKBridgeFixtureController new]; physical.extendedGamepad=@YES;
    AKBridgeFixtureControllers=@[(id)physical]; [gamepad refresh];
    assert(!gamepad.enabled && gamepad.controllerModeActive && controls.trackpadEnabled && !adventure.enabled);
    AKBridgeFixtureControllers=@[]; [gamepad refresh];
    assert(!controls.trackpadEnabled && adventure.enabled);
    [controls toggleKeyboard]; assert(controls.keyboardVisible && !adventure.enabled);
    [controls dismissKeyboard]; assert(!controls.keyboardVisible && adventure.enabled);
    [gamepad toggleSettings]; assert(gamepad.configuring && !adventure.enabled);
    [gamepad toggleSettings]; assert(!gamepad.configuring && adventure.enabled);
    [adventure layoutIfNeeded];
    [host touchAdventureTapAt:CGPointMake(60,80)];
    NSPoint anchor=guest.ak_mouseLocation;
    (void)AKTakeBridgeEvents();
    CGFloat width=host.bounds.size.width, height=host.bounds.size.height;
    AKBridgeFixtureTouch *camera=AKBridgeTouch(CGPointMake(width*.56,height*.35),1);
    [adventure touchesBegan:[NSSet setWithObject:camera] withEvent:nil];
    assert(!AKTakeBridgeEvents().count);
    camera.point=CGPointMake(camera.point.x+10,camera.point.y+7); camera.time=1.1;
    [adventure touchesMoved:[NSSet setWithObject:camera] withEvent:nil];
    NSArray<NSEvent *> *events=AKTakeBridgeEvents();
    assert(events.count==2 && events[0].type==NSEventTypeRightMouseDown && events[1].type==NSEventTypeRightMouseDragged);
    assert(CGPointEqualToPoint(events[0].locationInWindow,anchor) &&
        CGPointEqualToPoint(events[1].locationInWindow,anchor));
    assert(events[1].deltaX==10 && events[1].deltaY==7 && CGPointEqualToPoint(guest.ak_mouseLocation,anchor));
    // An ability press must release the camera BEFORE moving the one guest
    // pointer. A second unclaimed finger cannot release its held left button.
    AKBridgeFixtureTouch *direct=AKBridgeTouch(CGPointMake(width*.84,height*.40),2);
    [host touchesBegan:[NSSet setWithObject:direct] withEvent:nil];
    events=AKTakeBridgeEvents();
    assert(events.count==3 && events[0].type==NSEventTypeRightMouseUp &&
        events[1].type==NSEventTypeMouseMoved && events[2].type==NSEventTypeLeftMouseDown);
    AKBridgeFixtureTouch *other=AKBridgeTouch(CGPointMake(width*.90,height*.40),2.1);
    [host touchesBegan:[NSSet setWithObject:other] withEvent:nil];
    other.fixturePhase=UITouchPhaseEnded; [host touchesEnded:[NSSet setWithObject:other] withEvent:nil];
    camera.fixturePhase=UITouchPhaseEnded; [adventure touchesEnded:[NSSet setWithObject:camera] withEvent:nil];
    assert(!AKTakeBridgeEvents().count);
    // Nor can a new camera finger steal that drag before its owner lifts.
    camera=AKBridgeTouch(CGPointMake(width*.56,height*.35),3);
    [adventure touchesBegan:[NSSet setWithObject:camera] withEvent:nil];
    camera.point=CGPointMake(camera.point.x+12,camera.point.y); camera.time=3.1;
    [adventure touchesMoved:[NSSet setWithObject:camera] withEvent:nil];
    assert(!AKTakeBridgeEvents().count);
    direct.fixturePhase=UITouchPhaseMoved; direct.point=CGPointMake(width*.82,height*.50);
    [host touchesMoved:[NSSet setWithObject:direct] withEvent:nil];
    direct.fixturePhase=UITouchPhaseEnded; [host touchesEnded:[NSSet setWithObject:direct] withEvent:nil];
    events=AKTakeBridgeEvents();
    assert(events.count==2 && events[0].type==NSEventTypeLeftMouseDragged && events[1].type==NSEventTypeLeftMouseUp);
    // Window hiding is an interruption, even without an app background event.
    direct=AKBridgeTouch(CGPointMake(width*.84,height*.40),4);
    [host touchesBegan:[NSSet setWithObject:direct] withEvent:nil]; (void)AKTakeBridgeEvents();
    [NSNotificationCenter.defaultCenter postNotificationName:UIWindowDidBecomeHiddenNotification object:host.window];
    events=AKTakeBridgeEvents();
    assert(!adventure.enabled && events.count==1 && events[0].type==NSEventTypeLeftMouseUp);
    [NSNotificationCenter.defaultCenter postNotificationName:UIWindowDidBecomeVisibleNotification object:host.window];
    [host updateTouchMode]; assert(adventure.enabled);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
    // UIKit still says Active while WillResign is being delivered. Later
    // mode/configuration callbacks must not reactivate the touch surface.
    gamepad.enabled=YES; gamepad.enabled=NO; [host updateTouchMode];
    assert(!adventure.enabled);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
    assert(adventure.enabled);
    [adventure cancelTouches]; (void)AKTakeBridgeEvents();
    method_setImplementation(discover,originalDiscover); method_setImplementation(connect,originalConnect);
    AKBridgeFixtureControllers=nil; [gamepad refresh];
    puts("TOUCH_ADVENTURE_BRIDGE_PASS: three-button toolbar, automatic modes, native UI suspension, relative queued camera and direct touch ownership.");
}

@interface AKInputFixtureScene : UIResponder <UIWindowSceneDelegate>
@property NSWindow *guest;
@property NSTimer *pump;
@end
@implementation AKInputFixtureScene
- (void)checkTrackingUIProgress {
    UIView *host = [self.guest valueForKey:@"_host"];
    AKTouchControls *controls = [host valueForKey:@"_touchControls"];
    AKTouchGamepad *gamepad = [host valueForKey:@"_touchGamepad"];
    for (NSUInteger surface = 0; surface < 2; surface++) {
        if (surface == 0) [controls toggleKeyboard]; else [gamepad toggleSettings];
        __block BOOL trackingFired = NO, defaultFired = NO;
        NSTimer *tracking = [NSTimer timerWithTimeInterval:0.02 repeats:NO block:^(NSTimer *timer) {
            (void)timer; trackingFired = YES;
        }];
        [NSRunLoop.mainRunLoop addTimer:tracking forMode:UITrackingRunLoopMode];
        NSTimer *ordinary = [NSTimer scheduledTimerWithTimeInterval:0.02 repeats:NO block:^(NSTimer *timer) {
            (void)timer; defaultFired = YES;
        }];
        NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 1;
        while (!(trackingFired && defaultFired) && NSProcessInfo.processInfo.systemUptime < deadline) {
            AKFixtureInputSource(NULL);
            [NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES];
        }
        [tracking invalidate]; [ordinary invalidate];
        NSLog(@"Native tracking progress: surface=%lu tracking=%d default=%d", (unsigned long)surface, trackingFired, defaultFired);
        assert(trackingFired && defaultFired);
        if (surface == 0) [controls dismissKeyboard]; else [gamepad toggleSettings];
    }
    NSLog(@"TOUCH_UI_SELF_TEST_PASS: UIKit tracking and default work progress while native editor/settings are open");
    exit(EXIT_SUCCESS);
}
- (void)checkNativeUIProgress {
    UIView *host = [self.guest valueForKey:@"_host"];
    CFRunLoopSourceContext context = {0}; context.perform = AKFixtureInputSource;
    CFRunLoopSourceRef source = CFRunLoopSourceCreate(NULL, 0, &context);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    // Empty nonblocking polls, source-driven blocking polls, a permanently
    // occupied queue, repeated peeks, and NSApplication's own run loop must
    // all let native UI make progress.
    for (NSUInteger traffic = 0; traffic < 5; traffic++) {
        UIView *probe = [[UIView alloc] initWithFrame:CGRectMake(60, 260, 24, 24)];
        probe.backgroundColor = UIColor.systemGreenColor;
        [host addSubview:probe];
        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(60, 300, 220, 32)];
        [host addSubview:slider];
        __block BOOL completed = NO, deferred = NO, timerFired = NO;
        dispatch_async(dispatch_get_main_queue(), ^{ deferred = YES; });
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.02 repeats:NO block:^(NSTimer *fired) {
            (void)fired; slider.value = 0.75; timerFired = YES;
        }];
        // No explicit flush in the fixture: it previously hid presentation
        // problems by forcing a Core Animation commit after every key/motion.
        [UIView animateWithDuration:0.05 animations:^{
            probe.center = CGPointMake(200, 272);
        } completion:^(BOOL finished) { completed = finished; }];
        NSEvent *peeked = nil;
        if (traffic == 3) {
            AKFixtureInputSource(NULL);
            peeked = [NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast
                inMode:NSDefaultRunLoopMode dequeue:NO];
            assert(peeked);
        }
        NSTimeInterval deadline = NSProcessInfo.processInfo.systemUptime + 2;
        if (traffic == 4) {
            [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:NO block:^(NSTimer *stop) {
                (void)stop; [NSApp stop:nil];
            }];
            [NSApp run];
        }
        while (traffic != 4 && !(completed && deferred && timerFired) && NSProcessInfo.processInfo.systemUptime < deadline) {
            @autoreleasepool {
                if (traffic == 2) AKFixtureInputSource(NULL);
                if (traffic == 1) CFRunLoopSourceSignal(source);
                NSEvent *event = [NSApp nextEventMatchingMask:UINT64_MAX
                    untilDate:traffic == 1 ? [NSDate dateWithTimeIntervalSinceNow:0.01] : NSDate.distantPast
                    inMode:NSDefaultRunLoopMode dequeue:traffic != 3];
                if (peeked) assert(event == peeked);
            }
        }
        [timer invalidate];
        NSLog(@"Native UI progress: traffic=%lu animation=%d deferred=%d timer=%d",
            (unsigned long)traffic, completed, deferred, timerFired);
        assert(completed && deferred && timerFired && slider.value == 0.75);
        if (peeked) assert([NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast
            inMode:NSDefaultRunLoopMode dequeue:YES] == peeked);
        [probe removeFromSuperview]; [slider removeFromSuperview];
    }
    CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, kCFRunLoopDefaultMode);
    CFRelease(source);
    NSLog(@"TOUCH_UI_SELF_TEST_PASS: native UI presentation, deferred work, slider updates and queue peeking inside guest loop");
    exit(EXIT_SUCCESS);
}
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    [NSApplication sharedApplication];
    self.guest = [[NSWindow alloc] initWithContentRect:((UIWindowScene *)scene).screen.bounds styleMask:0 backing:2 defer:NO];
    self.guest.contentView = [[AKInputFixtureView alloc] initWithFrame:self.guest.frame];
    self.guest.acceptsMouseMovedEvents = YES;
    [self.guest makeFirstResponder:self.guest.contentView];
    [self.guest makeKeyAndOrderFront:nil];
    self.pump = [NSTimer scheduledTimerWithTimeInterval:0.016 repeats:YES block:^(NSTimer *timer) {
        (void)timer;
        NSEvent *event;
        while ((event = [NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES])) [NSApp sendEvent:event];
    }];
    BOOL selfTest = [NSProcessInfo.processInfo.arguments containsObject:@"--self-test"];
    BOOL nativeReference = [NSProcessInfo.processInfo.arguments containsObject:@"--native-keyboard-reference"];
    if (selfTest) {
        // A blocked main thread must fail instead of leaving simctl waiting.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC),
            dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                fprintf(stderr, "TOUCH_UI_SELF_TEST_TIMEOUT\n");
                _Exit(EXIT_FAILURE);
            });
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--tracking-progress-test"]) {
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:NO block:^(NSTimer *timer) {
            (void)timer; [self.pump invalidate]; self.pump = nil;
            [self checkTrackingUIProgress];
        }];
        return;
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--ui-progress-test"]) {
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:NO block:^(NSTimer *timer) {
            (void)timer;
            [self.pump invalidate]; self.pump = nil;
            [self checkNativeUIProgress];
        }];
        return;
    }
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--guest-poll-loop"]) {
        // Exercise UIKit inside the timer-entered desktop loop used by the
        // runtime, rather than only returning to UIApplicationMain each turn.
        [NSTimer scheduledTimerWithTimeInterval:2 repeats:NO block:^(NSTimer *timer) {
            (void)timer;
            [self.pump invalidate];
            self.pump = nil;
            while (YES) { @autoreleasepool {
                if ([NSProcessInfo.processInfo.arguments containsObject:@"--queued-traffic"]) AKFixtureInputSource(NULL);
                NSEvent *event = [NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast
                    inMode:NSDefaultRunLoopMode dequeue:YES];
                if (event.window) [NSApp sendEvent:event];
            } }
        }];
    }
    if (selfTest || nativeReference || [NSProcessInfo.processInfo.arguments containsObject:@"--show-keyboard"]) {
        [NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *timer) {
            (void)timer;
            UIView *host = [self.guest valueForKey:@"_host"];
            AKTouchControls *controls = [host valueForKey:@"_touchControls"];
            CGSize originalSize = host.bounds.size;
            if (nativeReference) {
                UITextView *reference = [[UITextView alloc] initWithFrame:CGRectMake(48, 130, 360, 70)];
                reference.backgroundColor = UIColor.whiteColor;
                reference.accessibilityIdentifier = @"tolkara.reference-input";
                [host addSubview:reference];
                [reference becomeFirstResponder];
                return;
            }
            if (selfTest) {
                [self.pump invalidate]; self.pump=nil;
                AKTestAdventureBridge(self.guest);
            }
            [controls toggleKeyboard];
            if (!selfTest) return;
            [NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *timer) {
                (void)timer;
                [host layoutIfNeeded];
                assert(controls.keyboardVisible && CGSizeEqualToSize(originalSize, host.bounds.size));
                assert(host.keyboardLayoutGuide.layoutFrame.size.height > 100);
                assert(CGRectGetMaxY(controls.frame) <= CGRectGetMinY(host.keyboardLayoutGuide.layoutFrame));
                assert(CGRectGetMinY(controls.frame) >= 0);
                CGRect toolbarFrame = controls.frame;
                assert(fabs(CGRectGetMidX(toolbarFrame) - CGRectGetMidX(host.safeAreaLayoutGuide.layoutFrame)) < 1);
                assert(fabs(CGRectGetMinY(toolbarFrame) - CGRectGetMinY(host.safeAreaLayoutGuide.layoutFrame) - 8) < 1);
                UITextView *input = (UITextView *)AKFindInputView(host, @"wolkara.keyboard.draft");
                UIButton *insert = (UIButton *)AKFindInputView(host, @"wolkara.keyboard.insert");
                UIButton *clear = (UIButton *)AKFindInputView(host, @"wolkara.keyboard.clear");
                assert(input.isFirstResponder && [input conformsToProtocol:@protocol(UITextInput)]);
                assert(!input.superview.hidden && input.bounds.size.width > 100 && input.bounds.size.height >= 44);
                CGRect editor = [input convertRect:input.bounds toView:host];
                assert(CGRectGetMaxY(editor) < CGRectGetMinY(host.keyboardLayoutGuide.layoutFrame));
                assert(CGRectGetMinY(editor) >= CGRectGetMaxY(controls.frame));
                AKInputFixtureView *fixture = (AKInputFixtureView *)self.guest.contentView;
                // Reopening with unknown existing text starts an empty draft;
                // an explicit empty replacement must clear the entire field.
                [fixture.text setString:@"Previous synthetic value"];
                fixture.selection = NSMakeRange(4, 0);
                assert(!input.text.length && insert.enabled);
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                assert(!fixture.text.length && !insert.enabled && fixture.replacements == 1);
                [fixture.text setString:@"A different old value"];
                fixture.selection = NSMakeRange(2, 3);
                [input insertText:@"Fixture @ñ🙂"];
                AKDrainFixtureEvents();
                assert([input.text isEqual:@"Fixture @ñ🙂"] && [fixture.text isEqual:@"A different old value"] && insert.enabled && clear.enabled);
                [input deleteBackward];
                assert([input.text isEqual:@"Fixture @ñ"]);
                // Editing an earlier range stays local; it must not append to
                // the game or emit backspaces until the user requests Insert.
                UITextPosition *end = [input positionFromPosition:input.beginningOfDocument offset:7];
                [input replaceRange:[input textRangeFromPosition:input.beginningOfDocument toPosition:end] withText:@"Draft"];
                assert([input.text isEqual:@"Draft @ñ"]);
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@"Draft @ñ"] && input.text.length == 0 && !insert.enabled && !clear.enabled);
                NSUInteger replacements = fixture.replacements;
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                [input.delegate textView:input shouldChangeTextInRange:NSMakeRange(0, 0) replacementText:@"\n"];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@"Draft @ñ"] && fixture.replacements == replacements);
                // Provisional text and unfinished dictation cannot be inserted.
                [input setMarkedText:@" provisional" selectedRange:NSMakeRange(12, 0)];
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@"Draft @ñ"]);
                [input setMarkedText:@" ¡Hola equipo!" selectedRange:NSMakeRange(@" ¡Hola equipo!".length, 0)];
                [input unmarkText];
                id placeholder = [input insertDictationResultPlaceholder];
                assert(placeholder);
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:@"Draft @ñ"]);
                [input removeDictationResultPlaceholder:placeholder willInsertResult:YES];
                [input insertText:@" Dictado."];
                assert([input.text isEqual:@" ¡Hola equipo! Dictado."]);
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                NSMutableString *expected = [@" ¡Hola equipo! Dictado." mutableCopy];
                assert([fixture.text isEqual:expected]);
                // Many edits are now one normal document, not 64 resets of
                // UIKit's selection/undo context and 64 asynchronous forwards.
                for (NSUInteger i = 0; i < 64; i++) {
                    [input insertText:@"a"]; [input insertText:@"b"]; [input deleteBackward];
                    AKDrainFixtureEvents();
                    assert(input.text.length == i + 1 && [fixture.text isEqual:expected]);
                }
                NSString *draft = [input.text copy];
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                [expected setString:draft];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:expected] && !input.text.length);
                [input insertText:@" discarded"];
                [clear sendActionsForControlEvents:UIControlEventTouchUpInside];
                assert(!input.text.length);
                [input insertText:@" failed recognition" ];
                [input setMarkedText:@" provisional" selectedRange:NSMakeRange(12, 0)];
                [input dictationRecognitionFailed];
                assert([input.text isEqual:@" failed recognition"]);
                [clear sendActionsForControlEvents:UIControlEventTouchUpInside];
                // Pasted controls are text, never implicit game commands.
                input.text = @"one\ntwo\tthree";
                [insert sendActionsForControlEvents:UIControlEventTouchUpInside];
                [expected setString:@"one two three"];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:expected]);
                UIStackView *accessory = (UIStackView *)controls.inputAccessoryView;
                [input insertText:@" done"];
                [(UIButton *)accessory.arrangedSubviews[5] sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:expected]);
                // The system Done key replaces only; Return stays explicit.
                [input.delegate textView:input shouldChangeTextInRange:NSMakeRange(input.text.length, 0) replacementText:@"\n"];
                AKDrainFixtureEvents();
                [expected setString:@" done"];
                assert([fixture.text isEqual:expected] && !input.text.length);
                [(UIButton *)accessory.arrangedSubviews[5] sendActionsForControlEvents:UIControlEventTouchUpInside];
                AKDrainFixtureEvents();
                [expected appendString:@"\r"];
                assert([fixture.text isEqual:expected]);
                [input insertText:@" close without inserting"];
                [controls dismissKeyboard]; [controls toggleKeyboard];
                AKDrainFixtureEvents();
                assert([fixture.text isEqual:expected] && !input.text.length);
                [input setMarkedText:@" discard me" selectedRange:NSMakeRange(11, 0)];
                [controls dismissKeyboard];
                [input insertText:@" late result"];
                [input removeDictationResultPlaceholder:placeholder willInsertResult:NO];
                [input unmarkText];
                assert(!input.text.length);
                [controls toggleKeyboard];
                [input insertText:@" cancelled on background"];
                [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
                [NSNotificationCenter.defaultCenter postNotificationName:UIWindowDidResignKeyNotification object:input.window];
                assert(controls.keyboardVisible && input.text.length);
                [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
                assert(!controls.keyboardVisible && !input.text.length && input.superview.hidden);
                [input insertText:@" background result"];
                [host layoutIfNeeded];
                assert(CGRectEqualToRect(toolbarFrame, controls.frame));
                [controls setGamepadVisible:NO]; [host layoutIfNeeded];
                assert(CGRectEqualToRect(toolbarFrame, controls.frame));
                [NSTimer scheduledTimerWithTimeInterval:1 repeats:NO block:^(NSTimer *timer) {
                    (void)timer;
                    assert([fixture.text isEqual:expected]);
                    assert(!controls.keyboardVisible && host.isFirstResponder);
                    NSLog(@"TOUCH_UI_SELF_TEST_PASS: whole-field replacement, empty clearing, duplicate suppression, draft editing, dictation, cancellation and fixed toolbar");
                    exit(EXIT_SUCCESS);
                }];
            }];
        }];
    }
}
@end

@interface AKInputFixtureApp : UIResponder <UIApplicationDelegate>
@end
@implementation AKInputFixtureApp
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)app; (void)options;
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"Input fixture" sessionRole:session.role];
    config.delegateClass = AKInputFixtureScene.class;
    return config;
}
@end
int main(int argc, char **argv) { @autoreleasepool {
    if ([NSProcessInfo.processInfo.arguments containsObject:@"--self-test"])
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:@"TKTouchGamepadEnabled"];
    return UIApplicationMain(argc, argv, nil, NSStringFromClass(AKInputFixtureApp.class));
} }
