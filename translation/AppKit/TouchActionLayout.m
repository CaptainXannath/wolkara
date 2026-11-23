#import "TouchActionLayout.h"
#include <math.h>

static NSString *const ActionsKey = @"WolkaraTouchAbilitiesV2";
static NSString *const LegacyActionsKey = @"WolkaraTouchAbilitiesV1";

typedef struct {
    __unsafe_unretained NSString *name;
    __unsafe_unretained NSString *shortName;
    unsigned short keyCode;
    __unsafe_unretained NSString *characters;
} AKTouchKeyEntry;

static const AKTouchKeyEntry AKTouchKeyTable[] = {
    {@"1", @"1", 18, @"1"}, {@"2", @"2", 19, @"2"}, {@"3", @"3", 20, @"3"}, {@"4", @"4", 21, @"4"},
    {@"5", @"5", 23, @"5"}, {@"6", @"6", 22, @"6"}, {@"7", @"7", 26, @"7"}, {@"8", @"8", 28, @"8"},
    {@"9", @"9", 25, @"9"}, {@"0", @"0", 29, @"0"}, {@"-", @"-", 27, @"-"}, {@"=", @"=", 24, @"="},
    {@"F1", @"F1", 122, @"\uF704"}, {@"F2", @"F2", 120, @"\uF705"}, {@"F3", @"F3", 99, @"\uF706"},
    {@"F4", @"F4", 118, @"\uF707"}, {@"F5", @"F5", 96, @"\uF708"}, {@"F6", @"F6", 97, @"\uF709"},
    {@"F7", @"F7", 98, @"\uF70A"}, {@"F8", @"F8", 100, @"\uF70B"}, {@"F9", @"F9", 101, @"\uF70C"},
    {@"F10", @"F10", 109, @"\uF70D"}, {@"F11", @"F11", 103, @"\uF70E"}, {@"F12", @"F12", 111, @"\uF70F"},
    {@"Space", @"Spc", 49, @" "}, {@"Tab", @"Tab", 48, @"\t"}, {@"Esc", @"Esc", 53, @"\x1b"},
    {@"Return", @"Ret", 36, @"\r"}, {@"`", @"`", 50, @"`"},
    {@"Q", @"Q", 12, @"q"}, {@"E", @"E", 14, @"e"}, {@"R", @"R", 15, @"r"}, {@"T", @"T", 17, @"t"},
    {@"F", @"F", 3, @"f"}, {@"G", @"G", 5, @"g"}, {@"V", @"V", 9, @"v"}, {@"C", @"C", 8, @"c"},
    {@"X", @"X", 7, @"x"}, {@"Z", @"Z", 6, @"z"}, {@"B", @"B", 11, @"b"}, {@"H", @"H", 4, @"h"},
    {@"J", @"J", 38, @"j"}, {@"K", @"K", 40, @"k"}, {@"L", @"L", 37, @"l"}, {@"N", @"N", 45, @"n"},
    {@"M", @"M", 46, @"m"}, {@"A", @"A", 0, @"a"}, {@"S", @"S", 1, @"s"}, {@"D", @"D", 2, @"d"},
    {@"W", @"W", 13, @"w"}, {@"I", @"I", 34, @"i"}, {@"O", @"O", 31, @"o"}, {@"P", @"P", 35, @"p"},
    {@"U", @"U", 32, @"u"}, {@"Y", @"Y", 16, @"y"},
    {@"[", @"[", 33, @"["}, {@"]", @"]", 30, @"]"}, {@"\\", @"\\", 42, @"\\"}, {@";", @";", 41, @";"},
    {@"'", @"'", 39, @"'"}, {@",", @",", 43, @","}, {@".", @".", 47, @"."}, {@"/", @"/", 44, @"/"},
};

static const NSUInteger AKTouchKeyTableCount = sizeof(AKTouchKeyTable) / sizeof(AKTouchKeyTable[0]);

static CGFloat Bounded(CGFloat x, CGFloat low, CGFloat high, CGFloat fallback) {
    return isfinite(x) ? MAX(low, MIN(high, x)) : fallback;
}

static CGFloat Number(id value, CGFloat fallback) {
    return [value isKindOfClass:NSNumber.class] ? [value doubleValue] : fallback;
}

