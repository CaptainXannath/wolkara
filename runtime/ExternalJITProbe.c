#include "ExternalJITProbe.h"
#include "DebuggerArena.h"
#include <TargetConditionals.h>
#include <stdint.h>
#include <unistd.h>

bool da_external_wait_for_detachment(void) {
    for (unsigned i=0;i<400;i++) {
        if (!da_debugger_present()) return true;
        usleep(5000);
    }
    return !da_debugger_present();
}

bool da_synthetic_probe(FILE *log) {
#if defined(__aarch64__) && TARGET_OS_IOS && !TARGET_OS_SIMULATOR
    if (!log || !da_debugger_present()) return false;
    NativeCodeMemory memory={0};
    bool success=false;
    if (!da_request_arena(&memory,(size_t)getpagesize(),log)) return false;
    // This is our own fixture, not bytes from any application.
    const uint32_t sample[]={0x52800540,0xd65f03c0}; // mov w0,#42; ret
    bool written=nc_write(&memory,0,sample,sizeof sample);
    bool executable=da_release_debugger(&memory,log);
    bool detached=da_external_wait_for_detachment();
    if (!written || !executable || !detached) goto done;
    fprintf(log,"[external-jit] detached; calling host sample expected=42\n"); fflush(log);
    int (*function)(void)=(int (*)(void))memory.executable;
    int first=function();
    fprintf(log,"[external-jit] sample returned=%d\n",first); fflush(log);
    if (first!=42) goto done;
    uint32_t replacement=0x5280a720; // mov w0,#1337
    if (!nc_write(&memory,0,&replacement,sizeof replacement) || da_debugger_present()) goto done;
    int second=function();
    fprintf(log,"[external-jit] rewritten sample returned=%d\n",second); fflush(log);
    success=second==1337;
done:
    // Never unmap a region while an external preparation may still own it.
    if (!da_debugger_present()) nc_destroy(&memory);
    return success;
#else
    if (log) fprintf(log,"[external-jit] probe requires a physical arm64 iOS device\n");
    return false;
#endif
}
