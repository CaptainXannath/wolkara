#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT BOOL TKAddonDownloadURLIsTrusted(NSURL *url);
FOUNDATION_EXPORT BOOL TKAddonResponseIsZIP(NSURLResponse *response);
FOUNDATION_EXPORT NSURL *TKAddonBrowseURL(NSString *product);

// Uses the site's normal browser/download flow. No API credential or page scraping.
@interface TKAddonBrowserViewController : UIViewController
- (instancetype)initWithURL:(NSURL *)url edition:(NSString *)edition;
// The URL remains valid until completion. The caller validates and installs on a worker queue.
@property(nonatomic, copy) void (^installArchive)(NSURL *url, void (^completion)(NSError * _Nullable error));
@end
NS_ASSUME_NONNULL_END
