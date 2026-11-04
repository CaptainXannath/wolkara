#import "GuestTactObject.h"
#import "../launcher/WoW/CASC.h"
#include <stdlib.h>
#include <string.h>

const GTOObjectSpec gto_patch_index_70755={
    "46c3d32d04ba185323ebea70f24ce282",
    "f5dac064c0740aa65482c7f66b79f449",35927,40865
};
struct GTOCapture {
    GTOObjectSpec spec;
    GTOResult result;
    bool finished;
    unsigned char bytes[];
};

static bool hash_valid(const char hash[33]) {
    if (hash[32]) return false;
    for (size_t i=0;i<32;i++)
        if (!((hash[i]>='0' && hash[i]<='9') || (hash[i]>='a' && hash[i]<='f'))) return false;
    return true;
}
bool gto_spec_valid(const GTOObjectSpec *spec) {
    return spec && hash_valid(spec->ekey) && hash_valid(spec->ckey) &&
        spec->encoded_size>=9 && spec->encoded_size<=GTO_MAX_OBJECT_BYTES &&
        spec->decoded_size>0 && spec->decoded_size<=GTO_MAX_OBJECT_BYTES;
}
const char *gto_status_name(GTOStatus status) {
    switch (status) {
        case GTO_PENDING:return "pending";
        case GTO_VERIFIED:return "observer-verified";
        case GTO_INVALID_SPEC:return "invalid-specification";
        case GTO_INVALID_DATA:return "unavailable-observation-bytes";
        case GTO_LENGTH_MISMATCH:return "encoded-size-mismatch";
        case GTO_OFFSET_MISMATCH:return "nonsequential-observation";
        case GTO_INCOMPLETE:return "incomplete-observation";
        case GTO_BLTE_LAYOUT_ERROR:return "invalid-blte-layout";
        case GTO_ENCODED_HASH_MISMATCH:return "encoded-key-mismatch";
        case GTO_CHUNK_HASH_MISMATCH:return "chunk-checksum-mismatch";
        case GTO_UNSUPPORTED_CHUNK:return "encrypted-or-unsupported-chunk";
        case GTO_DECOMPRESSION_ERROR:return "decompression-or-decoded-size-error";
        case GTO_DECODED_HASH_MISMATCH:return "decoded-key-mismatch";
    }
    return "unknown-observer-status";
}
static GTOStatus encoded_failure(NSError *error) {
    NSString *message=error.localizedDescription;
    if ([message isEqualToString:@"Encoded object checksum mismatch."]) return GTO_ENCODED_HASH_MISMATCH;
    if ([message isEqualToString:@"Encoded chunk checksum mismatch."]) return GTO_CHUNK_HASH_MISMATCH;
    return GTO_BLTE_LAYOUT_ERROR;
}
static GTOStatus decoded_failure(NSError *error) {
    NSString *message=error.localizedDescription;
    if ([message isEqualToString:@"Decoded content hash mismatch."]) return GTO_DECODED_HASH_MISMATCH;
    if ([message isEqualToString:@"Unsupported BLTE chunk type."] ||
        [message isEqualToString:@"This file requires an encryption key. Encrypted extraction is not supported."])
        return GTO_UNSUPPORTED_CHUNK;
    return GTO_DECOMPRESSION_ERROR;
}
GTOStatus gto_verify_bytes(const GTOObjectSpec *spec,const void *bytes,size_t length,GTOResult *result) {
    GTOResult observed={.status=GTO_INVALID_SPEC,.observed_size=length};
    if (!gto_spec_valid(spec)) goto done;
    if (length!=spec->encoded_size) {observed.status=GTO_LENGTH_MISMATCH;goto done;}
    if (!bytes) {observed.status=GTO_INVALID_DATA;goto done;}
    @autoreleasepool {
        // Reuse the launcher's existing bounded verifier and BLTE decoder. No
        // independent copy of format parsing or relaxed integrity check exists.
        NSData *data=[NSData dataWithBytesNoCopy:(void *)bytes length:length freeWhenDone:NO];
        NSError *error=nil;
        if (!TKWoWEncodedValid(data,@(spec->ekey),&error)) {
            observed.status=encoded_failure(error);goto done;
        }
        observed.encoded_verified=true;
        NSData *decoded=TKWoWDecode(data,@(spec->ekey),@(spec->ckey),spec->decoded_size,
            GTO_MAX_OBJECT_BYTES,&error);
        if (!decoded) {observed.status=decoded_failure(error);goto done;}
        observed.decoded_size=decoded.length;
        observed.decoded_verified=true;
        observed.status=GTO_VERIFIED;
    }
done:
    if (result) *result=observed;
    return observed.status;
}
GTOCapture *gto_create(const GTOObjectSpec *spec) {
    if (!gto_spec_valid(spec)) return NULL;
    GTOCapture *capture=calloc(1,sizeof *capture+spec->encoded_size);
    if (capture) capture->spec=*spec;
    return capture;
}
GTOStatus gto_append(GTOCapture *capture,const void *bytes,size_t length,size_t offset) {
    if (!capture) return GTO_INVALID_SPEC;
    if (capture->finished || capture->result.status!=GTO_PENDING) return capture->result.status;
    if (offset!=capture->result.observed_size) capture->result.status=GTO_OFFSET_MISMATCH;
    else if (length>capture->spec.encoded_size-capture->result.observed_size)
        capture->result.status=GTO_LENGTH_MISMATCH;
    else if (length && !bytes) capture->result.status=GTO_INVALID_DATA;
    else {
        if (length) memcpy(capture->bytes+capture->result.observed_size,bytes,length);
        capture->result.observed_size+=length;
    }
    return capture->result.status;
}
GTOStatus gto_finish(GTOCapture *capture,GTOResult *result) {
    if (!capture) {
        if (result) *result=(GTOResult){.status=GTO_INVALID_SPEC};
        return GTO_INVALID_SPEC;
    }
    if (!capture->finished) {
        capture->finished=true;
        if (capture->result.status==GTO_PENDING) {
            if (capture->result.observed_size!=capture->spec.encoded_size) capture->result.status=GTO_INCOMPLETE;
            else gto_verify_bytes(&capture->spec,capture->bytes,capture->result.observed_size,&capture->result);
        }
    }
    if (result) *result=capture->result;
    return capture->result.status;
}
void gto_destroy(GTOCapture *capture) {free(capture);}