static const AKTouchKeyEntry *FindKeyEntry(NSString *name) {
    if (![name isKindOfClass:NSString.class] || !name.length) return NULL;
    for (NSUInteger i = 0; i < AKTouchKeyTableCount; i++) {
        if ([AKTouchKeyTable[i].name caseInsensitiveCompare:name] == NSOrderedSame) return &AKTouchKeyTable[i];
    }
    return NULL;
}

static NSString *DefaultGroup(NSString *identifier, AKTouchActionAnchor anchor) {
    if (anchor == AKTouchActionAnchorLeft) return @"side.left";
    if (anchor == AKTouchActionAnchorRight) return @"side.right";
    NSArray *parts = [identifier componentsSeparatedByString:@"."];
    if (parts.count == 2 && [@[@"0", @"1", @"2", @"3"] containsObject:parts[0]]) {
        if ([@[@"up", @"right", @"down", @"left"] containsObject:parts[1]]) return [parts[0] stringByAppendingString:@".dpad"];
        if ([@[@"Y", @"B", @"A", @"X"] containsObject:parts[1]]) return [parts[0] stringByAppendingString:@".face"];
    }
    return identifier;
}

@implementation AKTouchAction

- (instancetype)init {
    if ((self = [super init])) {
        _button = @"A";
        _keyName = @"1";
        _diameter = 40;
        _enabled = YES;
    }
    return self;
}

+ (NSArray<NSString *> *)availableKeyNames {
    static NSArray<NSString *> *names;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *list = [NSMutableArray arrayWithCapacity:AKTouchKeyTableCount];
        for (NSUInteger i = 0; i < AKTouchKeyTableCount; i++) [list addObject:AKTouchKeyTable[i].name];
        names = [list copy];
    });
    return names;
}

+ (BOOL)keyInfoForName:(NSString *)name
               keyCode:(unsigned short *)keyCode
            characters:(NSString **)characters {
    const AKTouchKeyEntry *entry = FindKeyEntry(name);
    if (!entry) return NO;
    if (keyCode) *keyCode = entry->keyCode;
    if (characters) *characters = entry->characters;
    return YES;
}

+ (NSString *)shortLabelForKeyName:(NSString *)name modifiers:(AKTouchKeyModifier)modifiers {
    const AKTouchKeyEntry *entry = FindKeyEntry(name);
    NSString *base = entry ? entry->shortName : (name.length ? name : @"1");
    NSMutableString *prefix = [NSMutableString new];
    if (modifiers & AKTouchKeyModifierControl) [prefix appendString:@"C"];
    if (modifiers & AKTouchKeyModifierShift) [prefix appendString:@"S"];
    if (modifiers & AKTouchKeyModifierOption) [prefix appendString:@"A"];
    if (modifiers & AKTouchKeyModifierCommand) [prefix appendString:@"M"];
    if (prefix.length) [prefix appendString:@"-"];
    return [prefix stringByAppendingString:base];
}

- (unsigned short)macKeyCode {
    unsigned short code = 18;
    [AKTouchAction keyInfoForName:self.keyName keyCode:&code characters:nil];
    return code;
}

- (NSString *)macCharacters {
    NSString *chars = @"1";
    [AKTouchAction keyInfoForName:self.keyName keyCode:nil characters:&chars];
    return chars;
}

- (NSString *)label {
    if (self.customLabel.length) return self.customLabel;
    if (self.kind == AKTouchActionKindKeyboard) {
        return [AKTouchAction shortLabelForKeyName:self.keyName modifiers:self.keyModifiers];
    }
    NSString *prefix = @[@"", @"LT + ", @"RT + ", @"LT + RT + "][MIN(self.modifiers, 3)];
    NSString *button = @{@"up": @"↑", @"right": @"→", @"down": @"↓", @"left": @"←"}[self.button] ?: self.button;
    return [prefix stringByAppendingString:button ?: @"A"];
}

@end

@implementation AKTouchActionLayout {
    NSUserDefaults *_defaults;
    NSMutableArray<AKTouchAction *> *_items;
}

