// Exercises bounded on-disk history and process counters, never guest memory.
#import "../translation/AppKit/MemoryDiagnostics.m"
#include <assert.h>
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
    [NSFileManager.defaultManager removeItemAtURL:url error:nil];
    puts("Memory journal bounded persistence, lifetime extrema and native process counters: PASS");
} }
