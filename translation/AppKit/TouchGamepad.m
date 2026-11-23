#import "TouchGamepad.h"
#import "TouchGamepadLayout.h"
#import "AKHostLocalization.h"
#import "TouchHaptics.h"
#import "TouchStickButtons.h"
#import "TouchActionInput.h"
#import "TouchActionOverlay.h"
#include <math.h>
#import <UIKit/UIGestureRecognizerSubclass.h>

static UIColor *AKPhotoFill(CGFloat alpha) {
    return [UIColor colorWithRed:0.06 green:0.06 blue:0.06 alpha:alpha];
}

static UIColor *AKPhotoBorder(CGFloat alpha) {
    return [UIColor colorWithRed:0.84 green:0.75 blue:0.55 alpha:alpha];
}

static UIColor *AKPhotoText(void) {
    return [UIColor colorWithRed:0.96 green:0.95 blue:0.90 alpha:0.95];
}

static UIColor *AKPhotoPressed(void) {
    return [UIColor colorWithRed:0.84 green:0.68 blue:0.32 alpha:0.42];
}

static UIColor *AKPhotoKnob(void) {
    return [UIColor colorWithRed:0.80 green:0.72 blue:0.56 alpha:0.78];
}

CGPoint AKTouchGamepadStickPosition(CGPoint point, CGSize size) {
    if (!isfinite(point.x) || !isfinite(point.y) || !isfinite(size.width) || !isfinite(size.height) ||
        size.width <= 0 || size.height <= 0) return CGPointZero;
    CGFloat radius = MIN(size.width, size.height) / 2;
    CGFloat x = (point.x - size.width / 2) / radius, y = (size.height / 2 - point.y) / radius;
    CGFloat length = hypot(x, y);
    if (!isfinite(x) || !isfinite(y) || !isfinite(length)) return CGPointZero;
    if (length < 0.10) return CGPointZero;
    CGFloat scale = MIN(1, (length - 0.10) / 0.90) / length;
    return CGPointMake(x * scale, y * scale);
}

// Reject a camera/stick drag at the same threshold as the direct-touch host.
// UIKit handles tap count and timing; no movement or button event is replayed.
@interface AKStickDoubleTap : UITapGestureRecognizer
@end
@implementation AKStickDoubleTap { CGPoint _tapOrigin; }
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    _tapOrigin = [touches.anyObject locationInView:self.view];
    [super touchesBegan:touches withEvent:event];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    CGPoint point = [touches.anyObject locationInView:self.view];
    if (hypot(point.x - _tapOrigin.x, point.y - _tapOrigin.y) >= AKTouchDragThreshold) {
        self.state = UIGestureRecognizerStateFailed;
        return;
    }
    [super touchesMoved:touches withEvent:event];
}
@end

@interface AKGamepadButton : UIButton
@property(nonatomic, copy) NSString *element;
@property(nonatomic, readonly) BOOL pressed;
@property(nonatomic) NSInteger sector;
@property(nonatomic) BOOL circular;
@property(nonatomic) CGFloat cornerRadiusOverride;
- (void)releaseInput;
@end

@implementation AKGamepadButton { CAShapeLayer *_sectorLayer; UIBezierPath *_sectorPath; }
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _sector = -1;
        _cornerRadiusOverride = -1;
        self.exclusiveTouch = NO;
        self.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        self.layer.cornerRadius = 19;
        self.layer.borderWidth = 1;
        self.layer.borderColor = AKPhotoBorder(0.45).CGColor;
        self.backgroundColor = AKPhotoFill(0.62);
        [self setTitleColor:AKPhotoText() forState:UIControlStateNormal];
        [self addTarget:self action:@selector(pressInput) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
        [self addTarget:self action:@selector(releaseInput) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
    }
    return self;
}

- (void)setPressed:(BOOL)pressed {
    if (_pressed == pressed) return;
    _pressed = pressed;
    UIColor *color = pressed ? AKPhotoPressed() : AKPhotoFill(0.62);
    if (_sector >= 0) _sectorLayer.fillColor = color.CGColor;
    else self.backgroundColor = color;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (void)setSector:(NSInteger)sector {
    _sector = sector;
    self.backgroundColor = UIColor.clearColor;
    self.layer.borderWidth = 0;
    if (!_sectorLayer) {
        _sectorLayer = [CAShapeLayer layer];
        [self.layer insertSublayer:_sectorLayer atIndex:0];
    }
    _sectorLayer.fillColor = AKPhotoFill(0.62).CGColor;
    _sectorLayer.strokeColor = AKPhotoBorder(0.45).CGColor;
    _sectorLayer.lineWidth = 1;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (_sector < 0) {
        if (_circular) self.layer.cornerRadius = MIN(self.bounds.size.width, self.bounds.size.height) / 2;
        else if (_cornerRadiusOverride >= 0) self.layer.cornerRadius = _cornerRadiusOverride;
        return;
    }
    CGPoint center = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
    CGFloat angle = (_sector - 1) * M_PI_2, start = angle - M_PI_4 + 0.045, end = angle + M_PI_4 - 0.045;
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path addArcWithCenter:center radius:104 startAngle:start endAngle:end clockwise:YES];
    [path addArcWithCenter:center radius:60 startAngle:end endAngle:start clockwise:NO];
    [path closePath];
    _sectorPath = path;
    _sectorLayer.frame = self.bounds;
    _sectorLayer.path = path.CGPath;
    self.titleLabel.frame = CGRectMake(center.x + 82 * cos(angle) - 26, center.y + 82 * sin(angle) - 18, 52, 36);
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (_sector >= 0) return [_sectorPath containsPoint:point];
    if (_circular) {
        CGFloat r = MIN(self.bounds.size.width, self.bounds.size.height) / 2;
        return hypot(point.x - self.bounds.size.width / 2, point.y - self.bounds.size.height / 2) <= r;
    }
    return [super pointInside:point withEvent:event];
}

- (CGPoint)accessibilityActivationPoint {
    if (_sector < 0 || !self.window) return super.accessibilityActivationPoint;
    CGPoint point = [self convertPoint:self.titleLabel.center toView:self.window];
    return [self.window convertPoint:point toCoordinateSpace:self.window.screen.coordinateSpace];
}

- (void)pressInput { [self setPressed:YES]; }
- (void)releaseInput { [self setPressed:NO]; }
@end

@interface AKGamepadStick : UIControl
@property(nonatomic, copy) NSString *element;
@property(nonatomic, readonly) CGPoint position;
- (void)reset;
@end

@implementation AKGamepadStick { UIView *_knob; }
- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.exclusiveTouch = NO;
        self.backgroundColor = AKPhotoFill(0.55);
        self.layer.borderWidth = 1;
        self.layer.borderColor = AKPhotoBorder(0.45).CGColor;
        _knob = [UIView new];
        _knob.userInteractionEnabled = NO;
        _knob.backgroundColor = AKPhotoKnob();
        [self addSubview:_knob];
        self.isAccessibilityElement = YES;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat diameter = MIN(self.bounds.size.width, self.bounds.size.height);
    self.layer.cornerRadius = diameter / 2;
    _knob.bounds = CGRectMake(0, 0, diameter * 0.42, diameter * 0.42);
    _knob.layer.cornerRadius = diameter * 0.21;
    _knob.center = CGPointMake(self.bounds.size.width / 2 + _position.x * diameter * 0.27,
                               self.bounds.size.height / 2 - _position.y * diameter * 0.27);
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    (void)event;
    return hypot(point.x - self.bounds.size.width / 2, point.y - self.bounds.size.height / 2) <= MIN(self.bounds.size.width, self.bounds.size.height) / 2;
}

- (void)updatePosition:(CGPoint)position {
    if (CGPointEqualToPoint(_position, position)) return;
    _position = position;
    [self setNeedsLayout];
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    [self updatePosition:AKTouchGamepadStickPosition([touch locationInView:self], self.bounds.size)];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    [self updatePosition:AKTouchGamepadStickPosition([touch locationInView:self], self.bounds.size)];
    return YES;
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event { (void)touch; (void)event; [self reset]; }
- (void)cancelTrackingWithEvent:(UIEvent *)event { (void)event; [self reset]; }
- (void)reset { [self updatePosition:CGPointZero]; }
@end

@interface AKCameraPadView : UIView
@property(nonatomic) BOOL editing;
@property(nonatomic, copy) BOOL (^beginDrag)(UITouch *touch, CGPoint origin);
@property(nonatomic, copy) void (^moveDrag)(UITouch *touch);
@property(nonatomic, copy) void (^endDrag)(UITouch *touch, BOOL cancelled);
- (void)cancelPendingTouch;
@end

@implementation AKCameraPadView {
    UILabel *_titleLabel;
    __weak UITouch *_activeTouch;
    BOOL _forwarded;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = NO;
        self.backgroundColor = AKPhotoFill(0.55);
        self.layer.cornerRadius = 22;
        self.layer.borderWidth = 1;
        self.layer.borderColor = AKPhotoBorder(0.45).CGColor;
        _titleLabel = [UILabel new];
        _titleLabel.text = @"Camera";
        _titleLabel.textColor = AKPhotoText();
        _titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        _titleLabel.textAlignment = NSTextAlignmentCenter;
        _titleLabel.userInteractionEnabled = NO;
        [self addSubview:_titleLabel];
        self.isAccessibilityElement = YES;
        self.accessibilityLabel = @"Camera";
        self.accessibilityIdentifier = @"wolkara.hud.camera";
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _titleLabel.frame = self.bounds;
}

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if (self.editing || _activeTouch) return;
    UITouch *touch = touches.anyObject;
    if (!touch) return;
    _activeTouch = touch;
    self.backgroundColor = AKPhotoPressed();
    _forwarded = self.beginDrag && self.beginDrag(touch, [touch locationInView:self]);
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if (!_activeTouch || ![touches containsObject:_activeTouch]) return;
    if (_forwarded && self.moveDrag) self.moveDrag(_activeTouch);
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if (!_activeTouch || ![touches containsObject:_activeTouch]) return;
    if (_forwarded && self.endDrag) self.endDrag(_activeTouch, NO);
    _activeTouch = nil;
    _forwarded = NO;
    self.backgroundColor = AKPhotoFill(0.55);
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    (void)event;
    if (!_activeTouch || ![touches containsObject:_activeTouch]) return;
    [self cancelPendingTouch];
}

