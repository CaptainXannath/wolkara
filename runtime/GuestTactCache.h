#ifndef GUEST_TACT_CACHE_H
#define GUEST_TACT_CACHE_H
#include "GuestTactObject.h"
#include <stdio.h>

typedef struct GTCObserver GTCObserver;
// data_directory is the CASC Data/data directory. Creation only reads existing
// local indexes and candidate bytes. It never creates a directory or receipt.
GTCObserver *gtc_create(const char *data_directory,const GTOObjectSpec *spec,FILE *log);
void gtc_destroy(GTCObserver *observer);
// All functions preserve incoming errno, print only allowlisted labels/numeric
// metadata, and accept NULL observers as a no-op. Caller owns path string bytes.
void gtc_lookup(GTCObserver *observer,const char *path,const char *operation,int result,int error_number);
void gtc_opened(GTCObserver *observer,const char *path,int fd,int flags,int error_number);
// Offset -1 means unknown (e.g. buffered I/O). Result is the actual byte count;
// for mmap, supply the mapped length on success and -1 on failure. A mapping is
// logged as a mapping, not proof that the guest consumed any mapped byte.
void gtc_io(GTCObserver *observer,int fd,const char *operation,int64_t offset,
            uint64_t requested,int64_t result,int error_number);
void gtc_closed(GTCObserver *observer,int fd,int result,int error_number);
// Exported to test the matching contract: no arbitrary substring/hex-prefix match.
bool gtc_named_key(const char *path,const char key[33]);
#endif
