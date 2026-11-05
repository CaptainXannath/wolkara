#import "SavedTextStore.h"
#import <Security/Security.h>

@implementation WKSavedTextStore {
    NSString *_service;
}
- (instancetype)init {
    return [self initWithService:[(NSBundle.mainBundle.bundleIdentifier ?: @"local.wolkaraforever")
        stringByAppendingString:@".toolbar.saved-text"]];
}
- (instancetype)initWithService:(NSString *)service {
    if ((self = [super init])) _service = [service copy];
    return self;
}
- (NSDictionary *)query {
    return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:_service, (__bridge id)kSecAttrAccount:@"toolbar-key",
        (__bridge id)kSecAttrSynchronizable:@NO, (__bridge id)kSecUseDataProtectionKeychain:@YES};
}
- (BOOL)result:(OSStatus)status error:(NSError **)error {
    if (status == errSecSuccess) return YES;
    if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil];
    return NO;
}
- (NSString *)readText:(NSError **)error {
    NSMutableDictionary *query = [[self query] mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecItemNotFound) return @"";
    if (![self result:status error:error]) return nil;
    NSData *data = CFBridgingRelease(result);
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) [self result:errSecDecode error:error];
    return text;
}
- (BOOL)saveText:(NSString *)text error:(NSError **)error {
    if (!text.length) {
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)[self query]);
        return status == errSecItemNotFound || [self result:status error:error];
    }
    NSDictionary *values = @{(__bridge id)kSecValueData:[text dataUsingEncoding:NSUTF8StringEncoding],
        (__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly};
    NSMutableDictionary *item = [[self query] mutableCopy];
    [item addEntriesFromDictionary:values];
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    if (status == errSecDuplicateItem) status = SecItemUpdate((__bridge CFDictionaryRef)[self query], (__bridge CFDictionaryRef)values);
    return [self result:status error:error];
}
@end
