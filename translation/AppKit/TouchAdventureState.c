#include "TouchAdventureState.h"
#include <math.h>
#include <stddef.h>

static const unsigned short keyCodes[] = {13, 0, 1, 2}; // W, A, S, D
static void keysChanged(AKAdventureJoystick *stick, unsigned next,
                        AKAdventureEmit emit, void *context) {
    unsigned previous = stick->keys;
    stick->keys = next;
    if (!emit) return;
    // Release before pressing the opposite direction, even after a large move.
    for (unsigned i = 0; i < 4; i++)
        if ((previous & (1u << i)) && !(next & (1u << i)))
            emit(context, AKAdventureKeyUp, 0, 0, keyCodes[i]);
    for (unsigned i = 0; i < 4; i++)
        if (!(previous & (1u << i)) && (next & (1u << i)))
            emit(context, AKAdventureKeyDown, 0, 0, keyCodes[i]);
}

void AKAdventureJoystickUpdate(AKAdventureJoystick *stick, double x, double y,
                              AKAdventureEmit emit, void *context) {
    if (!stick) return;
    if (!isfinite(x) || !isfinite(y)) {
        AKAdventureJoystickCancel(stick, emit, context);
        return;
    }
    // Axis thresholds with hysteresis stop a stationary finger chattering at
    // the dead zone. Diagonals hold exactly the two corresponding keys.
    double directions[] = {-y, -x, y, x};
    unsigned next = 0;
    for (unsigned i = 0; i < 4; i++) {
        double threshold = (stick->keys & (1u << i)) ? 0.20 : 0.30;
        if (directions[i] > threshold) next |= 1u << i;
    }
    keysChanged(stick, next, emit, context);
}

void AKAdventureJoystickCancel(AKAdventureJoystick *stick, AKAdventureEmit emit, void *context) {
    if (stick) keysChanged(stick, 0, emit, context);
}

void AKAdventureCameraEnd(AKAdventureCamera *camera, double time, bool cancelled,
                          AKAdventureEmit emit, void *context) {
    if (!camera || !camera->active) return;
    AKAdventureCamera previous = *camera;
    *camera = (AKAdventureCamera){0};
    if (!emit) return;
    if (previous.dragging) emit(context, AKAdventureCameraUp, 0, 0, 0);
    else if (!cancelled && isfinite(time) && time >= previous.lastTime &&
             time - previous.started <= 0.45)
        emit(context, AKAdventureTap, previous.startX, previous.startY, 0);
}

void AKAdventureCameraBegin(AKAdventureCamera *camera, double x, double y, double time,
                            AKAdventureEmit emit, void *context) {
    if (!camera) return;
    AKAdventureCameraEnd(camera, time, true, emit, context);
    if (!isfinite(x) || !isfinite(y) || !isfinite(time)) return;
    *camera = (AKAdventureCamera){
        .active = true, .startX = x, .startY = y, .x = x, .y = y,
        .started = time, .lastTime = time,
    };
}

void AKAdventureCameraUpdate(AKAdventureCamera *camera, double x, double y, double time,
                             AKAdventureEmit emit, void *context) {
    if (!camera || !camera->active) return;
    double dx = x - camera->x, dy = y - camera->y;
    if (!isfinite(x) || !isfinite(y) || !isfinite(time) ||
        !isfinite(dx) || !isfinite(dy) || time < camera->lastTime) {
        AKAdventureCameraEnd(camera, time, true, emit, context);
        return;
    }
    camera->lastTime = time;
    if (!camera->dragging) {
        dx = x - camera->startX; dy = y - camera->startY;
        if (hypot(dx, dy) < 6.0) return;
        camera->dragging = true;
        if (emit) emit(context, AKAdventureCameraDown, 0, 0, 0);
        // The host may reject the camera while another finger owns a direct
        // ability drag. Its down callback cancels us synchronously.
        if (!camera->active || !camera->dragging) return;
    }
    camera->x = x; camera->y = y;
    if (emit && (dx != 0 || dy != 0)) emit(context, AKAdventureCameraMove, dx, dy, 0);
}
