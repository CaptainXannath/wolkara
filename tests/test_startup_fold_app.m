// UIKit-only startup regression. No imported executable, game input or debugger.
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "StartupActivity.h"
#include "GuestWait.h"
#include <assert.h>

@interface FoldProbeController : UIViewController @end
@implementation FoldProbeController
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskAll; }
@end
@interface FoldProbe : UIResponder <UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@property NSTimer *timer;
@property UIView *panel;
@property NSUInteger ticks, geometryUpdates, requested, errors;
@property double began, lastTick, longestGap;
@property BOOL waiting;
@end
@implementation FoldProbe
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    FoldProbeController *controller=[FoldProbeController new];
    controller.view.backgroundColor=UIColor.systemBackgroundColor;
    self.panel=[[UIView alloc] initWithFrame:CGRectMake(10,10,200,100)];
    self.panel.backgroundColor=UIColor.systemCyanColor; [controller.view addSubview:self.panel];
    self.window.rootViewController=controller; [self.window makeKeyAndVisible];
    [self performSelector:@selector(runProbe) withObject:nil afterDelay:.5];
}
- (void)windowScene:(UIWindowScene *)scene didUpdateCoordinateSpace:(id<UICoordinateSpace>)space
    interfaceOrientation:(UIInterfaceOrientation)orientation traitCollection:(UITraitCollection *)traits {
    (void)scene; (void)space; (void)orientation; (void)traits;
    if (self.waiting) self.geometryUpdates++;
}
- (void)runProbe {
    self.waiting=YES; self.began=self.lastTick=CACurrentMediaTime();
    __weak FoldProbe *weakSelf=self;
    self.timer=[NSTimer scheduledTimerWithTimeInterval:.04 repeats:YES block:^(NSTimer *timer) {
        (void)timer; FoldProbe *self=weakSelf; if (!self) return;
        double now=CACurrentMediaTime(); self.longestGap=MAX(self.longestGap,now-self.lastTick); self.lastTick=now; self.ticks++;
        // Exercise layout/commit while an original main-thread startup is asleep.
        self.panel.frame=self.ticks%2 ? CGRectMake(10,10,180,240) : CGRectMake(10,10,320,150);
        [self.window.rootViewController.view layoutIfNeeded];
        if (self.requested<6 && now-self.began>.25+self.requested*.6) {
            UIInterfaceOrientationMask mask=self.requested%2 ? UIInterfaceOrientationMaskLandscapeRight : UIInterfaceOrientationMaskPortrait;
            self.requested++;
            UIWindowSceneGeometryPreferencesIOS *preferences=[[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:mask];
            [self.window.windowScene requestGeometryUpdateWithPreferences:preferences errorHandler:^(NSError *error) {
                (void)error; weakSelf.errors++;
            }];
        }
    }];
    gw_set_startup_pump(TKPumpStartupUI);
    struct timespec request={6,0};
    BOOL original=[NSProcessInfo.processInfo.arguments containsObject:@"--native-sleep"];
    assert(!(original ? nanosleep(&request,NULL) : gw_nanosleep(&request,NULL)));
    self.waiting=NO; [self.timer invalidate];
    fprintf(stderr,"STARTUP_FOLD_COUNTS ticks=%lu geometry=%lu requests=%lu errors=%lu max_gap_ms=%.1f\n",
        (unsigned long)self.ticks,(unsigned long)self.geometryUpdates,(unsigned long)self.requested,(unsigned long)self.errors,self.longestGap*1000);
    assert(self.ticks>50 && self.geometryUpdates>=2 && self.requested==6 && !self.errors && self.longestGap<1);
    assert(CACurrentMediaTime()-self.began>=6);
    // Once the guest window is ready the launcher removes this policy.
    gw_set_startup_pump(NULL); NSUInteger ticks=self.ticks;
    assert(!gw_usleep(50000) && self.ticks==ticks);
    puts("STARTUP_FOLD_UI_PASS: UIKit timers, scene rotations and layout progress during a six-second main-thread startup wait; normal sleeps after readiness.");
    fflush(stdout); exit(0);
}
@end
@interface FoldProbeApplication : UIResponder <UIApplicationDelegate> @end
@implementation FoldProbeApplication
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)app; (void)options;
    UISceneConfiguration *configuration=[[UISceneConfiguration alloc] initWithName:@"Fold probe" sessionRole:session.role];
    configuration.delegateClass=FoldProbe.class; return configuration;
}
@end
int main(int argc,char **argv) { @autoreleasepool {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC),dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        fputs("STARTUP_FOLD_UI_TIMEOUT\n",stderr); _Exit(1);
    });
    return UIApplicationMain(argc,argv,nil,NSStringFromClass(FoldProbeApplication.class));
} }
