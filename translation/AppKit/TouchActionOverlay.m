#import "TouchActionOverlay.h"
#import "TouchGamepad.h"
#include <math.h>

@class AKActionCircle;
@interface AKTouchActionOverlay (Tracking)
- (void)up:(AKActionCircle *)circle;
- (void)updateAppearance;
@end

@interface AKActionCircle : UIButton
@property(nonatomic, strong) AKTouchAction *action;
@property(nonatomic) BOOL inputHeld;
@property(nonatomic) BOOL toggledOn;
@property(nonatomic, weak) AKTouchActionOverlay *owner;
- (void)cancelPendingTouch;
@end

@implementation AKActionCircle {
    __weak UITouch *_finger;
    CGPoint _origin;
    BOOL _dragged, _forwarded, _holdSent;
}

static CGFloat CornerRadiusForAction(AKTouchAction *action, CGSize size) {
    CGFloat m = MIN(size.width, size.height);
    if (action.shape == AKTouchActionShapeSquare) return MIN(10, m * 0.22);
    return m / 2.0;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = CornerRadiusForAction(self.action, self.bounds.size);
    self.clipsToBounds = YES;
    CGFloat fontSize = MAX(9, MIN(14, MIN(self.bounds.size.width, self.bounds.size.height) * 0.30));
    if (fabs(self.titleLabel.font.pointSize - fontSize) > 0.5) {
        self.titleLabel.font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightBold];
    }
}

- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)event {
    (void)event;
    if (self.action.shape != AKTouchActionShapeCircle || fabs(self.bounds.size.width - self.bounds.size.height) > 2.0) {
        return CGRectContainsPoint(self.bounds, p);
    }
    CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) / 2;
    return hypot(p.x - self.bounds.size.width / 2, p.y - self.bounds.size.height / 2) <= radius;
}

- (BOOL)beginTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    if (_finger || self.owner.editing || !self.owner.active || !self.owner.layout.enabled || !self.action.enabled) return NO;
    _finger = touch;
    _origin = [touch locationInView:self.owner];
    _dragged = NO;
    _forwarded = NO;
    _holdSent = NO;
    if (self.action.behavior == AKTouchActionBehaviorHold) {
        BOOL ok = self.owner.press && self.owner.press(self.action);
        _holdSent = ok;
        self.inputHeld = ok;
        [self.owner updateAppearance];
        return YES;
    }
    self.inputHeld = YES;
    [self.owner updateAppearance];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    if (touch != _finger) return NO;
    if (_holdSent) return YES;
    CGPoint point = [touch locationInView:self.owner];
    if (!_dragged && hypot(point.x - _origin.x, point.y - _origin.y) >= AKTouchDragThreshold) {
        _dragged = YES;
        self.inputHeld = NO;
        [self.owner updateAppearance];
        _forwarded = self.owner.beginDrag && self.owner.beginDrag(touch, _origin);
    }
    if (_forwarded && self.owner.moveDrag) self.owner.moveDrag(touch);
    return YES; // Keep the drag after the finger leaves the circle.
}

- (void)endTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    if (touch != _finger) return;
    if (_holdSent) {
        _finger = nil;
        _holdSent = NO;
        self.inputHeld = NO;
        if (self.owner.released) self.owner.released(self.action);
        [self.owner updateAppearance];
        return;
    }
    CGPoint point = [touch locationInView:self.owner];
    BOOL tap = !_dragged && hypot(point.x - _origin.x, point.y - _origin.y) < AKTouchDragThreshold &&
               [self pointInside:[touch locationInView:self] withEvent:event];
    if (_forwarded && self.owner.endDrag) self.owner.endDrag(touch, NO);
    _finger = nil;
    _forwarded = NO;
    self.inputHeld = NO;
    if (tap) {
        if (self.action.behavior == AKTouchActionBehaviorToggle) {
            if (self.toggledOn) {
                self.toggledOn = NO;
                if (self.owner.released) self.owner.released(self.action);
            } else {
                BOOL accepted = self.owner.press && self.owner.press(self.action);
                self.toggledOn = accepted;
                if (!accepted) {
                    [self.owner updateAppearance];
                    self.layer.borderWidth = 2;
                    self.layer.borderColor = UIColor.systemOrangeColor.CGColor;
                    return;
                }
            }
            [self.owner updateAppearance];
            return;
        }
        [self.owner updateAppearance];
        [self.owner up:self]; // Leave rejection feedback visible after lift.
        return;
    }
    [self.owner updateAppearance];
}

- (void)cancelPendingTouch {
    if (_holdSent && self.owner.released) self.owner.released(self.action);
    if (_forwarded && _finger && self.owner.endDrag) self.owner.endDrag(_finger, YES);
    _finger = nil;
    _forwarded = NO;
    _holdSent = NO;
    self.inputHeld = NO;
    self.toggledOn = NO;
}

- (void)cancelTrackingWithEvent:(UIEvent *)event {
    (void)event;
    [self cancelPendingTouch];
    [self.owner updateAppearance];
}

- (BOOL)accessibilityActivate {
    if (self.owner.editing || !self.owner.active || !self.action.enabled) return NO;
    [self.owner up:self];
    return YES;
}
@end

@interface AKTouchActionOverlay () <UIGestureRecognizerDelegate>
@end

@implementation AKTouchActionOverlay {
    NSMutableArray<AKActionCircle *> *_circles;
    AKTouchAction *_selected, *_dragCreated;
    UIView *_panel, *_panelHeader, *_inspectorBox;
    UISegmentedControl *_mode;
    UISlider *_size, *_widthSlider, *_border, *_fill;
    UISwitch *_enabled, *_shown, *_labelsSwitch, *_snapSwitch;
    UILabel *_sizeLabel, *_widthLabel, *_selectionLabel;
    UIButton *_kindButton, *_binding, *_modifier, *_labelButton, *_presetButton, *_profileButton;
    UIButton *_behaviorButton, *_shapeButton, *_colorButton, *_dragAddChip, *_dockButton;
    CAShapeLayer *_gridLayer, *_axesLayer;
    BOOL _panelAtBottom, _panelCustomMoved;
    CGPoint _panelOffset, _panelDragStart;
    CGFloat _pinchInitial;
    CGSize _lastViewportSize;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = YES;
        _gridLayer = [CAShapeLayer layer];
        _axesLayer = [CAShapeLayer layer];
        for (CAShapeLayer *layer in @[_gridLayer, _axesLayer]) {
            layer.fillColor = nil;
            layer.zPosition = -1;
            layer.hidden = YES;
            [self.layer addSublayer:layer];
        }
        _gridLayer.strokeColor = [UIColor colorWithWhite:1 alpha:0.14].CGColor;
        _gridLayer.lineWidth = 0.5;
        _axesLayer.strokeColor = [UIColor colorWithRed:0.84 green:0.75 blue:0.55 alpha:0.45].CGColor;
        _axesLayer.lineWidth = 1;
        _axesLayer.lineDashPattern = @[@4, @4];
        _layout = [[AKTouchActionLayout alloc] initWithDefaults:NSUserDefaults.standardUserDefaults];
        [self rebuildCircles];
        UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(pinch:)];
        pinch.delegate = self;
        [self addGestureRecognizer:pinch];
    }
    return self;
}

- (CGRect)placementBounds {
    return UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets);
}

