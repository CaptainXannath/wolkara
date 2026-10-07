#import "TouchAdventure.h"
#import "TouchAdventureState.h"
#include <math.h>

@interface AKTouchAdventure ()
- (void)emitAction:(AKAdventureAction)action x:(double)x y:(double)y key:(unsigned short)key;
@end

static void AKAdventureDeliver(void *context, AKAdventureAction action, double x, double y,
                               unsigned short key) {
    [(__bridge AKTouchAdventure *)context emitAction:action x:x y:y key:key];
}

@implementation AKTouchAdventure {
    UIView *_stickRing, *_stickThumb;
    UITouch *_stickTouch, *_cameraTouch;
    AKAdventureJoystick _stick;
    AKAdventureCamera _camera;
    CGPoint _stickCentre;
    CGSize _viewportSize;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _reservedRightFraction = 0.33;
        _reservedBottomFraction = 0.16;
        self.multipleTouchEnabled = YES;
        self.backgroundColor = UIColor.clearColor;
        self.accessibilityIdentifier = @"wolkara.adventure";
        _stickRing = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 116, 116)];
        _stickRing.backgroundColor = [UIColor colorWithWhite:1 alpha:0.08];
        _stickRing.layer.borderWidth = 1.5;
        _stickRing.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.35].CGColor;
        _stickRing.layer.cornerRadius = 58;
        _stickRing.userInteractionEnabled = NO;
        _stickRing.accessibilityIdentifier = @"wolkara.adventure.stick";
        [self addSubview:_stickRing];
        _stickThumb = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 48, 48)];
        _stickThumb.backgroundColor = [UIColor colorWithWhite:1 alpha:0.25];
        _stickThumb.layer.borderWidth = 1;
        _stickThumb.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.55].CGColor;
        _stickThumb.layer.cornerRadius = 24;
        _stickThumb.userInteractionEnabled = NO;
        [self addSubview:_stickThumb];
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(cancelTouches)
            name:UIApplicationWillResignActiveNotification object:nil];
        self.hidden = YES;
    }
    return self;
}
- (void)setEnabled:(BOOL)enabled {
    if (_enabled == enabled) return;
    _enabled = enabled;
    if (!enabled) [self cancelTouches];
    self.hidden = !enabled;
}
- (void)setHidden:(BOOL)hidden {
    if (hidden) [self cancelTouches];
    [super setHidden:hidden];
}
- (void)setReservedRightFraction:(CGFloat)value {
    if (!isfinite(value)) return;
    _reservedRightFraction = MAX(0, MIN(0.50, value));
    [self cancelTouches]; [self setNeedsLayout];
}
- (void)setReservedBottomFraction:(CGFloat)value {
    if (!isfinite(value)) return;
    _reservedBottomFraction = MAX(0, MIN(0.40, value));
    [self cancelTouches]; [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    if (!CGSizeEqualToSize(_viewportSize, self.bounds.size)) {
        [self cancelTouches]; _viewportSize = self.bounds.size;
    }
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    _stickCentre = CGPointMake(MAX(self.safeAreaInsets.left + 76, width * 0.14),
        MAX(76, height - MAX(self.safeAreaInsets.bottom + 76, height * _reservedBottomFraction + 68)));
    _stickRing.center = _stickCentre;
    if (!_stickTouch) _stickThumb.center = _stickCentre;
}
- (BOOL)inStick:(CGPoint)point {
    return point.x < self.bounds.size.width * 0.5 &&
        hypot(point.x - _stickCentre.x, point.y - _stickCentre.y) <= 74;
}
- (BOOL)inCamera:(CGPoint)point {
    return point.x >= self.bounds.size.width * 0.5 &&
        point.x < self.bounds.size.width * (1 - _reservedRightFraction) &&
        point.y >= self.safeAreaInsets.top &&
        point.y < self.bounds.size.height * (1 - _reservedBottomFraction);
}
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (!_enabled || self.hidden || !CGRectContainsPoint(self.bounds, point)) return NO;
    // Hardware mouse events continue to the desktop bridge unchanged.
    for (UITouch *touch in event.allTouches)
        if (touch.type == UITouchTypeIndirectPointer) return NO;
    return [self inStick:point] || [self inCamera:point];
}
- (void)emitAction:(AKAdventureAction)action x:(double)x y:(double)y key:(unsigned short)key {
    switch (action) {
        case AKAdventureKeyDown: [self.delegate touchAdventureKey:key pressed:YES]; break;
        case AKAdventureKeyUp: [self.delegate touchAdventureKey:key pressed:NO]; break;
        case AKAdventureCameraDown: [self.delegate touchAdventureCameraButtonPressed:YES]; break;
        case AKAdventureCameraUp: [self.delegate touchAdventureCameraButtonPressed:NO]; break;
        case AKAdventureCameraMove: [self.delegate touchAdventureCameraMoveBy:CGPointMake(x, y)]; break;
        case AKAdventureTap: [self.delegate touchAdventureTapAt:CGPointMake(x, y)]; break;
    }
}
- (void)updateStick:(UITouch *)touch {
    CGPoint point = [touch locationInView:self];
    CGFloat dx = (point.x - _stickCentre.x) / 46, dy = (point.y - _stickCentre.y) / 46;
    CGFloat length = hypot(dx, dy);
    if (length > 1) { dx /= length; dy /= length; }
    if (!isfinite(dx) || !isfinite(dy)) { [self cancelTouches]; return; }
    _stickThumb.center = CGPointMake(_stickCentre.x + dx * 36, _stickCentre.y + dy * 36);
    AKAdventureJoystickUpdate(&_stick, dx, dy, AKAdventureDeliver, (__bridge void *)self);
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if (!_enabled) return;
    for (UITouch *touch in touches) {
        if (touch.type != UITouchTypeDirect) continue;
        CGPoint point = [touch locationInView:self];
        if (!_stickTouch && [self inStick:point]) {
            _stickTouch = touch; [self updateStick:touch];
        } else if (!_cameraTouch && [self inCamera:point]) {
            _cameraTouch = touch;
            AKAdventureCameraBegin(&_camera, point.x, point.y, touch.timestamp,
                AKAdventureDeliver, (__bridge void *)self);
        }
    }
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if (_stickTouch && [touches containsObject:_stickTouch]) [self updateStick:_stickTouch];
    if (_cameraTouch && [touches containsObject:_cameraTouch]) {
        CGPoint point = [_cameraTouch locationInView:self];
        AKAdventureCameraUpdate(&_camera, point.x, point.y, _cameraTouch.timestamp,
            AKAdventureDeliver, (__bridge void *)self);
    }
}
- (void)finishTouches:(NSSet<UITouch *> *)touches cancelled:(BOOL)cancelled {
    if (_stickTouch && [touches containsObject:_stickTouch]) {
        AKAdventureJoystickCancel(&_stick, AKAdventureDeliver, (__bridge void *)self);
        _stickTouch = nil; _stickThumb.center = _stickCentre;
    }
    if (_cameraTouch && [touches containsObject:_cameraTouch]) {
        AKAdventureCameraEnd(&_camera, _cameraTouch.timestamp, cancelled,
            AKAdventureDeliver, (__bridge void *)self);
        _cameraTouch = nil;
    }
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event; [self finishTouches:touches cancelled:NO];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event; [self finishTouches:touches cancelled:YES];
}
- (void)cancelCameraForDirectTouch {
    AKAdventureCameraEnd(&_camera, 0, true, AKAdventureDeliver, (__bridge void *)self);
    _cameraTouch = nil;
}
- (void)cancelTouches {
    AKAdventureJoystickCancel(&_stick, AKAdventureDeliver, (__bridge void *)self);
    _stickTouch = nil; _stickThumb.center = _stickCentre;
    [self cancelCameraForDirectTouch];
}
- (void)didMoveToWindow {
    [super didMoveToWindow]; if (!self.window) [self cancelTouches];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end
