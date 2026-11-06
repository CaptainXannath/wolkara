#pragma once
#include <stdbool.h>
#include <stdint.h>
typedef int (*GWWait)(uint32_t operation, void *address, uint64_t value, uint32_t microseconds);
typedef bool (*GWPending)(void);
typedef void (*GWPump)(void);
// Keep the host responsive only while a shader worker is paused. Other wait
// operations, explicit deadlines, native errors and wakeups retain their ABI.
int gw_wait(GWWait wait, uint32_t operation, void *address, uint64_t value,
            uint32_t microseconds, bool main_thread, GWPending pending, GWPump pump);

// Main-thread-only lifecycle: the launcher enables this before native startup
// and clears it when the guest window appears or startup stops. Worker sleeps
// and nested callbacks always use the system implementation unchanged.
#include <time.h>
#include <unistd.h>
void gw_set_startup_pump(GWPump pump);
int gw_nanosleep(const struct timespec *request, struct timespec *remaining);
int gw_usleep(useconds_t microseconds);
unsigned gw_sleep(unsigned seconds);
