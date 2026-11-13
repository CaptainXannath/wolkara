// Only linked into the input fixture's late-loaded library. No game is loaded.
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <assert.h>

extern void AKInstallMetalPresentationDiagnostics(id<MTLDevice> device);
extern void AKRecordMetalFramePresented(double timestamp);
extern bool AKMetalDeviceMemory(uint64_t *allocated,uint64_t *recommended);
void AKLog(NSString *format, ...) { (void)format; }
void AKInstallRenderDiagnostics(Class cls) { (void)cls; }
NSArray *AKRenderStatsForCommand(id command) { (void)command; return @[]; }

@interface AKFixtureMemoryDevice : NSObject
@end
@implementation AKFixtureMemoryDevice
- (NSUInteger)currentAllocatedSize { return 123456; }
- (uint64_t)recommendedMaxWorkingSetSize { return 8589934592ULL; }
@end

static IMP originalDrawable;
void AKTestPrepareLateMetal(void) {
    originalDrawable = class_getMethodImplementation(CAMetalLayer.class, @selector(nextDrawable));
    uint64_t allocated=1, recommended=1;
    assert(!AKMetalDeviceMemory(&allocated,&recommended) && !allocated && !recommended);
    AKInstallMetalPresentationDiagnostics((id)[NSObject new]);
    allocated=recommended=1;
    assert(!AKMetalDeviceMemory(&allocated,&recommended) && !allocated && !recommended);
    AKInstallMetalPresentationDiagnostics((id)[AKFixtureMemoryDevice new]);
    assert(AKMetalDeviceMemory(&allocated,&recommended));
    assert(allocated==123456 && recommended==8589934592ULL);
    assert(AKMetalDeviceMemory(NULL,NULL));
    assert(originalDrawable == class_getMethodImplementation(CAMetalLayer.class, @selector(nextDrawable)));
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    assert(device);
    AKInstallMetalPresentationDiagnostics(device);
    assert(AKMetalDeviceMemory(&allocated,&recommended));
    assert(AKMetalDeviceMemory(NULL,NULL));
    assert(originalDrawable == class_getMethodImplementation(CAMetalLayer.class, @selector(nextDrawable)));
}
void AKTestRecordMetalFrames(void) {
    assert(originalDrawable != class_getMethodImplementation(CAMetalLayer.class, @selector(nextDrawable)));
    // Synthetic timestamps verify the HUD's measurement path, not device FPS.
    double now = CACurrentMediaTime();
    for (NSUInteger i = 0; i < 60; i++) AKRecordMetalFramePresented(now - (59-i)/60.0);
}

extern void AKEnableMetalFrameStatistics(void);
extern void AKDisableMetalFrameStatistics(void);
extern double AKMetalCurrentFPS(void);
extern double AKMetalLastFrameTimeMs(void);
void AKTestMetricIntervals(void) {
    AKDisableMetalFrameStatistics(); AKEnableMetalFrameStatistics();
    double now = CACurrentMediaTime();
    for (NSUInteger i=0;i<60;i++) AKRecordMetalFramePresented(now-(59-i)/60.0);
    assert(fabs(AKMetalCurrentFPS()-60)<0.01 && fabs(AKMetalLastFrameTimeMs()-1000.0/60)<0.01);
    AKRecordMetalFramePresented(NAN); AKRecordMetalFramePresented(now-2); AKRecordMetalFramePresented(now);
    assert(fabs(AKMetalCurrentFPS()-60)<0.01);
    AKDisableMetalFrameStatistics(); AKEnableMetalFrameStatistics();
    assert(AKMetalCurrentFPS()==0 && AKMetalLastFrameTimeMs()==0);
    for (NSUInteger i=0;i<60;i++) AKRecordMetalFramePresented(now-2-(59-i)/60.0);
    assert(AKMetalCurrentFPS()==0); // stale frames must not masquerade as live FPS.
    AKRecordMetalFramePresented(now-1.0/30); AKRecordMetalFramePresented(now);
    assert(fabs(AKMetalCurrentFPS()-30)<0.01);
}