- (void)cancelPendingTouch {
    if (_forwarded && _activeTouch && self.endDrag) self.endDrag(_activeTouch, YES);
    _activeTouch = nil;
    _forwarded = NO;
    self.backgroundColor = AKPhotoFill(0.55);
}
@end

@interface AKGamepadOverlay : UIView <UIGestureRecognizerDelegate>
@property(nonatomic, readonly) NSDictionary<NSString *, AKGamepadButton *> *buttons;
@property(nonatomic, readonly) NSDictionary<NSString *, AKGamepadButton *> *hudButtons;
@property(nonatomic, readonly) AKCameraPadView *cameraPad;
@property(nonatomic, readonly) AKGamepadStick *leftStick;
@property(nonatomic, readonly) AKGamepadStick *rightStick;
@property(nonatomic, readonly) AKGamepadLayout *preferences;
@property(nonatomic, readonly) AKTouchActionOverlay *actions;
@property(nonatomic) BOOL controlsVisible;
@property(nonatomic) BOOL simple;
@property(nonatomic, readonly) BOOL configuring;
@property(nonatomic, readonly) BOOL editing;
@property(nonatomic, copy) void (^configurationChanged)(void);
- (void)reset;
- (void)toggleSettings;
- (void)finishConfiguration;
- (BOOL)configurationContainsPoint:(CGPoint)point inView:(UIView *)view;
@end

@implementation AKGamepadOverlay {
    NSDictionary<NSString *, UIView *> *_items;
    NSMutableDictionary<NSString *, NSValue *> *_dragOrigins;
    UIView *_settings;
    UIButton *_editDone, *_editAbilitiesButton;
    UILabel *_hint;
    UISwitch *_editSwitch, *_hapticsSwitch, *_swapShouldersSwitch, *_performanceSwitch, *_leftStickWasdSwitch;
    UIButton *_targetButton, *_interactButton, *_jumpButton, *_cameraDragButton, *_hudVisibilityButton;
    UIStackView *_settingsColumns;
    NSArray<UISlider *> *_sliders;
    NSArray<UILabel *> *_values;
    CAShapeLayer *_editGrid, *_editAxes;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = YES;
        // Above the guest surface, below the cursor and keyboard toolbar.
        self.layer.zPosition = 99999;
        _preferences = [[AKGamepadLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
        _dragOrigins = [NSMutableDictionary new];
        _actions = [[AKTouchActionOverlay alloc] initWithFrame:self.bounds];
        _actions.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_actions];
        __weak AKGamepadOverlay *weakSelf = self;
        _actions.configurationChanged = ^{
            AKGamepadOverlay *self = weakSelf;
            if (!self) return;
            [self updateAppearance];
            if (self.configurationChanged) self.configurationChanged();
        };
        _editGrid = [CAShapeLayer layer];
        _editAxes = [CAShapeLayer layer];
        _editGrid.name = @"WolkaraForeverEditGrid";
        _editAxes.name = @"WolkaraForeverEditAxes";
        for (CAShapeLayer *layer in @[_editGrid, _editAxes]) {
            layer.fillColor = nil;
            layer.zPosition = -1;
            [self.layer addSublayer:layer];
        }
        _editGrid.strokeColor = [UIColor colorWithWhite:1 alpha:0.16].CGColor;
        _editGrid.lineWidth = 0.5;
        _editAxes.strokeColor = [UIColor.systemYellowColor colorWithAlphaComponent:0.6].CGColor;
        _editAxes.lineWidth = 1;
        _editAxes.lineDashPattern = @[@4, @4];

        NSArray *elements = @[GCInputButtonA, GCInputButtonB, GCInputButtonX, GCInputButtonY,
            GCInputLeftShoulder, GCInputLeftTrigger, GCInputRightTrigger, GCInputRightShoulder,
            GCInputButtonMenu, @"dpad.up", @"dpad.right", @"dpad.down", @"dpad.left"];
        NSArray *titles = @[@"A", @"B", @"X", @"Y", @"LB", @"LT", @"RT", @"RB", @"+", @"↑", @"→", @"↓", @"←"];
        NSMutableDictionary *buttons = [NSMutableDictionary new];
        UIView *left = [UIView new], *right = [UIView new];
        left.multipleTouchEnabled = right.multipleTouchEnabled = YES;
        [self addSubview:left];
        [self addSubview:right];
        for (NSUInteger i = 0; i < elements.count; i++) {
            AKGamepadButton *button = [AKGamepadButton new];
            button.element = elements[i];
            [button setTitle:titles[i] forState:UIControlStateNormal];
            button.accessibilityLabel = AKHostLocalizedFormat(@"touch.gamepad.button", elements[i]);
            button.accessibilityIdentifier = [@"tolkara.gamepad." stringByAppendingString:elements[i]];
            buttons[elements[i]] = button;
            [(i < 4 ? right : i >= 9 ? left : self) addSubview:button];
        }
        _buttons = buttons;

        AKGamepadButton *targetBtn = [AKGamepadButton new];
        targetBtn.element = @"hud.target";
        targetBtn.cornerRadiusOverride = 18;
        targetBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        [targetBtn setTitle:@"Target" forState:UIControlStateNormal];
        targetBtn.accessibilityLabel = @"Target";
        targetBtn.accessibilityIdentifier = @"wolkara.hud.target";
        [self addSubview:targetBtn];

        AKGamepadButton *interactBtn = [AKGamepadButton new];
        interactBtn.element = @"hud.interact";
        interactBtn.cornerRadiusOverride = 18;
        interactBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        [interactBtn setTitle:@"Interact" forState:UIControlStateNormal];
        interactBtn.accessibilityLabel = @"Interact";
        interactBtn.accessibilityIdentifier = @"wolkara.hud.interact";
        [self addSubview:interactBtn];

        AKGamepadButton *jumpBtn = [AKGamepadButton new];
        jumpBtn.element = @"hud.jump";
        jumpBtn.circular = YES;
        jumpBtn.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
        [jumpBtn setTitle:@"Jump" forState:UIControlStateNormal];
        jumpBtn.accessibilityLabel = @"Jump";
        jumpBtn.accessibilityIdentifier = @"wolkara.hud.jump";
        [self addSubview:jumpBtn];

        _hudButtons = @{@"hud.target": targetBtn, @"hud.interact": interactBtn, @"hud.jump": jumpBtn};
        _cameraPad = [AKCameraPadView new];
        [self addSubview:_cameraPad];

        _leftStick = [AKGamepadStick new];
        _rightStick = [AKGamepadStick new];
        _leftStick.element = GCInputLeftThumbstick;
        _rightStick.element = GCInputRightThumbstick;
        _leftStick.accessibilityLabel = AKHostLocalized(@"touch.gamepad.leftStick");
        _rightStick.accessibilityLabel = AKHostLocalized(@"touch.gamepad.rightStick");
        _leftStick.accessibilityIdentifier = @"tolkara.gamepad.leftStick";
        _rightStick.accessibilityIdentifier = @"tolkara.gamepad.rightStick";
        [left addSubview:_leftStick];
        [right addSubview:_rightStick];

        _items = @{
            @"left": left,
            @"right": right,
            @"LB": buttons[GCInputLeftShoulder],
            @"LT": buttons[GCInputLeftTrigger],
            @"RB": buttons[GCInputRightShoulder],
            @"RT": buttons[GCInputRightTrigger],
            @"menu": buttons[GCInputButtonMenu],
            @"hud.target": targetBtn,
            @"hud.interact": interactBtn,
            @"hud.jump": jumpBtn,
            @"hud.camera": _cameraPad,
        };
        for (NSString *name in _items) {
            UIView *item = _items[name];
            if (!item.accessibilityIdentifier.length) {
                item.accessibilityIdentifier = [@"wolkaraforever.layout." stringByAppendingString:name];
            }
            UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
            pan.delegate = self;
            [item addGestureRecognizer:pan];
        }

        _editDone = [UIButton buttonWithType:UIButtonTypeSystem];
        [_editDone setTitle:AKHostLocalized(@"touch.gamepad.doneEditing") forState:UIControlStateNormal];
        _editDone.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.96];
        _editDone.tintColor = UIColor.systemYellowColor;
        _editDone.layer.cornerRadius = 14;
        _editDone.accessibilityIdentifier = @"wolkaraforever.layout.done";
        [_editDone addTarget:self action:@selector(finishConfiguration) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_editDone];

        _editAbilitiesButton = [UIButton buttonWithType:UIButtonTypeSystem];
        [_editAbilitiesButton setTitle:@"Edit Buttons…" forState:UIControlStateNormal];
        _editAbilitiesButton.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.96];
        _editAbilitiesButton.tintColor = [UIColor colorWithRed:0.92 green:0.80 blue:0.50 alpha:1];
        _editAbilitiesButton.layer.cornerRadius = 14;
        _editAbilitiesButton.accessibilityIdentifier = @"wolkara.layout.editAbilities";
        [_editAbilitiesButton addTarget:self action:@selector(editAbilities) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_editAbilitiesButton];

        _hint = [UILabel new];
        _hint.text = AKHostLocalized(@"touch.gamepad.dragHint");
        _hint.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
        _hint.textColor = UIColor.whiteColor;
        _hint.textAlignment = NSTextAlignmentCenter;
        _hint.userInteractionEnabled = NO;
        [self addSubview:_hint];

        [self updateAppearance];
    }
    return self;
}

- (BOOL)configuring { return _settings != nil || _editing || _actions.editing; }

