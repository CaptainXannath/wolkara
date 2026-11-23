#import <UIKit/UIKit.h>

typedef NS_ENUM(NSUInteger, AKTouchActionKind) {
    AKTouchActionKindGamepad = 0,
    AKTouchActionKindKeyboard = 1,
    AKTouchActionKindMouse = 2,
};

typedef NS_ENUM(NSUInteger, AKTouchActionAnchor) {
    AKTouchActionAnchorCenter = 0,
    AKTouchActionAnchorLeft = 1,
    AKTouchActionAnchorRight = 2,
};

typedef NS_ENUM(NSUInteger, AKTouchActionBehavior) {
    AKTouchActionBehaviorTap = 0,
    AKTouchActionBehaviorHold = 1,
    AKTouchActionBehaviorToggle = 2,
};

typedef NS_ENUM(NSUInteger, AKTouchActionShape) {
    AKTouchActionShapeCircle = 0,
    AKTouchActionShapePill = 1,
    AKTouchActionShapeSquare = 2,
};

typedef NS_ENUM(NSUInteger, AKTouchActionColor) {
    AKTouchActionColorDefault = 0,
    AKTouchActionColorGold = 1,
    AKTouchActionColorRed = 2,
    AKTouchActionColorBlue = 3,
    AKTouchActionColorGreen = 4,
    AKTouchActionColorPurple = 5,
    AKTouchActionColorClear = 6,
};

typedef NS_OPTIONS(NSUInteger, AKTouchKeyModifier) {
    AKTouchKeyModifierShift   = 1 << 0,
    AKTouchKeyModifierControl = 1 << 1,
    AKTouchKeyModifierOption  = 1 << 2,
    AKTouchKeyModifierCommand = 1 << 3,
};

@interface AKTouchAction : NSObject
@property(nonatomic, copy) NSString *identifier, *button;
@property(nonatomic, copy) NSString *groupIdentifier;
@property(nonatomic) AKTouchActionKind kind;
@property(nonatomic) AKTouchActionAnchor anchor;
@property(nonatomic) NSUInteger modifiers;
@property(nonatomic, copy) NSString *keyName;
@property(nonatomic) AKTouchKeyModifier keyModifiers;
@property(nonatomic) unsigned mouseButton;
@property(nonatomic) AKTouchActionBehavior behavior;
@property(nonatomic) AKTouchActionShape shape;
@property(nonatomic) AKTouchActionColor colorPreset;
@property(nonatomic, copy) NSString *customLabel;
@property(nonatomic) CGPoint position;
@property(nonatomic) CGFloat diameter;
@property(nonatomic) CGFloat widthScale;
@property(nonatomic) BOOL enabled;
@property(nonatomic, readonly) NSString *label;
@property(nonatomic, readonly) unsigned short macKeyCode;
@property(nonatomic, readonly) NSString *macCharacters;

+ (NSArray<NSString *> *)availableKeyNames;
+ (BOOL)keyInfoForName:(NSString *)name
               keyCode:(unsigned short *)keyCode
            characters:(NSString **)characters;
+ (NSString *)shortLabelForKeyName:(NSString *)name modifiers:(AKTouchKeyModifier)modifiers;
@end

@interface AKTouchActionLayout : NSObject
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
@property(nonatomic) NSUInteger profileIndex;
@property(nonatomic) BOOL enabled;
@property(nonatomic) BOOL showLabels;
@property(nonatomic) BOOL snapToGrid;
@property(nonatomic) CGFloat scale, borderOpacity, fillOpacity;
@property(nonatomic) CGPoint center;
@property(nonatomic) CGPoint leftOffset, rightOffset;
@property(nonatomic, readonly) NSArray<AKTouchAction *> *actions;
- (void)switchToProfile:(NSUInteger)profile;
- (CGFloat)unitScaleInBounds:(CGRect)bounds;
- (CGFloat)unitScaleForAnchor:(AKTouchActionAnchor)anchor inBounds:(CGRect)bounds;
// Convert a reference offset from the action's anchor in bounds.
- (CGPoint)pointForPosition:(CGPoint)position inBounds:(CGRect)bounds;
- (CGRect)frameForAction:(AKTouchAction *)action inBounds:(CGRect)bounds;
- (void)moveGroupBy:(CGPoint)delta inBounds:(CGRect)bounds;
- (void)moveAction:(AKTouchAction *)action by:(CGPoint)delta inBounds:(CGRect)bounds;
- (void)setCenter:(CGPoint)point forAction:(AKTouchAction *)action inBounds:(CGRect)bounds snap:(BOOL)snap;
- (NSArray<AKTouchAction *> *)groupForAction:(AKTouchAction *)action;
- (void)moveButtonGroupForAction:(AKTouchAction *)action by:(CGPoint)delta inBounds:(CGRect)bounds;
- (void)resizeButtonGroupForAction:(AKTouchAction *)action diameter:(CGFloat)diameter inBounds:(CGRect)bounds;
- (AKTouchAction *)addAction;
- (AKTouchAction *)addActionOnAnchor:(AKTouchActionAnchor)anchor;
- (AKTouchAction *)addActionAtCenter:(CGPoint)point inBounds:(CGRect)bounds snap:(BOOL)snap;
- (AKTouchAction *)duplicateAction:(AKTouchAction *)action inBounds:(CGRect)bounds;
- (void)removeAction:(AKTouchAction *)action;
- (void)clearActions;
- (void)reset;
- (void)resetToSideLayout;
- (void)resetToClassicLayout;
- (void)save;
@end
