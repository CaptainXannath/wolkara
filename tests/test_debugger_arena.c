#include "DebuggerArena.h"
#include "HostDiagnostics.h"
#include <assert.h>
#include <errno.h>
#include <mach/mach.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static unsigned asked;
// Attached and staying: the launch has no way in.
static bool holds_on(void) { asked++; return true; }
// Attached, then gone once asked.
static bool lets_go(void) { return asked++ == 0; }

static bool mapped(const void *pointer) {
    vm_address_t address = (vm_address_t)pointer;
    vm_size_t size = 0;
    vm_region_basic_info_data_64_t info = {0};
    mach_msg_type_number_t count = VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object = MACH_PORT_NULL;
    kern_return_t result = vm_region_64(mach_task_self(), &address, &size, VM_REGION_BASIC_INFO_64,
                                        (vm_region_info_t)&info, &count, &object);
    if (object != MACH_PORT_NULL) mach_port_deallocate(mach_task_self(), object);
    return result == KERN_SUCCESS && address <= (vm_address_t)pointer && (vm_address_t)pointer - address < size;
}

static void test_high_grants(FILE *record) {
    size_t page = (size_t)getpagesize();
    uintptr_t reach = (uintptr_t)1 << 36;
    uintptr_t high_hint = (uintptr_t)0x7000000000ull;
    uintptr_t wrapping = UINTPTR_MAX - page + 1;
    // Malformed bounds and the complete low range must not inspect memory.
    assert(!da_region_unprepared(NULL, page));
    assert(!da_region_unprepared((const void *)(page * 4), page));
    assert(!da_region_unprepared((const void *)(reach - page), page));
    assert(!da_region_unprepared((const void *)(high_hint + 1), page));
    assert(!da_region_unprepared((const void *)high_hint, 0));
    assert(!da_region_unprepared((const void *)high_hint, page - 1));
    assert(!da_region_unprepared((const void *)high_hint, page + 1));
    assert(!da_region_unprepared((const void *)high_hint, (size_t)NC_MAX_ARENA + page));
    assert(!da_region_unprepared((const void *)wrapping, 2 * page));
    NativeCodeMemory invalid = {0};
    assert(!da_adopt_region(&invalid, (void *)(high_hint + 1), page, record) && errno == EINVAL);
    assert(!da_adopt_region(&invalid, (void *)wrapping, 2 * page, record) && errno == EINVAL);
    assert(!invalid.executable && !invalid.writable && !invalid.published);

    unsigned char *high = mmap((void *)high_hint, 2 * page, PROT_READ | PROT_WRITE,
                               MAP_PRIVATE | MAP_ANON, -1, 0);
    assert(high != MAP_FAILED && (uintptr_t)high >= reach);
    assert(!da_adopt_region(NULL, high, 2 * page, record) && errno == EINVAL);
    assert(mapped(high));
    // A destination with owned-length metadata is not empty. Refuse it before
    // classifying this untouched high grant, and leave the grant mapped.
    NativeCodeMemory stale = {.executable_size = page};
    assert(!da_adopt_region(&stale, high, 2 * page, record) && errno == EINVAL);
    assert(stale.executable_size == page && !stale.writable_size && !stale.size && !stale.published);
    assert(mapped(high));
    stale = (NativeCodeMemory){.writable_size = page};
    assert(!da_adopt_region(&stale, high, 2 * page, record) && errno == EINVAL);
    assert(stale.writable_size == page && !stale.executable_size && !stale.size && !stale.published);
    assert(mapped(high));
    assert(da_region_unprepared(high, 2 * page));
    high[0] = 0x69;
    assert(da_region_unprepared(high, 2 * page));
    high[0] = 0; high[page] = 0x69;
    assert(da_region_unprepared(high, 2 * page));
    high[0] = 0x69;
    assert(!da_region_unprepared(high, 2 * page));
    // A corrected enabler can prepare high memory with another nonzero marker.
    high[0] = 1; high[page] = 2;
    assert(!da_region_unprepared(high, 2 * page));
    assert(!mprotect(high, page, PROT_NONE));
    assert(da_region_unprepared(high, 2 * page));
    assert(!mprotect(high, page, PROT_READ | PROT_WRITE));
    assert(!mprotect(high + page, page, PROT_NONE));
    assert(da_region_unprepared(high, 2 * page));
    assert(!mprotect(high + page, page, PROT_READ | PROT_WRITE));
    NativeCodeMemory prepared = {0};
    assert(da_adopt_region(&prepared, high, 2 * page, record));
    assert(prepared.executable == high && prepared.writable && prepared.published);
    unsigned char marker = 3;
    assert(nc_write(&prepared, page, &marker, 1) && high[page] == marker);
    // A repeated call must preserve the arena already owned by its destination.
    assert(!da_adopt_region(&prepared, high, 2 * page, record) && errno == EINVAL);
    assert(hd_protection(high) && prepared.published);
    nc_destroy(&prepared);
    assert(!mapped(high));

    unsigned char *untouched = mmap((void *)high_hint, 2 * page, PROT_READ | PROT_WRITE,
                                    MAP_PRIVATE | MAP_ANON, -1, 0);
    assert(untouched != MAP_FAILED && (uintptr_t)untouched >= reach);
    NativeCodeMemory refused = {0};
    assert(!da_adopt_region(&refused, untouched, 2 * page, record) && errno == EACCES);
    assert(!refused.executable && !refused.writable && !refused.published && !mapped(untouched));
    void *unreadable = mmap((void *)high_hint, 2 * page, PROT_NONE, MAP_PRIVATE | MAP_ANON, -1, 0);
    assert(unreadable != MAP_FAILED && (uintptr_t)unreadable >= reach);
    assert(mapped(unreadable));
    assert(!da_adopt_region(&refused, unreadable, 2 * page, record) && errno == EACCES);
    assert(!mapped(unreadable) && !refused.executable && !refused.writable);
    assert(!fflush(record));
}

