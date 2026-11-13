#include "NativeCodeMemory.h"
#include <assert.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>
#include <mach/mach.h>

static vm_prot_t protection(void *pointer) {
    vm_address_t address=(vm_address_t)pointer; vm_size_t size=0;
    vm_region_basic_info_data_64_t info={0}; mach_msg_type_number_t count=VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object=MACH_PORT_NULL;
    assert(vm_region_64(mach_task_self(),&address,&size,VM_REGION_BASIC_INFO_64,(vm_region_info_t)&info,&count,&object)==KERN_SUCCESS);
    if(object!=MACH_PORT_NULL)mach_port_deallocate(mach_task_self(),object);
    assert(address<=(vm_address_t)pointer && (vm_address_t)pointer-address<size);
    return info.protection;
}
// Whether anything is mapped at this address now.
static bool mapped(void *pointer) {
    vm_address_t address=(vm_address_t)pointer; vm_size_t size=0;
    vm_region_basic_info_data_64_t info={0}; mach_msg_type_number_t count=VM_REGION_BASIC_INFO_COUNT_64;
    mach_port_t object=MACH_PORT_NULL;
    if(vm_region_64(mach_task_self(),&address,&size,VM_REGION_BASIC_INFO_64,(vm_region_info_t)&info,&count,&object)!=KERN_SUCCESS) return false;
    if(object!=MACH_PORT_NULL)mach_port_deallocate(mach_task_self(),object);
    return address<=(vm_address_t)pointer && (vm_address_t)pointer-address<size;
}