- (BOOL)configurationContainsPoint:(CGPoint)point inView:(UIView *)view {
    if ([_actions editorContainsPoint:point inView:view]) return YES;
    if (_editing) {
        for (UIView *v in @[_editDone, _editAbilitiesButton]) {
            if (!v.hidden && CGRectContainsPoint(v.bounds, [v convertPoint:point fromView:view])) return YES;
        }
        return NO;
    }
    return _settings && !_settings.hidden && CGRectContainsPoint(_settings.bounds, [_settings convertPoint:point fromView:view]);
}

- (void)setControlsVisible:(BOOL)visible { _controlsVisible = visible; [self updateAppearance]; }
- (void)setSimple:(BOOL)simple { _simple = simple; [self updateAppearance]; }

- (void)updateAppearance {
    self.hidden = !_controlsVisible && !self.configuring;
    _actions.active = _controlsVisible && !self.configuring;
    BOOL showControls = _controlsVisible || self.configuring;
    NSArray<NSString *> *fullOnlyItems = @[@"right", @"LB", @"LT", @"RT", @"RB", @"menu"];
    NSArray<NSString *> *simpleOnlyItems = @[@"hud.target", @"hud.interact", @"hud.jump", @"hud.camera"];
    for (NSString *name in _items) {
        UIView *item = _items[name];
        BOOL omitted = _simple ? [fullOnlyItems containsObject:name] : [simpleOnlyItems containsObject:name];
        if (_simple && !_editing && [simpleOnlyItems containsObject:name]) {
            if ([name isEqualToString:@"hud.target"] && !_preferences.showHudTarget) omitted = YES;
            else if ([name isEqualToString:@"hud.interact"] && !_preferences.showHudInteract) omitted = YES;
            else if ([name isEqualToString:@"hud.jump"] && !_preferences.showHudJump) omitted = YES;
            else if ([name isEqualToString:@"hud.camera"] && !_preferences.showHudCamera) omitted = YES;
        }
        item.hidden = omitted || !showControls;
        item.alpha = _editing ? MAX(0.5, _preferences.opacity) : _preferences.opacity;
        if ([item isKindOfClass:AKGamepadButton.class] || item == _cameraPad) {
            item.layer.borderWidth = 1;
            item.layer.borderColor = (_editing ? UIColor.systemYellowColor : AKPhotoBorder(0.45)).CGColor;
        } else {
            item.layer.borderWidth = _editing ? 1 : 0;
            item.layer.borderColor = (_editing ? UIColor.systemYellowColor : AKPhotoBorder(0.45)).CGColor;
        }
    }
    _leftStick.layer.borderColor = (_editing ? UIColor.systemYellowColor : AKPhotoBorder(0.45)).CGColor;
    // An enabled UIControl is needed for its own pan recognizer to receive
    // touches. The manager suppresses game input throughout configuration.
    for (NSString *name in _buttons) {
        AKGamepadButton *button = _buttons[name];
        if ([name hasPrefix:@"dpad."]) button.hidden = _simple;
        button.enabled = (!self.configuring || _editing) && !button.hidden && !button.superview.hidden;
    }
    for (AKGamepadButton *button in _hudButtons.allValues) {
        button.enabled = (!self.configuring || _editing) && !button.hidden;
    }
    _cameraPad.editing = _editing || self.configuring;
    _leftStick.enabled = !self.configuring;
    _rightStick.enabled = !self.configuring && !_simple;
    _editDone.hidden = _editAbilitiesButton.hidden = _hint.hidden = !_editing;
    _editGrid.hidden = _editAxes.hidden = !_editing;
    [self setNeedsLayout];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (self.configuring) return hit; // Editing/settings must never click the game.
    if (hit == self || hit == _items[@"left"] || hit == _items[@"right"]) return nil;
    return hit;
}

- (CGRect)usableBounds { return UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets); }

- (NSString *)positionName:(NSString *)name {
    if (!_preferences.swapShoulders) return name;
    return @{@"LT": @"LB", @"LB": @"LT", @"RT": @"RB", @"RB": @"RT"}[name] ?: name;
}

- (NSString *)preferenceKeyForControl:(NSString *)name {
    if (_simple && [name isEqual:@"left"]) return @"simple.left";
    return [self positionName:name];
}

- (void)place:(NSString *)name frame:(CGRect)frame baseSize:(CGSize)base safe:(CGRect)safe {
    NSString *control = [self positionName:name];
    UIView *item = _items[control];
    CGRect placed = [_preferences frameForItem:[self preferenceKeyForControl:control] defaultFrame:frame inBounds:safe];
    item.transform = CGAffineTransformIdentity;
    item.bounds = (CGRect){CGPointZero, base};
    item.center = CGPointMake(CGRectGetMidX(placed), CGRectGetMidY(placed));
    item.transform = CGAffineTransformMakeScale(placed.size.width / base.width, placed.size.height / base.height);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect safe = [self usableBounds];
    if (_editing) [self layoutEditGridInBounds:safe];

    CGFloat left = CGRectGetMinX(safe) + 8, right = CGRectGetMaxX(safe) - 8;
    CGFloat bottom = CGRectGetMaxY(safe) - 6, top = CGRectGetMinY(safe) + 8;

    if (_simple) {
        CGFloat stickSide = MAX(56, MIN(96 * _preferences.frontScale, MIN(safe.size.height * 0.34, safe.size.width * 0.25)));
        [self place:@"left" frame:CGRectMake(left + 6, bottom - stickSide - 4, stickSide, stickSide)
           baseSize:CGSizeMake(104, 104) safe:safe];
        _leftStick.frame = CGRectMake(0, 0, 104, 104);

        CGFloat s = _preferences.rearScale;
        CGFloat fit = MIN(1.0, safe.size.width / 700.0);
        CGFloat scale = s * fit;
        CGFloat camW = 168 * scale, camH = 74 * scale;
        CGFloat jumpSide = 60 * scale;
        CGFloat pillW = 84 * scale, pillH = 36 * scale;
        [self place:@"hud.camera" frame:CGRectMake(right - camW, bottom - camH, camW, camH)
           baseSize:CGSizeMake(168, 74) safe:safe];
        [self place:@"hud.jump" frame:CGRectMake(right - camW - 14 - jumpSide, bottom - jumpSide - 4, jumpSide, jumpSide)
           baseSize:CGSizeMake(60, 60) safe:safe];
        [self place:@"hud.interact" frame:CGRectMake(right - camW - 14 - pillW, bottom - jumpSide - 12 - pillH, pillW, pillH)
           baseSize:CGSizeMake(84, 36) safe:safe];
        [self place:@"hud.target" frame:CGRectMake(right - camW - 14 - pillW, bottom - jumpSide - 18 - pillH * 2, pillW, pillH)
           baseSize:CGSizeMake(84, 36) safe:safe];
    } else {
        CGFloat side = MAX(44, MIN(216 * _preferences.frontScale, MIN(safe.size.height - 70, safe.size.width / 2 - 12)));
        CGFloat w = 56 * _preferences.rearScale, h = 44 * _preferences.rearScale;
        [self place:@"left" frame:CGRectMake(left, bottom - side, side, side) baseSize:CGSizeMake(216, 216) safe:safe];
        [self place:@"right" frame:CGRectMake(right - side, bottom - side, side, side) baseSize:CGSizeMake(216, 216) safe:safe];
        _leftStick.frame = _rightStick.frame = CGRectMake(56, 56, 104, 104);
        NSArray *leftNames = @[@"dpad.up", @"dpad.right", @"dpad.down", @"dpad.left"];
        NSArray *rightNames = @[GCInputButtonY, GCInputButtonB, GCInputButtonA, GCInputButtonX];
        for (NSUInteger i = 0; i < 4; i++) {
            AKGamepadButton *a = _buttons[leftNames[i]], *b = _buttons[rightNames[i]];
            if (a.sector != (NSInteger)i) a.sector = i;
            if (b.sector != (NSInteger)i) b.sector = i;
            a.frame = b.frame = CGRectMake(0, 0, 216, 216);
        }
        [self place:@"LT" frame:CGRectMake(left, top, w, h) baseSize:CGSizeMake(56, 44) safe:safe];
        [self place:@"LB" frame:CGRectMake(left + w + 8, top, w, h) baseSize:CGSizeMake(56, 44) safe:safe];
        [self place:@"RT" frame:CGRectMake(right - w, top, w, h) baseSize:CGSizeMake(56, 44) safe:safe];
        [self place:@"RB" frame:CGRectMake(right - w * 2 - 8, top, w, h) baseSize:CGSizeMake(56, 44) safe:safe];
        [self place:@"menu" frame:CGRectMake(CGRectGetMidX(self.bounds) - 22, bottom - side + 190 * side / 216 - 22, 44, 44)
           baseSize:CGSizeMake(44, 44) safe:safe];
    }

    _editDone.frame = CGRectMake(CGRectGetMidX(safe) - 144, CGRectGetMinY(safe) + 96, 136, 40);
    _editAbilitiesButton.frame = CGRectMake(CGRectGetMidX(safe) + 8, CGRectGetMinY(safe) + 96, 136, 40);
    _hint.frame = CGRectMake(CGRectGetMidX(safe) - 160, CGRectGetMinY(safe) + 140, 320, 22);

    if (_settings) {
        BOOL wide = safe.size.width >= 620;
        CGFloat width = MIN(wide ? 700 : 390, safe.size.width - 24);
        CGFloat height = MIN(wide ? 315 : 460, safe.size.height - 100);
        _settingsColumns.axis = wide ? UILayoutConstraintAxisHorizontal : UILayoutConstraintAxisVertical;
        _settingsColumns.alignment = wide ? UIStackViewAlignmentTop : UIStackViewAlignmentFill;
        _settingsColumns.distribution = wide ? UIStackViewDistributionFillEqually : UIStackViewDistributionFill;
        _settings.frame = CGRectMake(CGRectGetMidX(safe) - width / 2, CGRectGetMaxY(safe) - height - 8, width, height);
    }
}