- (instancetype)initWithDefaults:(NSUserDefaults *)defaults {
    if ((self = [super init])) {
        _defaults = defaults;
        [self resetToSideLayout];
        id stored = [defaults objectForKey:ActionsKey];
        if (![stored isKindOfClass:NSDictionary.class]) {
            // Preserve explicit legacy V1 ability layouts only if the user enabled them.
            id legacy = [defaults objectForKey:LegacyActionsKey];
            if ([legacy isKindOfClass:NSDictionary.class] && Number(legacy[@"enabled"], 0) != 0) {
                stored = legacy;
            } else {
                return self;
            }
        }
        [self loadFromDictionary:stored];
    }
    return self;
}

- (void)loadFromDictionary:(NSDictionary *)saved {
    _enabled = Number(saved[@"enabled"], 1) != 0;
    _showLabels = Number(saved[@"showLabels"], 1) != 0;
    self.scale = Number(saved[@"scale"], 1);
    self.borderOpacity = Number(saved[@"border"], 0.45);
    self.fillOpacity = Number(saved[@"fill"], 0.55);
    self.center = CGPointMake(Number(saved[@"x"], 0.5), Number(saved[@"y"], 700.0 / 900.0));
    self.leftOffset = CGPointMake(Number(saved[@"lx"], 0), Number(saved[@"ly"], 0));
    self.rightOffset = CGPointMake(Number(saved[@"rx"], 0), Number(saved[@"ry"], 0));
    id actions = saved[@"actions"];
    if (![actions isKindOfClass:NSArray.class] || [actions count] > 64) return;
    NSMutableArray *loaded = [NSMutableArray new];
    NSMutableSet *ids = [NSMutableSet new];
    NSArray *validButtons = @[@"A", @"B", @"X", @"Y", @"LB", @"RB", @"up", @"right", @"down", @"left"];
    for (id item in actions) {
        if (![item isKindOfClass:NSDictionary.class]) continue;
        NSString *identifier = item[@"id"];
        if (![identifier isKindOfClass:NSString.class] || !identifier.length || identifier.length > 80 ||
            [ids containsObject:identifier]) continue;
        AKTouchActionKind kind = (AKTouchActionKind)Bounded(Number(item[@"kind"], 0), 0, 1, 0);
        NSString *button = item[@"button"];
        NSString *keyName = item[@"key"];
        if (kind == AKTouchActionKindGamepad) {
            if (![button isKindOfClass:NSString.class] || ![validButtons containsObject:button]) continue;
        } else {
            if (![keyName isKindOfClass:NSString.class] || !FindKeyEntry(keyName)) continue;
            if (![button isKindOfClass:NSString.class] || ![validButtons containsObject:button]) button = @"A";
        }
        AKTouchAction *a = [AKTouchAction new];
        a.identifier = identifier;
        a.kind = kind;
        a.anchor = (AKTouchActionAnchor)Bounded(Number(item[@"anchor"], 0), 0, 2, 0);
        a.button = button ?: @"A";
        a.keyName = FindKeyEntry(keyName) ? keyName : @"1";
        a.keyModifiers = (AKTouchKeyModifier)Bounded(Number(item[@"keyMods"], 0), 0, 15, 0);
        id custom = item[@"label"];
        if ([custom isKindOfClass:NSString.class] && [custom length] > 0 && [custom length] <= 24) a.customLabel = custom;
        id group = item[@"group"];
        a.groupIdentifier = [group isKindOfClass:NSString.class] && [group length] > 0 && [group length] <= 80
            ? group : DefaultGroup(identifier, a.anchor);
        a.modifiers = (NSUInteger)Bounded(Number(item[@"modifiers"], 0), 0, 3, 0);
        a.position = CGPointMake(Bounded(Number(item[@"x"], 0), -1200, 1200, 0),
                                 Bounded(Number(item[@"y"], 0), -900, 900, 0));
        a.diameter = Bounded(Number(item[@"diameter"], 40), 20, 160, 40);
        a.enabled = Number(item[@"enabled"], 1) != 0;
        [loaded addObject:a];
        [ids addObject:identifier];
    }
    _items = loaded;
}

