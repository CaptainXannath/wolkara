#import "AddonBrowser.h"
#import "../App/WKLocalization.h"
#import "../App/WolkaraForeverTheme.h"

static int64_t const ArchiveLimit=128LL*1024*1024;
BOOL TKAddonDownloadURLIsTrusted(NSURL *url) {
    if (![url.scheme.lowercaseString isEqual:@"https"] || url.user.length || url.password.length) return NO;
    NSString *host=url.host.lowercaseString;
    return [host isEqual:@"curseforge.com"] || [host hasSuffix:@".curseforge.com"] ||
           [host isEqual:@"forgecdn.net"] || [host hasSuffix:@".forgecdn.net"];
}
BOOL TKAddonResponseIsZIP(NSURLResponse *response) {
    NSString *mime=response.MIMEType.lowercaseString ?: @"";
    if ([mime hasPrefix:@"text/"] || [mime containsString:@"html"] || [mime containsString:@"json"]) return NO;
    return [mime isEqual:@"application/zip"] || [mime isEqual:@"application/x-zip-compressed"] ||
        [response.suggestedFilename.pathExtension.lowercaseString isEqual:@"zip"] ||
        [response.URL.pathExtension.lowercaseString isEqual:@"zip"];
}
NSURL *TKAddonBrowseURL(NSString *product) {
    // The public site's Forever filter, observed on 2026-11-09. Other editions can
    // choose their flavor on the site; do not invent provider version identifiers.
    NSString *url=[product isEqual:@"wowf"]
        ? @"https://www.curseforge.com/wow/search?class=addons&gameVersionTypeId=88568"
        : @"https://www.curseforge.com/wow/addons";
    return [NSURL URLWithString:url];
}

@interface TKAddonBrowserViewController () <WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate>
@property(nonatomic) WKWebView *webView;
@property(nonatomic) NSURL *startURL;
@property(nonatomic,copy) NSString *edition;
@property(nonatomic) WKDownload *download;
@property(nonatomic) NSURL *downloadURL;
@property(nonatomic) NSURL *jobURL;
@property(nonatomic) NSTimer *progressTimer;
@property(nonatomic) UILabel *status;
@property(nonatomic) UIProgressView *progressView;
@property(nonatomic) UIBarButtonItem *backItem, *forwardItem, *reloadItem, *homeItem, *cancelItem;
@property(nonatomic) BOOL importing, cancelling, previousPopEnabled, previousModal;
@property(nonatomic) BOOL hasResult;
@end

