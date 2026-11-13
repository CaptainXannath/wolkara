// A narrow syscall wrapper forces a partial trim and cleanup failure. No
// production test hook is needed, and no generated or application code runs.
#include "NativeCodeMemory.h"
#include <assert.h>
#include <errno.h>
#include <mach/mach.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static void *failure_address, *must_be_mapped;
static size_t failure_size;
static unsigned failures;
static int controlled_munmap(void *address,size_t size);
#define munmap controlled_munmap
#include "../runtime/NativeCodeMemory.c"
#undef munmap

static bool mapped(void *pointer) {
    vm_address_t address=(vm_address_t)pointer; vm_size_t size=0;
    vm_region_basic_info_data_64_t info={0}; mach_msg_type_number_t count=VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object=MACH_PORT_NULL;
    if(vm_region_64(mach_task_self(),&address,&size,VM_REGION_BASIC_INFO_64,(vm_region_info_t)&info,&count,&object)!=KERN_SUCCESS) return false;
    if(object!=MACH_PORT_NULL)mach_port_deallocate(mach_task_self(),object);
    return address<=(vm_address_t)pointer && (vm_address_t)pointer-address<size;
}
static int controlled_munmap(void *address,size_t size) {
    if(address==must_be_mapped)assert(mapped(address));
    if(address==failure_address && size==failure_size) {
        failure_address=NULL; failures++; errno=EIO; return -1;
    }
    return munmap(address,size);
}
static void *sentinel_at(void *pointer,size_t size) {
    vm_address_t address=(vm_address_t)pointer;
    assert(vm_allocate(mach_task_self(),&address,size,VM_FLAGS_FIXED)==KERN_SUCCESS);
    assert(address==(vm_address_t)pointer);
    memset(pointer,0xa7,size);
    return pointer;
}
int main(void) {
    size_t page=(size_t)getpagesize();
    void *region=mmap(NULL,4*page,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);
    assert(region!=MAP_FAILED);
    memset(region,0x69,4*page);
    assert(!mprotect(region,4*page,PROT_READ));
    NativeCodeMemory memory={0};
    assert(nc_adopt(&memory,region,4*page));
    void *alias=memory.writable;
    failure_address=(char *)region+2*page; failure_size=2*page;
    assert(!nc_trim(&memory,2*page) && errno==EIO && failures==1);
    assert(!memory.published && memory.size==4*page);
    assert(memory.executable_size==4*page && memory.writable_size==2*page);
    assert(mapped((char *)region+2*page) && !mapped((char *)alias+2*page));
    assert(((unsigned char *)region)[0]==0x69 && ((unsigned char *)alias)[0]==0x69);
    unsigned char byte=0x53;
    assert(!nc_write(&memory,0,&byte,1) && errno==EINVAL);
    assert(!nc_clear(&memory,page) && errno==EINVAL);
    assert(!nc_trim(&memory,page) && errno==EINVAL);
    void *tail_sentinel=sentinel_at((char *)alias+2*page,page);
    // A cleanup failure keeps only its still-owned RX range for a later try.
    failure_address=region; failure_size=4*page;
    errno=EDOM; nc_destroy(&memory);
    assert(errno==EDOM && failures==2);
    assert(memory.executable==region && memory.executable_size==4*page);
    assert(!memory.writable && !memory.writable_size && !memory.published);
    assert(mapped(region) && !mapped(alias) && mapped(tail_sentinel));
    void *prefix_sentinel=sentinel_at(alias,page);
    nc_destroy(&memory);
    assert(!memory.executable && !memory.writable && !memory.size);
    assert(!mapped(region) && mapped(prefix_sentinel) && mapped(tail_sentinel));
    assert(((unsigned char *)prefix_sentinel)[0]==0xa7 && ((unsigned char *)tail_sentinel)[0]==0xa7);
    assert(!munmap(prefix_sentinel,page) && !munmap(tail_sentinel,page));

    // The signed-image backend uses one shared view. Destroy it once.
    void *shared=mmap(NULL,page,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);
    assert(shared!=MAP_FAILED);
    NativeCodeMemory same={.executable=shared,.writable=shared,.size=page,
        .executable_size=page,.writable_size=page,.published=true};
    must_be_mapped=shared;
    nc_destroy(&same);
    assert(!mapped(shared) && !same.executable && !same.writable);
    puts("PASS: partial trim revokes publication, exact per-view cleanup and cleanup retry preserve reused addresses (no generated code executed)");
}
