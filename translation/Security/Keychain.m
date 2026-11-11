#import "SystemRoots.h"
#import <TargetConditionals.h>
#include <dlfcn.h>

static NSArray *candidates;
static const char *candidateSource="provided candidates";
static unsigned openDiagnostics,enumerationDiagnostics;
static CFStringRef marker(void){return CFSTR("Tolkara public system certificate source");}
BOOL AKLoadSystemCertificateCandidates(NSString *path) {
    NSData *data=path?[NSData dataWithContentsOfFile:path]:nil;
    if(!data || data.length>4*1024*1024)return NO;
    id items=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:NULL];
    if(![items isKindOfClass:NSArray.class] || ![items count] || [items count]>1024)return NO;
    NSMutableArray *certificates=[NSMutableArray array];
    for(id der in items){
        if(![der isKindOfClass:NSData.class] || [der length]>65536)return NO;
        SecCertificateRef certificate=SecCertificateCreateWithData(NULL,(__bridge CFDataRef)der);
        if(!certificate)return NO;
        [certificates addObject:CFBridgingRelease(certificate)];
    }
    @synchronized(NSProcessInfo.class){candidates=[certificates copy];candidateSource="provided candidates";}return YES;
}
OSStatus AKOpenSystemKeychain(const char *path,CFTypeRef *keychain) {
    if(!keychain)return errSecParam;*keychain=NULL;
    if(!path || strcmp(path,"/System/Library/Keychains/SystemRootCertificates.keychain"))return errSecUnimplemented;
    @synchronized(NSProcessInfo.class){
        OSStatus status=errSecSuccess;
        if(!candidates) {
            if(AKLoadSystemCertificateCandidates([NSBundle.mainBundle pathForResource:@"CompatibilityRootCertificates" ofType:@"plist"]))
                candidateSource="CompatibilityRootCertificates";
            else if(AKLoadSystemCertificateCandidates([NSBundle.mainBundle pathForResource:@"PublicRootCertificates" ofType:@"plist"]))
                candidateSource="PublicRootCertificates";
            else status=errSecNotAvailable;
        }
        if(status==errSecSuccess)*keychain=CFRetain(marker());
        if(openDiagnostics<8) {
            openDiagnostics++;
            fprintf(stderr,"[security] system root source=%s candidates=%lu open_status=%d\n",
                candidates?candidateSource:"unavailable",(unsigned long)candidates.count,(int)status);
        }
        return status;
    }
}
static OSStatus CertificateResult(OSStatus status,NSUInteger matched,NSUInteger total) {
    @synchronized(NSProcessInfo.class){
        if(enumerationDiagnostics<8) {
            enumerationDiagnostics++;
            fprintf(stderr,"[security] native-trusted public roots matched=%lu candidates=%lu enumeration_status=%d\n",
                (unsigned long)matched,(unsigned long)total,(int)status);
        }
    }
    return status;
}
OSStatus AKCopySystemCertificates(CFDictionaryRef raw,CFTypeRef *result,BOOL *handled) {
    if(handled)*handled=NO;
    if(!raw || CFGetTypeID(raw)!=CFDictionaryGetTypeID())return errSecParam;
    NSDictionary *query=(__bridge NSDictionary *)raw;
    id list=query[(__bridge id)kSecMatchSearchList];
    if(![list isKindOfClass:NSArray.class] || ![list containsObject:(__bridge id)marker()])return errSecParam;
    if(handled)*handled=YES;if(result)*result=NULL;
    NSArray *snapshot;@synchronized(NSProcessInfo.class){snapshot=candidates;}
    if(!result || [list count]!=1 || ![query[(__bridge id)kSecClass] isEqual:(__bridge id)kSecClassCertificate] ||
       ![query[(__bridge id)kSecReturnRef] isEqual:@YES])return CertificateResult(errSecParam,0,snapshot.count);
    NSSet *keys=[NSSet setWithArray:@[(__bridge id)kSecClass,(__bridge id)kSecMatchLimit,(__bridge id)kSecMatchSearchList,
        (__bridge id)kSecReturnRef,(__bridge id)kSecMatchPolicy,(__bridge id)kSecMatchTrustedOnly]];
    for(id key in query)if(![keys containsObject:key])return CertificateResult(errSecUnimplemented,0,snapshot.count);
    id limit=query[(__bridge id)kSecMatchLimit];BOOL all=[limit isEqual:(__bridge id)kSecMatchLimitAll];
    if(limit && !all && ![limit isEqual:(__bridge id)kSecMatchLimitOne])return CertificateResult(errSecUnimplemented,0,snapshot.count);
    id requested=query[(__bridge id)kSecMatchPolicy];
    if(requested && CFGetTypeID((__bridge CFTypeRef)requested)!=SecPolicyGetTypeID())return CertificateResult(errSecParam,0,snapshot.count);
    if(requested) {
        SecPolicyRef ssl=SecPolicyCreateSSL(true,NULL),basic=SecPolicyCreateBasicX509();
        NSDictionary *properties=CFBridgingRelease(SecPolicyCopyProperties((__bridge SecPolicyRef)requested));
        BOOL supported=[properties isEqual:CFBridgingRelease(SecPolicyCopyProperties(ssl))] ||
            [properties isEqual:CFBridgingRelease(SecPolicyCopyProperties(basic))];
        CFRelease(ssl);CFRelease(basic);if(!supported)return CertificateResult(errSecUnimplemented,0,snapshot.count);
    }
    // Candidates identify possible public roots. Check their native root trust
    // with a CA policy; the original TLS stack still validates the server peer.
    SecPolicyRef policy=SecPolicyCreateBasicX509();
    NSMutableArray *matching=[NSMutableArray array];
    for(id cert in snapshot){
        SecTrustRef trust=NULL;
        if(SecTrustCreateWithCertificates((__bridge CFTypeRef)cert,policy,&trust))continue;
        // The device's system trust store must independently accept each root.
        SecTrustSetNetworkFetchAllowed(trust,false);
        BOOL trusted=SecTrustEvaluateWithError(trust,NULL);CFRelease(trust);
        if(trusted){[matching addObject:cert];if(!all)break;}
    }
    CFRelease(policy);
    if(!matching.count)return CertificateResult(errSecItemNotFound,0,snapshot.count);
    *result=CFRetain((__bridge CFTypeRef)(all?matching:matching.firstObject));return CertificateResult(errSecSuccess,matching.count,snapshot.count);
}
#if TARGET_OS_IPHONE
OSStatus SecKeychainOpen(const char *path,CFTypeRef *keychain){return AKOpenSystemKeychain(path,keychain);}
OSStatus SecItemCopyMatching(CFDictionaryRef query,CFTypeRef *result){
    BOOL handled=NO;OSStatus status=AKCopySystemCertificates(query,result,&handled);if(handled)return status;
    static OSStatus (*native)(CFDictionaryRef,CFTypeRef *);static dispatch_once_t once;
    dispatch_once(&once,^{void *library=dlopen("/System/Library/Frameworks/Security.framework/Security",RTLD_NOW|RTLD_LOCAL);native=library?dlsym(library,"SecItemCopyMatching"):NULL;});
    return native?native(query,result):errSecUnimplemented;
}
#endif
