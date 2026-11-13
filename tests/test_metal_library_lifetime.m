// Original loader fixture; no third-party shaders or application code.
#import "../translation/Metal/Devices.m"
#include <assert.h>
extern void AKFixtureAutoreleaseTemporary(void);
extern unsigned AKFixtureLiveTemporaries(void);
void AKInstallMetalPresentationDiagnostics(id<MTLDevice> device) { (void)device; }
void AKInstallManagedStorage(Class device) { (void)device; }
static BOOL failLoad;
static BOOL raiseLoad;
static void assertCounters(uint64_t hits,uint64_t misses,uint64_t loads,uint64_t inFlight,uint64_t purges) {
    uint64_t actual[5]={0};
    AKMetalLibraryCounters(&actual[0],&actual[1],&actual[2],&actual[3],&actual[4]);
    assert(actual[0]==hits && actual[1]==misses && actual[2]==loads && actual[3]==inFlight && actual[4]==purges);
}
static id<MTLLibrary> fixtureLoad(id device,SEL selector,dispatch_data_t data,NSError *__autoreleasing *error) __attribute__((ns_returns_retained));
static id<MTLLibrary> fixtureLoad(id device,SEL selector,dispatch_data_t data,NSError *__autoreleasing *error) {
    (void)device; (void)selector; (void)data;
    uint64_t inFlight=0;
    AKMetalLibraryCounters(NULL,NULL,NULL,&inFlight,NULL);
    assert(inFlight==1);
    AKFixtureAutoreleaseTemporary();
    if (raiseLoad) [NSException raise:@"Fixture" format:@"synthetic native loader exception"];
    if (failLoad) { if (error) *error=[NSError errorWithDomain:@"Fixture" code:7 userInfo:nil]; return nil; }
    if (error) *error=nil;
    return (id)[NSObject new];
}
int main(void) { @autoreleasepool {
    originalLibraryLoader=fixtureLoad;
    assertCounters(0,0,0,0,0);
    AKMetalLibraryCounters(NULL,NULL,NULL,NULL,NULL);
    NSObject *device=[NSObject new];
    // Zero-sized input takes the transparent native fallback, exercising the
    // same pool boundary without creating any files or translating a shader.
    for (unsigned i=0;i<1000;i++) {
        NSError *error=nil;
        id library=captureLibrary(device,@selector(newLibraryWithData:error:),dispatch_data_empty,&error);
        assert(library && !error);
        assert(AKFixtureLiveTemporaries()==0);
    }
    assertCounters(0,0,1000,0,0);
    failLoad=YES;
    NSError *error=nil;
    assert(!captureLibrary(device,@selector(newLibraryWithData:error:),dispatch_data_empty,&error));
    assert([error.domain isEqual:@"Fixture"] && error.code==7);
    assert(AKFixtureLiveTemporaries()==0);
    assertCounters(0,0,1001,0,0);
    failLoad=NO;
    const unsigned char fixtureBytes[]={1,2,3};
    dispatch_data_t input=dispatch_data_create(fixtureBytes,sizeof fixtureBytes,NULL,DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(fixtureBytes,sizeof fixtureBytes,digest);
    NSMutableString *key=[NSMutableString new];
    for (unsigned i=0;i<sizeof digest;i++) [key appendFormat:@"%02x",digest[i]];
    __weak NSObject *hitResult;
    @autoreleasepool {
        NSObject *library=[NSObject new]; hitResult=library;
        [libraryCache((id)device) setObject:(id)library forKey:key];
        error=[NSError errorWithDomain:@"Previous" code:1 userInfo:nil];
        id result=captureLibrary(device,@selector(newLibraryWithData:error:),input,&error);
        assert(result==library && !error && !AKFixtureLiveTemporaries());
        assertCounters(1,0,1001,0,0);
        [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:nil];
        assert(result==hitResult); // A caller still owns its result after purge.
    }
    assert(!hitResult);
    assert(captureLibrary(device,@selector(newLibraryWithData:error:),input,&error) && !error);
    assert(!AKFixtureLiveTemporaries());
    assertCounters(1,1,1002,0,1);
    raiseLoad=YES;
    BOOL caught=NO;
    @try { (void)captureLibrary(device,@selector(newLibraryWithData:error:),dispatch_data_empty,NULL); }
    @catch (NSException *exception) { caught=[exception.name isEqual:@"Fixture"]; }
    assert(caught && !AKFixtureLiveTemporaries());
    assertCounters(1,1,1003,0,1);
    __weak NSObject *cached;
    @autoreleasepool {
        NSObject *library=[NSObject new]; cached=library;
        [libraryCache((id)device) setObject:(id)library forKey:@"fixture"];
    }
    assert(cached);
    [NSNotificationCenter.defaultCenter postNotificationName:UIApplicationDidReceiveMemoryWarningNotification object:nil];
    assert(!cached);
    assertCounters(1,1,1003,0,2);
    puts("Metal library counters, temporaries and retained result/error lifetime: PASS");
} }
