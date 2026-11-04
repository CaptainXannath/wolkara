#import "AKSupport.h"
#import <objc/runtime.h>
#include <dlfcn.h>

void AKLogC(const char *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    fputs("[ak] ", stderr); vfprintf(stderr, fmt, ap); fputc('\n', stderr);
    va_end(ap);
}

void AKLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *s = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    fprintf(stderr, "[ak] %s\n", s.UTF8String);
}

void AKStubHit(const char *symbol, void *caller) {
    Dl_info info = {0};
    dladdr(caller, &info);
    AKLogC("STUB %s() called from %p %s+%#lx", symbol, caller, info.dli_fname ? strrchr(info.dli_fname, '/') + 1 : "?",
           info.dli_fbase ? (unsigned long)((char *)caller - (char *)info.dli_fbase) : 0UL);
}

@implementation AKStubObject
static void forward(id self, NSInvocation *inv) {
    static NSMutableSet *seen; static dispatch_once_t once;
    dispatch_once(&once, ^{ seen = [NSMutableSet new]; });
    NSString *key = [NSString stringWithFormat:@"%c[%@ %@]", object_isClass(self) ? '+' : '-',
                     NSStringFromClass(object_getClass(self)), NSStringFromSelector(inv.selector)];
    @synchronized (seen) { if (![seen containsObject:key]) { [seen addObject:key]; AKLog(@"UNIMPLEMENTED %@", key); } }
    id zero = nil; [inv setReturnValue:&zero];
}
// Unknown selector: pretend it is `id f(id, SEL)`. Extra arguments are ignored by
// the callee on arm64; struct/float returns are NOT zeroed (discovery aid only).
- (NSMethodSignature *)methodSignatureForSelector:(SEL)s { return [super methodSignatureForSelector:s] ?: [NSMethodSignature signatureWithObjCTypes:"@@:"]; }
+ (NSMethodSignature *)methodSignatureForSelector:(SEL)s { return [super methodSignatureForSelector:s] ?: [NSMethodSignature signatureWithObjCTypes:"@@:"]; }
- (void)forwardInvocation:(NSInvocation *)i { forward(self, i); }
+ (void)forwardInvocation:(NSInvocation *)i { forward(self, i); }
@end

@implementation AKQuartzEvent { NSMutableDictionary<NSNumber *, NSNumber *> *_fields; }
- (instancetype)init { if ((self = [super init])) _fields = [NSMutableDictionary new]; return self; }
// A field reads as either kind, as Quartz converts between them; unset is zero.
- (int64_t)integerValueField:(uint32_t)field { @synchronized (self) { return _fields[@(field)].longLongValue; } }
- (double)doubleValueField:(uint32_t)field { @synchronized (self) { return _fields[@(field)].doubleValue; } }
- (void)setIntegerValueField:(uint32_t)field value:(int64_t)value { @synchronized (self) { _fields[@(field)] = @(value); } }
- (void)setDoubleValueField:(uint32_t)field value:(double)value { @synchronized (self) { _fields[@(field)] = @(value); } }
@end

#include <stdatomic.h>
static atomic_uint cursorHideCount;
bool AKCursorIsHidden(void) { return atomic_load(&cursorHideCount)>0; }
void AKCursorHide(void) { atomic_fetch_add(&cursorHideCount,1); }
void AKCursorUnhide(void) { unsigned count=atomic_load(&cursorHideCount); while(count && !atomic_compare_exchange_weak(&cursorHideCount,&count,count-1)) {} }
static atomic_bool mouseCaptured;
bool AKMouseIsCaptured(void) { return atomic_load(&mouseCaptured); }
void AKMouseSetCaptured(bool captured) {
    if(atomic_exchange(&mouseCaptured,captured)!=captured)
        [NSNotificationCenter.defaultCenter postNotificationName:@"AKMouseCaptureDidChange" object:nil];
}

// Keep AppKit and CoreGraphics on exactly the same scale, including fractional
// performance scales. The launcher writes its selection before guest startup.
CGFloat AKConfiguredGuestBackingScale(void) {
    static CGFloat scale;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const char *environment=getenv("TOLKARA_BACKING_SCALE");
        id stored=[NSUserDefaults.standardUserDefaults objectForKey:@"WolkaraBackingScale"];
        CGFloat requested=environment && *environment ? atof(environment)
            : [stored respondsToSelector:@selector(doubleValue)] ? [stored doubleValue] : 2.0;
        scale=isfinite(requested) && requested>=0.5 && requested<=3.0 ? requested : 2.0;
    });
    return scale;
}

static CGSize guestDisplaySize;
static double guestDisplayRefresh;
BOOL AKGetGuestDisplayGeometry(CGSize *size, double *refresh) {
    @synchronized(AKStubObject.class) {
        if (guestDisplaySize.width<=0 || guestDisplaySize.height<=0) return NO;
        if (size) *size=guestDisplaySize;
        if (refresh) *refresh=guestDisplayRefresh;
        return YES;
    }
}
void AKSetGuestDisplayGeometry(CGSize size, double refresh) {
    if (!isfinite(size.width) || !isfinite(size.height) || size.width<=0 || size.height<=0
        || !isfinite(refresh) || refresh<=0) return;
    BOOL changed;
    @synchronized(AKStubObject.class) {
        changed=!CGSizeEqualToSize(size,guestDisplaySize) || refresh!=guestDisplayRefresh;
        guestDisplaySize=size; guestDisplayRefresh=refresh;
    }
    // Publish after releasing the lock: guest callbacks may query the new mode.
    if (changed) [NSNotificationCenter.defaultCenter postNotificationName:@"AKGuestDisplayDidChange" object:nil];
}