- (void)rebuildCircles {
    [self releaseTouches];
    for (UIView *view in _circles) [view removeFromSuperview];
    _circles = [NSMutableArray new];
    if (_selected && ![self.layout.actions containsObject:_selected]) {
        _selected = self.layout.actions.firstObject;
    }
    for (AKTouchAction *action in self.layout.actions) {
        AKActionCircle *circle = [AKActionCircle buttonWithType:UIButtonTypeCustom];
        circle.action = action;
        circle.owner = self;
        circle.exclusiveTouch = NO;
        circle.titleLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
        circle.titleLabel.numberOfLines = 2;
        circle.titleLabel.textAlignment = NSTextAlignmentCenter;
        circle.titleLabel.adjustsFontSizeToFitWidth = YES;
        circle.titleLabel.minimumScaleFactor = 0.65;
        [circle setTitleColor:[UIColor colorWithRed:0.96 green:0.95 blue:0.90 alpha:0.95] forState:UIControlStateNormal];
        circle.accessibilityIdentifier = [@"wolkara.ability." stringByAppendingString:action.identifier];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(drag:)];
        pan.delegate = self;
        [circle addGestureRecognizer:pan];
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(selectCircle:)];
        tap.delegate = self;
        [circle addGestureRecognizer:tap];
        [tap requireGestureRecognizerToFail:pan];
        UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(quickEditCircle:)];
        doubleTap.numberOfTapsRequired = 2;
        doubleTap.delegate = self;
        [circle addGestureRecognizer:doubleTap];
        [tap requireGestureRecognizerToFail:doubleTap];
        [self addSubview:circle];
        [_circles addObject:circle];
    }
    if (_panel) [self bringSubviewToFront:_panel];
    [self updateAppearance];
}

- (void)setActive:(BOOL)active {
    if (_active && !active) [self releaseTouches];
    _active = active;
    [self updateAppearance];
}

static UIColor *AKPresetFillColor(AKTouchActionColor preset, CGFloat alpha) {
    switch (preset) {
        case AKTouchActionColorGold:   return [UIColor colorWithRed:0.35 green:0.26 blue:0.06 alpha:alpha];
        case AKTouchActionColorRed:    return [UIColor colorWithRed:0.36 green:0.08 blue:0.08 alpha:alpha];
        case AKTouchActionColorBlue:   return [UIColor colorWithRed:0.07 green:0.18 blue:0.38 alpha:alpha];
        case AKTouchActionColorGreen:  return [UIColor colorWithRed:0.07 green:0.28 blue:0.14 alpha:alpha];
        case AKTouchActionColorPurple: return [UIColor colorWithRed:0.25 green:0.10 blue:0.36 alpha:alpha];
        case AKTouchActionColorClear:  return UIColor.clearColor;
        default:                       return [UIColor colorWithRed:0.06 green:0.06 blue:0.06 alpha:alpha];
    }
}

static UIColor *AKPresetBorderColor(AKTouchActionColor preset, CGFloat alpha) {
    switch (preset) {
        case AKTouchActionColorGold:   return [UIColor colorWithRed:0.98 green:0.82 blue:0.34 alpha:alpha];
        case AKTouchActionColorRed:    return [UIColor colorWithRed:0.95 green:0.38 blue:0.36 alpha:alpha];
        case AKTouchActionColorBlue:   return [UIColor colorWithRed:0.42 green:0.72 blue:0.98 alpha:alpha];
        case AKTouchActionColorGreen:  return [UIColor colorWithRed:0.36 green:0.88 blue:0.52 alpha:alpha];
        case AKTouchActionColorPurple: return [UIColor colorWithRed:0.78 green:0.50 blue:0.98 alpha:alpha];
        case AKTouchActionColorClear:  return UIColor.clearColor;
        default:                       return [UIColor colorWithRed:0.84 green:0.75 blue:0.55 alpha:alpha];
    }
}

- (void)updateAppearance {
    self.hidden = !self.editing && (!self.active || !self.layout.enabled);
    _gridLayer.hidden = _axesLayer.hidden = !self.editing;
    UIColor *heldFill = [UIColor colorWithRed:0.84 green:0.68 blue:0.32 alpha:0.42];
    for (AKActionCircle *circle in _circles) {
        BOOL selected = _selected && (circle.action == _selected ||
            (_mode.selectedSegmentIndex == 1 && [circle.action.groupIdentifier isEqual:_selected.groupIdentifier]));
        BOOL activeGlow = circle.inputHeld || circle.toggledOn;
        BOOL invisible = (circle.action.colorPreset == AKTouchActionColorClear) && !self.editing;
        circle.hidden = !self.editing && !circle.action.enabled;
        circle.layer.borderWidth = self.editing
            ? (selected ? 2.5 : 1.5)
            : (circle.toggledOn ? 2.0 : (!invisible && self.layout.borderOpacity > 0 ? 1.0 : 0));
        circle.layer.borderColor = (self.editing
            ? (selected ? UIColor.systemYellowColor : AKPresetBorderColor(circle.action.colorPreset == AKTouchActionColorClear ? AKTouchActionColorDefault : circle.action.colorPreset, 0.85))
            : (circle.toggledOn ? UIColor.systemYellowColor : AKPresetBorderColor(circle.action.colorPreset, self.layout.borderOpacity))).CGColor;
        CGFloat fillA = self.editing ? MAX(0.45, self.layout.fillOpacity) : self.layout.fillOpacity;
        circle.backgroundColor = activeGlow
            ? heldFill
            : AKPresetFillColor(self.editing && circle.action.colorPreset == AKTouchActionColorClear ? AKTouchActionColorDefault : circle.action.colorPreset, fillA);
        circle.alpha = self.editing && !circle.action.enabled ? 0.35 : 1;
        BOOL showText = self.editing || self.layout.showLabels;
        [circle setTitle:showText ? circle.action.label : @"" forState:UIControlStateNormal];
        circle.accessibilityLabel = circle.action.label;
        circle.accessibilityValue = circle.toggledOn ? @"Active" : (circle.action.enabled ? @"Enabled" : @"Hidden");
    }
    [self setNeedsLayout];
}

- (void)layoutGridInBounds:(CGRect)safe {
    UIBezierPath *grid = [UIBezierPath bezierPath], *axes = [UIBezierPath bezierPath];
    CGFloat step = 16.0;
    for (CGFloat line = CGRectGetMinX(safe); line <= CGRectGetMaxX(safe); line += step) {
        [grid moveToPoint:CGPointMake(line, CGRectGetMinY(safe))];
        [grid addLineToPoint:CGPointMake(line, CGRectGetMaxY(safe))];
    }
    for (CGFloat line = CGRectGetMinY(safe); line <= CGRectGetMaxY(safe); line += step) {
        [grid moveToPoint:CGPointMake(CGRectGetMinX(safe), line)];
        [grid addLineToPoint:CGPointMake(CGRectGetMaxX(safe), line)];
    }
    CGFloat midX = CGRectGetMidX(safe), midY = CGRectGetMidY(safe);
    [axes moveToPoint:CGPointMake(midX, CGRectGetMinY(safe))];
    [axes addLineToPoint:CGPointMake(midX, CGRectGetMaxY(safe))];
    [axes moveToPoint:CGPointMake(CGRectGetMinX(safe), midY)];
    [axes addLineToPoint:CGPointMake(CGRectGetMaxX(safe), midY)];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _gridLayer.frame = _axesLayer.frame = self.bounds;
    _gridLayer.path = grid.CGPath;
    _axesLayer.path = axes.CGPath;
    [CATransaction commit];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!CGSizeEqualToSize(_lastViewportSize, self.bounds.size)) {
        _lastViewportSize = self.bounds.size;
        [self releaseTouches];
    }
    CGRect bounds = [self placementBounds];
    if (self.editing) [self layoutGridInBounds:bounds];
    for (AKActionCircle *circle in _circles) {
        circle.frame = [self.layout frameForAction:circle.action inBounds:bounds];
        circle.layer.cornerRadius = CornerRadiusForAction(circle.action, circle.bounds.size);
    }
    if (_panel) {
        CGRect safe = UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets);
        CGFloat width = MIN(520, safe.size.width - 16);
        CGFloat height = MIN(272, safe.size.height - 20);
        if (_panelCustomMoved) {
            CGFloat x = MAX(CGRectGetMinX(safe) + 4, MIN(CGRectGetMaxX(safe) - width - 4, _panelOffset.x));
            CGFloat y = MAX(CGRectGetMinY(safe) + 4, MIN(CGRectGetMaxY(safe) - height - 4, _panelOffset.y));
            _panel.frame = CGRectMake(x, y, width, height);
        } else {
            CGFloat y = _panelAtBottom ? (CGRectGetMaxY(safe) - height - 8) : (CGRectGetMinY(safe) + 8);
            _panel.frame = CGRectMake(CGRectGetMidX(safe) - width / 2, y, width, height);
        }
    }
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}

