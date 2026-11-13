// Exercises bounded on-disk history and process counters, never guest memory.
#import "../translation/AppKit/MemoryDiagnostics.m"
#include <assert.h>
#include <string.h>
static BOOL lateMetalLoaded, deviceMetricsAvailable;
static unsigned lookups;
static bool fixtureDeviceMemory(uint64_t *allocated,uint64_t *recommended) {
    *allocated=123456; *recommended=8589934592ULL;
    return deviceMetricsAvailable;
}
static void fixtureLibraryCounters(uint64_t *hits,uint64_t *misses,uint64_t *loads,uint64_t *inFlight,uint64_t *purges) {
    *hits=10; *misses=20; *loads=21; *inFlight=2; *purges=1;
}
static void *fixtureLookup(void *handle,const char *name) {
    assert(handle==RTLD_DEFAULT); lookups++;
    if (!lateMetalLoaded) return NULL;
    if (!strcmp(name,"AKMetalDeviceMemory")) return (void *)fixtureDeviceMemory;
    if (!strcmp(name,"AKMetalLibraryCounters")) return (void *)fixtureLibraryCounters;
    assert(false); return NULL;
}
int main(void) { @autoreleasepool {
    NSURL *url=[NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    AKMemoryJournal *journal=[[AKMemoryJournal alloc] initWithURL:url];
    for (unsigned i=1;i<=500;i++) @autoreleasepool {
        [journal append:@{@"event":(i==5 || i==490)?@"memory_warning":@"sample",
            @"footprint_bytes":@(i*1024), @"available_bytes":@((500-i)*1024), @"sequence":@(i)}];
    }
    NSDictionary *saved=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:nil];
    NSArray *samples=saved[@"samples"];
    assert(samples.count==120 && [samples.firstObject[@"sequence"] unsignedIntValue]==381);
    assert([samples.lastObject[@"sequence"] unsignedIntValue]==500);
    assert([saved[@"peak_footprint_bytes"] unsignedLongLongValue]==512000);
    assert([saved[@"lowest_available_bytes"] unsignedLongLongValue]==0);
    assert([saved[@"memory_warnings"] unsignedIntValue]==2);
    NSDictionary *actual=memorySample(@"fixture",YES);
    assert(actual[@"available_bytes"] && [actual[@"footprint_bytes"] unsignedLongLongValue]>0);
    assert(!actual[@"query_error"] && [actual[@"foreground"] boolValue]);
    NSDictionary *missing=memorySampleWithLookup(@"fixture",YES,fixtureLookup);
    assert(lookups==2 && !missing[@"metal_allocated_bytes"] && !missing[@"metal_library_native_loads"]);
    lateMetalLoaded=YES;
    NSDictionary *unavailable=memorySampleWithLookup(@"fixture",YES,fixtureLookup);
    assert(lookups==4 && !unavailable[@"metal_allocated_bytes"] && !unavailable[@"metal_recommended_working_set_bytes"]);
    assert([unavailable[@"metal_library_requests_in_flight"] unsignedLongLongValue]==2);
    deviceMetricsAvailable=YES;
    NSDictionary *metal=memorySampleWithLookup(@"fixture",YES,fixtureLookup);
    assert(lookups==6 && [metal[@"metal_allocated_bytes"] unsignedLongLongValue]==123456);
    assert([metal[@"metal_recommended_working_set_bytes"] unsignedLongLongValue]==8589934592ULL);
    assert([metal[@"metal_library_cache_hits"] unsignedLongLongValue]==10);
    assert([metal[@"metal_library_cache_misses"] unsignedLongLongValue]==20);
    assert([metal[@"metal_library_native_loads"] unsignedLongLongValue]==21);
    assert([metal[@"metal_library_cache_purges"] unsignedLongLongValue]==1);
    [journal append:metal];
    saved=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:nil];
    assert([saved[@"samples"] count]==120);
    assert([saved[@"samples"] lastObject][@"metal_allocated_bytes"]);
    assert([saved[@"memory_warnings"] unsignedIntValue]==2);
    assert([saved[@"lowest_available_bytes"] unsignedLongLongValue]==0);
    assert([saved[@"peak_footprint_bytes"] unsignedLongLongValue]>=512000);
    [NSFileManager.defaultManager removeItemAtURL:url error:nil];
    puts("Memory journal bounded persistence, lifetime extrema, late optional Metal and native process counters: PASS");
} }
