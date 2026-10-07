#import "LaunchProgressView.h"
#import <QuartzCore/QuartzCore.h>
#include <math.h>

@implementation TKLaunchProgressView {
    NSArray<CALayer *> *_tracks;
    NSArray<UILabel *> *_labels;
    CALayer *_activity;
    TKLaunchPhase _phase;
    BOOL _running;
    CGFloat _animationWidth;
}
- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self=[super initWithFrame:frame])) return nil;
    self.hidden=YES;
    self.isAccessibilityElement=YES;
    self.accessibilityLabel=@"Startup progress";
    NSMutableArray *tracks=[NSMutableArray new], *labels=[NSMutableArray new];
    for (NSString *title in @[@"Connection",@"Memory",@"Game"]) {
        CALayer *track=[CALayer layer];
        track.cornerRadius=3; track.masksToBounds=YES;
        [self.layer addSublayer:track]; [tracks addObject:track];
        UILabel *label=[UILabel new];
        label.text=title; label.font=[UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
        label.textAlignment=NSTextAlignmentCenter;
        [self addSubview:label]; [labels addObject:label];
    }
    _tracks=tracks; _labels=labels;
    _activity=[CALayer layer]; _activity.name=@"startup.activity"; _activity.cornerRadius=3;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resumeActivity:)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(resumeActivity:)
        name:UIAccessibilityReduceMotionStatusDidChangeNotification object:nil];
    [self registerForTraitChanges:@[UITraitUserInterfaceStyle.class] withAction:@selector(updateAppearance)];
    return self;
}
- (CGSize)intrinsicContentSize { return CGSizeMake(270,38); }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width=MAX(0,(self.bounds.size.width-16)/3);
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    for (NSUInteger i=0;i<_tracks.count;i++) {
        _tracks[i].frame=CGRectMake(i*(width+8),3,width,6);
        _labels[i].frame=CGRectMake(i*(width+8),13,width,20);
    }
    _activity.bounds=CGRectMake(0,0,width*0.35,6);
    _activity.position=CGPointMake(width/2,3);
    [CATransaction commit];
    [self updateAppearance];
    [self ensureActivity];
}
- (void)updateAppearance {
    UIColor *accent=[self.tintColor resolvedColorWithTraitCollection:self.traitCollection];
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    for (NSUInteger i=0;i<_tracks.count;i++) {
        _tracks[i].backgroundColor=(i<_phase ? accent :
            [accent colorWithAlphaComponent:i==_phase ? 0.24 : 0.10]).CGColor;
        _labels[i].textColor=i<=_phase ? accent : UIColor.secondaryLabelColor;
    }
    _activity.backgroundColor=accent.CGColor;
    [CATransaction commit];
}
- (void)tintColorDidChange { [super tintColorDidChange]; if (_tracks) [self updateAppearance]; }
- (void)didMoveToWindow { [super didMoveToWindow]; [self ensureActivity]; }
- (void)ensureActivity {
    if (!_running || self.hidden || !self.window) return;
    CALayer *track=_tracks[_phase];
    if (_activity.superlayer!=track) {
        [_activity removeFromSuperlayer]; [track addSublayer:_activity];
        [_activity removeAllAnimations];
    }
    CGFloat width=track.bounds.size.width;
    if (UIAccessibilityIsReduceMotionEnabled() || width<=0) {
        [_activity removeAllAnimations]; return;
    }
    if ([_activity animationForKey:@"activity"] && _animationWidth==width) return;
    _animationWidth=width;
    CABasicAnimation *sweep=[CABasicAnimation animationWithKeyPath:@"position.x"];
    sweep.fromValue=@(-width*0.2); sweep.toValue=@(width*1.2);
    sweep.duration=1.3; sweep.repeatCount=HUGE_VALF;
    [_activity addAnimation:sweep forKey:@"activity"];
}
- (void)resumeActivity:(NSNotification *)notification {
    (void)notification;
    // iOS may remove animations during the handoff to the JIT helper. Recreate
    // them on return without resetting completed milestones.
    [_activity removeAllAnimations]; [self ensureActivity];
}
- (void)start {
    if (_running) return;
    _phase=TKLaunchPhaseConnection; _running=YES; self.hidden=NO;
    [self setNeedsLayout]; [self layoutIfNeeded];
    [self.superview layoutIfNeeded]; [self ensureActivity]; [CATransaction flush];
}
- (void)showPhase:(TKLaunchPhase)phase {
    if (phase>TKLaunchPhaseGame) return;
    if (!_running) [self start];
    if (phase<_phase) return;
    _phase=phase;
    [self updateAppearance]; [self ensureActivity]; [CATransaction flush];
}
- (NSString *)accessibilityValue {
    if (!_running) return @"Not running";
    return @[@"Connecting. 0 of 3 phases complete.",
             @"Preparing memory. 1 of 3 phases complete.",
             @"Loading game. 2 of 3 phases complete."][_phase];
}
- (void)stop {
    _running=NO; self.hidden=YES; [_activity removeAllAnimations];
}
- (void)dealloc { [NSNotificationCenter.defaultCenter removeObserver:self]; }
@end