@implementation TKAddonBrowserViewController
- (instancetype)initWithURL:(NSURL *)url edition:(NSString *)edition {
    if (!(self=[super init])) return nil;
    _startURL=url; _edition=edition.copy; self.title=@"CurseForge";
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.view.backgroundColor=WKInk();
    self.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:WKLocalized(@"common.done") style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    _cancelItem=[[UIBarButtonItem alloc] initWithTitle:WKLocalized(@"common.cancel") style:UIBarButtonItemStylePlain target:self action:@selector(cancelDownload)];
    _cancelItem.accessibilityIdentifier=@"wow.addons.browser.cancel";
    self.navigationItem.rightBarButtonItem=_cancelItem;
    WKWebViewConfiguration *configuration=[WKWebViewConfiguration new];
    _webView=[[WKWebView alloc] initWithFrame:CGRectZero configuration:configuration];
    _webView.navigationDelegate=self; _webView.UIDelegate=self;
    _webView.allowsBackForwardNavigationGestures=YES;
    _webView.accessibilityIdentifier=@"wow.addons.browser";
    _webView.translatesAutoresizingMaskIntoConstraints=NO;
    _status=WKLabel(13,UIFontWeightRegular,WKMuted());
    _status.accessibilityIdentifier=@"wow.addons.browser.status";
    _status.text=WKLocalizedFormat(@"addons.web.hint",_edition);
    _status.translatesAutoresizingMaskIntoConstraints=NO;
    _progressView=[UIProgressView new]; _progressView.translatesAutoresizingMaskIntoConstraints=NO;
    UIToolbar *bar=[UIToolbar new]; bar.translatesAutoresizingMaskIntoConstraints=NO;
    _backItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"chevron.left"] style:UIBarButtonItemStylePlain target:self action:@selector(back)];
    _forwardItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"] style:UIBarButtonItemStylePlain target:self action:@selector(forward)];
    _reloadItem=[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reload)];
    _homeItem=[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"house"] style:UIBarButtonItemStylePlain target:self action:@selector(home)];
    _backItem.accessibilityLabel=WKLocalized(@"addons.web.back");
    _forwardItem.accessibilityLabel=WKLocalized(@"addons.web.forward");
    _homeItem.accessibilityLabel=WKLocalized(@"addons.web.home");
    bar.items=@[_backItem,[UIBarButtonItem flexibleSpaceItem],_forwardItem,[UIBarButtonItem flexibleSpaceItem],_reloadItem,[UIBarButtonItem flexibleSpaceItem],_homeItem];
    for (UIView *view in @[_webView,_status,_progressView,bar]) [self.view addSubview:view];
    UILayoutGuide *safe=self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [_webView.topAnchor constraintEqualToAnchor:safe.topAnchor],
        [_webView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [_webView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [_webView.bottomAnchor constraintEqualToAnchor:_progressView.topAnchor],
        [_progressView.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [_progressView.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [_progressView.bottomAnchor constraintEqualToAnchor:_status.topAnchor constant:-6],
        [_status.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
        [_status.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
        [_status.bottomAnchor constraintEqualToAnchor:bar.topAnchor constant:-6],
        [bar.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor],
        [bar.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor],
        [bar.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor],
        [bar.heightAnchor constraintEqualToConstant:44],
    ]];
    [self updateControls];
    [_webView loadRequest:[NSURLRequest requestWithURL:_startURL]];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.previousPopEnabled=self.navigationController.interactivePopGestureRecognizer.enabled;
    self.previousModal=self.navigationController.modalInPresentation;
    [self updateControls];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    self.navigationController.interactivePopGestureRecognizer.enabled=self.previousPopEnabled;
    self.navigationController.modalInPresentation=self.previousModal;
}
- (BOOL)isBusy { return _download!=nil || _importing; }
- (void)updateControls {
    BOOL busy=self.isBusy;
    self.navigationItem.leftBarButtonItem.enabled=!busy;
    self.navigationItem.hidesBackButton=busy;
    self.modalInPresentation=busy;
    self.navigationController.modalInPresentation=busy || self.previousModal;
    self.navigationController.interactivePopGestureRecognizer.enabled=!busy && self.previousPopEnabled;
    _cancelItem.enabled=_download && !_cancelling && !_importing;
    _backItem.enabled=!busy && _webView.canGoBack;
    _forwardItem.enabled=!busy && _webView.canGoForward;
    _reloadItem.enabled=!busy; _homeItem.enabled=!busy;
    _webView.userInteractionEnabled=!busy;
    _progressView.hidden=!busy;
}
- (void)close { if (!self.isBusy) WKDismissPage(self); }
- (void)back { if (!self.isBusy) [_webView goBack]; }
- (void)forward { if (!self.isBusy) [_webView goForward]; }
- (void)reload { if (!self.isBusy) { _hasResult=NO; [_webView reload]; } }
- (void)home { if (!self.isBusy) { _hasResult=NO; [_webView loadRequest:[NSURLRequest requestWithURL:_startURL]]; } }
- (BOOL)acceptsDownloadURL:(NSURL *)url { return TKAddonDownloadURLIsTrusted(url); }
- (void)showMessage:(NSString *)message { _hasResult=YES; _status.text=message; }
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action decisionHandler:(void (^)(WKNavigationActionPolicy))decision {
    (void)webView;
    NSString *scheme=action.request.URL.scheme.lowercaseString;
    if (![@[@"https",@"http",@"about",@"blob"] containsObject:scheme]) {
        decision(WKNavigationActionPolicyCancel);
        if (action.targetFrame.isMainFrame || !action.targetFrame) [self showMessage:WKLocalized(@"addons.web.useDownload")];
        return;
    }
    if (action.shouldPerformDownload) {
        BOOL allowed=!self.isBusy && [self acceptsDownloadURL:action.request.URL];
        decision(allowed?WKNavigationActionPolicyDownload:WKNavigationActionPolicyCancel);
        if (!allowed && !self.isBusy) [self showMessage:WKLocalized(@"addons.web.unsupported")];
        return;
    }
    decision(WKNavigationActionPolicyAllow);
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)response decisionHandler:(void (^)(WKNavigationResponsePolicy))decision {
    (void)webView;
    if (TKAddonResponseIsZIP(response.response) || !response.canShowMIMEType) {
        BOOL allowed=!self.isBusy && TKAddonResponseIsZIP(response.response) && [self acceptsDownloadURL:response.response.URL];
        decision(allowed?WKNavigationResponsePolicyDownload:WKNavigationResponsePolicyCancel);
        if (!allowed && !self.isBusy) [self showMessage:WKLocalized(@"addons.web.unsupported")];
    } else decision(WKNavigationResponsePolicyAllow);
}
- (WKWebView *)webView:(WKWebView *)webView createWebViewWithConfiguration:(WKWebViewConfiguration *)configuration forNavigationAction:(WKNavigationAction *)action windowFeatures:(WKWindowFeatures *)features {
    (void)configuration; (void)features;
    if (!action.targetFrame && !self.isBusy) [webView loadRequest:action.request];
    return nil;
}
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    (void)navigation;
    if (!_hasResult && !self.isBusy) _status.text=WKLocalizedFormat(@"addons.web.hint",_edition);
    self.title=webView.URL.host ?: @"CurseForge";
    [self updateControls];
}
- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    (void)webView; (void)navigation;
    if (error.code!=NSURLErrorCancelled && !self.isBusy) [self showMessage:error.localizedDescription];
    [self updateControls];
}
- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    [self webView:webView didFailProvisionalNavigation:navigation withError:error];
}
- (void)acceptDownload:(WKDownload *)download {
    if (self.isBusy) { [download cancel:nil]; return; }
    _download=download; download.delegate=self; _hasResult=NO;
    _status.text=WKLocalized(@"addons.web.downloading"); _progressView.progress=0;
    [self updateControls];
    __weak TKAddonBrowserViewController *weakSelf=self;
    _progressTimer=[NSTimer scheduledTimerWithTimeInterval:0.2 repeats:YES block:^(NSTimer *timer) {
        (void)timer;
        TKAddonBrowserViewController *self=weakSelf; if (!self) return;
        NSProgress *progress=self.download.progress;
        if (progress.completedUnitCount>ArchiveLimit) { [self cancelWithMessage:WKLocalized(@"addons.web.tooLarge")]; return; }
        self.progressView.progress=progress.totalUnitCount>0?progress.fractionCompleted:0;
    }];
}
- (void)webView:(WKWebView *)webView navigationAction:(WKNavigationAction *)action didBecomeDownload:(WKDownload *)download {
    (void)webView; (void)action; [self acceptDownload:download];
}
- (void)webView:(WKWebView *)webView navigationResponse:(WKNavigationResponse *)response didBecomeDownload:(WKDownload *)download {
    (void)webView; (void)response; [self acceptDownload:download];
}
- (void)download:(WKDownload *)download decideDestinationUsingResponse:(NSURLResponse *)response suggestedFilename:(NSString *)filename completionHandler:(void (^)(NSURL *))completion {
    (void)filename;
    NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]?[(NSHTTPURLResponse *)response statusCode]:0;
    if (download!=_download || _cancelling) { completion(nil); return; }
    if (![self acceptsDownloadURL:response.URL] || !TKAddonResponseIsZIP(response) || status<200 || status>=300 || response.expectedContentLength>ArchiveLimit) {
        completion(nil);
        [self finishWithMessage:WKLocalized(response.expectedContentLength>ArchiveLimit?@"addons.web.tooLarge":@"addons.web.unsupported")];
        return;
    }
    _jobURL=[[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES] URLByAppendingPathComponent:[@"WolkaraAddon-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
    NSError *error=nil;
    if (![NSFileManager.defaultManager createDirectoryAtURL:_jobURL withIntermediateDirectories:YES attributes:nil error:&error]) {
        completion(nil); [self finishWithMessage:error.localizedDescription]; return;
    }
    _downloadURL=[_jobURL URLByAppendingPathComponent:@"addon.zip"];
    completion(_downloadURL);
}
- (void)download:(WKDownload *)download willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request decisionHandler:(void (^)(WKDownloadRedirectPolicy))decision {
    (void)response;
    BOOL allowed=download==_download && [self acceptsDownloadURL:request.URL];
    decision(allowed?WKDownloadRedirectPolicyAllow:WKDownloadRedirectPolicyCancel);
    if (!allowed && download==_download) [self finishWithMessage:WKLocalized(@"addons.web.unsupported")];
}
- (void)downloadDidFinish:(WKDownload *)download {
    if (download!=_download || _cancelling) return;
    [_progressTimer invalidate]; _progressTimer=nil;
    _download=nil; _importing=YES; _progressView.progress=1;
    _status.text=WKLocalized(@"addons.web.installing"); [self updateControls];
    if (!self.installArchive || !_downloadURL) { [self finishWithMessage:WKLocalized(@"addons.error.importMessage")]; return; }
    self.installArchive(_downloadURL, ^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self finishWithMessage:error.localizedDescription ?: WKLocalized(@"addons.web.installed")];
        });
    });
}
- (void)download:(WKDownload *)download didFailWithError:(NSError *)error resumeData:(NSData *)resumeData {
    (void)resumeData;
    if (download==_download && !_cancelling) [self finishWithMessage:error.localizedDescription];
}
- (void)cancelDownload { [self cancelWithMessage:WKLocalized(@"addons.web.cancelled")]; }
- (void)cancelWithMessage:(NSString *)message {
    if (!_download || _cancelling || _importing) return;
    _cancelling=YES; [self updateControls];
    [_download cancel:^(NSData *resumeData) { (void)resumeData; [self finishWithMessage:message]; }];
}
- (void)finishWithMessage:(NSString *)message {
    [_progressTimer invalidate]; _progressTimer=nil;
    _download.delegate=nil; _download=nil; _importing=NO; _cancelling=NO;
    if (_jobURL) [NSFileManager.defaultManager removeItemAtURL:_jobURL error:NULL];
    _jobURL=nil; _downloadURL=nil;
    [self showMessage:message]; [self updateControls];
}
- (void)dealloc { [_progressTimer invalidate]; }
@end