- (void)layoutEditGridInBounds:(CGRect)safe {
    UIBezierPath *grid = [UIBezierPath bezierPath], *axes = [UIBezierPath bezierPath];
    CGFloat x = CGRectGetMidX(safe), y = CGRectGetMidY(safe), step = 24;
    for (NSInteger column = -(NSInteger)floor(safe.size.width / (2 * step)); column * step <= safe.size.width / 2; column++) {
        CGFloat line = x + column * step;
        [grid moveToPoint:CGPointMake(line, CGRectGetMinY(safe))];
        [grid addLineToPoint:CGPointMake(line, CGRectGetMaxY(safe))];
    }
    for (NSInteger row = -(NSInteger)floor(safe.size.height / (2 * step)); row * step <= safe.size.height / 2; row++) {
        CGFloat line = y + row * step;
        [grid moveToPoint:CGPointMake(CGRectGetMinX(safe), line)];
        [grid addLineToPoint:CGPointMake(CGRectGetMaxX(safe), line)];
    }
    [axes moveToPoint:CGPointMake(x, CGRectGetMinY(safe))];
    [axes addLineToPoint:CGPointMake(x, CGRectGetMaxY(safe))];
    [axes moveToPoint:CGPointMake(CGRectGetMinX(safe), y)];
    [axes addLineToPoint:CGPointMake(CGRectGetMaxX(safe), y)];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _editGrid.frame = _editAxes.frame = self.bounds;
    _editGrid.path = grid.CGPath;
    _editAxes.path = axes.CGPath;
    [CATransaction commit];
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    (void)gestureRecognizer;
    return _editing;
}

- (void)drag:(UIPanGestureRecognizer *)pan {
    NSString *name = [_items allKeysForObject:pan.view].firstObject;
    if (!name || !_editing) return;
    if (pan.state == UIGestureRecognizerStateBegan) {
        [_dragOrigins setObject:[NSValue valueWithCGRect:pan.view.frame] forKey:name];
        [self reset];
    }
    CGRect frame = [_dragOrigins[name] CGRectValue];
    if (pan.state == UIGestureRecognizerStateCancelled) {
        [_preferences moveItem:[self preferenceKeyForControl:name] toFrame:frame inBounds:[self usableBounds]];
    } else {
        CGPoint delta = [pan translationInView:self];
        frame.origin.x += delta.x;
        frame.origin.y += delta.y;
        [_preferences moveItem:[self preferenceKeyForControl:name] toFrame:frame inBounds:[self usableBounds]];
    }
    [self setNeedsLayout];
    [self layoutIfNeeded];
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        [_preferences save];
        [_dragOrigins removeObjectForKey:name];
    }
}

- (UILabel *)label:(NSString *)text {
    UILabel *label = [UILabel new];
    label.text = text;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    label.numberOfLines = 0;
    return label;
}

- (UIButton *)menuButtonWithIdentifier:(NSString *)identifier {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    btn.showsMenuAsPrimaryAction = YES;
    btn.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    btn.accessibilityIdentifier = identifier;
    return btn;
}

- (void)configureMenuButton:(UIButton *)button
                     prefix:(NSString *)prefix
                    choices:(NSArray<NSString *> *)choices
                    current:(NSString *)current
                     setter:(void (^)(NSString *choice))setter {
    [button setTitle:[NSString stringWithFormat:@"%@: %@ ▾", prefix, current] forState:UIControlStateNormal];
    __weak AKGamepadOverlay *weakSelf = self;
    NSMutableArray<UIAction *> *actions = [NSMutableArray arrayWithCapacity:choices.count];
    for (NSString *choice in choices) {
        UIAction *act = [UIAction actionWithTitle:choice image:nil identifier:nil handler:^(__kindof UIAction *a) {
            (void)a;
            AKGamepadOverlay *self = weakSelf;
            if (!self) return;
            setter(choice);
            [self->_preferences save];
            [self rebuildHudBindingMenus];
        }];
        act.state = [choice isEqualToString:current] ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:act];
    }
    button.menu = [UIMenu menuWithChildren:actions];
}

- (void)rebuildHudBindingMenus {
    __weak AKGamepadOverlay *weakSelf = self;
    [self configureMenuButton:_targetButton prefix:@"Target"
                      choices:[AKGamepadLayout allowedTargetBindings]
                      current:_preferences.targetBinding
                       setter:^(NSString *c) {
        AKGamepadOverlay *self = weakSelf;
        if (self) self->_preferences.targetBinding = c;
    }];
    [self configureMenuButton:_interactButton prefix:@"Interact"
                      choices:[AKGamepadLayout allowedInteractBindings]
                      current:_preferences.interactBinding
                       setter:^(NSString *c) {
        AKGamepadOverlay *self = weakSelf;
        if (self) self->_preferences.interactBinding = c;
    }];
    [self configureMenuButton:_jumpButton prefix:@"Jump"
                      choices:[AKGamepadLayout allowedJumpBindings]
                      current:_preferences.jumpBinding
                       setter:^(NSString *c) {
        AKGamepadOverlay *self = weakSelf;
        if (self) self->_preferences.jumpBinding = c;
    }];
    NSString *camLabel = _preferences.cameraRightDrag ? @"Right Drag" : @"Left Drag";
    [_cameraDragButton setTitle:[NSString stringWithFormat:@"Camera: %@ ▾", camLabel] forState:UIControlStateNormal];
    _cameraDragButton.menu = [UIMenu menuWithChildren:@[
        [UIAction actionWithTitle:@"Right Drag (Turn)" image:nil identifier:nil handler:^(__kindof UIAction *a) {
            (void)a;
            AKGamepadOverlay *self = weakSelf;
            if (!self) return;
            self->_preferences.cameraRightDrag = YES;
            [self->_preferences save];
            [self rebuildHudBindingMenus];
        }],
        [UIAction actionWithTitle:@"Left Drag (Orbit)" image:nil identifier:nil handler:^(__kindof UIAction *a) {
            (void)a;
            AKGamepadOverlay *self = weakSelf;
            if (!self) return;
            self->_preferences.cameraRightDrag = NO;
            [self->_preferences save];
            [self rebuildHudBindingMenus];
        }],
    ]];
    NSUInteger shownCount = (_preferences.showHudTarget ? 1 : 0) + (_preferences.showHudInteract ? 1 : 0) +
                            (_preferences.showHudJump ? 1 : 0) + (_preferences.showHudCamera ? 1 : 0);
    [_hudVisibilityButton setTitle:[NSString stringWithFormat:@"Right HUD Controls (%lu/4) ▾", (unsigned long)shownCount] forState:UIControlStateNormal];
    UIAction *(^visAction)(NSString *, BOOL, void (^)(AKGamepadOverlay *)) = ^UIAction *(NSString *title, BOOL shown, void (^flip)(AKGamepadOverlay *)) {
        UIAction *act = [UIAction actionWithTitle:title image:nil identifier:nil handler:^(__kindof UIAction *a) {
            (void)a;
            AKGamepadOverlay *self = weakSelf;
            if (!self) return;
            flip(self);
            [self->_preferences save];
            [self rebuildHudBindingMenus];
            [self updateAppearance];
        }];
        act.state = shown ? UIMenuElementStateOn : UIMenuElementStateOff;
        return act;
    };
    _hudVisibilityButton.menu = [UIMenu menuWithChildren:@[
        visAction(@"Target", _preferences.showHudTarget, ^(AKGamepadOverlay *s) { s->_preferences.showHudTarget = !s->_preferences.showHudTarget; }),
        visAction(@"Interact", _preferences.showHudInteract, ^(AKGamepadOverlay *s) { s->_preferences.showHudInteract = !s->_preferences.showHudInteract; }),
        visAction(@"Jump", _preferences.showHudJump, ^(AKGamepadOverlay *s) { s->_preferences.showHudJump = !s->_preferences.showHudJump; }),
        visAction(@"Camera", _preferences.showHudCamera, ^(AKGamepadOverlay *s) { s->_preferences.showHudCamera = !s->_preferences.showHudCamera; }),
    ]];
}

