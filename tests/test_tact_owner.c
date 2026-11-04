#include "GuestTactOwner.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>

static uint32_t imm(bool sub,unsigned rd,unsigned rn,unsigned value) {
    return (sub?0xd1000000u:0x91000000u)|(value<<10)|(rn<<5)|rd;
}
static uint32_t pair(unsigned rt,unsigned rt2,unsigned offset) {
    return 0xa9000000u|((offset/8)<<15)|(rt2<<10)|(31u<<5)|rt;
}
static uint32_t mov(unsigned rd,unsigned rm) {return 0xaa0003e0u|(rm<<16)|rd;}
static uint32_t ldr(unsigned rt,unsigned rn,unsigned offset) {
    return 0xf9400000u|((offset/8)<<10)|(rn<<5)|rt;
}
int main(void) {
    uint8_t digest[32];
    const char *hex=gto_70755_expected_sha256();
    assert(!strcmp(hex,"29b5e106f5ff89a91b7e1bec0d475dc8b31fb684f34217fff571d8a0888519d8"));
    for (size_t i=0;i<32;i++) {
        unsigned byte=0;assert(sscanf(hex+i*2,"%2x",&byte)==1);digest[i]=(uint8_t)byte;
    }
    // Content identity does not depend on an edition folder or imported filename.
    assert(gto_70755_gate(true,digest,sizeof digest)==GTO_EXACT_70755);
    assert(gto_70755_gate(false,digest,sizeof digest)==GTO_NOT_EXTERNAL);
    assert(gto_70755_gate(true,NULL,32)==GTO_NO_DIGEST);
    assert(gto_70755_gate(true,digest,31)==GTO_NO_DIGEST);
    for (size_t i=0;i<32;i++) {digest[i]^=1;assert(gto_70755_gate(true,digest,32)==GTO_HASH_MISMATCH);digest[i]^=1;}
    uint32_t frame[]={imm(true,31,31,64),pair(22,21,16),pair(20,19,32),pair(29,30,48),
        imm(false,29,31,48),mov(22,1),mov(21,0),imm(false,19,0,0x170),mov(0,19),0x94000001u};
    uint32_t origin[]={ldr(8,19,0x10),ldr(0,8,0x700),0x34000001u};
    uint32_t thunk[]={imm(false,0,0,0x28),0xb9400000u|(1u<<5)|1u,
        0x14000000u|((0x102a3aa14ULL-0x102a2ea30ULL)/4)};
    assert(gto_70755_layout(frame,origin,thunk));
    for (size_t i=0;i<10;i++) {uint32_t old=frame[i];frame[i]=0;assert(!gto_70755_layout(frame,origin,thunk));frame[i]=old;}
    for (size_t i=0;i<3;i++) {uint32_t old=origin[i];origin[i]=0;assert(!gto_70755_layout(frame,origin,thunk));origin[i]=old;}
    thunk[2]++;assert(!gto_70755_layout(frame,origin,thunk));thunk[2]--;
    frame[2]=pair(20,19,24);assert(!gto_70755_layout(frame,origin,thunk));
    assert(gto_stack_frame(0x2000,0x1000,0x3000));
    assert(!gto_stack_frame(0x2001,0x1000,0x3000));
    assert(!gto_stack_frame(0x2000,0x3000,0x1000));
    assert(gto_parent_frame(0x2000,0x2100,0x1000,0x3000));
    assert(!gto_parent_frame(0x2000,0x1f00,0x1000,0x3000));
    assert(!gto_parent_frame(0x2000,0x2101,0x1000,0x3000));
    assert(!gto_parent_frame(0,16,0,8));
    uintptr_t derived=0;
    assert(gto_mutex_derived(0,0x198,&derived) && derived==0x198);
    assert(gto_mutex_derived(0x10000,0x10198,&derived));
    assert(!gto_mutex_derived(0x10000,0x198,&derived));
    assert(!gto_mutex_derived(UINTPTR_MAX-0x197,0,&derived));
    assert(!gto_mutex_derived(0,0x198,NULL));
    puts("PASS: 70755 identity, ARM64 layout, stack bounds and null-derived mutex policy");
}
