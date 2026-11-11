#import "SystemRoots.h"
#include <assert.h>
static NSArray *Matches(NSDictionary *query) {
    BOOL handled=NO;CFTypeRef result=NULL;
    assert(AKCopySystemCertificates((__bridge CFDictionaryRef)query,&result,&handled)==0 && handled && result);
    assert(CFGetTypeID(result)==CFArrayGetTypeID());
    return CFBridgingRelease(result);
}
static NSArray *CertificateData(NSArray *certificates) {
    NSMutableArray *encoded=[NSMutableArray new];
    for(id certificate in certificates)
        [encoded addObject:CFBridgingRelease(SecCertificateCopyData((__bridge SecCertificateRef)certificate))];
    return encoded;
}
static void WriteCandidates(NSString *path,id items) {
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:items format:NSPropertyListBinaryFormat_v1_0 options:0 error:NULL];
    assert(data && [data writeToFile:path atomically:YES]);
}
static void TestCandidateInputs(NSDictionary *query,NSArray *trusted) {
    NSFileManager *manager=NSFileManager.defaultManager;
    NSString *directory=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *path=[directory stringByAppendingPathComponent:@"candidates.plist"];
    assert([manager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL]);
    NSArray *original=CertificateData(trusted);
    assert(!AKLoadSystemCertificateCandidates(path));
    assert([CertificateData(Matches(query)) isEqual:original]);
    assert([[@"invalid plist" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:path atomically:YES]);
    assert(!AKLoadSystemCertificateCandidates(path));
    assert([CertificateData(Matches(query)) isEqual:original]);
    for(id invalid in @[@{},@[],@[original[0],NSData.data],@[original[0],@"invalid DER"],@[original[0],[NSMutableData dataWithLength:65537]]]) {
        WriteCandidates(path,invalid);
        assert(!AKLoadSystemCertificateCandidates(path));
        assert([CertificateData(Matches(query)) isEqual:original]);
    }
    // Our own self-signed P-256 CA. Its key was generated in memory and is not
    // retained. Being a valid public certificate does not make it a trusted root.
    NSString *fixture=@"MIIBXzCCAQagAwIBAgIBATAKBggqhkjOPQQDAjAmMSQwIgYDVQQDDBtXb2xrYXJh"
        @"IHVudHJ1c3RlZCB0ZXN0IHJvb3QwIBcNMDAwMTAxMDAwMDAwWhgPMjEwMDAxMDEw"
        @"MDAwMDBaMCYxJDAiBgNVBAMMG1dvbGthcmEgdW50cnVzdGVkIHRlc3Qgcm9vdDBZMBMG"
        @"ByqGSM49AgEGCCqGSM49AwEHA0IABKFZQVs2CbqnzTG00xZVlxWUe895iidu1cTCQUuo"
        @"LcVNcBgvdz81epCR6EHXL95lAqWut9uygRKifwAcdTh9p0ijIzAhMA8GA1UdEwEB/wQF"
        @"MAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMCA0cAMEQCIF2r1rL4Y97JA2Xj"
        @"SoGFoOgwjVLPTFmwhQMKgRjCDIoKAiBydps4nobVVwm6B9NJMV3N9slJnUUbmRBMsVPR"
        @"iJWLEg==";
    NSData *untrusted=[[NSData alloc] initWithBase64EncodedString:fixture options:0];
    SecCertificateRef certificate=SecCertificateCreateWithData(NULL,(__bridge CFDataRef)untrusted);
    assert(certificate);CFRelease(certificate);
    WriteCandidates(path,@[original[0],untrusted]);
    assert(AKLoadSystemCertificateCandidates(path));
    assert([CertificateData(Matches(query)) isEqual:@[original[0]]]);
    WriteCandidates(path,@[untrusted]);assert(AKLoadSystemCertificateCandidates(path));
    BOOL handled=NO;CFTypeRef result=(void *)1;
    assert(AKCopySystemCertificates((__bridge CFDictionaryRef)query,&result,&handled)==errSecItemNotFound && handled && !result);
    WriteCandidates(path,original);assert(AKLoadSystemCertificateCandidates(path));
    assert([CertificateData(Matches(query)) isEqual:original]);
    assert([manager removeItemAtPath:directory error:NULL]);
}
int main(int argc,const char **argv){@autoreleasepool{
    assert(argc==2);
    if([@(argv[1]) isEqual:@"--bundled"]) {
        assert([NSBundle.mainBundle pathForResource:@"PublicRootCertificates" ofType:@"plist"]);
        assert(![NSBundle.mainBundle pathForResource:@"CompatibilityRootCertificates" ofType:@"plist"]);
    } else assert(AKLoadSystemCertificateCandidates(@(argv[1])));
    CFTypeRef handle=(void *)1;assert(AKOpenSystemKeychain("/not-a-system-keychain",&handle)==errSecUnimplemented && !handle);
    assert(AKOpenSystemKeychain("/System/Library/Keychains/SystemRootCertificates.keychain",&handle)==0 && handle);
    SecPolicyRef policy=SecPolicyCreateSSL(true,NULL);
    NSDictionary *query=@{(__bridge id)kSecClass:(__bridge id)kSecClassCertificate,
        (__bridge id)kSecMatchLimit:(__bridge id)kSecMatchLimitAll,(__bridge id)kSecReturnRef:@YES,
        (__bridge id)kSecMatchPolicy:(__bridge id)policy,(__bridge id)kSecMatchTrustedOnly:@YES,
        (__bridge id)kSecMatchSearchList:@[(__bridge id)handle]};
    BOOL handled=NO;CFTypeRef result=NULL;
    assert(AKCopySystemCertificates((__bridge CFDictionaryRef)query,&result,&handled)==0 && handled && result);
    assert(CFGetTypeID(result)==CFArrayGetTypeID() && CFArrayGetCount(result)>20);
    NSArray *trusted=[(__bridge NSArray *)result copy];
    SecPolicyRef rootPolicy=SecPolicyCreateBasicX509();
    for(id certificate in (__bridge NSArray *)result){SecTrustRef trust=NULL;assert(SecTrustCreateWithCertificates((__bridge CFTypeRef)certificate,rootPolicy,&trust)==0);SecTrustSetNetworkFetchAllowed(trust,false);assert(SecTrustEvaluateWithError(trust,NULL));CFRelease(trust);}
    CFRelease(rootPolicy);CFRelease(result);result=NULL;
    NSMutableDictionary *bad=[query mutableCopy];bad[(__bridge id)kSecReturnData]=@YES;
    assert(AKCopySystemCertificates((__bridge CFDictionaryRef)bad,&result,&handled)!=0 && handled && !result);
    [bad removeObjectForKey:(__bridge id)kSecMatchSearchList];handled=YES;
    assert(AKCopySystemCertificates((__bridge CFDictionaryRef)bad,&result,&handled)!=0 && !handled);
    TestCandidateInputs(query,trusted);
    CFRelease(policy);CFRelease(handle);puts("system roots: certificate loading, native trust filtering, invalid-file cache preservation and query isolation pass");
    }
    return 0;
}