- (void)toggleSettings {
    if (self.configuring) { [self finishConfiguration]; return; }
    [self reset];
    _settings = [UIView new];
    _settings.backgroundColor = [UIColor colorWithRed:0.06 green:0.07 blue:0.09 alpha:0.97];
    _settings.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _settings.layer.cornerRadius = 20;
    _settings.layer.borderWidth = 1;
    _settings.layer.borderColor = AKPhotoBorder(0.45).CGColor;
    _settings.accessibilityIdentifier = @"wolkaraforever.controls.settings";
    [self addSubview:_settings];

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [_settings addSubview:scroll];

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:AKHostLocalized(@"touch.settings.title")]]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    UIStackView *sizes = [UIStackView new], *options = [UIStackView new];
    sizes.axis = options.axis = UILayoutConstraintAxisVertical;
    sizes.spacing = 6;
    options.spacing = 7;
    _settingsColumns = [[UIStackView alloc] initWithArrangedSubviews:@[sizes, options]];
    _settingsColumns.spacing = 24;
    _settingsColumns.alignment = UIStackViewAlignmentTop;
    [stack addArrangedSubview:_settingsColumns];

    NSMutableArray *sliders = [NSMutableArray new], *values = [NSMutableArray new];
    NSArray *names = @[
        AKHostLocalized(@"touch.settings.transparency"),
        AKHostLocalized(@"touch.settings.shoulderSize"),
        AKHostLocalized(@"touch.settings.stickSize")
    ];
    CGFloat initial[] = {1 - _preferences.opacity, _preferences.rearScale, _preferences.frontScale};
    CGFloat min[] = {0, 0.8, 0.65}, max[] = {0.8, 1.5, 1.4};
    for (NSUInteger i = 0; i < 3; i++) {
        UILabel *value = [self label:@""];
        [values addObject:value];
        [sizes addArrangedSubview:value];
        UISlider *slider = [UISlider new];
        slider.tag = (NSInteger)i;
        slider.minimumValue = min[i];
        slider.maximumValue = max[i];
        slider.value = initial[i];
        slider.accessibilityLabel = names[i];
        slider.accessibilityIdentifier = [@"wolkaraforever.controls." stringByAppendingString:@[@"transparency", @"rearScale", @"frontScale"][i]];
        [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [sliders addObject:slider];
        [sizes addArrangedSubview:slider];
    }
    _sliders = sliders;
    _values = values;
    [self updateValues];

    _targetButton = [self menuButtonWithIdentifier:@"wolkara.controls.targetBinding"];
    _interactButton = [self menuButtonWithIdentifier:@"wolkara.controls.interactBinding"];
    _jumpButton = [self menuButtonWithIdentifier:@"wolkara.controls.jumpBinding"];
    _cameraDragButton = [self menuButtonWithIdentifier:@"wolkara.controls.cameraDrag"];
    _hudVisibilityButton = [self menuButtonWithIdentifier:@"wolkara.controls.hudVisibility"];
    [self rebuildHudBindingMenus];

    UIStackView *hudRow1 = [[UIStackView alloc] initWithArrangedSubviews:@[_targetButton, _interactButton]];
    hudRow1.axis = UILayoutConstraintAxisHorizontal;
    hudRow1.distribution = UIStackViewDistributionFillEqually;
    hudRow1.spacing = 6;
    [sizes addArrangedSubview:hudRow1];

    UIStackView *hudRow2 = [[UIStackView alloc] initWithArrangedSubviews:@[_jumpButton, _cameraDragButton]];
    hudRow2.axis = UILayoutConstraintAxisHorizontal;
    hudRow2.distribution = UIStackViewDistributionFillEqually;
    hudRow2.spacing = 6;
    [sizes addArrangedSubview:hudRow2];
    [sizes addArrangedSubview:_hudVisibilityButton];

    UIButton *abilities = [UIButton buttonWithType:UIButtonTypeSystem];
    [abilities setTitle:@"Custom Buttons (Drag & Drop)…" forState:UIControlStateNormal];
    abilities.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    abilities.tintColor = [UIColor colorWithRed:0.95 green:0.82 blue:0.48 alpha:1];
    abilities.accessibilityIdentifier = @"wolkara.controls.abilities";
    [abilities addTarget:self action:@selector(editAbilities) forControlEvents:UIControlEventTouchUpInside];
    [options addArrangedSubview:abilities];

    _editSwitch = [UISwitch new];
    _editSwitch.accessibilityLabel = AKHostLocalized(@"touch.settings.edit");
    _editSwitch.accessibilityIdentifier = @"wolkaraforever.controls.edit";
    [_editSwitch addTarget:self action:@selector(beginEditing:) forControlEvents:UIControlEventValueChanged];
    UIStackView *editRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:AKHostLocalized(@"touch.settings.edit")], _editSwitch]];
    editRow.axis = UILayoutConstraintAxisHorizontal;
    editRow.alignment = UIStackViewAlignmentCenter;
    [options addArrangedSubview:editRow];

    _hapticsSwitch = [UISwitch new];
    _hapticsSwitch.on = _preferences.hapticsEnabled;
    _hapticsSwitch.accessibilityLabel = AKHostLocalized(@"touch.settings.haptics");
    _hapticsSwitch.accessibilityIdentifier = @"wolkaraforever.controls.haptics";
    [_hapticsSwitch addTarget:self action:@selector(hapticsChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *hapticsRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:AKHostLocalized(@"touch.settings.haptics")], _hapticsSwitch]];
    hapticsRow.axis = UILayoutConstraintAxisHorizontal;
    hapticsRow.alignment = UIStackViewAlignmentCenter;
    [options addArrangedSubview:hapticsRow];

    _performanceSwitch = [UISwitch new];
    _performanceSwitch.on = _preferences.performanceOverlayEnabled;
    _performanceSwitch.accessibilityLabel = AKHostLocalized(@"touch.settings.overlay.detail");
    _performanceSwitch.accessibilityIdentifier = @"wolkara.controls.performance";
    [_performanceSwitch addTarget:self action:@selector(performanceChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *performanceRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:AKHostLocalized(@"touch.settings.overlay.detail")], _performanceSwitch]];
    performanceRow.axis = UILayoutConstraintAxisHorizontal;
    performanceRow.alignment = UIStackViewAlignmentCenter;
    [options addArrangedSubview:performanceRow];

    _swapShouldersSwitch = [UISwitch new];
    _swapShouldersSwitch.on = !_preferences.swapShoulders;
    _swapShouldersSwitch.accessibilityLabel = AKHostLocalized(@"touch.settings.outerTriggers");
    _swapShouldersSwitch.accessibilityIdentifier = @"wolkaraforever.controls.swapShoulders";
    [_swapShouldersSwitch addTarget:self action:@selector(swapShouldersChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *shouldersRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:AKHostLocalized(@"touch.settings.outerTriggers")], _swapShouldersSwitch]];
    shouldersRow.axis = UILayoutConstraintAxisHorizontal;
    shouldersRow.alignment = UIStackViewAlignmentCenter;
    [options addArrangedSubview:shouldersRow];

    _leftStickWasdSwitch = [UISwitch new];
    _leftStickWasdSwitch.on = _preferences.leftStickWASD;
    _leftStickWasdSwitch.accessibilityLabel = @"Left Stick WASD";
    _leftStickWasdSwitch.accessibilityIdentifier = @"wolkara.controls.leftStickWASD";
    [_leftStickWasdSwitch addTarget:self action:@selector(leftStickWasdChanged:) forControlEvents:UIControlEventValueChanged];
    UIStackView *wasdRow = [[UIStackView alloc] initWithArrangedSubviews:@[[self label:@"Left Stick: WASD Keys"], _leftStickWasdSwitch]];
    wasdRow.axis = UILayoutConstraintAxisHorizontal;
    wasdRow.alignment = UIStackViewAlignmentCenter;
    [options addArrangedSubview:wasdRow];

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [reset setTitle:AKHostLocalized(@"touch.settings.reset") forState:UIControlStateNormal];
    reset.accessibilityIdentifier = @"wolkaraforever.controls.reset";
    [reset addTarget:self action:@selector(resetLayout) forControlEvents:UIControlEventTouchUpInside];

    UIButton *done = [UIButton buttonWithType:UIButtonTypeSystem];
    [done setTitle:AKHostLocalized(@"common.done") forState:UIControlStateNormal];
    done.accessibilityIdentifier = @"wolkaraforever.controls.done";
    [done addTarget:self action:@selector(finishConfiguration) forControlEvents:UIControlEventTouchUpInside];

    UIStackView *footer = [[UIStackView alloc] initWithArrangedSubviews:@[reset, done]];
    footer.axis = UILayoutConstraintAxisHorizontal;
    footer.distribution = UIStackViewDistributionFillEqually;
    footer.translatesAutoresizingMaskIntoConstraints = NO;
    [_settings addSubview:footer];

    [NSLayoutConstraint activateConstraints:@[
        [footer.bottomAnchor constraintEqualToAnchor:_settings.bottomAnchor constant:-8],
        [footer.heightAnchor constraintEqualToConstant:44],
        [footer.leadingAnchor constraintEqualToAnchor:_settings.leadingAnchor constant:18],
        [footer.trailingAnchor constraintEqualToAnchor:_settings.trailingAnchor constant:-18],
        [scroll.topAnchor constraintEqualToAnchor:_settings.topAnchor constant:16],
        [scroll.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-8],
        [scroll.leadingAnchor constraintEqualToAnchor:_settings.leadingAnchor constant:18],
        [scroll.trailingAnchor constraintEqualToAnchor:_settings.trailingAnchor constant:-18],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
    ]];
    [self updateAppearance];
    if (self.configurationChanged) self.configurationChanged();
}

- (void)updateValues {
    _values[0].text = AKHostLocalizedFormat(@"touch.settings.transparency.value", (1 - _preferences.opacity) * 100);
    _values[1].text = AKHostLocalizedFormat(@"touch.settings.shoulderSize.value", _preferences.rearScale * 100);
    _values[2].text = AKHostLocalizedFormat(@"touch.settings.stickSize.value", _preferences.frontScale * 100);
    for (NSUInteger i = 0; i < _sliders.count; i++) _sliders[i].accessibilityValue = _values[i].text;
}

- (void)sliderChanged:(UISlider *)slider {
    if (slider.tag == 0) _preferences.opacity = 1 - slider.value;
    else if (slider.tag == 1) _preferences.rearScale = slider.value;
    else if (slider.tag == 2) _preferences.frontScale = slider.value;
    [_preferences save];
    [self updateValues];
    [self updateAppearance];
}

- (void)swapShouldersChanged:(UISwitch *)sender {
    [self reset];
    _preferences.swapShoulders = !sender.on;
    [_preferences save];
    [self updateAppearance];
}

- (void)hapticsChanged:(UISwitch *)sender {
    _preferences.hapticsEnabled = sender.on;
    [_preferences save];
    if (self.configurationChanged) self.configurationChanged();
}

- (void)performanceChanged:(UISwitch *)sender {
    _preferences.performanceOverlayEnabled = sender.on;
    [_preferences save];
}

- (void)leftStickWasdChanged:(UISwitch *)sender {
    _preferences.leftStickWASD = sender.on;
    [_preferences save];
    if (self.configurationChanged) self.configurationChanged();
}

- (void)clearSettingsViews {
    [_settings removeFromSuperview];
    _settings = nil;
    _sliders = nil;
    _values = nil;
    _editSwitch = nil;
    _hapticsSwitch = nil;
    _swapShouldersSwitch = nil;
    _performanceSwitch = nil;
    _leftStickWasdSwitch = nil;
    _settingsColumns = nil;
    _targetButton = nil;
    _interactButton = nil;
    _jumpButton = nil;
    _cameraDragButton = nil;
    _hudVisibilityButton = nil;
}

- (void)beginEditing:(UISwitch *)sender {
    if (!sender.on) return;
    [self reset];
    _editing = YES;
    [self clearSettingsViews];
    [self updateAppearance];
    if (self.configurationChanged) self.configurationChanged();
}