static bool accept_zeroed_pages(void *address, size_t size, void *context) {
    unsigned *calls = context;
    (*calls)++;
    const unsigned char *bytes = address;
    for (size_t i = 0; i < size; i++) assert(bytes[i] == 0);
    // This fixture validates aliases only. It does not grant executable permission.
    return true;
}
static bool reject_pages(void *address, size_t size, void *context) {
    (void)address; (void)size; (void)context;
    return false;
}
// The mapping is the point, not its contents.
static NCPreparation accept_without_reading(void *address,size_t size,void *context) {
    (void)address; (void)size; (void)context; return NC_PREPARED;
}
static NCPreparation uncertain_pages(void *address,size_t size,void *context) {
    assert(accept_zeroed_pages(address,size,context)); return NC_UNCERTAIN;
}
static void *sentinel_at(void *pointer,size_t page) {
    vm_address_t address=(vm_address_t)pointer;
    assert(vm_allocate(mach_task_self(),&address,page,VM_FLAGS_FIXED)==KERN_SUCCESS);
    assert(address==(vm_address_t)pointer);
    memset(pointer,0xa7,page);
    return pointer;
}
static void test_trim(size_t page) {
    void *region=mmap(NULL,4*page,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);
    assert(region!=MAP_FAILED);
    memset(region,0x69,4*page);
    assert(!mprotect(region,4*page,PROT_READ));
    NativeCodeMemory memory={0};
    assert(nc_adopt(&memory,region,4*page));
    void *alias=memory.writable;
    assert(memory.executable_size==4*page && memory.writable_size==4*page);
    assert(!nc_trim(NULL,page) && errno==EINVAL);
    assert(!nc_trim(&memory,0) && errno==EINVAL);
    assert(!nc_trim(&memory,5*page) && errno==EINVAL);
    assert(!nc_trim(&memory,page+1) && errno==EINVAL);
    assert(!nc_trim(&memory,SIZE_MAX) && errno==EINVAL);
    NativeCodeMemory invalid={0};
    assert(!nc_trim(&invalid,page) && errno==EINVAL);
    invalid=memory; invalid.published=false;
    assert(!nc_trim(&invalid,page) && errno==EINVAL);
    invalid=memory; invalid.quarantined=true;
    assert(!nc_trim(&invalid,page) && errno==EINVAL);
    invalid=memory; invalid.executable=NULL;
    assert(!nc_trim(&invalid,page) && errno==EINVAL);
    invalid=memory; invalid.writable=NULL;
    assert(!nc_trim(&invalid,page) && errno==EINVAL);
    invalid=memory; invalid.executable_size=page;
    assert(!nc_trim(&invalid,page) && errno==EINVAL);
    invalid=memory; invalid.writable_size=page;
    assert(!nc_trim(&invalid,page) && errno==EINVAL);
    invalid=memory; invalid.executable=(char *)region+1;
    assert(!nc_trim(&invalid,page) && errno==EINVAL);
    invalid=memory; invalid.writable=(char *)region+page; // overlapping views
    assert(!nc_trim(&invalid,page) && errno==EINVAL);
    invalid=memory; invalid.writable=region;
    assert(!nc_trim(&invalid,page) && errno==EINVAL);
    invalid=memory; invalid.executable=(void *)(UINTPTR_MAX-page+1);
    assert(!nc_trim(&invalid,page) && errno==EINVAL);
    assert(memory.published && memory.size==4*page && mapped((char *)region+3*page));
    assert(nc_trim(&memory,4*page)); // exact size is a no-op
    assert(nc_trim(&memory,2*page));
    assert(memory.size==2*page && memory.executable_size==2*page && memory.writable_size==2*page);
    assert(memory.published && memory.executable==region && memory.writable==alias);
    assert(!mapped((char *)region+2*page) && !mapped((char *)region+3*page));
    assert(!mapped((char *)alias+2*page) && !mapped((char *)alias+3*page));
    assert(!(protection(region)&VM_PROT_WRITE) && (protection(alias)&VM_PROT_WRITE));
    for(size_t i=0;i<2*page;i++)assert(((unsigned char *)region)[i]==0x69);
    assert(nc_clear(&memory,page));
    for(size_t i=0;i<page;i++)assert(((unsigned char *)region)[i]==0);
    assert(((unsigned char *)region)[page]==0x69);
    unsigned char bytes[16]; memset(bytes,0x53,sizeof bytes);
    assert(nc_write(&memory,page-8,bytes,sizeof bytes));
    assert(!memcmp((char *)region+page-8,bytes,sizeof bytes));
    assert(!nc_write(&memory,2*page-8,bytes,sizeof bytes) && errno==EINVAL);
    assert(!nc_clear(&memory,2*page+1) && errno==EINVAL);
    assert(nc_trim(&memory,2*page));
    assert(nc_trim(&memory,page));
    assert(!mapped((char *)region+page) && !mapped((char *)alias+page));
    // Cleanup of the shortened owner must leave reused tail addresses alone.
    void *rx_sentinel=sentinel_at((char *)region+page,page);
    void *rw_sentinel=sentinel_at((char *)alias+page,page);
    nc_destroy(&memory);
    assert(!mapped(region) && !mapped(alias));
    assert(mapped(rx_sentinel) && mapped(rw_sentinel));
    assert(((unsigned char *)rx_sentinel)[0]==0xa7 && ((unsigned char *)rw_sentinel)[0]==0xa7);
    assert(!munmap(rx_sentinel,page) && !munmap(rw_sentinel,page));
    assert(!memory.executable && !memory.writable && !memory.executable_size && !memory.writable_size);
}
int main(void) {
    NativeCodeMemory memory = {0};
    size_t page = (size_t)getpagesize(); unsigned calls = 0;
    assert(!nc_create(&memory, 0, accept_zeroed_pages, &calls) && errno == EINVAL);
    assert(!nc_create(&memory, page + 1, accept_zeroed_pages, &calls) && errno == EINVAL);
    assert(!nc_create(&memory, page, NULL, NULL) && errno == EINVAL);
    assert(!nc_create(&memory, page, reject_pages, NULL) && errno == EPERM);
    assert(!memory.executable && !memory.writable && !memory.size);
    assert(nc_create(&memory, 2 * page, accept_zeroed_pages, &calls));
    assert(calls == 1 && memory.executable != memory.writable);
    assert(memory.executable_size==2*page && memory.writable_size==2*page);
    assert(!(protection(memory.executable)&VM_PROT_WRITE) && (protection(memory.writable)&VM_PROT_WRITE));
    assert(!nc_create(&memory, page, accept_zeroed_pages, &calls));
    unsigned char data[16]; memset(data, 0x53, sizeof data);
    assert(nc_write(&memory, page - 8, data, sizeof data));
    assert(!memcmp((char *)memory.executable + page - 8, data, sizeof data));
    assert(!nc_write(&memory, SIZE_MAX, data, sizeof data));
    assert(!nc_write(&memory, 2 * page - 8, data, sizeof data));
    assert(!nc_write(&memory, 0, NULL, 4));
    assert(nc_write(&memory, 2 * page, data, 0));
    nc_destroy(&memory);
    assert(!memory.executable && !memory.writable && !memory.size);
    nc_destroy(&memory);
    NativeCodeMemory quarantine={0};
    assert(!nc_create_managed(&memory,page,uncertain_pages,&calls,&quarantine) && errno==EINPROGRESS);
    assert(!memory.executable && !memory.published);
    assert(quarantine.executable && quarantine.writable && quarantine.quarantined && !quarantine.published);
    assert(quarantine.executable_size==page && quarantine.writable_size==page);
    assert(!(protection(quarantine.executable)&VM_PROT_WRITE) && !(protection(quarantine.writable)&VM_PROT_WRITE));
    assert(!nc_write(&quarantine,0,data,sizeof data));
    assert(!nc_clear(&quarantine,page) && errno==EINVAL);
    assert(!nc_trim(&quarantine,page) && errno==EINVAL);
    void *retained=quarantine.executable;
    nc_destroy(&quarantine);
    assert(quarantine.executable==retained && ((unsigned char *)retained)[0]==0);
    // A mapping we did not make: nc_adopt adds the alias.
    void *foreign=mmap(NULL,2*page,PROT_READ|PROT_EXEC,MAP_PRIVATE|MAP_ANON,-1,0);
    if(foreign==MAP_FAILED) foreign=mmap(NULL,2*page,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);
    assert(foreign!=MAP_FAILED);
    NativeCodeMemory adopted={0};
    assert(!nc_adopt(&adopted,NULL,2*page) && errno==EINVAL);
    assert(!nc_adopt(&adopted,foreign,0) && errno==EINVAL);
    assert(!nc_adopt(&adopted,foreign,page+1) && errno==EINVAL);
    assert(!nc_adopt(&adopted,(char *)foreign+8,2*page) && errno==EINVAL);
    // The ceiling bounds an adoption; what the device has left does not.
    assert(!nc_adopt(&adopted,foreign,(size_t)NC_MAX_ARENA+page) && errno==EINVAL);
    assert(!adopted.executable && !adopted.writable);
    assert(nc_adopt(&adopted,foreign,2*page));
    assert(adopted.published && adopted.executable==foreign && adopted.writable!=foreign);
    assert(adopted.executable_size==2*page && adopted.writable_size==2*page);
    assert(protection(adopted.writable)&VM_PROT_WRITE);
    assert(!nc_adopt(&adopted,foreign,2*page) && errno==EINVAL); // already owns a mapping
    assert(nc_write(&adopted,page,data,sizeof data));
    assert(!memcmp((char *)adopted.executable+page,data,sizeof data));
    void *alias=adopted.writable;
    nc_destroy(&adopted);
    assert(!adopted.executable && !adopted.writable);
    // Adopted, the region is ours: teardown unmaps it with the alias.
    assert(!mapped(foreign) && !mapped(alias));

    // An enabler touches every page before adoption. Zero-fill sections must
    // read as zero through RX even when no image bytes are placed in them.
    void *touched=mmap(NULL,3*page,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);
    assert(touched!=MAP_FAILED);
    memset(touched,0x69,3*page);
    assert(!mprotect(touched,3*page,PROT_READ));
    NativeCodeMemory clearing={0};
    assert(nc_adopt(&clearing,touched,3*page));
    assert(!nc_clear(NULL,page) && errno==EINVAL);
    assert(!nc_clear(&clearing,3*page+1) && errno==EINVAL);
    assert(!nc_clear(&clearing,SIZE_MAX) && errno==EINVAL);
    assert(((unsigned char *)clearing.executable)[0]==0x69);
    assert(nc_clear(&clearing,0));
    assert(((unsigned char *)clearing.executable)[0]==0x69);
    assert(nc_clear(&clearing,2*page));
    for(size_t i=0;i<2*page;i++)assert(((unsigned char *)clearing.executable)[i]==0);
    for(size_t i=2*page;i<3*page;i++)assert(((unsigned char *)clearing.executable)[i]==0x69);
    assert(!(protection(clearing.executable)&VM_PROT_WRITE));
    assert(nc_write(&clearing,page-8,data,sizeof data));
    assert(!memcmp((char *)clearing.executable+page-8,data,sizeof data));
    assert(((unsigned char *)clearing.executable)[page+8]==0);
    assert(nc_clear(&clearing,2*page));
    assert(((unsigned char *)clearing.executable)[page-8]==0);
    alias=clearing.writable;
    nc_destroy(&clearing);
    assert(!mapped(touched) && !mapped(alias));
    assert(!nc_clear(&clearing,page) && errno==EINVAL);
    test_trim(page);

    unsigned old_calls=calls;
    assert(!nc_create_managed(&memory,page,uncertain_pages,&calls,&quarantine) && errno==EINVAL);
    assert(calls==old_calls); // No second helper attempt or allocation.
    // Quarantined mappings intentionally live until process exit.

    // Any route accepts up to the ceiling (more than the old 128 MiB); only a
    // launch compares with what the device has left (nc_launch_limit).
    NativeCodeMemory large={0},spare={0};
    size_t big=160u*1024u*1024u;
    assert(nc_arena_limit()<=nc_launch_limit() && nc_launch_limit()<=NC_MAX_ARENA);
    assert(!(nc_arena_limit()%page) && !(nc_launch_limit()%page));
    if(big<=nc_launch_limit()) {
        assert(nc_create_managed(&large,big,accept_without_reading,NULL,&spare));
        assert(large.size==big && large.published);
        nc_destroy(&large);
    }
    assert(!nc_create_managed(&large,(size_t)NC_MAX_ARENA+page,accept_without_reading,NULL,&spare) && errno==EINVAL);
    assert(!large.executable && !large.writable);
    NativeCodeMemory stale={.executable_size=page};
    assert(!nc_create_managed(&stale,page,accept_without_reading,NULL,&spare) && errno==EINVAL);
    assert(!nc_adopt(&stale,(void *)page,page) && errno==EINVAL);
    stale=(NativeCodeMemory){.writable_size=page};
    assert(!nc_create_managed(&stale,page,accept_without_reading,NULL,&spare) && errno==EINVAL);
    assert(!nc_adopt(&stale,(void *)page,page) && errno==EINVAL);
    assert(!nc_create_managed(&large,page,accept_without_reading,NULL,&stale) && errno==EINVAL);
    puts("PASS: native alias coherence, bounds, rejection cleanup, uncertain quarantine, write/retry denial (no generated code executed)");
    puts("PASS: device-sized arena limit, adopted image zero-fill, reserved tail preservation (no generated code executed)");
    puts("PASS: arena tail trim, retained aliases/protection, bounds and cleanup after tail address reuse (no generated code executed)");
}
