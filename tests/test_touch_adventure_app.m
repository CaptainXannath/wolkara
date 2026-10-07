// Original UIKit fixture. All contacts below are synthetic and never enter a game.
#import <UIKit/UIKit.h>
#import "../translation/AppKit/TouchAdventure.h"
#include <assert.h>

@interface AKAdventureFixtureTouch : UITouch
@property CGPoint point;
@property NSTimeInterval time;
@property UITouchType kind;
@end
@implementation AKAdventureFixtureTouch
- (CGPoint)locationInView:(UIView *)view { (void)view; return self.point; }
- (NSTimeInterval)timestamp { return self.time; }
- (UITouchType)type { return self.kind; }
@end
@interface AKAdventureFixtureEvent : UIEvent
@property NSSet<UITouch *> *contacts;
@end
@implementation AKAdventureFixtureEvent
- (NSSet<UITouch *> *)allTouches { return self.contacts; }
@end
@interface AKAdventureFixtureTrace : NSObject <AKTouchAdventureDelegate>
@property NSMutableArray<NSDictionary *> *events;
@end
@implementation AKAdventureFixtureTrace
- (instancetype)init { if ((self=[super init])) _events=[NSMutableArray new]; return self; }
- (void)touchAdventureKey:(unsigned short)code pressed:(BOOL)pressed {
    [self.events addObject:@{@"kind":@"key",@"key":@(code),@"pressed":@(pressed)}];
}
- (void)touchAdventureCameraButtonPressed:(BOOL)pressed {
    [self.events addObject:@{@"kind":@"right",@"pressed":@(pressed)}];
}
- (void)touchAdventureCameraMoveBy:(CGPoint)delta {
    [self.events addObject:@{@"kind":@"move",@"x":@(delta.x),@"y":@(delta.y)}];
}
- (void)touchAdventureTapAt:(CGPoint)point {
    [self.events addObject:@{@"kind":@"tap",@"x":@(point.x),@"y":@(point.y)}];
}
@end
static AKAdventureFixtureTouch *Touch(CGPoint point, NSTimeInterval time) {
    AKAdventureFixtureTouch *touch=[AKAdventureFixtureTouch new];
    touch.point=point; touch.time=time; return touch;
}
static void TestAdventure(UIView *host) {
    AKTouchAdventure *overlay=[[AKTouchAdventure alloc] initWithFrame:CGRectMake(0,0,1000,500)];
    AKAdventureFixtureTrace *trace=[AKAdventureFixtureTrace new]; overlay.delegate=trace;
    [host addSubview:overlay]; overlay.enabled=YES; [overlay layoutIfNeeded];
    UIView *ring=nil;
    for (UIView *view in overlay.subviews)
        if ([view.accessibilityIdentifier isEqual:@"wolkara.adventure.stick"]) ring=view;
    assert(ring && [overlay pointInside:ring.center withEvent:nil]);
    assert([overlay pointInside:CGPointMake(600,150) withEvent:nil]);
    assert(![overlay pointInside:CGPointMake(800,150) withEvent:nil]); // Ability/modifier bar.
    assert(![overlay pointInside:CGPointMake(600,470) withEvent:nil]); // Bottom menus.
    assert(![overlay pointInside:CGPointMake(300,180) withEvent:nil]); // World direct touch.
    assert(![overlay pointInside:CGPointMake(-10,150) withEvent:nil]);
    AKAdventureFixtureEvent *pointer=[AKAdventureFixtureEvent new];
    AKAdventureFixtureTouch *mouse=Touch(CGPointMake(600,150),1); mouse.kind=UITouchTypeIndirectPointer;
    pointer.contacts=[NSSet setWithObject:mouse];
    assert(![overlay pointInside:mouse.point withEvent:pointer]);
    // Simultaneous joystick/camera fingers retain their own identities.
    AKAdventureFixtureTouch *stick=Touch(ring.center,1);
    AKAdventureFixtureTouch *camera=Touch(CGPointMake(600,150),1);
    AKAdventureFixtureTouch *extra=Touch(CGPointMake(610,160),1);
    [overlay touchesBegan:[NSSet setWithObject:stick] withEvent:nil];
    [overlay touchesBegan:[NSSet setWithObject:camera] withEvent:nil];
    [overlay touchesBegan:[NSSet setWithObject:extra] withEvent:nil];
    assert(!trace.events.count);
    stick.point=CGPointMake(ring.center.x,ring.center.y-40); stick.time=1.1;
    [overlay touchesMoved:[NSSet setWithObject:stick] withEvent:nil];
    assert(trace.events.count==1 && [trace.events[0][@"key"] intValue]==13 &&
        [trace.events[0][@"pressed"] boolValue]);
    camera.point=CGPointMake(610,145); camera.time=1.1;
    [overlay touchesMoved:[NSSet setWithObject:camera] withEvent:nil];
    assert(trace.events.count==3 && [trace.events[1][@"kind"] isEqual:@"right"] &&
        [trace.events[1][@"pressed"] boolValue] && [trace.events[2][@"x"] intValue]==10 &&
        [trace.events[2][@"y"] intValue]==-5);
    [overlay touchesEnded:[NSSet setWithObject:extra] withEvent:nil];
    assert(trace.events.count==3); // Unclaimed finger cannot release the camera.
    [overlay cancelCameraForDirectTouch];
    assert(trace.events.count==4 && [trace.events[3][@"kind"] isEqual:@"right"] &&
        ![trace.events[3][@"pressed"] boolValue]);
    camera.point=CGPointMake(650,200); camera.time=1.2;
    [overlay touchesMoved:[NSSet setWithObject:camera] withEvent:nil];
    [overlay touchesEnded:[NSSet setWithObject:camera] withEvent:nil];
    assert(trace.events.count==4); // Cancelled finger cannot resume until a fresh touch.
    [overlay touchesCancelled:[NSSet setWithObject:stick] withEvent:nil];
    assert(trace.events.count==5 && ![trace.events[4][@"pressed"] boolValue]);
    [trace.events removeAllObjects];
    camera=Touch(CGPointMake(560,100),2);
    [overlay touchesBegan:[NSSet setWithObject:camera] withEvent:nil];
    camera.time=2.1; [overlay touchesEnded:[NSSet setWithObject:camera] withEvent:nil];
    assert(trace.events.count==1 && [trace.events[0][@"kind"] isEqual:@"tap"] &&
        [trace.events[0][@"x"] intValue]==560);
    // App deactivation, switching modes, rotation and removing the view all
    // release held keys/right mouse once. No click is synthesized by cancellation.
    for (unsigned scenario=0; scenario<4; scenario++) {
        overlay.enabled=YES; overlay.frame=CGRectMake(0,0,1000,500);
        if (!overlay.superview) [host addSubview:overlay];
        [overlay layoutIfNeeded]; [trace.events removeAllObjects];
        stick=Touch(CGPointMake(ring.center.x,ring.center.y-40),3);
        camera=Touch(CGPointMake(600,150),3);
        [overlay touchesBegan:[NSSet setWithObject:stick] withEvent:nil];
        [overlay touchesBegan:[NSSet setWithObject:camera] withEvent:nil];
        camera.point=CGPointMake(610,150); camera.time=3.1;
        [overlay touchesMoved:[NSSet setWithObject:camera] withEvent:nil];
        assert(trace.events.count==3);
        if (scenario==0) [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationWillResignActiveNotification object:nil];
        if (scenario==1) overlay.enabled=NO;
        if (scenario==2) { overlay.frame=CGRectMake(0,0,900,450); [overlay layoutIfNeeded]; }
        if (scenario==3) [overlay removeFromSuperview];
        assert(trace.events.count==5 && [trace.events[3][@"kind"] isEqual:@"key"] &&
            ![trace.events[3][@"pressed"] boolValue] && [trace.events[4][@"kind"] isEqual:@"right"] &&
            ![trace.events[4][@"pressed"] boolValue]);
        [overlay cancelTouches]; assert(trace.events.count==5);
    }
    overlay.enabled=NO;
    assert(![overlay pointInside:CGPointMake(600,150) withEvent:nil]);
    puts("TOUCH_ADVENTURE_UI_PASS: hit regions, pointer passthrough, independent fingers and lifecycle releases.");
}

@interface AKAdventureFixtureScene : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
@implementation AKAdventureFixtureScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController=[UIViewController new];
    [self.window makeKeyAndVisible];
    [self performSelector:@selector(run) withObject:nil afterDelay:0.2];
}
- (void)run { TestAdventure(self.window.rootViewController.view); fflush(stdout); exit(0); }
@end
@interface AKAdventureFixtureApp : UIResponder <UIApplicationDelegate>
@end
@implementation AKAdventureFixtureApp
- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)application; (void)options;
    UISceneConfiguration *configuration=[[UISceneConfiguration alloc] initWithName:@"Adventure fixture" sessionRole:session.role];
    configuration.delegateClass=AKAdventureFixtureScene.class; return configuration;
}
@end
int main(int argc,char **argv) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{
            fputs("TOUCH_ADVENTURE_UI_TIMEOUT\n",stderr); _Exit(1);
        });
        return UIApplicationMain(argc,argv,nil,NSStringFromClass(AKAdventureFixtureApp.class));
    }
}