- (BOOL)editorContainsPoint:(CGPoint)point inView:(UIView *)view {
    return self.editing && CGRectContainsPoint(_panel.bounds, [_panel convertPoint:point fromView:view]);
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (!self.editing) return NO;
    if ([gesture isKindOfClass:UIPinchGestureRecognizer.class]) {
        return ![self editorContainsPoint:[gesture locationInView:self] inView:self];
    }
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (!self.editing) return NO;
    if (gesture.view == _dragAddChip) return YES;
    if (gesture.view == _panelHeader) return ![touch.view isKindOfClass:UIControl.class];
    return !_panel || ![touch.view isDescendantOfView:_panel];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)a shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)b {
    (void)a;
    (void)b;
    return NO;
}

- (void)up:(AKActionCircle *)circle {
    if (self.editing || !self.active || !self.layout.enabled || !circle.action.enabled) return;
    BOOL accepted = self.press && self.press(circle.action);
    if (accepted && self.released) self.released(circle.action);
    [self updateAppearance];
    if (!accepted) {
        // Reject an incompatible chord visibly, without typing a different shortcut.
        circle.layer.borderWidth = 2;
        circle.layer.borderColor = UIColor.systemOrangeColor.CGColor;
    }
}

- (void)releaseTouches {
    if (self.cancelledAll) self.cancelledAll();
    for (AKActionCircle *circle in _circles) [circle cancelPendingTouch];
    [self updateAppearance];
}

- (void)selectCircle:(UITapGestureRecognizer *)tap {
    if (!self.editing || tap.state != UIGestureRecognizerStateEnded) return;
    _selected = ((AKActionCircle *)tap.view).action;
    [self updateEditor];
}

- (void)quickEditCircle:(UITapGestureRecognizer *)tap {
    if (!self.editing || tap.state != UIGestureRecognizerStateEnded) return;
    _selected = ((AKActionCircle *)tap.view).action;
    _mode.selectedSegmentIndex = 0;
    [self updateEditor];
    [self editCustomLabel];
}

- (void)drag:(UIPanGestureRecognizer *)pan {
    if (!self.editing) return;
    AKTouchAction *action = ((AKActionCircle *)pan.view).action;
    if (pan.state == UIGestureRecognizerStateBegan) _selected = action;
    CGPoint delta = [pan translationInView:self];
    CGRect bounds = [self placementBounds];
    if (_mode.selectedSegmentIndex == 2) [self.layout moveGroupBy:delta inBounds:bounds];
    else if (_mode.selectedSegmentIndex == 1) [self.layout moveButtonGroupForAction:action by:delta inBounds:bounds];
    else [self.layout moveAction:action by:delta inBounds:bounds];
    if (_mode.selectedSegmentIndex == 0 && pan.state == UIGestureRecognizerStateEnded && self.layout.snapToGrid) {
        CGRect placed = [self.layout frameForAction:action inBounds:bounds];
        [self.layout setCenter:CGPointMake(CGRectGetMidX(placed), CGRectGetMidY(placed))
                     forAction:action inBounds:bounds snap:YES];
    }
    [pan setTranslation:CGPointZero inView:self];
    [self updateEditor];
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) [self.layout save];
}

