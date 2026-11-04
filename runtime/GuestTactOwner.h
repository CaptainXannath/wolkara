#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum { GTO_NOT_EXTERNAL, GTO_NO_DIGEST, GTO_HASH_MISMATCH, GTO_EXACT_70755 } GTOGate;
const char *gto_70755_expected_sha256(void);
GTOGate gto_70755_gate(bool external,const uint8_t *digest,size_t length);
const char *gto_gate_reason(GTOGate gate);

// Inputs are read from the current writable code alias, after unpacking. These
// are semantic ARM64 contracts, not a permission to reuse another build's FP.
bool gto_70755_layout(const uint32_t frame[10],const uint32_t origin[3],
                      const uint32_t thunk[3]);
bool gto_stack_frame(uintptr_t frame,uintptr_t start,uintptr_t end);
bool gto_parent_frame(uintptr_t frame,uintptr_t parent,uintptr_t start,uintptr_t end);
bool gto_mutex_derived(uintptr_t child,uintptr_t mutex,uintptr_t *derived);