- (NSArray<AKTouchAction *> *)actions { return _items.copy; }
- (void)setScale:(CGFloat)value { _scale = Bounded(value, 0.4, 4, 1); }
- (void)setBorderOpacity:(CGFloat)value { _borderOpacity = Bounded(value, 0, 0.9, 0.45); }
- (void)setFillOpacity:(CGFloat)value { _fillOpacity = Bounded(value, 0, 0.9, 0.55); }
- (void)setCenter:(CGPoint)value { _center = CGPointMake(Bounded(value.x, 0, 1, 0.5), Bounded(value.y, 0, 1, 700.0 / 900.0)); }
- (void)setLeftOffset:(CGPoint)value { _leftOffset = CGPointMake(Bounded(value.x, -0.5, 0.8, 0), Bounded(value.y, -0.5, 0.5, 0)); }
- (void)setRightOffset:(CGPoint)value { _rightOffset = CGPointMake(Bounded(value.x, -0.8, 0.5, 0), Bounded(value.y, -0.5, 0.5, 0)); }

- (void)reset {
    [self resetToSideLayout];
}

- (void)resetToSideLayout {
    _enabled = YES;
    _showLabels = YES;
    _scale = 1;
    _borderOpacity = 0.45;
    _fillOpacity = 0.55;
    _center = CGPointMake(0.5, 700.0 / 900.0);
    _leftOffset = CGPointZero;
    _rightOffset = CGPointZero;
    _items = [NSMutableArray new];

    // Left cluster: 2 rows x 4 columns above the bottom-left joystick (keys 1-8).
    NSArray<NSString *> *leftKeys = @[@"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8"];
    const CGFloat leftCols[4] = {32, 78, 124, 170};
    const CGFloat leftRows[2] = {8, 54};
    for (NSUInteger i = 0; i < leftKeys.count; i++) {
        AKTouchAction *a = [AKTouchAction new];
        a.identifier = [NSString stringWithFormat:@"side.left.%lu", (unsigned long)i];
        a.groupIdentifier = @"side.left";
        a.anchor = AKTouchActionAnchorLeft;
        a.kind = AKTouchActionKindKeyboard;
        a.keyName = leftKeys[i];
        a.keyModifiers = 0;
        a.position = CGPointMake(leftCols[i % 4], leftRows[i / 4]);
        a.diameter = 40;
        a.enabled = YES;
        [_items addObject:a];
    }

    // Right cluster: 2 rows x 4 columns below the minimap and above Camera (keys C-1..C-8).
    NSArray<NSString *> *rightKeys = @[@"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8"];
    const CGFloat rightCols[4] = {-168, -124, -80, -36};
    const CGFloat rightRows[2] = {8, 54};
    for (NSUInteger i = 0; i < rightKeys.count; i++) {
        AKTouchAction *a = [AKTouchAction new];
        a.identifier = [NSString stringWithFormat:@"side.right.%lu", (unsigned long)i];
        a.groupIdentifier = @"side.right";
        a.anchor = AKTouchActionAnchorRight;
        a.kind = AKTouchActionKindKeyboard;
        a.keyName = rightKeys[i];
        a.keyModifiers = AKTouchKeyModifierControl;
        a.position = CGPointMake(rightCols[i % 4], rightRows[i / 4]);
        a.diameter = 40;
        a.enabled = YES;
        [_items addObject:a];
    }
}

- (void)resetToClassicLayout {
    _enabled = YES;
    _showLabels = NO;
    _scale = 1;
    _borderOpacity = 0.25;
    _fillOpacity = 0.20;
    _center = CGPointMake(0.5, 700.0 / 900.0);
    _leftOffset = CGPointZero;
    _rightOffset = CGPointZero;
    _items = [NSMutableArray new];
    const CGPoint centers[4][2] = {{{565, 631}, {710, 631}}, {{388, 689}, {500, 689}}, {{777, 689}, {889, 689}}, {{582, 747}, {694, 747}}};
    NSArray *keys = @[@"up", @"right", @"down", @"left", @"Y", @"B", @"A", @"X"];
    for (NSUInteger group = 0; group < 4; group++) {
        for (NSUInteger i = 0; i < 8; i++) {
            CGPoint p = centers[group][i / 4];
            CGFloat dx = group ? 32 : 43, dy = group ? 18 : 23;
            if (i % 4 == 0) p.y -= dy;
            else if (i % 4 == 1) p.x += dx;
            else if (i % 4 == 2) p.y += dy;
            else p.x -= dx;
            AKTouchAction *a = [AKTouchAction new];
            a.identifier = [NSString stringWithFormat:@"%lu.%@", (unsigned long)group, keys[i]];
            a.groupIdentifier = DefaultGroup(a.identifier, AKTouchActionAnchorCenter);
            a.anchor = AKTouchActionAnchorCenter;
            a.kind = AKTouchActionKindGamepad;
            a.button = keys[i];
            a.modifiers = group;
            a.position = CGPointMake(p.x - 640, p.y - 700);
            a.diameter = group ? 32 : 42;
            a.enabled = YES;
            [_items addObject:a];
        }
    }
}

