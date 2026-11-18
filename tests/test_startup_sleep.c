// Synthetic waits only: no guest images, debugger or imported application.
#include "GuestWait.h"
#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
static unsigned pumps;
static bool nest, slow, stop;
static double now(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+t.tv_nsec/1e9; }
static void pump(void) {
    pumps++;
    if (stop) gw_set_startup_pump(NULL);
    if (nest) { unsigned before=pumps; assert(!gw_usleep(1000)); assert(!gw_sleep(0)); assert(pumps==before); }
    if (slow) usleep(20000);
    errno=EDOM; // Native UI callbacks must not corrupt the caller's errno.
}
static void *worker(void *unused) {
    (void)unused; unsigned before=pumps; assert(!gw_usleep(20000)); assert(pumps==before); return NULL;
}
static pthread_t main_thread;
static void signal_handler(int signal) { (void)signal; }
static atomic_bool stop_interrupt;
static void *interrupt(void *unused) {
    (void)unused;
    usleep(25000);
    while (!atomic_load(&stop_interrupt)) {
        pthread_kill(main_thread, SIGUSR1);
        usleep(1000);
    }
    return NULL;
}
static void begin_interrupt(pthread_t *thread) {
    atomic_store(&stop_interrupt, false);
    assert(!pthread_create(thread, NULL, interrupt, NULL));
}
static void end_interrupt(pthread_t thread) {
    atomic_store(&stop_interrupt, true);
    assert(!pthread_join(thread, NULL));
}
int main(void) {
    alarm(10); main_thread=pthread_self();
    gw_set_startup_pump(NULL); errno=EAGAIN; assert(!gw_usleep(1000) && !pumps);
    gw_set_startup_pump(pump);
    struct timespec invalid={0,1000000000},request={0,80000000},remaining={123,456};
    errno=0; assert(gw_nanosleep(&invalid,NULL)==-1 && errno==EINVAL && !pumps);
    nest=true; errno=EAGAIN; double began=now();
    assert(!gw_nanosleep(&request,&remaining));
    double elapsed=now()-began;
    if (!(elapsed>=.08 && pumps>2 && errno==EAGAIN))
        fprintf(stderr,"cooperative wait: elapsed=%.9f pumps=%u errno=%d\n",elapsed,pumps,errno);
    assert(elapsed>=.08 && pumps>2 && errno==EAGAIN);
    assert(remaining.tv_sec==123 && remaining.tv_nsec==456); // Success leaves it alone.
    nest=false; slow=true; began=now(); request=(struct timespec){0,50000000};
    assert(!gw_nanosleep(&request,NULL)); assert(now()-began>=.05 && now()-began<.15);
    slow=false; stop=true; unsigned stopped=pumps; began=now(); request=(struct timespec){0,30000000};
    assert(!gw_nanosleep(&request,NULL) && pumps==stopped+1 && now()-began>=.03);
    stop=false; gw_set_startup_pump(pump);
    pthread_t thread; assert(!pthread_create(&thread,NULL,worker,NULL)); assert(!pthread_join(thread,NULL));
    struct sigaction action={0}; action.sa_handler=signal_handler; sigemptyset(&action.sa_mask); assert(!sigaction(SIGUSR1,&action,NULL));
    request=(struct timespec){1,0};
    begin_interrupt(&thread);
    int result=gw_nanosleep(&request,&request), code=errno;
    end_interrupt(thread);
    assert(result==-1 && code==EINTR); // Aliased request/remainder.
    assert(request.tv_sec==0 && request.tv_nsec>0 && request.tv_nsec<1000000000);
    begin_interrupt(&thread);
    result=gw_usleep(1500000); code=errno;
    end_interrupt(thread);
    assert(result==-1 && code==EINTR);
    begin_interrupt(&thread);
    unsigned slept=gw_sleep(2);
    end_interrupt(thread);
    assert(slept>0 && slept<=2);
    unsigned before=pumps; gw_set_startup_pump(NULL); assert(!gw_usleep(20000) && pumps==before);
    alarm(0);
    puts("STARTUP_SLEEP_PASS: bounded cooperative waits, worker/nested bypass, monotonic deadlines, native errors, EINTR/remainder, aliases, sleep/usleep and disabled lifecycle.");
    return 0;
}
