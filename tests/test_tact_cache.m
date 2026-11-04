#import <Foundation/Foundation.h>
#include "GuestTactCache.h"
#import "../launcher/WoW/CASC.h"
#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// Synthetic BLTE and CASC files created in a private temporary directory.
static NSData *fixture(NSData *plain) {
    NSMutableData *raw=[[@"BLTE" dataUsingEncoding:NSUTF8StringEncoding] mutableCopy];
    uint32_t zero=0;[raw appendBytes:&zero length:sizeof zero];
    const char kind='N';[raw appendBytes:&kind length:1];[raw appendData:plain];
    return raw;
}
static NSDictionary<NSString *,NSString *> *snapshot(NSString *directory) {
    NSMutableDictionary *result=[NSMutableDictionary new];
    NSArray *names=[NSFileManager.defaultManager contentsOfDirectoryAtPath:directory error:NULL];
    for (NSString *name in names) {
        NSString *path=[directory stringByAppendingPathComponent:name];
        NSData *bytes=[NSData dataWithContentsOfFile:path];
        if(bytes) result[name]=TKWoWMD5(bytes);
    }
    return result;
}
int main(void) {
    @autoreleasepool {
        char template[]="/tmp/wolkara-tact-cache-XXXXXX";
        char *root=mkdtemp(template);assert(root);
        NSString *directory=[@(root) stringByAppendingPathComponent:@"data"];
        NSData *plain=[@"Synthetic patch-index entry with no game or credential bytes."
            dataUsingEncoding:NSUTF8StringEncoding];
        NSData *raw=fixture(plain);
        GTOObjectSpec spec={.encoded_size=(uint32_t)raw.length,.decoded_size=(uint32_t)plain.length};
        snprintf(spec.ekey,sizeof spec.ekey,"%s",TKWoWMD5(raw).UTF8String);
        snprintf(spec.ckey,sizeof spec.ckey,"%s",TKWoWMD5(plain).UTF8String);
        assert(gto_spec_valid(&spec));
        @autoreleasepool {
            NSError *error=nil;
            TKWoWCASCStore *writer=[[TKWoWCASCStore alloc] initWithDirectory:directory error:&error];
            assert(writer && !error);
            assert([writer addData:raw key:@(spec.ekey) error:&error] && !error);
            assert([writer checkpoint:&error] && !error);
        }
        NSDictionary *before=snapshot(directory);
        assert(before.count>=2);
        FILE *log=tmpfile();assert(log);
        GTCObserver *observer=gtc_create(directory.fileSystemRepresentation,&spec,log);
        assert(observer);
        NSError *error=nil;
        NSDictionary *extent=TKWoWCASCDiagnosticExtent(directory,@(spec.ekey),&error);
        assert(extent && !error && [extent[@"prefixOnly"] boolValue]);
        NSString *segment=[directory stringByAppendingPathComponent:
            [NSString stringWithFormat:@"data.%03u",[extent[@"segment"] unsignedIntValue]]];
        int fd=open(segment.fileSystemRepresentation,O_RDONLY);assert(fd>=0);
        assert(lseek(fd,7,SEEK_SET)==7);
        gtc_opened(observer,segment.fileSystemRepresentation,fd,O_RDONLY,0);
        assert(lseek(fd,0,SEEK_CUR)==7); // Observer snapshot uses pread only.
        int64_t offset=[extent[@"offset"] longLongValue];
        uint64_t size=[extent[@"encodedSize"] unsignedLongLongValue];
        assert(size==raw.length);
        gtc_io(observer,fd,"pread",offset,size,(int64_t)size,0);
        gtc_io(observer,fd,"mmap",offset,size,(int64_t)size,0);
        for(unsigned i=0;i<20;i++) gtc_io(observer,fd,"pread",offset+(int64_t)size+1,1,1,0);
        assert(lseek(fd,0,SEEK_CUR)==7);
        assert(!close(fd));gtc_closed(observer,fd,0,0);
        NSString *keyPath=[NSString stringWithFormat:@"/cache/%s",spec.ekey];
        assert(gtc_named_key(keyPath.UTF8String,spec.ekey));
        assert(!gtc_named_key("/cache/00000000000000000000000000000000",spec.ekey));
        NSString *badSuffix=[keyPath stringByAppendingString:@"a"];
        assert(!gtc_named_key(badSuffix.UTF8String,spec.ekey));
        gtc_lookup(observer,keyPath.UTF8String,"stat",-1,ENOENT);
        gtc_destroy(observer);
        fflush(log);rewind(log);
        char output[32768]={0};size_t n=fread(output,1,sizeof output-1,log);output[n]=0;
        assert(strstr(output,"casc-prefix=candidate"));
        assert(strstr(output,"encoded-checks=verified decoded-hash=verified"));
        assert(strstr(output,"source=guest-io") && strstr(output,"candidate-overlap=yes"));
        const char *cursor=output;unsigned unrelated=0;
        while((cursor=strstr(cursor,"candidate-overlap=no"))) {unrelated++;cursor++;}
        assert(unrelated==4);
        assert(strstr(output,"kind=encoded-key-name operation=stat result=-1 errno=2"));
        assert(!strstr(output,root) && !strstr(output,spec.ekey) && !strstr(output,spec.ckey));
        fclose(log);
        assert([before isEqualToDictionary:snapshot(directory)]);
        NSString *missing=[@(root) stringByAppendingPathComponent:@"absent"];
        log=tmpfile();assert(log);
        observer=gtc_create(missing.fileSystemRepresentation,&spec,log);
        assert(observer);gtc_destroy(observer);fclose(log);
        assert(![NSFileManager.defaultManager fileExistsAtPath:missing]);
        assert([NSFileManager.defaultManager removeItemAtPath:@(root) error:NULL]);
    }
    puts("PASS: read-only CASC candidate, guest descriptor ranges, key lookup and redacted cache observations");
    return 0;
}