- (void)editAbilities {
    [self finishConfiguration];
    [self bringSubviewToFront:_actions];
    [_actions beginEditing];
}

- (void)resetLayout {
    [self reset];
    [_preferences reset];
    _sliders[0].value = 1 - _preferences.opacity;
    _sliders[1].value = _preferences.rearScale;
    _sliders[2].value = _preferences.frontScale;
    _hapticsSwitch.on = _preferences.hapticsEnabled;
    _swapShouldersSwitch.on = !_preferences.swapShoulders;
    _performanceSwitch.on = _preferences.performanceOverlayEnabled;
    _leftStickWasdSwitch.on = _preferences.leftStickWASD;
    [self rebuildHudBindingMenus];
    [self updateValues];
    [self updateAppearance];
}

- (void)finishConfiguration {
    [_actions finishEditing];
    [self reset];
    [_preferences save];
    _editing = NO;
    [_dragOrigins removeAllObjects];
    [self clearSettingsViews];
    [self updateAppearance];
    if (self.configurationChanged) self.configurationChanged();
}

- (void)reset {
    [_actions releaseTouches];
    [_cameraPad cancelPendingTouch];
    for (AKGamepadButton *button in _buttons.allValues) [button releaseInput];
    for (AKGamepadButton *button in _hudButtons.allValues) [button releaseInput];
    [_leftStick reset];
    [_rightStick reset];
}
@end

@interface AKPendingKeyRelease : NSObject
@property(nonatomic) BOOL isMouse;
@property(nonatomic) unsigned mouseButton;
@property(nonatomic) unsigned short keyCode;
@property(nonatomic, copy) NSString *characters;
@property(nonatomic) NSUInteger modifiers;
@property(nonatomic, strong) NSTimer *timer;
@end
@implementation AKPendingKeyRelease
@end

@interface AKTouchGamepad () <UIGestureRecognizerDelegate>
@end

@implementation AKTouchGamepad {
    __weak UIView *_host;
    GCVirtualController *_virtualController;
    AKGamepadOverlay *_overlay;
    AKTouchHaptics *_haptics;
    AKTouchActionInput *_actionInput;
    NSMutableDictionary<NSString *, NSString *> *_activeHudBindings;
    NSMutableArray<AKPendingKeyRelease *> *_pendingKeyReleases;
    NSMutableDictionary<NSString *, AKTouchAction *> *_heldCustomActions;
    NSMutableSet<NSNumber *> *_heldWasdKeys;
    UITapGestureRecognizer *_leftDoubleTap, *_rightDoubleTap, *_areaDoubleTap;
    NSTimer *_leftClickTimer, *_rightClickTimer;
    BOOL _active, _connecting, _cancelConnect, _failed, _invalidated;
}

- (instancetype)initWithHostView:(UIView *)host {
    if ((self = [super init])) {
        _host = host;
        _enabled = YES;
        _activeHudBindings = [NSMutableDictionary new];
        _pendingKeyReleases = [NSMutableArray new];
        _heldCustomActions = [NSMutableDictionary new];
        _heldWasdKeys = [NSMutableSet new];
        _haptics = [self makeHaptics];
        _overlay = [[AKGamepadOverlay alloc] initWithFrame:host.bounds];
        _overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [host addSubview:_overlay];
        __weak AKTouchGamepad *weakSelf = self;
        _actionInput = [AKTouchActionInput new];
        _actionInput.changed = ^(NSString *button, BOOL pressed) {
            [weakSelf publishButton:button pressed:pressed];
        };
        _overlay.actions.press = ^BOOL(AKTouchAction *action) {
            AKTouchGamepad *self = weakSelf;
            if (!self || !self->_visible || self->_overlay.configuring) return NO;
            if (action.kind == AKTouchActionKindKeyboard) {
                [self->_haptics buttonPressed];
                if (action.behavior == AKTouchActionBehaviorTap) {
                    [self triggerKeyboardAction:action];
                } else {
                    self->_heldCustomActions[action.identifier] = action;
                    [self sendKeyCode:action.keyCode characters:action.keyCharacters modifiers:action.keyModifiers pressed:YES];
                }
                return YES;
            }
            if (action.kind == AKTouchActionKindMouse) {
                [self->_haptics buttonPressed];
                if (action.behavior == AKTouchActionBehaviorTap) {
                    [self triggerMouseAction:action];
                } else {
                    self->_heldCustomActions[action.identifier] = action;
                    [self sendMouseButton:action.mouseButton pressed:YES];
                }
                return YES;
            }
            BOOL accepted = [self->_actionInput beginAction:action.identifier button:action.button modifiers:action.modifiers];
            if (accepted) [self->_haptics buttonPressed];
            return accepted;
        };
        _overlay.actions.released = ^(AKTouchAction *action) {
            AKTouchGamepad *self = weakSelf;
            if (!self) return;
            if (action.kind == AKTouchActionKindGamepad) {
                [self->_actionInput endAction:action.identifier];
                return;
            }
            if (action.behavior != AKTouchActionBehaviorTap) {
                AKTouchAction *held = self->_heldCustomActions[action.identifier];
                if (!held) return;
                [self->_heldCustomActions removeObjectForKey:action.identifier];
                if (held.kind == AKTouchActionKindKeyboard) {
                    [self sendKeyCode:held.keyCode characters:held.keyCharacters modifiers:held.keyModifiers pressed:NO];
                } else if (held.kind == AKTouchActionKindMouse) {
                    [self sendMouseButton:held.mouseButton pressed:NO];
                }
            }
        };
        _overlay.actions.cancelledAll = ^{
            AKTouchGamepad *self = weakSelf;
            if (self) {
                [self->_actionInput cancelAllActions];
                [self releaseAllPendingKeyboardActions];
            }
        };
        _overlay.actions.beginDrag = ^BOOL(UITouch *touch, CGPoint origin) {
            AKTouchGamepad *self = weakSelf;
            if (!self) return NO;
            UIView<AKTouchDragHost> *host = (id)self->_host;
            if (!self->_visible || self->_overlay.configuring || ![host conformsToProtocol:@protocol(AKTouchDragHost)]) return NO;
            return [host ak_beginTouchDrag:touch origin:[self->_overlay.actions convertPoint:origin toView:host]];
        };
        _overlay.actions.moveDrag = ^(UITouch *touch) {
            AKTouchGamepad *self = weakSelf;
            if (!self) return;
            UIView<AKTouchDragHost> *host = (id)self->_host;
            if ([host conformsToProtocol:@protocol(AKTouchDragHost)]) [host ak_moveTouchDrag:touch];
        };
        _overlay.actions.endDrag = ^(UITouch *touch, BOOL cancelled) {
            AKTouchGamepad *self = weakSelf;
            if (!self) return;
            UIView<AKTouchDragHost> *host = (id)self->_host;
            if ([host conformsToProtocol:@protocol(AKTouchDragHost)]) [host ak_endTouchDrag:touch cancelled:cancelled];
        };

        _overlay.cameraPad.beginDrag = ^BOOL(UITouch *touch, CGPoint origin) {
            AKTouchGamepad *self = weakSelf;
            if (!self) return NO;
            UIView<AKTouchDragHost> *host = (id)self->_host;
            if (!self->_visible || self->_overlay.configuring || ![host conformsToProtocol:@protocol(AKTouchDragHost)]) return NO;
            CGPoint hostOrigin = [self->_overlay.cameraPad convertPoint:origin toView:host];
            if ([host respondsToSelector:@selector(ak_beginCameraDrag:origin:rightButton:)]) {
                return [host ak_beginCameraDrag:touch origin:hostOrigin rightButton:self->_overlay.preferences.cameraRightDrag];
            }
            return [host ak_beginTouchDrag:touch origin:hostOrigin];
        };
        _overlay.cameraPad.moveDrag = ^(UITouch *touch) {
            AKTouchGamepad *self = weakSelf;
            if (!self) return;
            UIView<AKTouchDragHost> *host = (id)self->_host;
            if ([host conformsToProtocol:@protocol(AKTouchDragHost)]) [host ak_moveTouchDrag:touch];
        };
        _overlay.cameraPad.endDrag = ^(UITouch *touch, BOOL cancelled) {
            AKTouchGamepad *self = weakSelf;
            if (!self) return;
            UIView<AKTouchDragHost> *host = (id)self->_host;
            if ([host conformsToProtocol:@protocol(AKTouchDragHost)]) [host ak_endTouchDrag:touch cancelled:cancelled];
        };

        _leftDoubleTap = [self installDoubleTapOn:_overlay.leftStick selector:@selector(leftStickDoubleTapped:) background:NO];
        _rightDoubleTap = [self installDoubleTapOn:_overlay.rightStick selector:@selector(rightStickDoubleTapped:) background:NO];
        _areaDoubleTap = [self installDoubleTapOn:host selector:@selector(rightStickDoubleTapped:) background:YES];
        _overlay.leftStick.accessibilityHint = AKHostLocalized(@"touch.gamepad.leftStick.hint");
        _overlay.rightStick.accessibilityHint = AKHostLocalized(@"touch.gamepad.rightStick.hint");
        _overlay.configurationChanged = ^{
            AKTouchGamepad *self = weakSelf;
            if (!self) return;
            if (self->_overlay.configuring) {
                [self cancelStickClicks];
                [self releaseAllHudBindings];
                [self releaseAllPendingKeyboardActions];
                [self->_actionInput releaseAll];
            }
            [self updateHaptics];
            if (self.visibilityChanged) self.visibilityChanged(self.visible);
        };
        for (AKGamepadButton *button in _overlay.buttons.allValues) {
            [button addTarget:self action:@selector(buttonChanged:) forControlEvents:UIControlEventValueChanged];
        }
        for (AKGamepadButton *button in _overlay.hudButtons.allValues) {
            [button addTarget:self action:@selector(hudButtonChanged:) forControlEvents:UIControlEventValueChanged];
        }
        [_overlay.leftStick addTarget:self action:@selector(stickChanged:) forControlEvents:UIControlEventValueChanged];
        [_overlay.rightStick addTarget:self action:@selector(stickChanged:) forControlEvents:UIControlEventValueChanged];
        _active = UIApplication.sharedApplication.applicationState == UIApplicationStateActive;
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        for (NSString *name in @[GCControllerDidConnectNotification, GCControllerDidDisconnectNotification,
                                 UIWindowDidBecomeKeyNotification, UIWindowDidResignKeyNotification,
                                 UIWindowDidBecomeVisibleNotification, UIWindowDidBecomeHiddenNotification])
            [center addObserver:self selector:@selector(environmentChanged:) name:name object:nil];
        [center addObserver:self selector:@selector(activate:) name:UIApplicationDidBecomeActiveNotification object:nil];
        [center addObserver:self selector:@selector(deactivate:) name:UIApplicationWillResignActiveNotification object:nil];
    }
    return self;
}