int main(void) {
    size_t page = (size_t)getpagesize();
    // An unserviced request leaves the breakpoint encoding, not a null.
    assert(!da_plausible_region(NULL));
    assert(!da_plausible_region((const void *)(uintptr_t)-1));
    assert(!da_plausible_region((const void *)(uintptr_t)0x690000e0ull));
    assert(!da_plausible_region((const void *)(uintptr_t)0xcccccccc690000e0ull));
    assert(!da_plausible_region((const void *)(uintptr_t)(page + 8)));
    assert(da_plausible_region((const void *)(uintptr_t)(page * 4)));

    // With nothing attached the protocol must refuse, not trap.
    NativeCodeMemory arena = {0};
    assert(!da_request_arena(&arena, page, NULL));
    assert(!arena.executable && !arena.writable && !arena.published);
    assert(!da_release_debugger(&arena, NULL));
    assert(!da_entry_allowed(&arena, NULL));

    // What the external path falls back to.
    void *mapped = mmap(NULL, page, PROT_READ | PROT_EXEC, MAP_PRIVATE | MAP_ANON, -1, 0);
    void *runs = mapped == MAP_FAILED ? (void *)(uintptr_t)&main : mapped;
    NativeCodeMemory fallback = {.executable = runs, .size = page, .published = true};
    void *writable = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    assert(writable != MAP_FAILED);
    NativeCodeMemory unexecutable = {.executable = writable, .size = page, .published = true};
    assert(da_entry_allowed(&fallback, NULL));
    assert(!da_entry_allowed(&unexecutable, NULL));

    // A refused request, with a debugger that holds on.
    asked = 0; da_attachment_probe(holds_on);
    NativeCodeMemory refused = {0};
    assert(!da_request_arena(&refused, page, NULL));
    assert(!da_entry_allowed(&fallback, NULL));
    assert(asked >= 2);   // asked to let go, then asked again
    assert(!da_release_debugger(&unexecutable, NULL));

    // One that lets go: the mapping decides on its own.
    asked = 0; da_attachment_probe(lets_go);
    assert(da_entry_allowed(&fallback, NULL));
    assert(asked == 2);
    da_attachment_probe(NULL);
    assert(munmap(writable, page) == 0);
    if (mapped != MAP_FAILED) assert(munmap(mapped, page) == 0);

    // A granted region the adoption refuses is given back, not stranded.
    char *text = NULL; size_t length = 0;
    FILE *record = open_memstream(&text, &length);
    assert(record);
    void *granted = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    assert(granted != MAP_FAILED);
    ((unsigned char *)granted)[0] = 0x69;
    assert(!mprotect(granted, page, PROT_READ | PROT_EXEC));
    // Execute-only, as a region from outside the app can be.
    assert(!vm_protect(mach_task_self(), (vm_address_t)granted, page, TRUE,
                       VM_PROT_READ | VM_PROT_EXECUTE));
    NativeCodeMemory stranded = {0};
    assert(!da_adopt_region(&stranded, granted, page, record));
    assert(!stranded.executable && !stranded.writable);
    assert(!hd_protection(granted));
    assert(!fflush(record) && strstr(text, "errno=") && strstr(text, ", given back"));

    // One it takes: the region stays ours, with a writable view beside it.
    void *region = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    assert(region != MAP_FAILED);
    ((unsigned char *)region)[0] = 0x69;
    NativeCodeMemory taken = {0};
    assert(da_adopt_region(&taken, region, page, NULL));
    assert(taken.executable == region && taken.writable && taken.published);
    assert(hd_protection(region));
    nc_destroy(&taken);

    // A size nothing could have been granted for is not unmapped either.
    void *kept = mmap(NULL, page, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0);
    assert(kept != MAP_FAILED);
    NativeCodeMemory oversized = {0};
    assert(!da_adopt_region(&oversized, kept, (size_t)NC_MAX_ARENA + page, record));
    assert(hd_protection(kept));
    assert(!fflush(record) && strstr(text, ", not given back"));
    assert(munmap(kept, page) == 0);
    test_high_grants(record);
    assert(strstr(text, "granted but not prepared") &&
           !strstr(text, "page-write address range; not given back"));
    fclose(record); free(text);

    puts("PASS: debugger region validation, refused request with nothing attached (no breakpoint executed),"
         " no entry while a debugger holds on, a refused region given back");
    puts("PASS: high enabler grant markers, bounds, read permissions, adoption and rejection cleanup; no code executed");
}
