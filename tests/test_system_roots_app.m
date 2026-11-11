// Run the same checks from an iOS app so NSBundle resolves the shipped fallback.
#define main TKRunSystemRootTests
#include "test_system_roots.m"
#undef main
#import <UIKit/UIKit.h>
#include <stdlib.h>

@interface TKSystemRootsTestDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic) UIWindow *window;
@end
@implementation TKSystemRootsTestDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application; (void)options;
    self.window=[[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController=[UIViewController new];
    [self.window makeKeyAndVisible];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
        const char *arguments[]={"system-roots-tests","--bundled"};
        int result=TKRunSystemRootTests(2,arguments);
        fflush(stdout);fflush(stderr);exit(result);
    });
    return YES;
}
@end
int main(int argc,char **argv) {
    @autoreleasepool {
        return UIApplicationMain(argc,argv,nil,NSStringFromClass(TKSystemRootsTestDelegate.class));
    }
}
