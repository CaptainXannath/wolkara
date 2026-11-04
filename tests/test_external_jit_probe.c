#include "ExternalJITProbe.h"
#include "DebuggerArena.h"
#include <assert.h>

static unsigned calls;
static bool detached(void) { return false; }
static bool delayed(void) { return ++calls<3; }
static bool attached(void) { return true; }
int main(void) {
    da_attachment_probe(detached);
    assert(da_external_wait_for_detachment());
    da_attachment_probe(delayed);
    assert(da_external_wait_for_detachment() && calls==3);
    da_attachment_probe(attached);
    assert(!da_external_wait_for_detachment());
    // Mac tests must refuse to execute the device-only fixture.
    assert(!da_synthetic_probe(NULL));
    da_attachment_probe(NULL);
    puts("external JIT detachment: PASS");
    return 0;
}
