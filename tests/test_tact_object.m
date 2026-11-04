#import <Foundation/Foundation.h>
#include "GuestTactObject.h"
#import "../launcher/WoW/Manifest.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

// All bytes and object keys below are generated from our own fixture.
static NSData *Text(NSString *text) {return [text dataUsingEncoding:NSUTF8StringEncoding];}
static void PutBE(NSMutableData *data,uint64_t value,unsigned length) {
    for (unsigned i=length;i>0;i--) {uint8_t byte=(uint8_t)(value>>((i-1)*8));[data appendBytes:&byte length:1];}
}
static NSData *DigestBytes(NSData *data) {
    NSString *hex=TKWoWMD5(data);NSMutableData *result=[NSMutableData new];
    for (NSUInteger i=0;i<16;i++) PutBE(result,strtoul([[hex substringWithRange:NSMakeRange(i*2,2)] UTF8String],NULL,16),1);
    return result;
}
static NSData *Fixture(NSData *plain,BOOL table,BOOL compressed) {
    NSMutableData *chunk=[NSMutableData new];PutBE(chunk,compressed?'Z':'N',1);
    if (compressed) {
        uLongf size=compressBound(plain.length);NSMutableData *encoded=[NSMutableData dataWithLength:size];
        assert(compress(encoded.mutableBytes,&size,plain.bytes,plain.length)==Z_OK);
        encoded.length=size;[chunk appendData:encoded];
    } else [chunk appendData:plain];
    NSMutableData *data=[Text(@"BLTE") mutableCopy];PutBE(data,table?36:0,4);
    if (table) {
        PutBE(data,15,1);PutBE(data,1,3);PutBE(data,chunk.length,4);PutBE(data,plain.length,4);
        [data appendData:DigestBytes(chunk)];
    }
    [data appendData:chunk];return data;
}
static GTOObjectSpec Specification(NSData *raw,NSData *plain,BOOL table) {
    GTOObjectSpec spec={.encoded_size=(uint32_t)raw.length,.decoded_size=(uint32_t)plain.length};
    snprintf(spec.ekey,sizeof spec.ekey,"%s",TKWoWMD5(table?[raw subdataWithRange:NSMakeRange(0,36)]:raw).UTF8String);
    snprintf(spec.ckey,sizeof spec.ckey,"%s",TKWoWMD5(plain).UTF8String);
    return spec;
}
static void CheckSpec(void) {
    assert(gto_spec_valid(&gto_patch_index_70755));
    assert(!strcmp(gto_patch_index_70755.ekey,"46c3d32d04ba185323ebea70f24ce282"));
    assert(!strcmp(gto_patch_index_70755.ckey,"f5dac064c0740aa65482c7f66b79f449"));
    assert(gto_patch_index_70755.encoded_size==35927 && gto_patch_index_70755.decoded_size==40865);
    GTOObjectSpec bad=gto_patch_index_70755;bad.encoded_size=GTO_MAX_OBJECT_BYTES+1;
    assert(!gto_spec_valid(&bad) && !gto_create(&bad));
    bad=gto_patch_index_70755;bad.decoded_size=GTO_MAX_OBJECT_BYTES+1;assert(!gto_spec_valid(&bad));
    bad=gto_patch_index_70755;bad.ekey[32]='x';assert(!gto_spec_valid(&bad));
    bad=gto_patch_index_70755;bad.ckey[0]='X';assert(!gto_spec_valid(&bad));
    bad=gto_patch_index_70755;bad.encoded_size=8;assert(!gto_spec_valid(&bad));
    assert(!gto_spec_valid(NULL));
}
static void CheckVerification(void) {
    NSData *plain=Text(@"Our synthetic patch-index observation fixture. No game or credential bytes.");
    for (unsigned table=0;table<2;table++) for (unsigned compressed=0;compressed<2;compressed++) {
        NSData *raw=Fixture(plain,table,compressed);GTOObjectSpec spec=Specification(raw,plain,table);GTOResult result={0};
        NSData *unchanged=[raw copy];
        assert(gto_verify_bytes(&spec,raw.bytes,raw.length,&result)==GTO_VERIFIED);
        assert(result.encoded_verified && result.decoded_verified && result.observed_size==raw.length && result.decoded_size==plain.length);
        assert([raw isEqual:unchanged]); // Observation never changes source bytes.
        assert(gto_verify_bytes(&spec,NULL,raw.length,&result)==GTO_INVALID_DATA);
        for (NSUInteger n=0;n<raw.length;n++)
            assert(gto_verify_bytes(&spec,raw.bytes,n,&result)==GTO_LENGTH_MISMATCH);
        assert(gto_verify_bytes(&spec,raw.bytes,SIZE_MAX,&result)==GTO_LENGTH_MISMATCH);
        GTOObjectSpec bad=spec;memset(bad.ekey,'0',32);
        assert(gto_verify_bytes(&bad,raw.bytes,raw.length,&result)==GTO_ENCODED_HASH_MISMATCH);
        bad=spec;memset(bad.ckey,'0',32);
        assert(gto_verify_bytes(&bad,raw.bytes,raw.length,&result)==GTO_DECODED_HASH_MISMATCH);
        assert(result.encoded_verified && !result.decoded_verified);
        bad=spec;bad.decoded_size++;
        assert(gto_verify_bytes(&bad,raw.bytes,raw.length,&result)==GTO_DECOMPRESSION_ERROR);
        NSMutableData *corrupt=[raw mutableCopy];((uint8_t *)corrupt.mutableBytes)[raw.length-1]^=1;
        GTOStatus expected=table?GTO_CHUNK_HASH_MISMATCH:GTO_ENCODED_HASH_MISMATCH;
        assert(gto_verify_bytes(&spec,corrupt.bytes,corrupt.length,&result)==expected);
        assert(!result.encoded_verified && !result.decoded_verified);
        corrupt=[raw mutableCopy];((uint8_t *)corrupt.mutableBytes)[0]='X';
        assert(gto_verify_bytes(&spec,corrupt.bytes,corrupt.length,&result)==GTO_BLTE_LAYOUT_ERROR);
        GTOCapture *capture=gto_create(&spec);assert(capture);
        for (NSUInteger i=0;i<raw.length;i++) assert(gto_append(capture,(const uint8_t *)raw.bytes+i,1,i)==GTO_PENDING);
        assert(gto_finish(capture,&result)==GTO_VERIFIED);
        assert(gto_finish(capture,NULL)==GTO_VERIFIED);
        // Once sealed, later observations cannot change verification results.
        assert(gto_append(capture,NULL,SIZE_MAX,SIZE_MAX)==GTO_VERIFIED);
        gto_destroy(capture);
    }
    NSMutableData *unsupported=[Text(@"BLTE") mutableCopy];PutBE(unsupported,0,4);[unsupported appendData:Text(@"Eopaque synthetic bytes")];
    GTOObjectSpec spec=Specification(unsupported,plain,NO);GTOResult result={0};
    assert(gto_verify_bytes(&spec,unsupported.bytes,unsupported.length,&result)==GTO_UNSUPPORTED_CHUNK);
    assert(result.encoded_verified && !result.decoded_verified);
    // A header can hash correctly and still describe an invalid chunk table.
    NSMutableData *bad=[Fixture(plain,YES,NO) mutableCopy];((uint8_t *)bad.mutableBytes)[11]=2;
    spec=Specification(bad,plain,YES);
    assert(gto_verify_bytes(&spec,bad.bytes,bad.length,&result)==GTO_BLTE_LAYOUT_ERROR);
}
static void CheckStreamingFailures(void) {
    NSData *plain=Text(@"Our own content");NSData *raw=Fixture(plain,YES,YES);
    GTOObjectSpec spec=Specification(raw,plain,YES);GTOResult result={0};
    GTOCapture *capture=gto_create(&spec);assert(capture);
    assert(gto_append(capture,raw.bytes,5,0)==GTO_PENDING);
    assert(gto_append(capture,raw.bytes,1,0)==GTO_OFFSET_MISMATCH);
    assert(gto_finish(capture,&result)==GTO_OFFSET_MISMATCH);
    assert(result.observed_size==5);gto_destroy(capture);
    capture=gto_create(&spec);assert(capture);
    assert(gto_append(capture,raw.bytes,5,0)==GTO_PENDING);
    assert(gto_finish(capture,&result)==GTO_INCOMPLETE && result.observed_size==5);
    assert(!result.encoded_verified && !result.decoded_verified);gto_destroy(capture);
    capture=gto_create(&spec);assert(capture);
    assert(gto_append(capture,raw.bytes,SIZE_MAX,0)==GTO_LENGTH_MISMATCH);gto_destroy(capture);
    capture=gto_create(&spec);assert(capture);
    assert(gto_append(capture,NULL,raw.length,0)==GTO_INVALID_DATA);gto_destroy(capture);
    assert(gto_finish(NULL,&result)==GTO_INVALID_SPEC);
    assert(gto_append(NULL,NULL,0,0)==GTO_INVALID_SPEC);gto_destroy(NULL);
    assert(gto_verify_bytes(NULL,NULL,0,&result)==GTO_INVALID_SPEC);
    assert(!strcmp(gto_status_name(GTO_VERIFIED),"observer-verified"));
    assert(!strcmp(gto_status_name((GTOStatus)999),"unknown-observer-status"));
}
int main(void) {
    @autoreleasepool {CheckSpec();CheckVerification();CheckStreamingFailures();}
    puts("PASS: bounded target-object observation, BLTE/chunk/decoded hash verification, stream bounds and failures (synthetic bytes)");
    return 0;
}
