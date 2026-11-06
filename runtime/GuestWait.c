#include "GuestWait.h"
#include <errno.h>
int gw_wait(GWWait wait, uint32_t operation, void *address, uint64_t value,
            uint32_t microseconds, bool main_thread, GWPending pending, GWPump pump) {
    // UL_COMPARE_AND_WAIT without flags is the client's job-completion wait.
    // Do not pump while owning an unfair lock or change finite timeout semantics.
    if (!main_thread || operation != 1 || microseconds || !pending || !pump)
        return wait(operation, address, value, microseconds);
    int original_errno = errno;
    for (;;) {
        errno = original_errno;
        int result = wait(operation, address, value, 10000);
        int native_errno = errno;
        if (result != -1 || native_errno != ETIMEDOUT) {
            errno = native_errno;
            return result;
        }
        if (pending()) pump();
    }
}


#include <pthread.h>
// Only the main thread reads or writes the callback. The TLS guard prevents a
// UIKit callback that itself sleeps from recursively entering the startup pump.
static GWPump startup_pump;
static _Thread_local bool pumping_startup_sleep;
void gw_set_startup_pump(GWPump pump) { startup_pump = pump; }
static bool startup_sleep_active(void) {
    return pthread_main_np() && !pumping_startup_sleep && startup_pump;
}
static struct timespec startup_sleep_remaining(struct timespec requested, struct timespec began) {
    struct timespec now;
    clock_gettime(CLOCK_MONOTONIC, &now);
    time_t seconds = now.tv_sec - began.tv_sec;
    long nanos = now.tv_nsec - began.tv_nsec;
    if (nanos < 0) { seconds--; nanos += 1000000000L; }
    if (seconds > requested.tv_sec || (seconds == requested.tv_sec && nanos >= requested.tv_nsec))
        return (struct timespec){0,0};
    struct timespec left = {requested.tv_sec - seconds, requested.tv_nsec - nanos};
    if (left.tv_nsec < 0) { left.tv_sec--; left.tv_nsec += 1000000000L; }
    return left;
}
int gw_nanosleep(const struct timespec *request, struct timespec *remaining) {
    if (!startup_sleep_active() || !request || request->tv_sec < 0 ||
        request->tv_nsec < 0 || request->tv_nsec >= 1000000000L)
        return nanosleep(request, remaining);
    // Copy before writing remaining: callers may use the same timespec for both.
    struct timespec requested = *request, began;
    if (clock_gettime(CLOCK_MONOTONIC, &began)) return nanosleep(request, remaining);
    int original_errno = errno, result = 0, result_errno = original_errno;
    pumping_startup_sleep = true;
    for (;;) {
        GWPump pump = startup_pump;
        if (pump) pump();
        struct timespec left = startup_sleep_remaining(requested, began);
        if (!left.tv_sec && !left.tv_nsec) break;
        // A window becoming visible during the callback ends this policy too.
        struct timespec slice = left;
        if (startup_pump && (slice.tv_sec || slice.tv_nsec > 10000000L))
            slice = (struct timespec){0,10000000L};
        errno = original_errno;
        result = nanosleep(&slice, NULL);
        if (result) {
            result_errno = errno;
            if (result_errno == EINTR && remaining)
                *remaining = startup_sleep_remaining(requested, began);
            break;
        }
    }
    pumping_startup_sleep = false;
    errno = result_errno;
    return result;
}
int gw_usleep(useconds_t microseconds) {
    if (!startup_sleep_active()) return usleep(microseconds);
    // Darwin accepts the full useconds_t range, including values >= one second.
    struct timespec request = {microseconds / 1000000, (long)(microseconds % 1000000) * 1000};
    return gw_nanosleep(&request, NULL);
}
unsigned gw_sleep(unsigned seconds) {
    if (!startup_sleep_active()) return sleep(seconds);
    struct timespec request = {seconds,0}, remaining = {0,0};
    return gw_nanosleep(&request, &remaining) ? (unsigned)remaining.tv_sec + (remaining.tv_nsec != 0) : 0;
}
