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
@property(nonatomic, weak) AKTouchActionOverlay *owner;
- (void)cancelPendingTouch;
@end

@implementation AKActionCircle {
    __weak UITouch *_finger;
    CGPoint _origin;
    BOOL _dragged, _forwarded;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat radius = MIN(self.bounds.size.width, self.bounds.size.height) / 2;
    self.layer.cornerRadius = radius;
    self.clipsToBounds = YES;
    CGFloat fontSize = MAX(9, MIN(14, self.bounds.size.width * 0.28));
    if (fabs(self.titleLabel.font.pointSize - fontSize) > 0.5) {
        self.titleLabel.font = [UIFont systemFontOfSize:fontSize weight:UIFontWeightBold];
    }
}

- (BOOL)pointInside:(CGPoint)p withEvent:(UIEvent *)event {
    (void)event;
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
    self.inputHeld = YES;
    [self.owner updateAppearance];
    return YES;
}

- (BOOL)continueTrackingWithTouch:(UITouch *)touch withEvent:(UIEvent *)event {
    (void)event;
    if (touch != _finger) return NO;
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
    CGPoint point = [touch locationInView:self.owner];
    BOOL tap = !_dragged && hypot(point.x - _origin.x, point.y - _origin.y) < AKTouchDragThreshold &&
               [self pointInside:[touch locationInView:self] withEvent:event];
    if (_forwarded && self.owner.endDrag) self.owner.endDrag(touch, NO);
    _finger = nil;
    _forwarded = NO;
    self.inputHeld = NO;
    [self.owner updateAppearance];
    if (tap) [self.owner up:self]; // Leave rejection feedback visible after lift.
}

