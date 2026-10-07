#import "ExternalJITRequest.h"
#include <assert.h>
#include <math.h>

static TKExternalJITRequest *begin(void) {
    TKExternalJITRequest *request=[TKExternalJITRequest new];
    NSURL *url=[request beginForBundle:@"example.wolkara.externaljit" process:1234
        debuggingPermission:YES helperInstalled:YES alreadyAttached:NO atTime:100];
    assert(url && request.state==TKExternalJITOpening);
    NSURLComponents *parts=[NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    assert([parts.scheme isEqual:@"stikdebug"] && [parts.host isEqual:@"enable-jit"]);
    NSMutableDictionary *query=[NSMutableDictionary new];
    for (NSURLQueryItem *item in parts.queryItems) query[item.name]=item.value;
    assert(([query isEqual:@{@"bundle-id":@"example.wolkara.externaljit",@"pid":@"1234",@"script-name":@"universal.js"}]));
    assert(![request beginForBundle:@"other.app" process:99 debuggingPermission:YES helperInstalled:YES alreadyAttached:NO atTime:101]);
    return request;
}
int main(void) {
    @autoreleasepool {
        for (NSUInteger failure=0;failure<3;failure++) {
            TKExternalJITRequest *r=[TKExternalJITRequest new];
            assert(![r beginForBundle:@"example.app" process:123 debuggingPermission:failure!=0
                helperInstalled:failure!=1 alreadyAttached:failure==2 atTime:0]);
            assert(r.state==TKExternalJITFailed && !r.restartRequired);
        }
        for (NSString *bundle in @[@"",@"../bad",@"example.app&script-name=other.js",@"example app",[@"a" stringByPaddingToLength:256 withString:@"a" startingAtIndex:0]]) {
            TKExternalJITRequest *r=[TKExternalJITRequest new];
            assert(![r beginForBundle:bundle process:123 debuggingPermission:YES helperInstalled:YES alreadyAttached:NO atTime:0]);
            assert(r.state==TKExternalJITFailed);
        }
        TKExternalJITRequest *r=[TKExternalJITRequest new];
        assert(![r beginForBundle:@"example.app" process:0 debuggingPermission:YES helperInstalled:YES alreadyAttached:NO atTime:0]);
        r=[TKExternalJITRequest new];
        assert(![r beginForBundle:@"example.app" process:1 debuggingPermission:YES helperInstalled:YES alreadyAttached:NO atTime:NAN]);
        r=begin(); [r opened:NO];
        assert(r.state==TKExternalJITFailed && !r.restartRequired);
        [r opened:YES]; [r prepared:YES detached:YES];
        assert(r.state==TKExternalJITFailed);
        r=begin(); [r opened:YES];
        assert(r.state==TKExternalJITWaiting && r.restartRequired);
        assert(![r pollAtTime:101 attached:NO prepared:NO]);
        assert(r.state==TKExternalJITWaiting); // URL acceptance proves nothing.
        assert([r pollAtTime:102 attached:YES prepared:NO]);
        assert(![r pollAtTime:103 attached:YES prepared:NO]); // Exactly one worker.
        [r prepared:YES detached:NO]; assert(r.state==TKExternalJITFailed);
        [r prepared:YES detached:YES]; assert(r.state==TKExternalJITFailed);
        r=begin(); [r opened:YES]; assert([r pollAtTime:101 attached:YES prepared:NO]);
        [r prepared:NO detached:YES]; assert(r.state==TKExternalJITFailed);
        r=begin(); [r opened:YES]; assert([r pollAtTime:101 attached:YES prepared:NO]);
        [r prepared:YES detached:YES]; assert(r.state==TKExternalJITReady);
        assert(![r pollAtTime:1000 attached:YES prepared:NO]);
        for (NSUInteger stage=0;stage<3;stage++) {
            r=begin();
            if (stage>0) [r opened:YES];
            if (stage>1) assert([r pollAtTime:101 attached:YES prepared:NO]);
            assert(![r pollAtTime:400 attached:YES prepared:YES]);
            assert(r.state==TKExternalJITFailed && r.restartRequired);
            [r opened:YES]; [r prepared:YES detached:YES];
            assert(r.state==TKExternalJITFailed); // Late helpers cannot revive timeout.
        }
        r=begin(); [r opened:YES]; [r cancel];
        assert(r.state==TKExternalJITFailed && r.restartRequired);
        assert(![r pollAtTime:102 attached:YES prepared:YES]);
        r=begin(); [r opened:YES];
        assert(![r pollAtTime:NAN attached:YES prepared:NO]);
        assert(r.state==TKExternalJITFailed);
        puts("external JIT request: PASS");
    }
    return 0;
}
