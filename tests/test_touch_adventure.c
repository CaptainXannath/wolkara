// Synthetic contacts only: no application, credentials, or generated gameplay.
#include "TouchAdventureState.h"
#include <assert.h>
#include <float.h>
#include <math.h>
#include <stdio.h>

typedef struct { AKAdventureAction action; double x, y; unsigned short key; } Event;
typedef struct { Event events[64]; unsigned count; } Trace;
static void emit(void *context, AKAdventureAction action, double x, double y, unsigned short key) {
    Trace *trace = context;
    assert(trace->count < 64);
    trace->events[trace->count++] = (Event){action, x, y, key};
}
static void checkKey(Trace *trace, unsigned at, AKAdventureAction action, unsigned short key) {
    assert(at < trace->count && trace->events[at].action == action && trace->events[at].key == key);
}
typedef struct { Trace trace; AKAdventureCamera *camera; } CancelOnDown;
static void rejectCamera(void *context, AKAdventureAction action, double x, double y, unsigned short key) {
    CancelOnDown *test = context;
    emit(&test->trace, action, x, y, key);
    if (action == AKAdventureCameraDown)
        AKAdventureCameraEnd(test->camera, 0, true, rejectCamera, context);
}
int main(void) {
    Trace trace = {0}; AKAdventureJoystick stick = {0}; AKAdventureCamera camera = {0};
    // Dead zone and hysteresis: no repeating key-downs from stationary fingers.
    AKAdventureJoystickUpdate(&stick, 0.29, -0.29, emit, &trace);
    assert(!trace.count);
    AKAdventureJoystickUpdate(&stick, 0.8, -0.8, emit, &trace);
    assert(trace.count == 2);
    checkKey(&trace, 0, AKAdventureKeyDown, 13); // W
    checkKey(&trace, 1, AKAdventureKeyDown, 2); // D
    AKAdventureJoystickUpdate(&stick, 0.8, -0.8, emit, &trace);
    AKAdventureJoystickUpdate(&stick, 0.25, -0.25, emit, &trace);
    assert(trace.count == 2);
    AKAdventureJoystickUpdate(&stick, -0.8, 0.8, emit, &trace);
    assert(trace.count == 6);
    checkKey(&trace, 2, AKAdventureKeyUp, 13);
    checkKey(&trace, 3, AKAdventureKeyUp, 2);
    checkKey(&trace, 4, AKAdventureKeyDown, 0); // A
    checkKey(&trace, 5, AKAdventureKeyDown, 1); // S
    AKAdventureJoystickCancel(&stick, emit, &trace);
    AKAdventureJoystickCancel(&stick, emit, &trace);
    assert(trace.count == 8 && !stick.keys);
    checkKey(&trace, 6, AKAdventureKeyUp, 0);
    checkKey(&trace, 7, AKAdventureKeyUp, 1);
    trace.count = 0;
    AKAdventureJoystickUpdate(&stick, -1, 0, emit, &trace);
    AKAdventureJoystickUpdate(&stick, NAN, 0, emit, &trace);
    assert(trace.count == 2 && !stick.keys);
    AKAdventureJoystickUpdate(&stick, 0, 1, emit, &trace);
    AKAdventureJoystickUpdate(&stick, 0, INFINITY, emit, &trace);
    assert(trace.count == 4 && !stick.keys);
    // Touching different screen positions never teleports the pointer. The
    // first drag delta is finger displacement, not the absolute touch point.
    for (unsigned i = 0; i < 2; i++) {
        trace.count = 0;
        double x = i ? 1600 : 300, y = i ? 900 : 50;
        AKAdventureCameraBegin(&camera, x, y, 1, emit, &trace);
        assert(!trace.count);
        AKAdventureCameraUpdate(&camera, x + 2, y + 1, 1.01, emit, &trace);
        assert(!trace.count);
        AKAdventureCameraUpdate(&camera, x + 8, y + 2, 1.02, emit, &trace);
        assert(trace.count == 2 && trace.events[0].action == AKAdventureCameraDown);
        assert(trace.events[1].action == AKAdventureCameraMove);
        assert(trace.events[1].x == 8 && trace.events[1].y == 2);
        AKAdventureCameraUpdate(&camera, x + 13, y - 2, 1.03, emit, &trace);
        assert(trace.count == 3 && trace.events[2].x == 5 && trace.events[2].y == -4);
        AKAdventureCameraEnd(&camera, 1.04, false, emit, &trace);
        AKAdventureCameraEnd(&camera, 1.05, false, emit, &trace);
        assert(trace.count == 4 && trace.events[3].action == AKAdventureCameraUp);
    }
    // A stationary short contact selects the world at its own starting point;
    // no click follows a camera drag, cancelled touch, or a long stationary hold.
    trace.count = 0;
    AKAdventureCameraBegin(&camera, 400, 80, 2, emit, &trace);
    AKAdventureCameraUpdate(&camera, 402, 81, 2.02, emit, &trace);
    AKAdventureCameraEnd(&camera, 2.2, false, emit, &trace);
    assert(trace.count == 1 && trace.events[0].action == AKAdventureTap);
    assert(trace.events[0].x == 400 && trace.events[0].y == 80);
    AKAdventureCameraBegin(&camera, 600, 90, 3, emit, &trace);
    AKAdventureCameraEnd(&camera, 4, false, emit, &trace);
    AKAdventureCameraBegin(&camera, 600, 90, 5, emit, &trace);
    AKAdventureCameraEnd(&camera, 5.1, true, emit, &trace);
    assert(trace.count == 1);
    // Direct ability/menu touches and lifecycle changes cancel right-down once.
    trace.count = 0;
    AKAdventureCameraBegin(&camera, 400, 100, 6, emit, &trace);
    AKAdventureCameraUpdate(&camera, 410, 100, 6.1, emit, &trace);
    AKAdventureCameraEnd(&camera, 0, true, emit, &trace);
    AKAdventureCameraUpdate(&camera, 800, 200, 6.2, emit, &trace);
    AKAdventureCameraEnd(&camera, 6.3, false, emit, &trace);
    assert(trace.count == 3 && trace.events[2].action == AKAdventureCameraUp);
    // The stick may stay held across a camera gesture, independently.
    trace.count = 0;
    AKAdventureJoystickUpdate(&stick, 0, -1, emit, &trace);
    AKAdventureCameraBegin(&camera, 400, 100, 7, emit, &trace);
    AKAdventureCameraUpdate(&camera, 410, 100, 7.1, emit, &trace);
    AKAdventureCameraEnd(&camera, 7.2, true, emit, &trace);
    assert(stick.keys == 1 && trace.count == 4);
    AKAdventureJoystickCancel(&stick, emit, &trace);
    checkKey(&trace, 4, AKAdventureKeyUp, 13);
    // Bad coordinates/timestamps release any held button and never emit a tap.
    for (unsigned kind = 0; kind < 4; kind++) {
        trace.count = 0;
        AKAdventureCameraBegin(&camera, 400, 100, 8, emit, &trace);
        AKAdventureCameraUpdate(&camera, 410, 100, 8.1, emit, &trace);
        if (kind == 0) AKAdventureCameraUpdate(&camera, NAN, 100, 8.2, emit, &trace);
        if (kind == 1) AKAdventureCameraUpdate(&camera, 415, 100, INFINITY, emit, &trace);
        if (kind == 2) AKAdventureCameraUpdate(&camera, 415, 100, 7, emit, &trace);
        if (kind == 3) AKAdventureCameraBegin(&camera, NAN, 100, 9, emit, &trace);
        assert(trace.count == 3 && trace.events[2].action == AKAdventureCameraUp && !camera.active);
    }
    trace.count = 0;
    AKAdventureCameraBegin(&camera, -DBL_MAX, 100, 9, emit, &trace);
    AKAdventureCameraUpdate(&camera, DBL_MAX, 100, 9.1, emit, &trace);
    assert(!trace.count && !camera.active);
    CancelOnDown rejected = {.camera = &camera};
    AKAdventureCameraBegin(&camera, 100, 100, 10, rejectCamera, &rejected);
    AKAdventureCameraUpdate(&camera, 110, 100, 10.1, rejectCamera, &rejected);
    assert(rejected.trace.count == 2 && !camera.active);
    assert(rejected.trace.events[0].action == AKAdventureCameraDown &&
           rejected.trace.events[1].action == AKAdventureCameraUp);
    AKAdventureCameraBegin(NULL, 0, 0, 0, emit, &trace);
    AKAdventureCameraUpdate(NULL, 0, 0, 0, emit, &trace);
    AKAdventureCameraEnd(NULL, 0, false, emit, &trace);
    AKAdventureJoystickUpdate(NULL, 0, 0, emit, &trace);
    AKAdventureJoystickCancel(NULL, emit, &trace);
    puts("touch adventure: directional holds, relative camera, tap, cancellation and malformed traces: PASS");
}
