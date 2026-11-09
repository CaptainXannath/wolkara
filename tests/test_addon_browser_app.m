#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>
#import "../launcher/WoW/AddonBrowser.h"

@interface TKAddonBrowserViewController (Fixture)
- (BOOL)acceptsDownloadURL:(NSURL *)url;
- (BOOL)isBusy;
- (void)cancelDownload;
@end
@interface TKFixtureBrowser : TKAddonBrowserViewController
@end
@implementation TKFixtureBrowser
- (BOOL)acceptsDownloadURL:(NSURL *)url {
    return [super acceptsDownloadURL:url] || ([url.scheme isEqual:@"http"] && [url.host isEqual:@"127.0.0.1"]);
}
@end
static void Await(BOOL (^predicate)(void), const char *message) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:12];
    while (!predicate() && deadline.timeIntervalSinceNow>0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    if (!predicate()) { fprintf(stderr,"ADDON WEB FAIL: %s\n",message); exit(1); }
}
@interface TKBrowserFixture : UIResponder <UIWindowSceneDelegate>
@property(nonatomic) UIWindow *window;
@property(nonatomic) TKFixtureBrowser *browser;
@property(nonatomic) NSURL *base;
@property(nonatomic) NSUInteger received, completed;
@end
@implementation TKBrowserFixture
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)session; (void)options;
    NSArray *args=NSProcessInfo.processInfo.arguments;
    BOOL live=[args containsObject:@"--live"];
    self.base=live ? TKAddonBrowseURL(@"wowf") : [NSURL URLWithString:args.lastObject];
    self.browser=[[TKFixtureBrowser alloc] initWithURL:self.base edition:@"Forever"];
    __weak TKBrowserFixture *weakSelf=self;
    self.browser.installArchive=^(NSURL *url, void (^completion)(NSError *)) {
        TKBrowserFixture *self=weakSelf;
        assert(!live);
        NSData *bytes=[NSData dataWithContentsOfURL:url];
        assert(bytes.length>100 && memcmp(bytes.bytes,"PK\003\004",4)==0);
        assert([url.lastPathComponent isEqual:@"addon.zip"]);
        assert([url.URLByDeletingLastPathComponent.lastPathComponent hasPrefix:@"WolkaraAddon-"]);
        self.received+=1;
        assert(self.browser.isBusy && !self.browser.navigationItem.leftBarButtonItem.enabled);
        assert(!self.browser.navigationController.interactivePopGestureRecognizer.enabled);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(), ^{
            assert([NSFileManager.defaultManager fileExistsAtPath:url.path]);
            self.completed+=1; completion(nil);
        });
    };
    self.window=[[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController=[[UINavigationController alloc] initWithRootViewController:self.browser];
    [self.window makeKeyAndVisible];
    [self performSelector:live?@selector(livePreview):@selector(runTests) withObject:nil afterDelay:1];
}
- (WKWebView *)web { return [self.browser valueForKey:@"webView"]; }
- (void)click:(NSString *)identifier expecting:(NSUInteger)count {
    [self.web evaluateJavaScript:[NSString stringWithFormat:@"document.getElementById('%@').click()",identifier] completionHandler:nil];
    Await(^BOOL { return self.completed==count && !self.browser.isBusy; },identifier.UTF8String);
    assert(self.received==count);
    assert(![self.browser valueForKey:@"jobURL"]);
    assert(self.browser.navigationItem.leftBarButtonItem.enabled);
}
- (void)loadPath:(NSString *)path {
    [self.web loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:path relativeToURL:self.base]]];
}
- (void)runTests {
    Await(^BOOL { return !self.web.isLoading && [self.web.title isEqual:@"Addon download fixture"]; },"fixture page");
    [self click:@"plain" expecting:1];
    [self click:@"attribute" expecting:2];
    [self click:@"popup" expecting:3];
    [self click:@"redirect" expecting:4];
    [self loadPath:@"/slow.zip"];
    Await(^BOOL { return self.browser.isBusy; },"slow download started");
    [self.browser cancelDownload];
    Await(^BOOL { return !self.browser.isBusy; },"cancellation releases navigation");
    assert(self.received==4 && ![self.browser valueForKey:@"jobURL"]);
    for (NSString *path in @[@"/large.zip",@"/error.zip"]) {
        UILabel *status=[self.browser valueForKey:@"status"]; status.text=@"sentinel";
        [self loadPath:path];
        Await(^BOOL { return !self.web.isLoading && !self.browser.isBusy && ![status.text isEqual:@"sentinel"]; },path.UTF8String);
        assert(self.received==4 && ![self.browser valueForKey:@"jobURL"]);
    }
    [self loadPath:@"/html.zip"];
    Await(^BOOL { return !self.web.isLoading && [self.web.title isEqual:@"Not an archive"]; },"HTML with ZIP filename stays a web page");
    assert(self.received==4);
    [self loadPath:@"/addon.zip"];
    Await(^BOOL { return self.completed==5 && !self.browser.isBusy; },"retry after refused response");
    assert(self.received==5 && ![self.browser valueForKey:@"jobURL"]);
    puts("ADDON WEB PASS: real WKDownload links, download attribute, new window, redirects, delayed import, cancellation, HTTP error, size limit, HTML rejection and retry; no API key.");
    fflush(stdout); exit(0);
}
- (void)livePreview {
    // Read-only public page smoke test. No automatic addon install or game execution.
    [self performSelector:@selector(captureLive) withObject:nil afterDelay:45];
}
- (void)captureLive {
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithBounds:self.window.bounds];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        (void)context; [self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES];
    }];
    NSString *path=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES).firstObject stringByAppendingPathComponent:@"addon-web-live.png"];
    assert([UIImagePNGRepresentation(image) writeToFile:path atomically:YES]);
    printf("ADDON WEB LIVE: title=%s\n",self.web.title.UTF8String ?: ""); fflush(stdout); exit(0);
}
@end
@interface TKBrowserFixtureApp : UIResponder <UIApplicationDelegate>
@end
@implementation TKBrowserFixtureApp
- (UISceneConfiguration *)application:(UIApplication *)app configurationForConnectingSceneSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    (void)app; (void)options;
    UISceneConfiguration *configuration=[[UISceneConfiguration alloc] initWithName:@"Addon browser fixture" sessionRole:session.role];
    configuration.delegateClass=TKBrowserFixture.class; return configuration;
}
@end
int main(int argc,char **argv) {
    @autoreleasepool { return UIApplicationMain(argc,argv,nil,NSStringFromClass(TKBrowserFixtureApp.class)); }
}