- (void)panPanel:(UIPanGestureRecognizer *)pan {
    if (!self.editing || !_panel) return;
    if (pan.state == UIGestureRecognizerStateBegan) _panelDragStart = _panel.frame.origin;
    CGPoint delta = [pan translationInView:self];
    _panelOffset = CGPointMake(_panelDragStart.x + delta.x, _panelDragStart.y + delta.y);
    _panelCustomMoved = YES;
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

- (void)dragNewButton:(UIPanGestureRecognizer *)pan {
    if (!self.editing) return;
    CGRect bounds = [self placementBounds];
    CGPoint loc = [pan locationInView:self];
    if (pan.state == UIGestureRecognizerStateBegan) {
        _dragCreated = [self.layout addActionAtCenter:loc inBounds:bounds snap:self.layout.snapToGrid];
        if (!_dragCreated) return;
        _selected = _dragCreated;
        _mode.selectedSegmentIndex = 0;
        [self rebuildCircles];
        [self updateEditor];
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        if (!_dragCreated) return;
        [self.layout setCenter:loc forAction:_dragCreated inBounds:bounds snap:self.layout.snapToGrid];
        [self setNeedsLayout];
        [self layoutIfNeeded];
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        if (!_dragCreated) return;
        CGPoint drop = loc;
        if (_panel && CGRectContainsPoint(_panel.frame, drop)) {
            CGFloat below = CGRectGetMaxY(_panel.frame) + 28;
            CGFloat above = CGRectGetMinY(_panel.frame) - 28;
            drop = CGPointMake(loc.x, below <= CGRectGetMaxY(bounds) - 24 ? below : MAX(CGRectGetMinY(bounds) + 24, above));
        }
        [self.layout setCenter:drop forAction:_dragCreated inBounds:bounds snap:self.layout.snapToGrid];
        _dragCreated = nil;
        [self rebuildCircles];
        [self updateEditor];
        [self.layout save];
    }
}

- (void)pinch:(UIPinchGestureRecognizer *)pinch {
    if (!self.editing) return;
    BOOL group = _mode.selectedSegmentIndex == 2;
    if (pinch.state == UIGestureRecognizerStateBegan) _pinchInitial = group ? self.layout.scale : _selected.diameter;
    if (group) self.layout.scale = _pinchInitial * pinch.scale;
    else if (_mode.selectedSegmentIndex == 1) [self.layout resizeButtonGroupForAction:_selected diameter:_pinchInitial * pinch.scale inBounds:[self placementBounds]];
    else if (_selected) _selected.diameter = MAX(20, MIN(160, _pinchInitial * pinch.scale));
    [self updateEditor];
    if (pinch.state == UIGestureRecognizerStateEnded || pinch.state == UIGestureRecognizerStateCancelled) [self.layout save];
}

- (UILabel *)label:(NSString *)text {
    UILabel *label = [UILabel new];
    label.text = text;
    label.textColor = UIColor.whiteColor;
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    label.numberOfLines = 2;
    return label;
}

- (UIButton *)button:(NSString *)title action:(SEL)action identifier:(NSString *)identifier {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    button.accessibilityIdentifier = identifier;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (UIStackView *)row:(NSArray<UIView *> *)views {
    UIStackView *row = [[UIStackView alloc] initWithArrangedSubviews:views];
    row.axis = UILayoutConstraintAxisHorizontal;
    row.spacing = 8;
    row.alignment = UIStackViewAlignmentCenter;
    return row;
}

- (void)beginEditing {
    if (self.editing) return;
    [self releaseTouches];
    _editing = YES;
    _panelAtBottom = NO;
    _panelCustomMoved = NO;
    _dragCreated = nil;
    _selected = self.layout.actions.firstObject;
    _panel = [UIView new];
    _panel.backgroundColor = [UIColor colorWithRed:0.06 green:0.07 blue:0.09 alpha:0.96];
    _panel.layer.cornerRadius = 14;
    _panel.layer.borderWidth = 1;
    _panel.layer.borderColor = [UIColor colorWithRed:0.84 green:0.75 blue:0.55 alpha:0.45].CGColor;
    _panel.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    _panel.accessibilityIdentifier = @"wolkara.abilities.editor";
    [self addSubview:_panel];

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [_panel addSubview:scroll];

    UIStackView *stack = [UIStackView new];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 6;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    _enabled = [UISwitch new];
    _enabled.on = self.layout.enabled;
    _enabled.accessibilityLabel = @"Touch abilities";
    _enabled.accessibilityIdentifier = @"wolkara.abilities.enabled";
    [_enabled addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];

    _snapSwitch = [UISwitch new];
    _snapSwitch.on = self.layout.snapToGrid;
    _snapSwitch.accessibilityLabel = @"Snap to grid";
    _snapSwitch.accessibilityIdentifier = @"wolkara.abilities.snap";
    [_snapSwitch addTarget:self action:@selector(snapChanged:) forControlEvents:UIControlEventValueChanged];

    _dockButton = [self button:@"⇅ Bottom" action:@selector(toggleDock) identifier:@"wolkara.abilities.dock"];
    _dockButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];

    _profileButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _profileButton.showsMenuAsPrimaryAction = YES;
    _profileButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    _profileButton.accessibilityIdentifier = @"wolkara.abilities.profile";
    [self rebuildProfileMenu];

    UIButton *done = [self button:@"Done" action:@selector(finishEditing) identifier:@"wolkara.abilities.done"];
    UILabel *title = [self label:@"⠿"];
    title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    title.numberOfLines = 1;
    [title setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UILabel *snapLbl = [self label:@"Snap"];
    snapLbl.numberOfLines = 1;

    _panelHeader = [self row:@[title, _profileButton, _enabled, snapLbl, _snapSwitch, _dockButton]];
    _panelHeader.userInteractionEnabled = YES;
    UIPanGestureRecognizer *panelPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panPanel:)];
    panelPan.delegate = self;
    [_panelHeader addGestureRecognizer:panelPan];
    [stack addArrangedSubview:_panelHeader];

    _dragAddChip = [UIButton buttonWithType:UIButtonTypeSystem];
    [_dragAddChip setTitle:@"⊕ Drag Button" forState:UIControlStateNormal];
    _dragAddChip.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightBold];
    _dragAddChip.tintColor = [UIColor colorWithRed:0.98 green:0.86 blue:0.52 alpha:1];
    _dragAddChip.backgroundColor = [UIColor colorWithRed:0.15 green:0.13 blue:0.08 alpha:0.95];
    _dragAddChip.layer.cornerRadius = 11;
    _dragAddChip.layer.borderWidth = 1;
    _dragAddChip.layer.borderColor = [UIColor colorWithRed:0.84 green:0.75 blue:0.55 alpha:0.65].CGColor;
    _dragAddChip.contentEdgeInsets = UIEdgeInsetsMake(4, 10, 4, 10);
    _dragAddChip.accessibilityIdentifier = @"wolkara.abilities.dragAdd";
    [_dragAddChip addTarget:self action:@selector(tapDragAddChip) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *chipPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragNewButton:)];
    chipPan.delegate = self;
    [_dragAddChip addGestureRecognizer:chipPan];

    UIButton *addLeft = [self button:@"+ Left" action:@selector(addLeftCircle) identifier:@"wolkara.abilities.addLeft"];
    UIButton *addRight = [self button:@"+ Right" action:@selector(addRightCircle) identifier:@"wolkara.abilities.addRight"];
    addLeft.titleLabel.font = addRight.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    UIButton *clearAll = [self button:@"Clear" action:@selector(confirmClearAll) identifier:@"wolkara.abilities.clearAll"];
    clearAll.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    clearAll.tintColor = [UIColor colorWithRed:1.0 green:0.52 blue:0.48 alpha:1];

    _presetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_presetButton setTitle:@"Preset ▾" forState:UIControlStateNormal];
    _presetButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    _presetButton.showsMenuAsPrimaryAction = YES;
    _presetButton.accessibilityIdentifier = @"wolkara.abilities.preset";
    [self rebuildPresetMenu];

    [stack addArrangedSubview:[self row:@[_dragAddChip, addLeft, addRight, clearAll, _presetButton]]];

    _mode = [[UISegmentedControl alloc] initWithItems:@[@"Drag One", @"Side / Group", @"Move All"]];
    _mode.selectedSegmentIndex = 0;
    _mode.accessibilityIdentifier = @"wolkara.abilities.mode";
    [_mode addTarget:self action:@selector(modeChanged) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:_mode];

    _sizeLabel = [self label:@"Size"];
    [_sizeLabel.widthAnchor constraintEqualToConstant:92].active = YES;
    _size = [UISlider new];
    _size.accessibilityIdentifier = @"wolkara.abilities.size";
    [_size addTarget:self action:@selector(sizeChanged:) forControlEvents:UIControlEventValueChanged];
    [stack addArrangedSubview:[self row:@[_sizeLabel, _size]]];

    _fill = [UISlider new];
    _fill.minimumValue = 0;
    _fill.maximumValue = 0.9;
    _fill.value = self.layout.fillOpacity;
    _fill.accessibilityLabel = @"Circle fill opacity";
    [_fill addTarget:self action:@selector(fillChanged:) forControlEvents:UIControlEventValueChanged];

    _border = [UISlider new];
    _border.minimumValue = 0;
    _border.maximumValue = 0.9;
    _border.value = self.layout.borderOpacity;
    _border.accessibilityLabel = @"Circle border opacity";
    [_border addTarget:self action:@selector(borderChanged:) forControlEvents:UIControlEventValueChanged];

    _labelsSwitch = [UISwitch new];
    _labelsSwitch.on = self.layout.showLabels;
    _labelsSwitch.accessibilityLabel = @"Show circle labels";
    _labelsSwitch.accessibilityIdentifier = @"wolkara.abilities.showLabels";
    [_labelsSwitch addTarget:self action:@selector(labelsChanged:) forControlEvents:UIControlEventValueChanged];

    UILabel *fillLbl = [self label:@"Fill"];
    UILabel *borderLbl = [self label:@"Border"];
    UILabel *textLbl = [self label:@"Labels"];
    [stack addArrangedSubview:[self row:@[fillLbl, _fill, borderLbl, _border, textLbl, _labelsSwitch]]];

    _kindButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _kindButton.showsMenuAsPrimaryAction = YES;
    _kindButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    _kindButton.accessibilityIdentifier = @"wolkara.abilities.kind";

    _binding = [UIButton buttonWithType:UIButtonTypeSystem];
    _binding.showsMenuAsPrimaryAction = YES;
    _binding.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    _binding.accessibilityIdentifier = @"wolkara.abilities.binding";

    _modifier = [UIButton buttonWithType:UIButtonTypeSystem];
    _modifier.showsMenuAsPrimaryAction = YES;
    _modifier.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    _modifier.accessibilityIdentifier = @"wolkara.abilities.modifier";

    _labelButton = [self button:@"Label" action:@selector(editCustomLabel) identifier:@"wolkara.abilities.customLabel"];
    _labelButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];

    _shown = [UISwitch new];
    _shown.accessibilityLabel = @"Circle enabled";
    [_shown addTarget:self action:@selector(shownChanged:) forControlEvents:UIControlEventValueChanged];

    _behaviorButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _behaviorButton.showsMenuAsPrimaryAction = YES;
    _behaviorButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    _behaviorButton.accessibilityIdentifier = @"wolkara.abilities.behavior";

    _shapeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _shapeButton.showsMenuAsPrimaryAction = YES;
    _shapeButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    _shapeButton.accessibilityIdentifier = @"wolkara.abilities.shape";

    _colorButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _colorButton.showsMenuAsPrimaryAction = YES;
    _colorButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    _colorButton.accessibilityIdentifier = @"wolkara.abilities.color";

    _widthLabel = [self label:@"Width 1.0x"];
    _widthLabel.numberOfLines = 1;
    [_widthLabel.widthAnchor constraintEqualToConstant:72].active = YES;
    _widthSlider = [UISlider new];
    _widthSlider.minimumValue = 0.8;
    _widthSlider.maximumValue = 2.8;
    _widthSlider.value = 1.0;
    _widthSlider.accessibilityLabel = @"Button width aspect";
    _widthSlider.accessibilityIdentifier = @"wolkara.abilities.width";
    [_widthSlider addTarget:self action:@selector(widthChanged:) forControlEvents:UIControlEventValueChanged];

    UIButton *dupBtn = [self button:@"Copy" action:@selector(duplicateCircle) identifier:@"wolkara.abilities.duplicate"];
    dupBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    UIButton *delBtn = [self button:@"Delete" action:@selector(deleteCircle) identifier:@"wolkara.abilities.delete"];
    delBtn.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    delBtn.tintColor = [UIColor colorWithRed:1.0 green:0.52 blue:0.48 alpha:1];

    UILabel *shownLbl = [self label:@"Shown"];
    shownLbl.numberOfLines = 1;
    UIStackView *inspectTop = [self row:@[_kindButton, _binding, _modifier, _labelButton]];
    UIStackView *inspectMid = [self row:@[_behaviorButton, _shapeButton, _colorButton]];
    UIStackView *inspectBottom = [self row:@[_widthLabel, _widthSlider, shownLbl, _shown, dupBtn, delBtn]];
    UIStackView *inspectorStack = [[UIStackView alloc] initWithArrangedSubviews:@[inspectTop, inspectMid, inspectBottom]];
    inspectorStack.axis = UILayoutConstraintAxisVertical;
    inspectorStack.spacing = 4;
    _inspectorBox = inspectorStack;
    [stack addArrangedSubview:_inspectorBox];

    _selectionLabel = [self label:@""];
    _selectionLabel.textColor = [UIColor colorWithWhite:0.78 alpha:1];
    [stack addArrangedSubview:_selectionLabel];

    done.translatesAutoresizingMaskIntoConstraints = NO;
    [_panel addSubview:done];
    [NSLayoutConstraint activateConstraints:@[
        [done.trailingAnchor constraintEqualToAnchor:_panel.trailingAnchor constant:-10],
        [done.topAnchor constraintEqualToAnchor:_panel.topAnchor constant:4],
        [done.widthAnchor constraintEqualToConstant:58],
        [done.heightAnchor constraintEqualToConstant:36],
        [scroll.leadingAnchor constraintEqualToAnchor:_panel.leadingAnchor constant:12],
        [scroll.trailingAnchor constraintEqualToAnchor:done.leadingAnchor constant:-6],
        [scroll.topAnchor constraintEqualToAnchor:_panel.topAnchor constant:8],
        [scroll.bottomAnchor constraintEqualToAnchor:_panel.bottomAnchor constant:-8],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor]
    ]];
    [self updateEditor];
    if (self.configurationChanged) self.configurationChanged();
}