- (BOOL)editing { return _overlay.editing || _overlay.actions.editing; }
- (BOOL)editingAbilities { return _overlay.actions.editing; }

- (BOOL)configurationContainsPoint:(CGPoint)point inView:(UIView *)view {
    return [_overlay configurationContainsPoint:point inView:view];
}

- (AKGamepadLayout *)layout { return _overlay.preferences; }
- (NSArray<GCController *> *)connectedControllers { return GCController.controllers; }
- (AKTouchHaptics *)makeHaptics { return [AKTouchHaptics new]; }

- (void)updateHaptics {
    BOOL input = _visible && !_overlay.configuring;
    _haptics.enabled = input && _overlay.preferences.hapticsEnabled;
    _leftDoubleTap.enabled = _areaDoubleTap.enabled = input;
    _rightDoubleTap.enabled = input && !_simple;
}

- (UITapGestureRecognizer *)installDoubleTapOn:(UIView *)view selector:(SEL)selector background:(BOOL)background {
    UITapGestureRecognizer *tap = [[AKStickDoubleTap alloc] initWithTarget:self action:selector];
    tap.numberOfTapsRequired = 2;
    tap.numberOfTouchesRequired = 1;
    tap.allowedTouchTypes = @[@(UITouchTypeDirect)];
    tap.delegate = self;
    tap.enabled = NO;
    tap.delaysTouchesBegan = NO;
    tap.delaysTouchesEnded = background;
    tap.cancelsTouchesInView = background;
    [view addGestureRecognizer:tap];
    return tap;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (!_visible || _overlay.configuring || _keyboardVisible || touch.type != UITouchTypeDirect) return NO;
    if (gesture == _areaDoubleTap) {
        if (touch.view != _host) return NO;
        CGRect safe = UIEdgeInsetsInsetRect(_host.bounds, _host.safeAreaInsets);
        CGPoint point = [touch locationInView:_host];
        return CGRectContainsPoint(safe, point) && point.x >= CGRectGetMidX(safe) && point.y >= CGRectGetMidY(safe);
    }
    return gesture == _leftDoubleTap || (gesture == _rightDoubleTap && !_simple);
}

- (void)leftStickDoubleTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateRecognized) [self clickStick:YES];
}

- (void)rightStickDoubleTapped:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateRecognized) [self clickStick:NO];
}

- (void)clickStick:(BOOL)left {
    if (!_visible || _overlay.configuring || _keyboardVisible) return;
    NSString *button = left ? GCInputLeftThumbstickButton : GCInputRightThumbstickButton;
    if ([_actionInput.pressedButtons containsObject:button]) return;
    [_actionInput setManualButton:button pressed:YES];
    [_haptics buttonPressed];
    __weak AKTouchGamepad *weakSelf = self;
    NSTimer *timer = [NSTimer timerWithTimeInterval:0.08 repeats:NO block:^(NSTimer *t) {
        (void)t;
        AKTouchGamepad *self = weakSelf;
        if (!self) return;
        [self->_actionInput setManualButton:button pressed:NO];
        if (left) self->_leftClickTimer = nil;
        else self->_rightClickTimer = nil;
    }];
    if (left) _leftClickTimer = timer;
    else _rightClickTimer = timer;
    [NSRunLoop.mainRunLoop addTimer:timer forMode:NSRunLoopCommonModes];
}

- (void)cancelStickClicks {
    [_leftClickTimer invalidate];
    [_rightClickTimer invalidate];
    _leftClickTimer = _rightClickTimer = nil;
    _leftDoubleTap.enabled = _rightDoubleTap.enabled = _areaDoubleTap.enabled = NO;
    [_actionInput setManualButton:GCInputLeftThumbstickButton pressed:NO];
    [_actionInput setManualButton:GCInputRightThumbstickButton pressed:NO];
}

- (void)sendKeyCode:(unsigned short)keyCode characters:(NSString *)characters modifiers:(NSUInteger)modifiers pressed:(BOOL)pressed {
    UIView<AKTouchDragHost> *host = (id)_host;
    if ([host respondsToSelector:@selector(ak_sendKeyCode:characters:modifiers:pressed:)]) {
        [host ak_sendKeyCode:keyCode characters:characters modifiers:modifiers pressed:pressed];
    }
}

- (void)triggerKeyboardAction:(AKTouchAction *)action {
    unsigned short keyCode = action.macKeyCode;
    NSString *characters = action.macCharacters;
    NSUInteger modifiers = action.keyModifiers;
    [self sendKeyCode:keyCode characters:characters modifiers:modifiers pressed:YES];
    AKPendingKeyRelease *pending = [AKPendingKeyRelease new];
    pending.keyCode = keyCode;
    pending.characters = characters;
    pending.modifiers = modifiers;
    __weak AKTouchGamepad *weakSelf = self;
    __weak AKPendingKeyRelease *weakPending = pending;
    pending.timer = [NSTimer timerWithTimeInterval:0.04 repeats:NO block:^(NSTimer *timer) {
        (void)timer;
        AKTouchGamepad *self = weakSelf;
        AKPendingKeyRelease *item = weakPending;
        if (!self || !item) return;
        [self->_pendingKeyReleases removeObject:item];
        [self sendKeyCode:item.keyCode characters:item.characters modifiers:item.modifiers pressed:NO];
    }];
    [_pendingKeyReleases addObject:pending];
    [NSRunLoop.mainRunLoop addTimer:pending.timer forMode:NSRunLoopCommonModes];
}

- (void)sendMouseButton:(unsigned)button pressed:(BOOL)pressed {
    UIView<AKTouchDragHost> *host = (id)_host;
    if ([host respondsToSelector:@selector(ak_sendMouseClick:pressed:)]) {
        [host ak_sendMouseClick:button pressed:pressed];
    }
}

- (void)triggerMouseAction:(AKTouchAction *)action {
    unsigned button = action.mouseButton;
    [self sendMouseButton:button pressed:YES];
    AKPendingKeyRelease *pending = [AKPendingKeyRelease new];
    pending.isMouse = YES;
    pending.mouseButton = button;
    __weak AKTouchGamepad *weakSelf = self;
    __weak AKPendingKeyRelease *weakPending = pending;
    pending.timer = [NSTimer timerWithTimeInterval:0.04 repeats:NO block:^(NSTimer *timer) {
        (void)timer;
        AKTouchGamepad *self = weakSelf;
        AKPendingKeyRelease *item = weakPending;
        if (!self || !item) return;
        [self->_pendingKeyReleases removeObject:item];
        [self sendMouseButton:item.mouseButton pressed:NO];
    }];
    [_pendingKeyReleases addObject:pending];
    [NSRunLoop.mainRunLoop addTimer:pending.timer forMode:NSRunLoopCommonModes];
}

- (void)releaseAllHeldWasdKeys {
    if (!_heldWasdKeys.count) return;
    NSDictionary<NSNumber *, NSString *> *chars = @{@13: @"w", @0: @"a", @1: @"s", @2: @"d"};
    NSArray<NSNumber *> *keys = [_heldWasdKeys allObjects];
    [_heldWasdKeys removeAllObjects];
    for (NSNumber *k in keys) {
        [self sendKeyCode:k.unsignedShortValue characters:chars[k] ?: @"" modifiers:0 pressed:NO];
    }
}

- (void)releaseAllPendingKeyboardActions {
    NSArray<AKPendingKeyRelease *> *pending = [_pendingKeyReleases copy];
    [_pendingKeyReleases removeAllObjects];
    for (AKPendingKeyRelease *item in pending) {
        [item.timer invalidate];
        if (item.isMouse) [self sendMouseButton:item.mouseButton pressed:NO];
        else [self sendKeyCode:item.keyCode characters:item.characters modifiers:item.modifiers pressed:NO];
    }
    NSArray<AKTouchAction *> *heldCustom = [_heldCustomActions.allValues copy];
    [_heldCustomActions removeAllObjects];
    for (AKTouchAction *action in heldCustom) {
        if (action.kind == AKTouchActionKindMouse) [self sendMouseButton:action.mouseButton pressed:NO];
        else if (action.kind == AKTouchActionKindKeyboard) [self sendKeyCode:action.keyCode characters:action.keyCharacters modifiers:action.keyModifiers pressed:NO];
    }
    [self releaseAllHeldWasdKeys];
}

- (NSString *)bindingForHudElement:(NSString *)element {
    if ([element isEqualToString:@"hud.target"]) return _overlay.preferences.targetBinding;
    if ([element isEqualToString:@"hud.interact"]) return _overlay.preferences.interactBinding;
    if ([element isEqualToString:@"hud.jump"]) return _overlay.preferences.jumpBinding;
    return nil;
}