- (void)cancelPendingTouch {
    if (_forwarded && _finger && self.owner.endDrag) self.owner.endDrag(_finger, YES);
    _finger = nil;
    _forwarded = NO;
    self.inputHeld = NO;
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
    AKTouchAction *_selected;
    UIView *_panel;
    UISegmentedControl *_mode;
    UISlider *_size, *_border, *_fill;
    UISwitch *_enabled, *_shown, *_labelsSwitch;
    UILabel *_sizeLabel, *_selectionLabel;
    UIButton *_kindButton, *_binding, *_modifier, *_labelButton, *_presetButton;
    UIStackView *_bindingRow;
    CGFloat _pinchInitial;
    CGSize _lastViewportSize;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.multipleTouchEnabled = YES;
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

- (void)updateAppearance {
    self.hidden = !self.editing && (!self.active || !self.layout.enabled);
    UIColor *warmBorder = [UIColor colorWithRed:0.84 green:0.75 blue:0.55 alpha:self.layout.borderOpacity];
    UIColor *warmFill = [UIColor colorWithRed:0.06 green:0.06 blue:0.06 alpha:self.layout.fillOpacity];
    UIColor *heldFill = [UIColor colorWithRed:0.84 green:0.68 blue:0.32 alpha:0.38];
    for (AKActionCircle *circle in _circles) {
        BOOL selected = circle.action == _selected ||
            (_mode.selectedSegmentIndex == 1 && [circle.action.groupIdentifier isEqual:_selected.groupIdentifier]);
        circle.hidden = !self.editing && !circle.action.enabled;
        circle.layer.borderWidth = self.editing ? 2 : (self.layout.borderOpacity > 0 ? 1 : 0);
        circle.layer.borderColor = (self.editing
            ? (selected ? UIColor.systemYellowColor : [UIColor colorWithRed:0.84 green:0.75 blue:0.55 alpha:0.85])
            : warmBorder).CGColor;
        circle.backgroundColor = circle.inputHeld
            ? heldFill
            : (self.editing ? [UIColor colorWithRed:0.06 green:0.06 blue:0.06 alpha:MAX(0.45, self.layout.fillOpacity)] : warmFill);
        circle.alpha = self.editing && !circle.action.enabled ? 0.35 : 1;
        BOOL showText = self.editing || self.layout.showLabels;
        [circle setTitle:showText ? circle.action.label : @"" forState:UIControlStateNormal];
        circle.accessibilityLabel = circle.action.label;
        circle.accessibilityValue = circle.action.enabled ? @"Enabled" : @"Hidden";
    }
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (!CGSizeEqualToSize(_lastViewportSize, self.bounds.size)) {
        _lastViewportSize = self.bounds.size;
        [self releaseTouches];
    }
    CGRect bounds = [self placementBounds];
    for (AKActionCircle *circle in _circles) {
        circle.frame = [self.layout frameForAction:circle.action inBounds:bounds];
        circle.layer.cornerRadius = MIN(circle.bounds.size.width, circle.bounds.size.height) / 2;
    }
    if (_panel) {
        CGRect safe = UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets);
        CGFloat width = MIN(500, safe.size.width - 16);
        CGFloat height = MIN(224, safe.size.height - 20);
        _panel.frame = CGRectMake(CGRectGetMidX(safe) - width / 2, CGRectGetMinY(safe) + 8, width, height);
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
    (void)gesture;
    return self.editing && (!_panel || ![touch.view isDescendantOfView:_panel]);
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

- (void)drag:(UIPanGestureRecognizer *)pan {
    if (!self.editing) return;
    AKTouchAction *action = ((AKActionCircle *)pan.view).action;
    if (pan.state == UIGestureRecognizerStateBegan) _selected = action;
    CGPoint delta = [pan translationInView:self];
    CGRect bounds = [self placementBounds];
    if (_mode.selectedSegmentIndex == 0) [self.layout moveGroupBy:delta inBounds:bounds];
    else if (_mode.selectedSegmentIndex == 1) [self.layout moveButtonGroupForAction:action by:delta inBounds:bounds];
    else [self.layout moveAction:action by:delta inBounds:bounds];
    [pan setTranslation:CGPointZero inView:self];
    [self updateEditor];
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) [self.layout save];
}

- (void)pinch:(UIPinchGestureRecognizer *)pinch {
    if (!self.editing) return;
    BOOL group = _mode.selectedSegmentIndex == 0;
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
    stack.spacing = 7;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [scroll addSubview:stack];

    _enabled = [UISwitch new];
    _enabled.on = self.layout.enabled;
    _enabled.accessibilityLabel = @"Touch abilities";
    _enabled.accessibilityIdentifier = @"wolkara.abilities.enabled";
    [_enabled addTarget:self action:@selector(enabledChanged:) forControlEvents:UIControlEventValueChanged];

    UIButton *done = [self button:@"Done" action:@selector(finishEditing) identifier:@"wolkara.abilities.done"];
    UILabel *title = [self label:@"Abilities"];
    title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightBold];
    title.numberOfLines = 1;
    [title setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIButton *addLeft = [self button:@"+ Left" action:@selector(addLeftCircle) identifier:@"wolkara.abilities.addLeft"];
    UIButton *addRight = [self button:@"+ Right" action:@selector(addRightCircle) identifier:@"wolkara.abilities.addRight"];
    _presetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_presetButton setTitle:@"Preset ▾" forState:UIControlStateNormal];
    _presetButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    _presetButton.showsMenuAsPrimaryAction = YES;
    _presetButton.accessibilityIdentifier = @"wolkara.abilities.preset";
    [self rebuildPresetMenu];

    [stack addArrangedSubview:[self row:@[title, _enabled, addLeft, addRight, _presetButton]]];

    _mode = [[UISegmentedControl alloc] initWithItems:@[@"Whole layout", @"Side / Group", @"One circle"]];
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
    _kindButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _kindButton.accessibilityIdentifier = @"wolkara.abilities.kind";

    _binding = [UIButton buttonWithType:UIButtonTypeSystem];
    _binding.showsMenuAsPrimaryAction = YES;
    _binding.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _binding.accessibilityIdentifier = @"wolkara.abilities.binding";

    _modifier = [UIButton buttonWithType:UIButtonTypeSystem];
    _modifier.showsMenuAsPrimaryAction = YES;
    _modifier.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _modifier.accessibilityIdentifier = @"wolkara.abilities.modifier";

    _labelButton = [self button:@"Label" action:@selector(editCustomLabel) identifier:@"wolkara.abilities.customLabel"];

    _shown = [UISwitch new];
    _shown.accessibilityLabel = @"Circle enabled";
    [_shown addTarget:self action:@selector(shownChanged:) forControlEvents:UIControlEventValueChanged];

    _bindingRow = [self row:@[_kindButton, _binding, _modifier, _labelButton, _shown,
                              [self button:@"Delete" action:@selector(deleteCircle) identifier:@"wolkara.abilities.delete"]]];
    [stack addArrangedSubview:_bindingRow];

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

- (void)rebuildPresetMenu {
    __weak AKTouchActionOverlay *weakSelf = self;
    UIAction *sides = [UIAction actionWithTitle:@"Side Bars (Photo)" image:nil identifier:nil handler:^(__kindof UIAction *a) {
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
        [self rebuildCircles];
        [self updateEditor];
        [self.layout save];
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
        [self rebuildCircles];
        [self updateEditor];
        [self.layout save];
    }];
    UIAction *reset = [UIAction actionWithTitle:@"Reset Current" image:nil identifier:nil handler:^(__kindof UIAction *a) {
        (void)a;
        [weakSelf resetLayout];
    }];
    _presetButton.menu = [UIMenu menuWithChildren:@[sides, classic, reset]];
}

- (UIMenu *)keyboardKeyMenu {
    __weak AKTouchActionOverlay *weakSelf = self;
    NSArray<NSString *> *bars = @[@"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"0", @"-", @"="];
    NSArray<NSString *> *fkeys = @[@"F1", @"F2", @"F3", @"F4", @"F5", @"F6", @"F7", @"F8", @"F9", @"F10", @"F11", @"F12"];
    NSArray<NSString *> *special = @[@"Space", @"Tab", @"Esc", @"Return", @"`", @"[", @"]", @"\\", @";", @"'", @",", @".", @"/"];
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

- (void)updateEditor {
    if (!self.editing) return;
    BOOL group = _mode.selectedSegmentIndex == 0;
    BOOL quad = _mode.selectedSegmentIndex == 1;
    _size.minimumValue = group ? 0.4 : 20;
    _size.maximumValue = group ? 4 : 160;
    _size.value = group ? self.layout.scale : (_selected ? _selected.diameter : 40);
    _size.enabled = group || _selected != nil;
    _sizeLabel.text = group
        ? [NSString stringWithFormat:@"Layout %.0f%%", self.layout.scale * 100]
        : [NSString stringWithFormat:quad ? @"Group %.0f" : @"Circle %.0f", _selected ? _selected.diameter : 40];
    _size.accessibilityLabel = group ? @"Whole layout scale" : quad ? @"Button group size" : @"Circle diameter";
    _size.accessibilityValue = _sizeLabel.text;
    _bindingRow.hidden = group || quad || !_selected;
    _selectionLabel.text = group
        ? @"Tap + Left or + Right to add side abilities. Drag to move all; pinch or Size to scale."
        : quad
        ? @"Drag a circle to move its entire side/group. Pinch or Size to resize together."
        : @"Tap a circle to select it, customize Key/Pad/Label, drag to place, or Delete.";

    BOOL isKey = _selected.kind == AKTouchActionKindKeyboard;
    [_kindButton setTitle:isKey ? @"Key ▾" : @"Pad ▾" forState:UIControlStateNormal];

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
        [UIAction actionWithTitle:@"Gamepad Chord" image:nil identifier:nil handler:^(__kindof UIAction *a) {
            (void)a;
            AKTouchActionOverlay *self = weakSelf;
            if (!self || !self->_selected) return;
            self->_selected.kind = AKTouchActionKindGamepad;
            [self.layout save];
            [self updateEditor];
        }],
    ]];

    if (isKey) {
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
    } else {
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
- (void)enabledChanged:(UISwitch *)sender { [self releaseTouches]; self.layout.enabled = sender.on; [self updateAppearance]; }
- (void)labelsChanged:(UISwitch *)sender { self.layout.showLabels = sender.on; [self updateAppearance]; }
- (void)shownChanged:(UISwitch *)sender { _selected.enabled = sender.on; [self updateEditor]; }
- (void)borderChanged:(UISlider *)sender { self.layout.borderOpacity = sender.value; [self updateAppearance]; }
- (void)fillChanged:(UISlider *)sender { self.layout.fillOpacity = sender.value; [self updateAppearance]; }

- (void)sizeChanged:(UISlider *)sender {
    if (_mode.selectedSegmentIndex == 0) self.layout.scale = sender.value;
    else if (_mode.selectedSegmentIndex == 1) [self.layout resizeButtonGroupForAction:_selected diameter:sender.value inBounds:[self placementBounds]];
    else _selected.diameter = sender.value;
    [self updateEditor];
}

- (void)addLeftCircle { [self addCircleOnAnchor:AKTouchActionAnchorLeft]; }
- (void)addRightCircle { [self addCircleOnAnchor:AKTouchActionAnchorRight]; }
- (void)addCircle { [self addCircleOnAnchor:AKTouchActionAnchorLeft]; }

- (void)addCircleOnAnchor:(AKTouchActionAnchor)anchor {
    AKTouchAction *added = [self.layout addActionOnAnchor:anchor];
    if (!added) return;
    _selected = added;
    _mode.selectedSegmentIndex = 2;
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
    [_panel removeFromSuperview];
    _panel = nil;
    _mode = nil;
    _size = _border = _fill = nil;
    _enabled = _shown = _labelsSwitch = nil;
    _sizeLabel = _selectionLabel = nil;
    _kindButton = _binding = _modifier = _labelButton = _presetButton = nil;
    _bindingRow = nil;
    [self updateAppearance];
    if (self.configurationChanged) self.configurationChanged();
}

@end