- (CGRect)referenceBoundsForAnchor:(AKTouchActionAnchor)anchor {
    CGRect result = CGRectNull;
    for (AKTouchAction *a in _items) {
        if (a.anchor != anchor) continue;
        result = CGRectUnion(result, CGRectMake(a.position.x - a.diameter / 2, a.position.y - a.diameter / 2, a.diameter, a.diameter));
    }
    return CGRectIsNull(result) ? CGRectMake(-20, -20, 40, 40) : result;
}

- (CGFloat)unitScaleInBounds:(CGRect)bounds {
    return [self unitScaleForAnchor:AKTouchActionAnchorLeft inBounds:bounds];
}

- (CGFloat)unitScaleForAnchor:(AKTouchActionAnchor)anchor inBounds:(CGRect)bounds {
    if (bounds.size.width <= 0 || bounds.size.height <= 0) return 0;
    if (anchor == AKTouchActionAnchorCenter) {
        CGRect content = [self referenceBoundsForAnchor:AKTouchActionAnchorCenter];
        return MAX(0, MIN(bounds.size.height / 900.0 * self.scale,
                          MIN(MAX(0, bounds.size.width - 8) / content.size.width,
                              MAX(0, bounds.size.height - 8) / content.size.height)));
    }
    CGFloat base = MIN(1.35, MAX(0.75, bounds.size.height / 420.0));
    return base * self.scale;
}

- (CGPoint)originForAnchor:(AKTouchActionAnchor)anchor inBounds:(CGRect)bounds unit:(CGFloat)unit {
    if (anchor == AKTouchActionAnchorLeft) {
        return CGPointMake(CGRectGetMinX(bounds) + self.leftOffset.x * bounds.size.width,
                           CGRectGetMidY(bounds) + self.leftOffset.y * bounds.size.height);
    }
    if (anchor == AKTouchActionAnchorRight) {
        return CGPointMake(CGRectGetMaxX(bounds) + self.rightOffset.x * bounds.size.width,
                           CGRectGetMidY(bounds) + self.rightOffset.y * bounds.size.height);
    }
    CGRect content = [self referenceBoundsForAnchor:AKTouchActionAnchorCenter];
    CGFloat x = CGRectGetMinX(bounds) + self.center.x * bounds.size.width;
    CGFloat y = CGRectGetMinY(bounds) + self.center.y * bounds.size.height;
    x = MAX(CGRectGetMinX(bounds) + 4 - CGRectGetMinX(content) * unit,
            MIN(CGRectGetMaxX(bounds) - 4 - CGRectGetMaxX(content) * unit, x));
    y = MAX(CGRectGetMinY(bounds) + 4 - CGRectGetMinY(content) * unit,
            MIN(CGRectGetMaxY(bounds) - 4 - CGRectGetMaxY(content) * unit, y));
    return CGPointMake(x, y);
}

- (CGPoint)pointForPosition:(CGPoint)position inBounds:(CGRect)bounds {
    CGFloat unit = [self unitScaleForAnchor:AKTouchActionAnchorCenter inBounds:bounds];
    CGPoint origin = [self originForAnchor:AKTouchActionAnchorCenter inBounds:bounds unit:unit];
    return CGPointMake(origin.x + position.x * unit, origin.y + position.y * unit);
}

