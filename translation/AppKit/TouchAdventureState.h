#pragma once
#include <stdbool.h>

// Human-driven movement/camera gestures only; independent of guest state.
typedef enum {
    AKAdventureKeyDown, AKAdventureKeyUp,
    AKAdventureCameraDown, AKAdventureCameraUp,
    AKAdventureCameraMove, AKAdventureTap,
} AKAdventureAction;
typedef void (*AKAdventureEmit)(void *context, AKAdventureAction action,
                                double x, double y, unsigned short keyCode);

typedef struct { unsigned keys; } AKAdventureJoystick;
typedef struct {
    bool active, dragging;
    double startX, startY, x, y, started, lastTime;
} AKAdventureCamera;

// Normalized displacement from the stick's fixed centre; UIKit y increases down.
void AKAdventureJoystickUpdate(AKAdventureJoystick *stick, double x, double y,
                              AKAdventureEmit emit, void *context);
void AKAdventureJoystickCancel(AKAdventureJoystick *stick, AKAdventureEmit emit, void *context);
// Starting a touch never emits pointer motion. Only a drag past the movement
// threshold presses the right button; subsequent movement remains relative.
void AKAdventureCameraBegin(AKAdventureCamera *camera, double x, double y, double time,
                            AKAdventureEmit emit, void *context);
void AKAdventureCameraUpdate(AKAdventureCamera *camera, double x, double y, double time,
                             AKAdventureEmit emit, void *context);
void AKAdventureCameraEnd(AKAdventureCamera *camera, double time, bool cancelled,
                          AKAdventureEmit emit, void *context);
