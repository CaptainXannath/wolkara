#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@protocol WKSavedTextStorage <NSObject>
- (nullable NSString *)readText:(NSError **)error;
// An empty value removes the saved item. Whitespace is significant.
- (BOOL)saveText:(NSString *)text error:(NSError **)error;
@end

@interface WKSavedTextStore : NSObject <WKSavedTextStorage>
- (instancetype)initWithService:(NSString *)service;
@end
NS_ASSUME_NONNULL_END