- (CGRect)frameForAction:(AKTouchAction *)action inBounds:(CGRect)bounds {
    if (!action || bounds.size.width <= 0 || bounds.size.height <= 0) return CGRectZero;
    CGFloat unit = [self unitScaleForAnchor:action.anchor inBounds:bounds];
    CGFloat diameter = MIN(action.diameter * unit, MIN(bounds.size.width - 8, bounds.size.height - 8));
    diameter = MAX(16, diameter);
    CGPoint origin = [self originForAnchor:action.anchor inBounds:bounds unit:unit];
    CGFloat cx = origin.x + action.position.x * unit;
    CGFloat cy = origin.y + action.position.y * unit;
    CGFloat minCx = CGRectGetMinX(bounds) + 4 + diameter / 2;
    CGFloat maxCx = CGRectGetMaxX(bounds) - 4 - diameter / 2;
    CGFloat minCy = CGRectGetMinY(bounds) + 4 + diameter / 2;
    CGFloat maxCy = CGRectGetMaxY(bounds) - 4 - diameter / 2;
    cx = Bounded(cx, minCx, MAX(minCx, maxCx), minCx);
    cy = Bounded(cy, minCy, MAX(minCy, maxCy), minCy);
    return CGRectMake(cx - diameter / 2, cy - diameter / 2, diameter, diameter);
}

- (void)moveGroupBy:(CGPoint)delta inBounds:(CGRect)bounds {
    if (bounds.size.width <= 0 || bounds.size.height <= 0) return;
    CGFloat dx = delta.x / bounds.size.width, dy = delta.y / bounds.size.height;
    BOOL hasCenter = NO, hasLeft = NO, hasRight = NO;
    for (AKTouchAction *a in _items) {
        if (a.anchor == AKTouchActionAnchorLeft) hasLeft = YES;
        else if (a.anchor == AKTouchActionAnchorRight) hasRight = YES;
        else hasCenter = YES;
    }
    if (hasCenter) {
        CGFloat unit = [self unitScaleForAnchor:AKTouchActionAnchorCenter inBounds:bounds];
        CGPoint p = [self originForAnchor:AKTouchActionAnchorCenter inBounds:bounds unit:unit];
        self.center = CGPointMake((p.x + delta.x - bounds.origin.x) / bounds.size.width,
                                  (p.y + delta.y - bounds.origin.y) / bounds.size.height);
        p = [self originForAnchor:AKTouchActionAnchorCenter inBounds:bounds unit:unit];
        self.center = CGPointMake((p.x - bounds.origin.x) / bounds.size.width,
                                  (p.y - bounds.origin.y) / bounds.size.height);
    }
    if (hasLeft) self.leftOffset = CGPointMake(self.leftOffset.x + dx, self.leftOffset.y + dy);
    if (hasRight) self.rightOffset = CGPointMake(self.rightOffset.x + dx, self.rightOffset.y + dy);
}

- (void)moveAction:(AKTouchAction *)action by:(CGPoint)delta inBounds:(CGRect)bounds {
    if (action) [self moveActions:@[action] by:delta inBounds:bounds];
}

- (NSArray<AKTouchAction *> *)groupForAction:(AKTouchAction *)action {
    if (!action) return @[];
    NSMutableArray *group = [NSMutableArray new];
    for (AKTouchAction *item in _items) {
        if ([item.groupIdentifier isEqual:action.groupIdentifier]) [group addObject:item];
    }
    return group;
}

- (void)moveButtonGroupForAction:(AKTouchAction *)action by:(CGPoint)delta inBounds:(CGRect)bounds {
    [self moveActions:[self groupForAction:action] by:delta inBounds:bounds];
}