- (void)dispatchBinding:(NSString *)binding pressed:(BOOL)pressed {
    if (!binding.length) return;
    if ([binding hasPrefix:@"gamepad."]) {
        NSString *btn = [binding substringFromIndex:@"gamepad.".length];
        [_actionInput setManualButton:btn pressed:pressed];
        return;
    }
    if ([binding isEqualToString:@"mouse.right"]) {
        [self sendMouseButton:1 pressed:pressed];
        return;
    }
    unsigned short keyCode = 0;
    NSString *chars = nil;
    if ([AKTouchAction keyInfoForName:binding keyCode:&keyCode characters:&chars]) {
        [self sendKeyCode:keyCode characters:chars modifiers:0 pressed:pressed];
    }
}

- (void)hudButtonChanged:(AKGamepadButton *)button {
    NSString *element = button.element;
    if (!element.length) return;
    if (button.pressed) {
        if (!_visible || _overlay.configuring || !button.enabled) return;
        NSString *binding = [self bindingForHudElement:element];
        if (!binding.length) return;
        [_haptics buttonPressed];
        _activeHudBindings[element] = binding;
        [self dispatchBinding:binding pressed:YES];
    } else {
        NSString *binding = _activeHudBindings[element];
        if (binding.length) {
            [_activeHudBindings removeObjectForKey:element];
            [self dispatchBinding:binding pressed:NO];
        }
    }
}

- (void)releaseAllHudBindings {
    NSDictionary<NSString *, NSString *> *held = [_activeHudBindings copy];
    [_activeHudBindings removeAllObjects];
    for (NSString *binding in held.allValues) {
        [self dispatchBinding:binding pressed:NO];
    }
}

- (GCVirtualController *)makeController {
    GCVirtualControllerConfiguration *configuration = [GCVirtualControllerConfiguration new];
    configuration.hidden = YES;
    configuration.elements = [NSSet setWithArray:@[GCInputLeftThumbstick, GCInputRightThumbstick,
        GCInputButtonA, GCInputButtonB, GCInputButtonX, GCInputButtonY,
        GCInputLeftShoulder, GCInputRightShoulder, GCInputLeftTrigger, GCInputRightTrigger]];
    GCVirtualController *controller = [[GCVirtualController alloc] initWithConfiguration:configuration];
    AKRegisterTouchStickButtons(controller);
    return controller;
}

- (BOOL)hostIsActive {
    UIWindow *window = _host.window;
    return _active && window.isKeyWindow && !window.hidden && !_host.hidden;
}

- (BOOL)hasPhysicalController {
    GCController *own = _virtualController.controller;
    for (GCController *controller in [self connectedControllers]) {
        if (controller != own && !controller.isSnapshot &&
            (controller.extendedGamepad || controller.microGamepad)) return YES;
    }
    return NO;
}

- (BOOL)wantsController {
    return !_invalidated && _enabled && !_keyboardVisible && [self hostIsActive];
}

- (void)setVisible:(BOOL)visible {
    if (_visible == visible) return;
    _visible = visible;
    _overlay.controlsVisible = visible;
    [self updateHaptics];
    if (self.visibilityChanged) self.visibilityChanged(visible);
}

- (void)buttonChanged:(AKGamepadButton *)button {
    if (!_visible || _overlay.configuring || (button.pressed && !button.enabled)) return;
    if (button.pressed) [_haptics buttonPressed];
    NSDictionary *names = @{
        GCInputButtonA: @"A", GCInputButtonB: @"B", GCInputButtonX: @"X", GCInputButtonY: @"Y",
        GCInputLeftTrigger: @"LT", GCInputRightTrigger: @"RT",
        GCInputLeftShoulder: @"LB", GCInputRightShoulder: @"RB",
        @"dpad.up": @"up", @"dpad.right": @"right", @"dpad.down": @"down", @"dpad.left": @"left"
    };
    [_actionInput setManualButton:names[button.element] ?: button.element pressed:button.pressed];
}

- (void)publishButton:(NSString *)button pressed:(BOOL)pressed {
    if (([button isEqual:GCInputLeftThumbstickButton] || [button isEqual:GCInputRightThumbstickButton]) &&
        AKSetTouchStickButton(_virtualController.controller, [button isEqual:GCInputLeftThumbstickButton], pressed)) return;
    if ([@[@"up", @"right", @"down", @"left"] containsObject:button]) {
        NSSet *held = _actionInput.pressedButtons;
        CGPoint value = CGPointMake([held containsObject:@"right"] - [held containsObject:@"left"],
                                    [held containsObject:@"up"] - [held containsObject:@"down"]);
        [_virtualController setPosition:value forDirectionPadElement:GCInputDirectionPad];
    } else {
        NSDictionary *elements = @{
            @"A": GCInputButtonA, @"B": GCInputButtonB, @"X": GCInputButtonX, @"Y": GCInputButtonY,
            @"LT": GCInputLeftTrigger, @"RT": GCInputRightTrigger,
            @"LB": GCInputLeftShoulder, @"RB": GCInputRightShoulder
        };
        [_virtualController setValue:pressed ? 1 : 0 forButtonElement:elements[button] ?: button];
    }
}

- (void)updateWasdForStickPosition:(CGPoint)position {
    static const CGFloat kDeadzone = 0.30;
    static const unsigned short kCodes[4] = {13, 0, 1, 2};
    NSArray<NSString *> *chars = @[@"w", @"a", @"s", @"d"];
    const BOOL down[4] = {
        position.y > kDeadzone,
        position.x < -kDeadzone,
        position.y < -kDeadzone,
        position.x > kDeadzone,
    };
    for (NSUInteger i = 0; i < 4; i++) {
        NSNumber *num = @(kCodes[i]);
        BOOL wasDown = [_heldWasdKeys containsObject:num];
        if (down[i] && !wasDown) {
            [_heldWasdKeys addObject:num];
            [self sendKeyCode:kCodes[i] characters:chars[i] modifiers:0 pressed:YES];
        } else if (!down[i] && wasDown) {
            [_heldWasdKeys removeObject:num];
            [self sendKeyCode:kCodes[i] characters:chars[i] modifiers:0 pressed:NO];
        }
    }
}

- (void)stickChanged:(AKGamepadStick *)stick {
    if (_visible && !_overlay.configuring && (!_simple || stick == _overlay.leftStick)) {
        [_haptics stickMoved:stick.position left:stick == _overlay.leftStick];
        if (stick == _overlay.leftStick && _overlay.preferences.leftStickWASD) {
            [self updateWasdForStickPosition:stick.position];
            [_virtualController setPosition:CGPointZero forDirectionPadElement:GCInputLeftThumbstick];
            return;
        }
        if (stick == _overlay.leftStick) [self releaseAllHeldWasdKeys];
        [_virtualController setPosition:stick.position forDirectionPadElement:stick.element];
    }
}

- (void)disconnectController {
    GCVirtualController *controller = _virtualController;
    [self cancelStickClicks];
    [_overlay reset];
    [self releaseAllHudBindings];
    [self releaseAllPendingKeyboardActions];
    [_actionInput releaseAll];
    _virtualController = nil;
    [controller disconnect];
    AKUnregisterTouchStickButtons(controller);
    [self setVisible:NO];
}

- (void)refresh {
    NSAssert(NSThread.isMainThread, @"Touch controller lifecycle belongs on the main thread");
    if ([self hasPhysicalController] && _overlay.configuring) [_overlay finishConfiguration];
    if (_connecting) {
        if (![self wantsController]) { _cancelConnect = YES; [_virtualController disconnect]; }
        return;
    }
    if (![self wantsController] || [self hasPhysicalController]) {
        [self disconnectController];
        return;
    }
    if (_virtualController || _failed) return;
    _virtualController = [self makeController];
    _connecting = YES;
    _cancelConnect = NO;
    GCVirtualController *connecting = _virtualController;
    __weak AKTouchGamepad *weakSelf = self;
    [connecting connectWithReplyHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            AKTouchGamepad *self = weakSelf;
            if (!self) { [connecting disconnect]; return; }
            self->_connecting = NO;
            BOOL cancelled = self->_cancelConnect;
            self->_cancelConnect = NO;
            if (error || cancelled || ![self wantsController] || [self hasPhysicalController]) {
                if (error) NSLog(@"[TouchGamepad] Connection failed: %@ (%ld)", error.domain, (long)error.code);
                self->_failed = error != nil;
                [self disconnectController];
                if (cancelled && !error) [self refresh];
                return;
            }
            [self setVisible:YES];
        });
    }];
}

- (void)environmentChanged:(NSNotification *)note {
    (void)note;
    __weak AKTouchGamepad *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf refresh]; });
}

- (void)activate:(NSNotification *)note {
    (void)note;
    _active = YES;
    _failed = NO;
    [self refresh];
}

- (void)deactivate:(NSNotification *)note {
    (void)note;
    [_overlay finishConfiguration];
    _active = NO;
    [self refresh];
}

- (void)setSimple:(BOOL)simple {
    if (_simple == simple) return;
    [self cancelStickClicks];
    [_overlay reset];
    [self releaseAllHudBindings];
    [self releaseAllPendingKeyboardActions];
    [_actionInput releaseAll];
    _simple = simple;
    _overlay.simple = simple;
    [self updateHaptics];
    if (self.visibilityChanged) self.visibilityChanged(_visible);
}

- (void)setEnabled:(BOOL)enabled {
    _enabled = enabled;
    _failed = NO;
    [self refresh];
}

- (void)setKeyboardVisible:(BOOL)visible {
    _keyboardVisible = visible;
    [self refresh];
}

- (BOOL)configuring { return _overlay.configuring; }
- (void)toggleSettings { [_overlay toggleSettings]; }

- (void)invalidate {
    [_overlay finishConfiguration];
    _invalidated = YES;
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self refresh];
    [_host removeGestureRecognizer:_areaDoubleTap];
    [_overlay removeFromSuperview];
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [_leftClickTimer invalidate];
    [_rightClickTimer invalidate];
    for (AKPendingKeyRelease *item in _pendingKeyReleases) [item.timer invalidate];
    [_pendingKeyReleases removeAllObjects];
    [_host removeGestureRecognizer:_areaDoubleTap];
    [_virtualController disconnect];
    AKUnregisterTouchStickButtons(_virtualController);
}
@end
