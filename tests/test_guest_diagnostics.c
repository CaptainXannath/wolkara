#include "GuestDiagnostics.h"
#include <assert.h>
#include <stdio.h>

int main(void) {
    uintptr_t source=0;
    assert(ng_diagnostic_source(0x10000,0x20000,4096,0x10004,4,&source) && source==0x20004);
    assert(ng_diagnostic_source(0x10000,0,4096,0x10ffc,4,&source) && source==0x10ffc);
    assert(!ng_diagnostic_source(0x10000,0,4096,0x10ffd,4,&source));
    assert(!ng_diagnostic_source(0x10000,0,4096,0xffff,4,&source));
    assert(!ng_diagnostic_source(0x10000,0,4096,0x11000,4,&source));
    assert(!ng_diagnostic_source(0x10000,UINTPTR_MAX-2,4096,0x10000,4,&source));
    assert(!ng_diagnostic_source(0x10000,UINTPTR_MAX-2,4096,0x10004,1,&source));
    assert(!ng_diagnostic_source(0,0,4096,4,4,&source));
    assert(!ng_diagnostic_source(0x10000,0,4096,0x10000,0,&source));
    assert(!ng_diagnostic_source(0x10000,0,4096,0x10000,4,NULL));
    assert(ng_diagnostic_source(UINTPTR_MAX-3,0,4,UINTPTR_MAX-3,4,&source));
    assert(!ng_diagnostic_source(UINTPTR_MAX-3,0,8,UINTPTR_MAX-3,8,&source));
    puts("PASS: diagnostic reads stay inside arena and alias without address overflow");
}