- (void)moveActions:(NSArray<AKTouchAction *> *)actions by:(CGPoint)delta inBounds:(CGRect)bounds {
    if (!actions.count || bounds.size.width <= 0 || bounds.size.height <= 0) return;
    AKTouchActionAnchor anchor = actions.firstObject.anchor;
    CGFloat unit = [self unitScaleForAnchor:anchor inBounds:bounds];
    if (unit <= 0) return;
    CGRect frame = CGRectNull;
    for (AKTouchAction *item in actions) frame = CGRectUnion(frame, [self frameForAction:item inBounds:bounds]);
    if (CGRectIsNull(frame)) return;
    if (anchor == AKTouchActionAnchorCenter) {
        CGPoint anchorPt = [self originForAnchor:AKTouchActionAnchorCenter inBounds:bounds unit:unit];
        self.center = CGPointMake((anchorPt.x - bounds.origin.x) / bounds.size.width,
                                  (anchorPt.y - bounds.origin.y) / bounds.size.height);
    }
    CGFloat x = Bounded(frame.origin.x + delta.x, CGRectGetMinX(bounds) + 4,
                        MAX(CGRectGetMinX(bounds) + 4, CGRectGetMaxX(bounds) - frame.size.width - 4), frame.origin.x);
    CGFloat y = Bounded(frame.origin.y + delta.y, CGRectGetMinY(bounds) + 4,
                        MAX(CGRectGetMinY(bounds) + 4, CGRectGetMaxY(bounds) - frame.size.height - 4), frame.origin.y);
    for (AKTouchAction *item in actions) {
        item.position = CGPointMake(Bounded(item.position.x + (x - frame.origin.x) / unit, -1200, 1200, item.position.x),
                                    Bounded(item.position.y + (y - frame.origin.y) / unit, -900, 900, item.position.y));
    }
}

- (void)resizeButtonGroupForAction:(AKTouchAction *)action diameter:(CGFloat)diameter inBounds:(CGRect)bounds {
    NSArray *group = [self groupForAction:action];
    if (!group.count || bounds.size.width <= 0 || bounds.size.height <= 0) return;
    CGFloat unit = [self unitScaleForAnchor:action.anchor inBounds:bounds];
    if (unit <= 0) return;
    CGRect frame = CGRectNull;
    CGFloat low = 0, high = INFINITY;
    for (AKTouchAction *item in group) {
        frame = CGRectUnion(frame, [self frameForAction:item inBounds:bounds]);
        low = MAX(low, 20.0 / item.diameter);
        high = MIN(high, 160.0 / item.diameter);
    }
    CGPoint middle = CGPointMake(CGRectGetMidX(frame), CGRectGetMidY(frame));
    if (frame.size.width > 0 && frame.size.height > 0) {
        high = MIN(high, 2.0 * MIN(middle.x - CGRectGetMinX(bounds) - 4, CGRectGetMaxX(bounds) - 4 - middle.x) / frame.size.width);
        high = MIN(high, 2.0 * MIN(middle.y - CGRectGetMinY(bounds) - 4, CGRectGetMaxY(bounds) - 4 - middle.y) / frame.size.height);
    }
    high = MAX(low, high);
    CGFloat factor = Bounded(diameter / action.diameter, low, high, 1);
    CGPoint anchorPt = [self originForAnchor:action.anchor inBounds:bounds unit:unit];
    if (action.anchor == AKTouchActionAnchorCenter) {
        self.center = CGPointMake((anchorPt.x - bounds.origin.x) / bounds.size.width,
                                  (anchorPt.y - bounds.origin.y) / bounds.size.height);
    }
    CGPoint center = CGPointMake((middle.x - anchorPt.x) / unit, (middle.y - anchorPt.y) / unit);
    for (AKTouchAction *item in group) {
        item.position = CGPointMake(center.x + (item.position.x - center.x) * factor,
                                    center.y + (item.position.y - center.y) * factor);
        item.diameter *= factor;
    }
}