- (void)rebuildProfileMenu {
    [_profileButton setTitle:[NSString stringWithFormat:@"P%lu ▾", (unsigned long)self.layout.profileIndex]
                    forState:UIControlStateNormal];
    __weak AKTouchActionOverlay *weakSelf = self;
    NSMutableArray<UIAction *> *items = [NSMutableArray arrayWithCapacity:3];
    for (NSUInteger p = 1; p <= 3; p++) {
        UIAction *act = [UIAction actionWithTitle:[NSString stringWithFormat:@"Profile %lu", (unsigned long)p]
                                            image:nil identifier:nil handler:^(__kindof UIAction *a) {
            (void)a;
            AKTouchActionOverlay *self = weakSelf;
            if (!self) return;
            [self.layout switchToProfile:p];
            self->_selected = self.layout.actions.firstObject;
            self->_enabled.on = self.layout.enabled;
            self->_border.value = self.layout.borderOpacity;
            self->_fill.value = self.layout.fillOpacity;
            self->_labelsSwitch.on = self.layout.showLabels;
            self->_snapSwitch.on = self.layout.snapToGrid;
            [self rebuildCircles];
            [self rebuildProfileMenu];
            [self updateEditor];
        }];
        act.state = (self.layout.profileIndex == p) ? UIMenuElementStateOn : UIMenuElementStateOff;
        [items addObject:act];
    }
    _profileButton.menu = [UIMenu menuWithChildren:items];
}

- (void)rebuildPresetMenu {
    __weak AKTouchActionOverlay *weakSelf = self;
    UIAction *sides = [UIAction actionWithTitle:@"Side Bars (1-8 / 9-F4)" image:nil identifier:nil handler:^(__kindof UIAction *a) {
        (void)a;
        AKTouchActionOverlay *self = weakSelf;
        if (!self) return;
        BOOL enabled = self.layout.enabled;
        [self.layout resetToSideLayout];
        self.layout.enabled = enabled;
        self->_selected = self.layout.actions.firstObject;
        self->_border.value = self.layout.borderOpacity;
        self->_fill.value = self.layout.fillOpacity;
        self->_labelsSwitch.on = self.layout.showLabels;
        self->_snapSwitch.on = self.layout.snapToGrid;
        [self rebuildCircles];
        [self updateEditor];
        [self.layout save];
    }];
    UIAction *blank = [UIAction actionWithTitle:@"Clear All (Blank Canvas)" image:nil identifier:nil handler:^(__kindof UIAction *a) {
        (void)a;
        [weakSelf clearAllCircles];
    }];
    UIAction *classic = [UIAction actionWithTitle:@"Classic Bottom 32 (Gamepad)" image:nil identifier:nil handler:^(__kindof UIAction *a) {
        (void)a;
        AKTouchActionOverlay *self = weakSelf;
        if (!self) return;
        BOOL enabled = self.layout.enabled;
        [self.layout resetToClassicLayout];
        self.layout.enabled = enabled;
        self->_selected = self.layout.actions.firstObject;
        self->_border.value = self.layout.borderOpacity;
        self->_fill.value = self.layout.fillOpacity;
        self->_labelsSwitch.on = self.layout.showLabels;
        self->_snapSwitch.on = self.layout.snapToGrid;
        [self rebuildCircles];
        [self updateEditor];
        [self.layout save];
    }];
    UIAction *reset = [UIAction actionWithTitle:@"Reset Current" image:nil identifier:nil handler:^(__kindof UIAction *a) {
        (void)a;
        [weakSelf resetLayout];
    }];
    _presetButton.menu = [UIMenu menuWithChildren:@[sides, blank, classic, reset]];
}

