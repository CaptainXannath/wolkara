// Synthetic UIKit touches only; no game is loaded or controlled by this fixture.
#import "AppKit.h"
#import "TouchControls.h"
#include <assert.h>
#include <math.h>

@interface CameraTouch : UITouch
@property CGPoint point;
@property UITouchPhase testPhase;
@property UITouchType testType;
@property(nonatomic,weak) UIView *host;
@end
@implementation CameraTouch
- (CGPoint)locationInView:(UIView *)view { (void)view; return self.point; }
- (UITouchPhase)phase { return self.testPhase; }
- (UITouchType)type { return self.testType; }
- (UIView *)view { return self.host; }
@end
@interface CameraEvent : UIEvent
@property(nonatomic,strong) NSSet<UITouch *> *touches;
@property UIEventButtonMask buttons;
@end
@implementation CameraEvent
- (NSSet<UITouch *> *)allTouches { return self.touches; }
- (UIEventButtonMask)buttonMask { return self.buttons; }
- (UIKeyModifierFlags)modifierFlags { return 0; }
- (NSTimeInterval)timestamp { return NSProcessInfo.processInfo.systemUptime; }
@end
static NSEvent *Next(void) {
    NSEvent *e=[NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES];
    assert(e); return e;
}
static void Empty(void) {
    assert(![NSApp nextEventMatchingMask:UINT64_MAX untilDate:NSDate.distantPast inMode:NSDefaultRunLoopMode dequeue:YES]);
}
static void Warp(CGPoint point) {
    [NSNotificationCenter.defaultCenter postNotificationName:@"AKMouseAnchorChanged" object:nil userInfo:@{@"x":@(point.x),@"y":@(point.y)}];
}
static void CheckDelta(NSEvent *e,CGFloat dx,CGFloat dy) {
    if (fabs(e.deltaX-dx)>.001 || fabs(e.deltaY-dy)>.001) {
        fprintf(stderr,"CAMERA_DELTA_MISMATCH expected=(%g,%g) actual=(%g,%g)\n",dx,dy,e.deltaX,e.deltaY);
        abort();
    }
}
static NSEvent *CheckEvent(NSEventType type, CGPoint point, CGSize size, CGFloat dx, CGFloat dy) {
    NSEvent *e=Next();
    assert(e.type==type);
    assert(CGPointEqualToPoint(e.locationInWindow,CGPointMake(point.x,size.height-point.y)));
    CheckDelta(e,dx,dy);
    return e;
}
static void Send(UIView *host, CameraEvent *event, CameraTouch *touch, UITouchPhase phase, CGPoint point) {
    touch.point=point; touch.testPhase=phase;
    NSSet *changed=[NSSet setWithObject:touch];
    switch (phase) {
        case UITouchPhaseBegan: [host touchesBegan:changed withEvent:event]; break;
        case UITouchPhaseMoved: [host touchesMoved:changed withEvent:event]; break;
        case UITouchPhaseEnded: [host touchesEnded:changed withEvent:event]; break;
        case UITouchPhaseCancelled: [host touchesCancelled:changed withEvent:event]; break;
        default: abort();
    }
}
static void CheckCamera(CGSize size, CGPoint start, BOOL right) {
    AKMouseSetCaptured(false);
    NSWindow *window=[[NSWindow alloc] initWithContentRect:(CGRect){CGPointZero,size} styleMask:0 backing:2 defer:NO];
    UIView *host=[[NSClassFromString(@"AKHostView") alloc] initWithFrame:(CGRect){CGPointZero,size}];
    [host setValue:window forKey:@"nsWindow"];
    AKTouchControls *controls=[host valueForKey:@"_touchControls"]; controls.trackpadEnabled=NO;
    [host layoutSubviews]; Empty();
    CameraTouch *finger=[CameraTouch new]; finger.host=host; finger.testType=UITouchTypeDirect;
    CameraEvent *event=[CameraEvent new]; event.touches=[NSSet setWithObject:finger];
    event.buttons=right ? UIEventButtonMaskSecondary : 0;
    NSEventType down=right ? NSEventTypeRightMouseDown : NSEventTypeLeftMouseDown;
    NSEventType drag=right ? NSEventTypeRightMouseDragged : NSEventTypeLeftMouseDragged;
    NSEventType up=right ? NSEventTypeRightMouseUp : NSEventTypeLeftMouseUp;
    Send(host,event,finger,UITouchPhaseBegan,start);
    assert(CheckEvent(down,start,size,0,0).buttonNumber==(right ? 1 : 0));

    // The game captures and warps its cursor after the down event. This must
    // not change the next delta, whatever the finger's starting position.
    CGPoint center=CGPointMake(size.width/2,size.height/2);
    AKMouseSetCaptured(true); Warp(center);
    CGPoint moved=CGPointMake(start.x+10,start.y+5);
    Send(host,event,finger,UITouchPhaseMoved,moved);
    CheckEvent(drag,center,size,10,5);
    // Repeated warps, including an edge, leave motion unclipped and continuous.
    CGPoint edge=CGPointMake(size.width-1,size.height-1); Warp(edge);
    Send(host,event,finger,UITouchPhaseMoved,moved); Empty();
    moved=CGPointMake(moved.x+4,moved.y-3);
    Send(host,event,finger,UITouchPhaseMoved,moved); CheckEvent(drag,edge,size,4,-3);

    CameraTouch *other=[CameraTouch new]; other.host=host;
    event.touches=[NSSet setWithObjects:finger,other,nil];
    Send(host,event,other,UITouchPhaseBegan,CGPointMake(20,20)); Empty();
    Send(host,event,other,UITouchPhaseMoved,CGPointMake(800,500)); Empty();
    Send(host,event,other,UITouchPhaseEnded,CGPointMake(800,500)); Empty();

    // Keep relative semantics through a release/re-capture during this drag.
    AKMouseSetCaptured(false);
    moved=CGPointMake(moved.x-6,moved.y+8);
    Send(host,event,finger,UITouchPhaseMoved,moved); CheckEvent(drag,edge,size,-6,8);
    Send(host,event,finger,UITouchPhaseEnded,moved); CheckEvent(up,edge,size,0,0); Empty();

    // Ordinary UI drags and taps still land under the finger, with zero delta
    // on button transitions, even if UIKit's final up sample moved slightly.
    event.touches=[NSSet setWithObject:finger];
    Send(host,event,finger,UITouchPhaseBegan,start); CheckEvent(down,start,size,0,0);
    moved=CGPointMake(start.x+12,start.y-7);
    Send(host,event,finger,UITouchPhaseMoved,moved); CheckEvent(drag,moved,size,12,-7);
    CGPoint end=CGPointMake(moved.x+2,moved.y+1);
    Send(host,event,finger,UITouchPhaseEnded,end); CheckEvent(up,end,size,0,0); Empty();

    // A touch starting while captured must not teleport the guest cursor.
    AKMouseSetCaptured(true); Warp(center);
    Send(host,event,finger,UITouchPhaseBegan,start); CheckEvent(down,center,size,0,0);
    Send(host,event,finger,UITouchPhaseCancelled,moved); CheckEvent(up,center,size,0,0);
    Send(host,event,finger,UITouchPhaseMoved,end); Empty();

    // Settings, focus loss and mode/viewport changes release the owned button
    // exactly once and consume the cancelled gesture's remaining samples.
    for (unsigned reason=0;reason<4;reason++) {
        Send(host,event,finger,UITouchPhaseBegan,start); CheckEvent(down,center,size,0,0);
        switch (reason) {
            case 0: [controls cancelTouches]; break;
            case 1: [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil]; break;
            case 2: controls.trackpadEnabled=YES; break;
            case 3: host.bounds=(CGRect){CGPointZero,CGSizeMake(size.width-10,size.height-10)}; [host layoutSubviews]; break;
        }
        CheckEvent(up,center,host.bounds.size,0,0);
        [controls cancelTouches]; Empty();
        Send(host,event,finger,UITouchPhaseMoved,moved); Empty();
        event.touches=[NSSet setWithObjects:finger,other,nil];
        Send(host,event,other,UITouchPhaseBegan,CGPointMake(80,80)); Empty();
        Send(host,event,other,UITouchPhaseMoved,CGPointMake(200,200)); Empty();
        Send(host,event,other,UITouchPhaseEnded,CGPointMake(200,200)); Empty();
        event.touches=[NSSet setWithObject:finger];
        Send(host,event,finger,UITouchPhaseEnded,moved); Empty();
        controls.trackpadEnabled=NO;
        host.bounds=(CGRect){CGPointZero,size}; [host layoutSubviews]; Warp(center); Empty();
    }

    // If UIKit omits an end after losing focus, a fresh gesture can still start.
    Send(host,event,finger,UITouchPhaseBegan,start); CheckEvent(down,center,size,0,0);
    [controls cancelTouches]; CheckEvent(up,center,size,0,0);
    event.touches=[NSSet setWithObject:other];
    Send(host,event,other,UITouchPhaseBegan,start); CheckEvent(down,center,size,0,0);
    Send(host,event,other,UITouchPhaseEnded,start); CheckEvent(up,center,size,0,0);
    AKMouseSetCaptured(false);

    // The trackpad and indirect pointer paths retain their existing behavior.
    controls.trackpadEnabled=YES;
    id<AKTouchControlsDelegate> delegate=(id)host;
    AKMouseSetCaptured(true); Warp(center);
    [delegate touchMoveBy:CGPointMake(9,-4)]; CheckEvent(NSEventTypeMouseMoved,center,size,9,-4);
    AKMouseSetCaptured(false); controls.trackpadEnabled=NO;
    other.testType=UITouchTypeIndirectPointer;
    Send(host,event,other,UITouchPhaseBegan,start); CheckEvent(down,start,size,0,0);
    Send(host,event,other,UITouchPhaseMoved,moved);
    CheckEvent(drag,moved,size,moved.x-start.x,moved.y-start.y);
    Send(host,event,other,UITouchPhaseEnded,moved); CheckEvent(up,moved,size,0,0); Empty();
}
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    const CGSize sizes[]={{852,393},{932,430},{951,669},{1194,834}};
    for (unsigned i=0;i<sizeof sizes/sizeof *sizes;i++) {
        CGSize size=sizes[i];
        const CGPoint starts[]={{40,40},{size.width/2,size.height/2},{size.width-30,size.height-30}};
        for (unsigned j=0;j<sizeof starts/sizeof *starts;j++) @autoreleasepool {
            CheckCamera(size,starts[j],j==2);
        }
    }
    puts("DIRECT_TOUCH_CAMERA_PASS");
} return 0; }
