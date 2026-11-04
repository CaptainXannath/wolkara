#import "GuestTactCache.h"
#import "../launcher/WoW/CASC.h"
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

enum { GTC_FDS=64, GTC_REPORTS=128 };
typedef struct {
    bool used;
    int fd;
    const char *kind;
    uint64_t offset,size;
    struct stat stamp;
} GTCDescriptor;
struct GTCObserver {
    pthread_mutex_t lock;
    GTOObjectSpec spec;
    FILE *log;
    unsigned reports;
    unsigned segment_open_reports,segment_close_reports,unrelated_io_reports;
    bool candidate;
    uint64_t offset,size;
    struct stat segment_stamp;
    GTCDescriptor descriptors[GTC_FDS];
};
static bool hex_byte(unsigned char c) {
    return (c>='0' && c<='9') || (c>='a' && c<='f') || (c>='A' && c<='F');
}
bool gtc_named_key(const char *path,const char key[33]) {
    if (!path || !key || key[32] || strlen(key)!=32) return false;
    size_t length=strnlen(path,PATH_MAX);
    if (length>=PATH_MAX || length<32) return false;
    for (size_t i=0;i<=length-32;i++) {
        if (i && hex_byte((unsigned char)path[i-1])) continue;
        if (memcmp(path+i,key,32)) continue;
        if (i+32<length && hex_byte((unsigned char)path[i+32])) continue;
        return true;
    }
    return false;
}
static const char *named_kind(const GTCObserver *observer,const char *path) {
    if (gtc_named_key(path,observer->spec.ekey)) return "encoded-key-name";
    if (gtc_named_key(path,observer->spec.ckey)) return "content-key-name";
    return NULL;
}
static const char *safe_operation(const char *operation) {
    static const char *allowed[]={"open","openat","fopen","stat","lstat","fstatat","access",
        "read","pread","fread","mmap","close","fclose","fstat","lookup"};
    for (size_t i=0;operation && i<sizeof allowed/sizeof allowed[0];i++)
        if (!strcmp(operation,allowed[i])) return allowed[i];
    return "other";
}
static bool same_stamp(const struct stat *a,const struct stat *b) {
    return S_ISREG(a->st_mode) && S_ISREG(b->st_mode) &&
        a->st_dev==b->st_dev && a->st_ino==b->st_ino && a->st_size==b->st_size &&
        a->st_mtimespec.tv_sec==b->st_mtimespec.tv_sec && a->st_mtimespec.tv_nsec==b->st_mtimespec.tv_nsec &&
        a->st_ctimespec.tv_sec==b->st_ctimespec.tv_sec && a->st_ctimespec.tv_nsec==b->st_ctimespec.tv_nsec;
}
static bool report(GTCObserver *observer) {return observer->log && observer->reports++<GTC_REPORTS;}
static bool pread_all(int fd,void *bytes,size_t length,uint64_t offset) {
    if (offset>INT64_MAX || length>(uint64_t)INT64_MAX-offset) return false;
    size_t got=0;
    while (got<length) {
        ssize_t n=pread(fd,(uint8_t *)bytes+got,length-got,(off_t)(offset+got));
        if (n<0 && errno==EINTR) continue;
        if (n<=0) return false;
        got+=(size_t)n;
    }
    return true;
}
static void snapshot(GTCObserver *observer,int fd,uint64_t offset,uint64_t size,
                      const char *kind,bool envelope) {
    struct stat before,after;
    if (fstat(fd,&before) || !S_ISREG(before.st_mode) || before.st_size<0 ||
        offset>(uint64_t)before.st_size || size>(uint64_t)before.st_size-offset || size>GTO_MAX_OBJECT_BYTES) {
        if (report(observer)) fprintf(observer->log,"[tact-cache] source=observer-snapshot kind=%s fd=%d result=unreadable-or-out-of-bounds\n",kind,fd);
        return;
    }
    if (envelope) {
        uint8_t header[30],key[16];bool valid=offset>=30 && TKWoWUnhex(@(observer->spec.ekey),key) &&
            pread_all(fd,header,sizeof header,offset-30);
        if (valid) {
            for (unsigned i=0;i<16;i++) if (header[i]!=key[15-i]) valid=false;
            uint64_t full=0;for (unsigned i=0;i<4;i++) full|=(uint64_t)header[16+i]<<(i*8);
            valid=valid && full==size+30;
        }
        if (!valid) {
            if (report(observer)) fprintf(observer->log,"[tact-cache] source=observer-snapshot kind=%s fd=%d result=prefix-collision-or-invalid-envelope\n",kind,fd);
            return;
        }
    }
    uint8_t *bytes=malloc(size?(size_t)size:1);
    if (!bytes) {
        if (report(observer)) fprintf(observer->log,"[tact-cache] source=observer-snapshot kind=%s fd=%d result=observer-allocation-failed\n",kind,fd);
        return;
    }
    bool read=pread_all(fd,bytes,(size_t)size,offset);
    bool stable=!fstat(fd,&after) && same_stamp(&before,&after);
    if (!read || !stable) {
        if (report(observer)) fprintf(observer->log,"[tact-cache] source=observer-snapshot kind=%s fd=%d result=%s\n",kind,fd,read?"file-changed":"read-failed");
    } else if (!envelope && !strcmp(kind,"content-key-name") && size==observer->spec.decoded_size) {
        NSData *decoded=[NSData dataWithBytesNoCopy:bytes length:(NSUInteger)size freeWhenDone:NO];
        bool match=[TKWoWMD5(decoded) isEqualToString:@(observer->spec.ckey)];
        if (report(observer)) fprintf(observer->log,"[tact-cache] source=observer-snapshot kind=%s fd=%d bytes=%llu decoded-hash=%s guest-decode=unobserved\n",
            kind,fd,(unsigned long long)size,match?"verified":"mismatch");
    } else {
        GTOResult result={0};gto_verify_bytes(&observer->spec,bytes,(size_t)size,&result);
        if (report(observer)) fprintf(observer->log,"[tact-cache] source=observer-snapshot kind=%s fd=%d offset=%llu bytes=%llu result=%s encoded-checks=%s decoded-hash=%s guest-decode=unobserved\n",
            kind,fd,(unsigned long long)offset,(unsigned long long)size,gto_status_name(result.status),
            result.encoded_verified?"verified":"unverified",result.decoded_verified?"verified":"unverified");
    }
    free(bytes);
}
GTCObserver *gtc_create(const char *directory,const GTOObjectSpec *spec,FILE *log) {
    int saved=errno;
    if (!directory || !gto_spec_valid(spec)) {errno=saved;return NULL;}
    GTCObserver *observer=calloc(1,sizeof *observer);
    if (!observer) {errno=saved;return NULL;}
    if (pthread_mutex_init(&observer->lock,NULL)) {free(observer);errno=saved;return NULL;}
    observer->spec=*spec;observer->log=log;
    @autoreleasepool {
        NSError *error=nil;
        NSDictionary *extent=TKWoWCASCDiagnosticExtent(@(directory),@(spec->ekey),&error);
        if (!extent) {
            if (report(observer)) fprintf(log,"[tact-cache] source=observer-preflight casc-prefix=absent-or-unreadable error-code=%ld no-files-created=yes\n",(long)error.code);
        } else {
            uint64_t segment=[extent[@"segment"] unsignedLongLongValue];
            observer->offset=[extent[@"offset"] unsignedLongLongValue];observer->size=[extent[@"encodedSize"] unsignedLongLongValue];
            if (report(observer)) fprintf(log,"[tact-cache] source=observer-preflight casc-prefix=candidate segment=%llu offset=%llu encoded-bytes=%llu full-key=unverified\n",
                (unsigned long long)segment,(unsigned long long)observer->offset,(unsigned long long)observer->size);
            if (segment<1024 && observer->size<=GTO_MAX_OBJECT_BYTES) {
                NSString *path=[@(directory) stringByAppendingPathComponent:[NSString stringWithFormat:@"data.%03u",(unsigned)segment]];
                int fd=open(path.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_NONBLOCK);
                if (fd>=0) {
                    observer->candidate=!fstat(fd,&observer->segment_stamp) && S_ISREG(observer->segment_stamp.st_mode);
                    snapshot(observer,fd,observer->offset,observer->size,"casc-prefix-candidate",true);
                    close(fd);
                } else if (report(observer)) fprintf(log,"[tact-cache] source=observer-preflight segment-open=failed errno=%d\n",errno);
            } else if (report(observer)) fprintf(log,"[tact-cache] source=observer-preflight result=unsupported-candidate-extent\n");
        }
    }
    errno=saved;return observer;
}
void gtc_destroy(GTCObserver *observer) {
    int saved=errno;
    if (observer) {pthread_mutex_destroy(&observer->lock);free(observer);}
    errno=saved;
}
void gtc_lookup(GTCObserver *observer,const char *path,const char *operation,int result,int error_number) {
    int saved=errno;
    if (observer) {
        pthread_mutex_lock(&observer->lock);
        const char *kind=named_kind(observer,path);
        if (kind && report(observer)) fprintf(observer->log,"[tact-cache] source=guest-lookup kind=%s operation=%s result=%d errno=%d\n",kind,safe_operation(operation),result,result<0?error_number:0);
        pthread_mutex_unlock(&observer->lock);
    }
    errno=saved;
}
void gtc_opened(GTCObserver *observer,const char *path,int fd,int flags,int error_number) {
    int saved=errno;
    if (!observer) {errno=saved;return;}
    pthread_mutex_lock(&observer->lock);
    const char *kind=named_kind(observer,path);struct stat current;
    bool valid=fd>=0 && !fstat(fd,&current) && S_ISREG(current.st_mode);
    bool segment=valid && observer->candidate && same_stamp(&observer->segment_stamp,&current);
    if (!kind && segment) kind="casc-prefix-candidate";
    if (!kind) goto done;
    bool report_segment=!segment || observer->segment_open_reports++<4;
    if (report_segment && report(observer)) fprintf(observer->log,"[tact-cache] source=guest-open kind=%s fd=%d flags=%#x errno=%d\n",kind,fd,flags,fd<0?error_number:0);
    if (!valid) goto done;
    size_t slot=GTC_FDS;
    for (size_t i=0;i<GTC_FDS;i++) {
        if (observer->descriptors[i].used && observer->descriptors[i].fd==fd) {slot=i;break;}
        if (!observer->descriptors[i].used && slot==GTC_FDS) slot=i;
    }
    if (slot==GTC_FDS) {
        if (report(observer)) fprintf(observer->log,"[tact-cache] source=observer-registry result=capacity-reached\n");
        goto done;
    }
    uint64_t offset=segment?observer->offset:0,size=segment?observer->size:(uint64_t)current.st_size;
    observer->descriptors[slot]=(GTCDescriptor){.used=true,.fd=fd,.kind=kind,.offset=offset,.size=size,.stamp=current};
    if(report_segment) snapshot(observer,fd,offset,size,kind,segment);
done:
    pthread_mutex_unlock(&observer->lock);errno=saved;
}
static bool overlaps(uint64_t start,uint64_t count,uint64_t object,uint64_t size) {
    if (!count || !size || start>UINT64_MAX-count || object>UINT64_MAX-size) return false;
    return start<object+size && object<start+count;
}
void gtc_io(GTCObserver *observer,int fd,const char *operation,int64_t offset,uint64_t requested,int64_t result,int error_number) {
    int saved=errno;
    if (!observer) {errno=saved;return;}
    pthread_mutex_lock(&observer->lock);
    for (size_t i=0;i<GTC_FDS;i++) {
        GTCDescriptor *entry=&observer->descriptors[i];
        if (!entry->used || entry->fd!=fd) continue;
        struct stat current;
        if (fstat(fd,&current) || !same_stamp(&entry->stamp,&current)) {
            if (report(observer)) fprintf(observer->log,"[tact-cache] source=observer-registry fd=%d result=identity-or-stamp-changed association=dropped\n",fd);
            entry->used=false;break;
        }
        const char *intersection=offset<0?"unknown":overlaps((uint64_t)offset,result>0?(uint64_t)result:requested,entry->offset,entry->size)?"yes":"no";
        if(!strcmp(entry->kind,"casc-prefix-candidate") && !strcmp(intersection,"no") &&
            !error_number && observer->unrelated_io_reports++>=4) break;
        if (report(observer)) fprintf(observer->log,"[tact-cache] source=guest-io kind=%s fd=%d operation=%s offset=%lld requested=%llu result=%lld errno=%d candidate-overlap=%s\n",
            entry->kind,fd,safe_operation(operation),(long long)offset,(unsigned long long)requested,(long long)result,error_number,intersection);
        break;
    }
    pthread_mutex_unlock(&observer->lock);errno=saved;
}
void gtc_closed(GTCObserver *observer,int fd,int result,int error_number) {
    int saved=errno;
    if (!observer) {errno=saved;return;}
    pthread_mutex_lock(&observer->lock);
    for (size_t i=0;i<GTC_FDS;i++) {
        GTCDescriptor *entry=&observer->descriptors[i];
        if (!entry->used || entry->fd!=fd) continue;
        bool report_segment=strcmp(entry->kind,"casc-prefix-candidate") ||
            observer->segment_close_reports++<4;
        if (report_segment && report(observer)) fprintf(observer->log,"[tact-cache] source=guest-close kind=%s fd=%d result=%d errno=%d association=prior-target\n",entry->kind,fd,result,result<0?error_number:0);
        if (!result || error_number==EBADF || error_number==EINTR) entry->used=false;
        break;
    }
    pthread_mutex_unlock(&observer->lock);errno=saved;
}