- (UIMenu *)keyboardKeyMenu {
    __weak AKTouchActionOverlay *weakSelf = self;
    NSArray<NSString *> *bars = @[@"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"0", @"-", @"="];
    NSArray<NSString *> *fkeys = @[@"F1", @"F2", @"F3", @"F4", @"F5", @"F6", @"F7", @"F8", @"F9", @"F10", @"F11", @"F12"];
    NSArray<NSString *> *special = @[@"Space", @"Tab", @"Esc", @"Return", @"Bksp", @"Del", @"`", @"[", @"]", @"\\", @";", @"'", @",", @".", @"/"];
    NSArray<NSString *> *nav = @[@"Up", @"Down", @"Left", @"Right", @"Home", @"End", @"PgUp", @"PgDn"];
    NSArray<NSString *> *stickyMods = @[@"LShift", @"LCtrl", @"LOpt", @"LCmd"];
    NSArray<NSString *> *letters = @[@"Q", @"E", @"R", @"T", @"F", @"G", @"V", @"C", @"X", @"Z", @"B", @"H", @"J", @"K", @"L", @"N", @"M", @"A", @"S", @"D", @"W", @"I", @"O", @"P", @"U", @"Y"];

    UIMenu *(^submenu)(NSString *, NSArray<NSString *> *) = ^UIMenu *(NSString *title, NSArray<NSString *> *keys) {
        NSMutableArray<UIAction *> *items = [NSMutableArray arrayWithCapacity:keys.count];
        for (NSString *key in keys) {
            UIAction *act = [UIAction actionWithTitle:key image:nil identifier:nil handler:^(__kindof UIAction *a) {
                (void)a;
                AKTouchActionOverlay *self = weakSelf;
                if (!self || !self->_selected) return;
                self->_selected.kind = AKTouchActionKindKeyboard;
                self->_selected.keyName = key;
                [self.layout save];
                [self updateEditor];
            }];
            act.state = (_selected.kind == AKTouchActionKindKeyboard && [_selected.keyName isEqual:key])
                ? UIMenuElementStateOn : UIMenuElementStateOff;
            [items addObject:act];
        }
        return [UIMenu menuWithTitle:title children:items];
    };

    return [UIMenu menuWithChildren:@[
        submenu(@"Numbers (1-=)", bars),
        submenu(@"Function (F1-F12)", fkeys),
        submenu(@"Action / Special", special),
        submenu(@"Arrows & Nav", nav),
        submenu(@"Modifiers (Use Toggle/Hold)", stickyMods),
        submenu(@"Letters", letters),
    ]];
}

- (UIMenu *)keyboardModifierMenu {
    __weak AKTouchActionOverlay *weakSelf = self;
    NSArray<NSDictionary *> *choices = @[
        @{@"title": @"None", @"mod": @(0)},
        @{@"title": @"Shift (S-)", @"mod": @(AKTouchKeyModifierShift)},
        @{@"title": @"Ctrl (C-)", @"mod": @(AKTouchKeyModifierControl)},
        @{@"title": @"Alt (A-)", @"mod": @(AKTouchKeyModifierOption)},
        @{@"title": @"Cmd (M-)", @"mod": @(AKTouchKeyModifierCommand)},
        @{@"title": @"Ctrl+Shift (CS-)", @"mod": @(AKTouchKeyModifierControl | AKTouchKeyModifierShift)},
        @{@"title": @"Ctrl+Alt (CA-)", @"mod": @(AKTouchKeyModifierControl | AKTouchKeyModifierOption)},
        @{@"title": @"Shift+Alt (SA-)", @"mod": @(AKTouchKeyModifierShift | AKTouchKeyModifierOption)},
    ];
    NSMutableArray<UIAction *> *actions = [NSMutableArray arrayWithCapacity:choices.count];
    for (NSDictionary *entry in choices) {
        AKTouchKeyModifier mod = [entry[@"mod"] unsignedIntegerValue];
        UIAction *act = [UIAction actionWithTitle:entry[@"title"] image:nil identifier:nil handler:^(__kindof UIAction *a) {
            (void)a;
            AKTouchActionOverlay *self = weakSelf;
            if (!self || !self->_selected) return;
            self->_selected.keyModifiers = mod;
            [self.layout save];
            [self updateEditor];
        }];
        act.state = (_selected.keyModifiers == mod) ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:act];
    }
    return [UIMenu menuWithChildren:actions];
}

- (UIMenu *)mouseButtonMenu {
    __weak AKTouchActionOverlay *weakSelf = self;
    NSArray<NSDictionary *> *choices = @[
        @{@"title": @"Left Click (LMB)", @"btn": @0},
        @{@"title": @"Right Click (RMB)", @"btn": @1},
        @{@"title": @"Middle Click (MMB)", @"btn": @2},
    ];
    NSMutableArray<UIAction *> *actions = [NSMutableArray arrayWithCapacity:choices.count];
    for (NSDictionary *entry in choices) {
        unsigned btn = [entry[@"btn"] unsignedIntValue];
        UIAction *act = [UIAction actionWithTitle:entry[@"title"] image:nil identifier:nil handler:^(__kindof UIAction *a) {
            (void)a;
            AKTouchActionOverlay *self = weakSelf;
            if (!self || !self->_selected) return;
            self->_selected.kind = AKTouchActionKindMouse;
            self->_selected.mouseButton = btn;
            [self.layout save];
            [self updateEditor];
        }];
        act.state = (_selected.kind == AKTouchActionKindMouse && _selected.mouseButton == btn)
            ? UIMenuElementStateOn : UIMenuElementStateOff;
        [actions addObject:act];
    }
    return [UIMenu menuWithChildren:actions];
}

