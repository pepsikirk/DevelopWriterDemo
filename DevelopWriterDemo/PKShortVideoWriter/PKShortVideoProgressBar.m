//
//  PKShortVideoProgressBar.m
//  DevelopWriterDemo
//
//  Created by jiangxincai on 16/1/15.
//  Copyright © 2016年 pepsikirk. All rights reserved.
//

#import "PKShortVideoProgressBar.h"

static NSInteger const PKProgressItemWidth = 5;

@interface PKShortVideoProgressBar ()

@property (nonatomic, assign) NSTimeInterval duration;

@property (nonatomic, strong) UIColor *themeColor;

@property (strong, nonatomic) UIView *progressItem;
@property (strong, nonatomic) UIView *progressingView;

@end

@implementation PKShortVideoProgressBar

#pragma mark - Public

- (instancetype)initWithFrame:(CGRect)frame themeColor:(UIColor *)themeColor duration:(NSTimeInterval)duration {
    self = [super initWithFrame:frame];
    if (self) {
        _themeColor = themeColor;
        _duration = duration;
        
        self.backgroundColor = [UIColor blackColor];
        self.alpha = 0.4f;
        
        _progressItem = [[UIView alloc] initWithFrame:CGRectMake(0, 0, PKProgressItemWidth, frame.size.height)];
        _progressItem.backgroundColor = [UIColor whiteColor];
        [self addSubview:_progressItem];
        _progressingView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, frame.size.height)];
        _progressingView.backgroundColor = themeColor;
        [self addSubview:_progressingView];
    }
    return self;
}

- (void)play {
    [UIView animateWithDuration:self.duration delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
        self.progressItem.frame = CGRectMake(self.bounds.size.width - PKProgressItemWidth, 0, PKProgressItemWidth, self.bounds.size.height);
        self.progressingView.frame = CGRectMake(0, 0, self.bounds.size.width - PKProgressItemWidth, self.bounds.size.height);
    } completion:NULL];
}

- (void)stop {
    [PKShortVideoProgressBar pauseLayer:self.progressItem.layer];
    [PKShortVideoProgressBar pauseLayer:self.progressingView.layer];
}

- (void)restore {
    [PKShortVideoProgressBar restoreLayer:self.progressItem.layer];
    [PKShortVideoProgressBar restoreLayer:self.progressingView.layer];
}



#pragma mark - Private

//暂停layer上面的动画
+ (void)pauseLayer:(CALayer*)layer {
    CFTimeInterval pausedTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil];
    layer.speed = 0.0;
    layer.timeOffset = pausedTime;
}

+ (void)restoreLayer:(CALayer *)layer {
    layer.speed = 1.0;
    layer.timeOffset = 0.0;
    [layer removeAllAnimations];
}

//继续layer上面的动画
+ (void)resumeLayer:(CALayer*)layer {
    CFTimeInterval pausedTime = [layer timeOffset];
    layer.speed = 1.0;
    layer.timeOffset = 0.0;
    layer.beginTime = 0.0;
    CFTimeInterval timeSincePause = [layer convertTime:CACurrentMediaTime() fromLayer:nil] - pausedTime;
    layer.beginTime = timeSincePause;
}

@end
