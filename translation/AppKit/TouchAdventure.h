#import <UIKit/UIKit.h>

@protocol AKTouchAdventureDelegate <NSObject>
- (void)touchAdventureKey:(unsigned short)code pressed:(BOOL)pressed;
- (void)touchAdventureCameraButtonPressed:(BOOL)pressed;
- (void)touchAdventureCameraMoveBy:(CGPoint)delta;
- (void)touchAdventureTapAt:(CGPoint)point;
@end

// Lightweight native layer for the addon mode. The reserved right/bottom area
// and the space outside the movement stick go to the guest's direct-touch path.
@interface AKTouchAdventure : UIView
@property (nonatomic, weak) id<AKTouchAdventureDelegate> delegate;
@property (nonatomic) BOOL enabled;
@property (nonatomic) CGFloat reservedRightFraction; // default 0.33
@property (nonatomic) CGFloat reservedBottomFraction; // default 0.16
- (void)cancelTouches;
// Call before forwarding a direct guest touch: one mouse pointer cannot also
// hold the camera while that touch clicks/drags an ability or menu.
- (void)cancelCameraForDirectTouch;
@end