- (void)updateEditor {
    if (!self.editing) return;
    BOOL group = _mode.selectedSegmentIndex == 2;
    BOOL quad = _mode.selectedSegmentIndex == 1;
    _size.minimumValue = group ? 0.4 : 20;
    _size.maximumValue = group ? 4 : 160;
    _size.value = group ? self.layout.scale : (_selected ? _selected.diameter : 40);
    _size.enabled = group || _selected != nil;
    _sizeLabel.text = group
        ? [NSString stringWithFormat:@"Layout %.0f%%", self.layout.scale * 100]
        : [NSString stringWithFormat:quad ? @"Group %.0f" : @"Button %.0f", _selected ? _selected.diameter : 40];
    _size.accessibilityLabel = group ? @"Whole layout scale" : quad ? @"Button group size" : @"Circle diameter";
    _size.accessibilityValue = _sizeLabel.text;
    _inspectorBox.hidden = group || quad || !_selected;
    _selectionLabel.text = group
        ? @"Drag anywhere to move all buttons; pinch or use Size to scale together."
        : quad
        ? @"Drag a button to move its entire group together. Pinch or Size to resize."
        : _selected
        ? @"Drag ⊕ onto screen to add, drag any circle to place, or customize Key/Mouse/Label above."
        : @"Drag ⊕ Drag Button onto the screen (or tap + Left / + Right) to drop a custom button.";

    AKTouchActionKind kind = _selected.kind;
    [_kindButton setTitle:kind == AKTouchActionKindMouse ? @"Mouse ▾" : kind == AKTouchActionKindGamepad ? @"Pad ▾" : @"Key ▾"
                 forState:UIControlStateNormal];

    __weak AKTouchActionOverlay *weakSelf = self;
    _kindButton.menu = [UIMenu menuWithChildren:@[
        [UIAction actionWithTitle:@"Keyboard Key" image:nil identifier:nil handler:^(__kindof UIAction *a) {
            (void)a;
            AKTouchActionOverlay *self = weakSelf;
            if (!self || !self->_selected) return;
            self->_selected.kind = AKTouchActionKindKeyboard;
            [self.layout save];
            [self updateEditor];
        }],
        [UIAction actionWithTitle:@"Mouse Click" image:nil identifier:nil handler:^(__kindof UIAction *a) {
            (void)a;
            AKTouchActionOverlay *self = weakSelf;
            if (!self || !self->_selected) return;
            self->_selected.kind = AKTouchActionKindMouse;
            [self.layout save];
            [self updateEditor];
        }],
        [UIAction actionWithTitle:@"Gamepad Chord" image:nil identifier:nil handler:^(__kindof UIAction *a) {
            (void)a;
            AKTouchActionOverlay *self = weakSelf;
            if (!self || !self->_selected) return;
            self->_selected.kind = AKTouchActionKindGamepad;
            [self.layout save];
            [self updateEditor];
        }],
    ]];

    if (kind == AKTouchActionKindKeyboard) {
        _modifier.hidden = NO;
        [_binding setTitle:[@"Key: " stringByAppendingString:_selected.keyName ?: @"1"] forState:UIControlStateNormal];
        NSString *modTitle = @"Mod: None";
        if (_selected.keyModifiers) {
            NSMutableString *m = [NSMutableString stringWithString:@"Mod: "];
            if (_selected.keyModifiers & AKTouchKeyModifierControl) [m appendString:@"C"];
            if (_selected.keyModifiers & AKTouchKeyModifierShift) [m appendString:@"S"];
            if (_selected.keyModifiers & AKTouchKeyModifierOption) [m appendString:@"A"];
            if (_selected.keyModifiers & AKTouchKeyModifierCommand) [m appendString:@"M"];
            modTitle = m;
        }
        [_modifier setTitle:modTitle forState:UIControlStateNormal];
        _binding.menu = [self keyboardKeyMenu];
        _modifier.menu = [self keyboardModifierMenu];
    } else if (kind == AKTouchActionKindMouse) {
        _modifier.hidden = YES;
        NSString *btnName = _selected.mouseButton == 1 ? @"RMB" : _selected.mouseButton == 2 ? @"MMB" : @"LMB";
        [_binding setTitle:[@"Click: " stringByAppendingString:btnName] forState:UIControlStateNormal];
        _binding.menu = [self mouseButtonMenu];
    } else {
        _modifier.hidden = NO;
        [_binding setTitle:[@"Btn: " stringByAppendingString:_selected.button ?: @"—"] forState:UIControlStateNormal];
        NSArray *modifiers = @[@"None", @"LT", @"RT", @"LT + RT"];
        [_modifier setTitle:modifiers[MIN(_selected.modifiers, 3)] forState:UIControlStateNormal];
        NSMutableArray *buttons = [NSMutableArray new], *mods = [NSMutableArray new];
        for (NSString *key in @[@"A", @"B", @"X", @"Y", @"LB", @"RB", @"up", @"right", @"down", @"left"]) {
            UIAction *action = [UIAction actionWithTitle:key image:nil identifier:nil handler:^(__kindof UIAction *a) {
                (void)a;
                AKTouchActionOverlay *self = weakSelf;
                if (!self) return;
                self->_selected.button = key;
                [self.layout save];
                [self updateEditor];
            }];
            action.state = [_selected.button isEqual:key] ? UIMenuElementStateOn : UIMenuElementStateOff;
            [buttons addObject:action];
        }
        for (NSUInteger i = 0; i < 4; i++) {
            UIAction *action = [UIAction actionWithTitle:modifiers[i] image:nil identifier:nil handler:^(__kindof UIAction *a) {
                (void)a;
                AKTouchActionOverlay *self = weakSelf;
                if (!self) return;
                self->_selected.modifiers = i;
                [self.layout save];
                [self updateEditor];
            }];
            action.state = _selected.modifiers == i ? UIMenuElementStateOn : UIMenuElementStateOff;
            [mods addObject:action];
        }
        _binding.menu = [UIMenu menuWithChildren:buttons];
        _modifier.menu = [UIMenu menuWithChildren:mods];
    }

    [_labelButton setTitle:_selected.customLabel.length ? [NSString stringWithFormat:@"\"%@\"", _selected.customLabel] : @"Label"
                  forState:UIControlStateNormal];
    _shown.on = _selected.enabled;

    NSArray<NSString *> *behaviorNames = @[@"Tap", @"Hold", @"Toggle"];
    NSUInteger bIdx = _selected.behavior < behaviorNames.count ? _selected.behavior : 0;
    [_behaviorButton setTitle:[NSString stringWithFormat:@"%@ ▾", behaviorNames[bIdx]]
                     forState:UIControlStateNormal];
    NSMutableArray<UIAction *> *behaviors = [NSMutableArray arrayWithCapacity:3];
    NSArray<NSString *> *behaviorTitles = @[@"Tap (Drag-safe)", @"Hold While Pressed", @"Toggle On / Off"];
    for (NSUInteger i = 0; i < 3; i++) {
        UIAction *act = [UIAction actionWithTitle:behaviorTitles[i] image:nil identifier:nil handler:^(__kindof UIAction *a) {
            (void)a;
            AKTouchActionOverlay *self = weakSelf;
            if (!self || !self->_selected) return;
            self->_selected.behavior = (AKTouchActionBehavior)i;
            [self.layout save];
            [self updateEditor];
        }];
        act.state = _selected.behavior == i ? UIMenuElementStateOn : UIMenuElementStateOff;
        [behaviors addObject:act];
    }
    _behaviorButton.menu = [UIMenu menuWithChildren:behaviors];

    NSArray<NSString *> *shapeNames = @[@"Circle", @"Pill", @"Box"];
    NSUInteger sIdx = _selected.shape < shapeNames.count ? _selected.shape : 0;
    [_shapeButton setTitle:[NSString stringWithFormat:@"%@ ▾", shapeNames[sIdx]]
                  forState:UIControlStateNormal];
    NSMutableArray<UIAction *> *shapes = [NSMutableArray arrayWithCapacity:3];
    for (NSUInteger i = 0; i < 3; i++) {
        UIAction *act = [UIAction actionWithTitle:shapeNames[i] image:nil identifier:nil handler:^(__kindof UIAction *a) {
            (void)a;
            AKTouchActionOverlay *self = weakSelf;
            if (!self || !self->_selected) return;
            self->_selected.shape = (AKTouchActionShape)i;
            if (i == AKTouchActionShapePill && self->_selected.widthScale < 1.3) self->_selected.widthScale = 1.6;
            else if (i == AKTouchActionShapeCircle) self->_selected.widthScale = 1.0;
            [self.layout save];
            [self updateEditor];
        }];
        act.state = _selected.shape == i ? UIMenuElementStateOn : UIMenuElementStateOff;
        [shapes addObject:act];
    }
    _shapeButton.menu = [UIMenu menuWithChildren:shapes];

    NSArray<NSString *> *colorNames = @[@"Charcoal", @"Gold", @"Red", @"Blue", @"Green", @"Purple", @"Invisible"];
    NSUInteger cIdx = _selected.colorPreset < colorNames.count ? _selected.colorPreset : 0;
    [_colorButton setTitle:[NSString stringWithFormat:@"%@ ▾", colorNames[cIdx]]
                  forState:UIControlStateNormal];
    NSMutableArray<UIAction *> *colors = [NSMutableArray arrayWithCapacity:colorNames.count];
    for (NSUInteger i = 0; i < colorNames.count; i++) {
        UIAction *act = [UIAction actionWithTitle:colorNames[i] image:nil identifier:nil handler:^(__kindof UIAction *a) {
            (void)a;
            AKTouchActionOverlay *self = weakSelf;
            if (!self || !self->_selected) return;
            self->_selected.colorPreset = (AKTouchActionColor)i;
            [self.layout save];
            [self updateEditor];
        }];
        act.state = _selected.colorPreset == i ? UIMenuElementStateOn : UIMenuElementStateOff;
        [colors addObject:act];
    }
    _colorButton.menu = [UIMenu menuWithChildren:colors];

    CGFloat w = _selected ? _selected.widthScale : 1.0;
    _widthSlider.value = w;
    _widthSlider.enabled = _selected != nil;
    _widthLabel.text = [NSString stringWithFormat:@"Width %.1fx", w];

    [self updateAppearance];
}