- (NSString *)nextSuggestedKeyForAnchor:(AKTouchActionAnchor)anchor modifierOut:(AKTouchKeyModifier *)modOut {
    NSArray<NSString *> *barKeys = @[@"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"0", @"-", @"="];
    NSArray<NSString *> *fKeys = @[@"F1", @"F2", @"F3", @"F4", @"F5", @"F6", @"F7", @"F8", @"F9", @"F10", @"F11", @"F12"];
    NSArray<NSNumber *> *mods = anchor == AKTouchActionAnchorRight
        ? @[@(AKTouchKeyModifierControl), @(AKTouchKeyModifierShift), @0, @(AKTouchKeyModifierOption)]
        : @[@0, @(AKTouchKeyModifierShift), @(AKTouchKeyModifierControl), @(AKTouchKeyModifierOption)];
    NSMutableSet<NSString *> *used = [NSMutableSet new];
    for (AKTouchAction *item in _items) {
        if (item.kind == AKTouchActionKindKeyboard) {
            [used addObject:[NSString stringWithFormat:@"%lu:%@", (unsigned long)item.keyModifiers, item.keyName]];
        }
    }
    for (NSNumber *m in mods) {
        for (NSString *k in barKeys) {
            NSString *sig = [NSString stringWithFormat:@"%lu:%@", (unsigned long)m.unsignedIntegerValue, k];
            if (![used containsObject:sig]) {
                if (modOut) *modOut = m.unsignedIntegerValue;
                return k;
            }
        }
    }
    for (NSString *k in fKeys) {
        NSString *sig = [NSString stringWithFormat:@"0:%@", k];
        if (![used containsObject:sig]) {
            if (modOut) *modOut = 0;
            return k;
        }
    }
    if (modOut) *modOut = 0;
    return @"1";
}

- (CGPoint)nextAvailablePositionForAnchor:(AKTouchActionAnchor)anchor {
    if (anchor == AKTouchActionAnchorCenter) return CGPointZero;
    const CGFloat rows[4] = {8, 54, -38, -84};
    const CGFloat leftCols[5] = {32, 78, 124, 170, 216};
    const CGFloat rightCols[5] = {-168, -124, -80, -36, -212};
    const CGFloat *cols = (anchor == AKTouchActionAnchorLeft) ? leftCols : rightCols;
    for (NSUInteger r = 0; r < 4; r++) {
        for (NSUInteger c = 0; c < 5; c++) {
            CGPoint candidate = CGPointMake(cols[c], rows[r]);
            BOOL occupied = NO;
            for (AKTouchAction *existing in _items) {
                if (existing.anchor != anchor) continue;
                if (hypot(existing.position.x - candidate.x, existing.position.y - candidate.y) < 34) {
                    occupied = YES;
                    break;
                }
            }
            if (!occupied) return candidate;
        }
    }
    return CGPointMake(anchor == AKTouchActionAnchorLeft ? 80 : -80, 0);
}

- (AKTouchAction *)addAction {
    return [self addActionOnAnchor:AKTouchActionAnchorLeft];
}

- (AKTouchAction *)addActionOnAnchor:(AKTouchActionAnchor)anchor {
    if (_items.count >= 64) return nil;
    AKTouchAction *a = [AKTouchAction new];
    a.identifier = NSUUID.UUID.UUIDString;
    a.anchor = anchor;
    a.groupIdentifier = DefaultGroup(a.identifier, anchor);
    a.kind = AKTouchActionKindKeyboard;
    AKTouchKeyModifier mods = 0;
    a.keyName = [self nextSuggestedKeyForAnchor:anchor modifierOut:&mods];
    a.keyModifiers = mods;
    a.position = [self nextAvailablePositionForAnchor:anchor];
    a.diameter = 40;
    a.enabled = YES;
    [_items addObject:a];
    return a;
}

- (void)removeAction:(AKTouchAction *)action {
    if (action) [_items removeObject:action];
}

- (void)save {
    NSMutableArray *actions = [NSMutableArray new];
    for (AKTouchAction *a in _items) {
        NSMutableDictionary *entry = [@{
            @"id": a.identifier,
            @"group": a.groupIdentifier ?: a.identifier,
            @"kind": @(a.kind),
            @"anchor": @(a.anchor),
            @"button": a.button ?: @"A",
            @"modifiers": @(a.modifiers),
            @"key": a.keyName ?: @"1",
            @"keyMods": @(a.keyModifiers),
            @"x": @(a.position.x),
            @"y": @(a.position.y),
            @"diameter": @(a.diameter),
            @"enabled": @(a.enabled),
        } mutableCopy];
        if (a.customLabel.length) entry[@"label"] = a.customLabel;
        [actions addObject:entry];
    }
    [_defaults setObject:@{
        @"enabled": @(self.enabled),
        @"showLabels": @(self.showLabels),
        @"scale": @(self.scale),
        @"border": @(self.borderOpacity),
        @"fill": @(self.fillOpacity),
        @"x": @(self.center.x),
        @"y": @(self.center.y),
        @"lx": @(self.leftOffset.x),
        @"ly": @(self.leftOffset.y),
        @"rx": @(self.rightOffset.x),
        @"ry": @(self.rightOffset.y),
        @"actions": actions,
    } forKey:ActionsKey];
}

@end
