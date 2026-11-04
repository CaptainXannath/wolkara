#ifndef GUEST_TACT_OBJECT_H
#define GUEST_TACT_OBJECT_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Independent, read-only observation of an encoded object already obtained by
// the guest. This API performs no file/network operations and does not report
// whether the guest's own decoder accepted the object.
enum { GTO_MAX_OBJECT_BYTES = 64 * 1024 };
typedef struct {
    char ekey[33], ckey[33];
    uint32_t encoded_size, decoded_size;
} GTOObjectSpec;
extern const GTOObjectSpec gto_patch_index_70755;

typedef enum {
    GTO_PENDING,
    GTO_VERIFIED,
    GTO_INVALID_SPEC,
    GTO_INVALID_DATA,
    GTO_LENGTH_MISMATCH,
    GTO_OFFSET_MISMATCH,
    GTO_INCOMPLETE,
    GTO_BLTE_LAYOUT_ERROR,
    GTO_ENCODED_HASH_MISMATCH,
    GTO_CHUNK_HASH_MISMATCH,
    GTO_UNSUPPORTED_CHUNK,
    GTO_DECOMPRESSION_ERROR,
    GTO_DECODED_HASH_MISMATCH
} GTOStatus;
typedef struct {
    GTOStatus status;
    size_t observed_size, decoded_size;
    // encoded_verified includes the encoded header and all chunk checksums.
    bool encoded_verified, decoded_verified;
} GTOResult;

// Only fixed enum descriptions are returned; untrusted parser error strings or
// content bytes never appear in diagnostic output from this module.
const char *gto_status_name(GTOStatus status);
bool gto_spec_valid(const GTOObjectSpec *spec);
GTOStatus gto_verify_bytes(const GTOObjectSpec *spec,const void *bytes,size_t length,
                           GTOResult *result);

typedef struct GTOCapture GTOCapture;
// Each capture owns at most 64 KiB; caller must bound the number of captures and
// serialize access to an individual capture. No global capture state is held.
GTOCapture *gto_create(const GTOObjectSpec *spec);
GTOStatus gto_append(GTOCapture *capture,const void *bytes,size_t length,size_t offset);
// Finalization is explicit: reaching the advertised size before EOF does not
// prematurely declare success. Finishing seals the capture; calls are idempotent.
GTOStatus gto_finish(GTOCapture *capture,GTOResult *result);
void gto_destroy(GTOCapture *capture);
#endif
