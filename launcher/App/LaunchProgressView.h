#pragma once
#import <UIKit/UIKit.h>

typedef NS_ENUM(NSUInteger, TKLaunchPhase) {
    TKLaunchPhaseConnection, TKLaunchPhaseMemory, TKLaunchPhaseGame
};

// Milestones, not a guessed percentage or elapsed-time animation. Activity in
// the current phase is rendered by Core Animation while app threads are paused.
@interface TKLaunchProgressView : UIView
- (void)start;
- (void)showPhase:(TKLaunchPhase)phase;
- (void)stop;
@end
