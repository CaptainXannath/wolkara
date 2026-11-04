#include "GuestTactOwner.h"
#include <string.h>

const char *gto_70755_expected_sha256(void) {
    return "29b5e106f5ff89a91b7e1bec0d475dc8b31fb684f34217fff571d8a0888519d8";
}
GTOGate gto_70755_gate(bool external,const uint8_t *digest,size_t length) {
    if (!external) return GTO_NOT_EXTERNAL;
    if (!digest || length!=32) return GTO_NO_DIGEST;
    const char *hex=gto_70755_expected_sha256();
    static const char digits[]="0123456789abcdef";
    for (size_t i=0;i<32;i++)
        if (digits[digest[i]>>4]!=hex[i*2] || digits[digest[i]&15]!=hex[i*2+1])
            return GTO_HASH_MISMATCH;
    return GTO_EXACT_70755;
}
const char *gto_gate_reason(GTOGate gate) {
    switch (gate) {
        case GTO_NOT_EXTERNAL:return "not-external-jit";
        case GTO_NO_DIGEST:return "fresh-file-digest-unavailable";
        case GTO_HASH_MISMATCH:return "fresh-file-sha256-mismatch";
        case GTO_EXACT_70755:return "fresh-file-sha256-match";
    }
    return "invalid-gate";
}
static bool immediate(uint32_t word,bool subtract,unsigned rd,unsigned rn,unsigned bytes) {
    return (word&0xffc00000u)==(subtract?0xd1000000u:0x91000000u) &&
        (word&31)==rd && ((word>>5)&31)==rn && ((word>>10)&4095)==bytes;
}
static bool pair_store(uint32_t word,unsigned rt,unsigned rt2,unsigned rn,unsigned bytes) {
    return (word&0xffc00000u)==0xa9000000u && (word&31)==rt &&
        ((word>>10)&31)==rt2 && ((word>>5)&31)==rn && ((word>>15)&127)*8==bytes;
}
static bool move_register(uint32_t word,unsigned rd,unsigned rm) {
    return (word&0xffe0ffe0u)==0xaa0003e0u && (word&31)==rd && ((word>>16)&31)==rm;
}
static bool load64(uint32_t word,unsigned rt,unsigned rn,unsigned bytes) {
    return (word&0xffc00000u)==0xf9400000u && (word&31)==rt &&
        ((word>>5)&31)==rn && ((word>>10)&4095)*8==bytes;
}
bool gto_70755_layout(const uint32_t frame[10],const uint32_t origin[3],const uint32_t thunk[3]) {
    if (!frame || !origin || !thunk) return false;
    // Saved x19 lives at SP+40, while FP is SP+48: only then is FP-8 valid.
    if (!immediate(frame[0],true,31,31,64) ||
        !pair_store(frame[1],22,21,31,16) || !pair_store(frame[2],20,19,31,32) ||
        !pair_store(frame[3],29,30,31,48) || !immediate(frame[4],false,29,31,48) ||
        !move_register(frame[5],22,1) || !move_register(frame[6],21,0) ||
        !immediate(frame[7],false,19,0,0x170) || !move_register(frame[8],0,19) ||
        (frame[9]&0xfc000000u)!=0x94000000u) return false;
    if (!load64(origin[0],8,19,0x10) || !load64(origin[1],0,8,0x700) ||
        (origin[2]&0xff00001fu)!=0x34000001u) return false;
    if (!immediate(thunk[0],false,0,0,0x28) ||
        (thunk[1]&0xffc003ffu)!=(0xb9400000u|(1u<<5)|1u) ||
        (thunk[2]&0xfc000000u)!=0x14000000u) return false;
    int64_t displacement=(int64_t)(thunk[2]&0x03ffffffu);
    if (displacement&(1LL<<25)) displacement-=1LL<<26;
    return INT64_C(0x102a2ea30)+displacement*4==INT64_C(0x102a3aa14);
}
bool gto_stack_frame(uintptr_t frame,uintptr_t start,uintptr_t end) {
    return start<end && end>=16 && !(frame&15) && frame>=start && frame<=end-16;
}
bool gto_parent_frame(uintptr_t frame,uintptr_t parent,uintptr_t start,uintptr_t end) {
    return gto_stack_frame(frame,start,end) && gto_stack_frame(parent,start,end) &&
        parent>frame && parent-frame<=1024*1024 && parent>=8 && parent-8>=start;
}
bool gto_mutex_derived(uintptr_t child,uintptr_t mutex,uintptr_t *derived) {
    if (!derived || child>UINTPTR_MAX-0x198) return false;
    *derived=child+0x28+0x170;
    return *derived==mutex;
}
