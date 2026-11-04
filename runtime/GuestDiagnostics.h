#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

// Translate a bounded executable-arena observation to its writable alias.
// Neither a wrapping address nor a range crossing the arena is observable.
static inline bool ng_diagnostic_source(uintptr_t executable,uintptr_t writable,
                                        size_t size,uintptr_t address,size_t length,
                                        uintptr_t *source) {
    if (!source || !executable || address<executable || !length) return false;
    uintptr_t offset=address-executable;
    if (offset>size || length>size-offset) return false;
    uintptr_t base=writable?writable:executable;
    if (offset>UINTPTR_MAX-base || length-1>UINTPTR_MAX-(base+offset)) return false;
    *source=base+offset;
    return true;
}