- (void)editCustomLabel {
    if (!_selected || !self.window.rootViewController) return;
    UIViewController *presenter = self.window.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    AKTouchAction *target = _selected;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Button Label"
        message:@"Enter a short custom label, or leave blank to use the keybind label."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field) {
        field.placeholder = target.label;
        field.text = target.customLabel ?: @"";
        field.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak AKTouchActionOverlay *weakSelf = self;
    __weak UIAlertController *weakAlert = alert;
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        (void)action;
        AKTouchActionOverlay *self = weakSelf;
        UIAlertController *strongAlert = weakAlert;
        if (!self || !strongAlert) return;
        NSString *text = [strongAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        target.customLabel = text.length > 24 ? [text substringToIndex:24] : (text.length ? text : nil);
        [self.layout save];
        [self updateEditor];
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)modeChanged { [self releaseTouches]; [self updateEditor]; }
- (void)enabledChanged:(UISwitch *)sender {
    [self releaseTouches];
    self.layout.enabled = sender.on;
    [NSUserDefaults.standardUserDefaults setBool:sender.on forKey:@"WolkaraTouchAbilitiesExplicit"];
    [self updateAppearance];
}
- (void)labelsChanged:(UISwitch *)sender { self.layout.showLabels = sender.on; [self updateAppearance]; }
- (void)snapChanged:(UISwitch *)sender { self.layout.snapToGrid = sender.on; [self.layout save]; }
- (void)shownChanged:(UISwitch *)sender { _selected.enabled = sender.on; [self updateEditor]; }
- (void)widthChanged:(UISlider *)sender {
    _selected.widthScale = sender.value;
    if (_selected.widthScale > 1.15 && _selected.shape == AKTouchActionShapeCircle) {
        _selected.shape = AKTouchActionShapePill;
    }
    [self updateEditor];
}
- (void)borderChanged:(UISlider *)sender { self.layout.borderOpacity = sender.value; [self updateAppearance]; }
- (void)fillChanged:(UISlider *)sender { self.layout.fillOpacity = sender.value; [self updateAppearance]; }

- (void)toggleDock {
    _panelAtBottom = !_panelAtBottom;
    _panelCustomMoved = NO;
    [_dockButton setTitle:_panelAtBottom ? @"⇅ Top" : @"⇅ Bottom" forState:UIControlStateNormal];
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

- (void)sizeChanged:(UISlider *)sender {
    if (_mode.selectedSegmentIndex == 2) self.layout.scale = sender.value;
    else if (_mode.selectedSegmentIndex == 1) [self.layout resizeButtonGroupForAction:_selected diameter:sender.value inBounds:[self placementBounds]];
    else _selected.diameter = sender.value;
    [self updateEditor];
}

- (void)tapDragAddChip {
    CGRect bounds = [self placementBounds];
    CGPoint pt = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    AKTouchAction *added = [self.layout addActionAtCenter:pt inBounds:bounds snap:self.layout.snapToGrid];
    if (!added) return;
    _selected = added;
    _mode.selectedSegmentIndex = 0;
    [self rebuildCircles];
    [self updateEditor];
    [self.layout save];
}

- (void)addLeftCircle { [self addCircleOnAnchor:AKTouchActionAnchorLeft]; }
- (void)addRightCircle { [self addCircleOnAnchor:AKTouchActionAnchorRight]; }
- (void)addCircle { [self addCircleOnAnchor:AKTouchActionAnchorLeft]; }

- (void)addCircleOnAnchor:(AKTouchActionAnchor)anchor {
    AKTouchAction *added = [self.layout addActionOnAnchor:anchor];
    if (!added) return;
    _selected = added;
    _mode.selectedSegmentIndex = 0;
    [self rebuildCircles];
    [self updateEditor];
    [self.layout save];
}

- (void)duplicateCircle {
    AKTouchAction *copy = [self.layout duplicateAction:_selected inBounds:[self placementBounds]];
    if (!copy) return;
    _selected = copy;
    _mode.selectedSegmentIndex = 0;
    [self rebuildCircles];
    [self updateEditor];
    [self.layout save];
}

- (void)confirmClearAll {
    if (!self.window.rootViewController) { [self clearAllCircles]; return; }
    UIViewController *presenter = self.window.rootViewController;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Clear All Buttons?"
        message:@"Remove every custom button so you can drag and drop your own from scratch."
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    __weak AKTouchActionOverlay *weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Clear All" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a) {
        (void)a;
        [weakSelf clearAllCircles];
    }]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

- (void)clearAllCircles {
    [self.layout clearActions];
    _selected = nil;
    _mode.selectedSegmentIndex = 0;
    [self rebuildCircles];
    [self updateEditor];
    [self.layout save];
}

- (void)deleteCircle {
    [self.layout removeAction:_selected];
    _selected = self.layout.actions.firstObject;
    [self rebuildCircles];
    [self updateEditor];
    [self.layout save];
}

- (void)resetLayout {
    BOOL enabled = self.layout.enabled;
    [self.layout reset];
    self.layout.enabled = enabled;
    _selected = self.layout.actions.firstObject;
    _border.value = self.layout.borderOpacity;
    _fill.value = self.layout.fillOpacity;
    _labelsSwitch.on = self.layout.showLabels;
    _snapSwitch.on = self.layout.snapToGrid;
    [self rebuildCircles];
    [self updateEditor];
    [self.layout save];
}

- (void)finishEditing {
    if (!self.editing) return;
    [self releaseTouches];
    [self.layout save];
    _editing = NO;
    _selected = nil;
    _dragCreated = nil;
    [_panel removeFromSuperview];
    _panel = _panelHeader = _inspectorBox = nil;
    _mode = nil;
    _size = _widthSlider = _border = _fill = nil;
    _enabled = _shown = _labelsSwitch = _snapSwitch = nil;
    _sizeLabel = _widthLabel = _selectionLabel = nil;
    _kindButton = _binding = _modifier = _labelButton = _presetButton = _profileButton = nil;
    _behaviorButton = _shapeButton = _colorButton = _dragAddChip = _dockButton = nil;
    [self updateAppearance];
    if (self.configurationChanged) self.configurationChanged();
}

@end
