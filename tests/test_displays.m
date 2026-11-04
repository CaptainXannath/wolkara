// The Core Graphics adapter's one display, as Wine's Mac driver queries and
// captures it; run in the simulator (tools/test_translation_sim.sh).
#import <UIKit/UIKit.h>
#import <Metal/Metal.h>
#include <assert.h>
#import "AKSupport.h"
typedef uint32_t CGDirectDisplayID;
typedef CFDictionaryRef CGDisplayModeRef;
extern CGError CGGetOnlineDisplayList(uint32_t, CGDirectDisplayID *, uint32_t *);
extern CGSize CGDisplayScreenSize(CGDirectDisplayID);
extern uint32_t CGDisplayIDToOpenGLDisplayMask(CGDirectDisplayID);
extern CGDirectDisplayID CGOpenGLDisplayMaskToDisplayID(uint32_t);
extern CGDirectDisplayID CGDisplayMirrorsDisplay(CGDirectDisplayID);
extern id<MTLDevice> CGDirectDisplayCopyCurrentMetalDevice(CGDirectDisplayID);
extern CGError CGCaptureAllDisplays(void), CGReleaseAllDisplays(void);
extern int32_t CGShieldingWindowLevel(void);
extern CGDisplayModeRef CGDisplayCopyDisplayMode(CGDirectDisplayID), CGDisplayModeRetain(CGDisplayModeRef);
extern void CGDisplayModeRelease(CGDisplayModeRef);
extern bool CGDisplayModeIsUsableForDesktopGUI(CGDisplayModeRef);
extern CGError CGDisplaySetDisplayMode(CGDirectDisplayID, CGDisplayModeRef, CFDictionaryRef);
extern CGError CGDisplayRegisterReconfigurationCallback(void (*)(uint32_t,uint32_t,void *),void *);
extern CGError CGDisplayRemoveReconfigurationCallback(void (*)(uint32_t,uint32_t,void *),void *);
static unsigned changes;
static void DisplayChanged(uint32_t display,uint32_t flags,void *context) {
    assert(display==1 && (flags&(1<<4)) && context==&changes);
    CGDisplayModeRef mode=CGDisplayCopyDisplayMode(1); // callback can safely reenter
    assert(mode); CGDisplayModeRelease(mode); changes++;
}
int main(void) { @autoreleasepool {
    CGDirectDisplayID displays[2]={0}; uint32_t count=0;
    assert(CGGetOnlineDisplayList(2,displays,&count)==kCGErrorSuccess && count==1 && displays[0]==1);
    assert(CGGetOnlineDisplayList(0,NULL,&count)==kCGErrorSuccess && count==1);
    assert(CGGetOnlineDisplayList(1,NULL,&count)==kCGErrorIllegalArgument);
    // 132 points an inch, in millimetres.
    CGSize points=UIScreen.mainScreen.bounds.size, size=CGDisplayScreenSize(1);
    assert(fabs(size.width-points.width*25.4/132)<0.01 && fabs(size.height-points.height*25.4/132)<0.01);
    assert(CGSizeEqualToSize(CGDisplayScreenSize(2),CGSizeZero));
    assert(CGDisplayIDToOpenGLDisplayMask(1)==1 && CGOpenGLDisplayMaskToDisplayID(1)==1 && !CGOpenGLDisplayMaskToDisplayID(2) && !CGDisplayIDToOpenGLDisplayMask(2));
    assert(!CGDisplayMirrorsDisplay(1) && CGDirectDisplayCopyCurrentMetalDevice(1) && !CGDirectDisplayCopyCurrentMetalDevice(2));
    assert(CGCaptureAllDisplays()==kCGErrorSuccess && CGReleaseAllDisplays()==kCGErrorSuccess && CGShieldingWindowLevel()>0);
    // The screen's own mode is the only one to set.
    CGDisplayModeRef mode=CGDisplayCopyDisplayMode(1); assert(mode && CGDisplayModeIsUsableForDesktopGUI(mode));
    assert(CGDisplayModeRetain(mode)==mode); CGDisplayModeRelease(mode);
    assert(CGDisplaySetDisplayMode(1,mode,NULL)==kCGErrorSuccess);
    NSMutableDictionary *other=[(__bridge NSDictionary *)mode mutableCopy]; other[@"width"]=@800;
    assert(CGDisplaySetDisplayMode(1,(__bridge CGDisplayModeRef)other,NULL)==kCGErrorIllegalArgument);
    assert(CGDisplaySetDisplayMode(2,mode,NULL)==kCGErrorIllegalArgument && CGDisplaySetDisplayMode(1,NULL,NULL)==kCGErrorIllegalArgument);
    CGDisplayModeRelease(mode);
    // Pro, Pro Max, and both observed Duo viewports; then rotate and unfold.
    const CGSize viewports[]={ {852,393},{956,440},{678,466},{951,669},{669,951} };
    CGFloat scale=AKConfiguredGuestBackingScale();
    const char *raw=getenv("TOLKARA_BACKING_SCALE");
    CGFloat requested=raw?atof(raw):2;
    CGFloat expected=isfinite(requested) && requested>=0.5 && requested<=3 ? requested : 2;
    assert(scale==expected && AKConfiguredGuestBackingScale()==expected);
    assert(CGDisplayRegisterReconfigurationCallback(DisplayChanged,&changes)==kCGErrorSuccess);
    for (NSUInteger i=0;i<sizeof(viewports)/sizeof(viewports[0]);i++) {
        CGDisplayModeRef before=CGDisplayCopyDisplayMode(1);
        AKSetGuestDisplayGeometry(viewports[i],120);
        CGDisplayModeRef after=CGDisplayCopyDisplayMode(1);
        NSDictionary *m=(__bridge NSDictionary *)after;
        assert([m[@"width"] doubleValue]==viewports[i].width);
        assert([m[@"height"] doubleValue]==viewports[i].height);
        assert([m[@"pixelWidth"] doubleValue]==round(viewports[i].width*scale));
        assert([m[@"pixelHeight"] doubleValue]==round(viewports[i].height*scale));
        assert(CGDisplaySetDisplayMode(1,after,NULL)==kCGErrorSuccess);
        assert(CGDisplaySetDisplayMode(1,before,NULL)==kCGErrorIllegalArgument);
        CGDisplayModeRelease(before); CGDisplayModeRelease(after);
    }
    assert(changes==5);
    AKSetGuestDisplayGeometry(viewports[4],120);
    assert(changes==5); // unchanged layouts do not flood guest callbacks
    assert(CGDisplayRemoveReconfigurationCallback(DisplayChanged,&changes)==kCGErrorSuccess);
    AKSetGuestDisplayGeometry(CGSizeMake(NAN,0),120);
    CGSize retained; assert(AKGetGuestDisplayGeometry(&retained,NULL));
    assert(CGSizeEqualToSize(retained,viewports[4]));
    puts("online displays, physical size, OpenGL masks, capture and display modes: PASS");
} }
