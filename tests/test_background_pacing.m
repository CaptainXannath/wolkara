// Synthetic drawable and lifecycle events; never starts an imported client.
#import "../translation/Metal/BackgroundPacing.m"
#include <assert.h>

static id<CAMetalDrawable> FakeDrawable(id object, SEL selector) { (void)object; (void)selector; return nil; }
int main(void) {
    @autoreleasepool {
        originalNextDrawable=FakeDrawable;
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidEnterBackgroundNotification object:nil];
        atomic_store(&lastAcquired,NSProcessInfo.processInfo.systemUptime);
        double started=NSProcessInfo.processInfo.systemUptime;
        pacedNextDrawable(nil,NULL);
        assert(NSProcessInfo.processInfo.systemUptime-started>=0.15);
        assert(atomic_load(&throttling));

        // Foregrounding during a wait releases it instead of inheriting the deadline.
        atomic_store(&lastAcquired,NSProcessInfo.processInfo.systemUptime+1);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_MSEC),dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidBecomeActiveNotification object:nil];
        });
        started=NSProcessInfo.processInfo.systemUptime;
        pacedNextDrawable(nil,NULL);
        assert(!atomic_load(&throttling));
        assert(NSProcessInfo.processInfo.systemUptime-started<0.5);
        assert(!atomic_load(&foregroundDrawablePending));
        atomic_store(&lastAcquired,NSProcessInfo.processInfo.systemUptime+10);
        started=NSProcessInfo.processInfo.systemUptime;
        pacedNextDrawable(nil,NULL);
        assert(NSProcessInfo.processInfo.systemUptime-started<0.5);
        puts("BACKGROUND_PACING_PASS: inactive cap, foreground wakeup and no foreground deadline");
    }
    return 0;
}
