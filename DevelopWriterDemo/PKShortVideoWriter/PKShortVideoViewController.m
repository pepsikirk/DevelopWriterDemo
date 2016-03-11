//
//  PKShortVideoViewController.m
//  DevelopWriterDemo
//
//  Created by jiangxincai on 16/1/14.
//  Copyright © 2016年 pepsikirk. All rights reserved.
//

#import "PKShortVideoViewController.h"
#import "PKShortVideoRecorder.h"
#import "PKShortVideoProgressBar.h"
#import "PKUtiltiies.h"
#import <AVFoundation/AVFoundation.h>
#import "PKFullScreenPlayerViewController.h"

static CGFloat PKOtherButtonVarticalHeight = 0;
static CGFloat PKRecordButtonVarticalHeight = 0;
static CGFloat PKPreviewLayerHeight = 0;

static CGFloat const PKRecordButtonWidth = 90;

@interface PKShortVideoViewController() <PKShortVideoRecorderDelegate>

@property (nonatomic, strong) NSURL *outputFileURL;
@property (nonatomic, assign) CGSize outputSize;

@property (nonatomic, strong) UIColor *themeColor;

@property (nonatomic, assign) NSTimeInterval beginRecordTime;

@property (nonatomic, strong) UIButton *recordButton;
@property (nonatomic, strong) UIButton *refreshButton;
@property (nonatomic, strong) UIButton *playButton;

@property (nonatomic, strong) PKShortVideoProgressBar *progressBar;
@property (nonatomic, strong) PKShortVideoRecorder *recorder;

@end

@implementation PKShortVideoViewController

#pragma mark - Init 

- (instancetype)initWithOutputFileURL:(NSURL *)outputFileURL outputSize:(CGSize)outputSize themeColor:(UIColor *)themeColor {
    self = [super init];
    if (self) {
        _themeColor = themeColor;
        _outputFileURL = outputFileURL;
        _outputSize = outputSize;
        _videoDurationTime = 6;
    }
    return self;
}



#pragma mark - LifeCycle

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Do any additional setup after loading the view, typically from a nib.
    PKPreviewLayerHeight = ceilf(3/4.0 * kScreenWidth);
    CGFloat spaceHeight = ceilf( (kScreenHeight - 44 - PKPreviewLayerHeight)/3 );
    PKRecordButtonVarticalHeight = ceilf( kScreenHeight - 2 * spaceHeight );
    PKOtherButtonVarticalHeight = ceilf( kScreenHeight - spaceHeight );
    
    self.view.backgroundColor = [UIColor blackColor];
    
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, kScreenWidth, 44)];
    toolbar.barTintColor = [UIColor blackColor];
    toolbar.translucent = NO;
    [self.view addSubview:toolbar];
    UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStyleDone target:self action:@selector(cancelShoot)];
    cancelItem.tintColor = [UIColor whiteColor];
    
    UIBarButtonItem *flexible = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:self action:nil];
    
    UIBarButtonItem *transformItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"PK_Camera_turn"] style:UIBarButtonItemStyleDone target:self action:@selector(swapCamera)];
    transformItem.tintColor = [UIColor whiteColor];
    
    [toolbar setItems:@[cancelItem,flexible,transformItem]];
    
    NSString *outputFileName = [NSProcessInfo processInfo].globallyUniqueString;
    NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[outputFileName stringByAppendingPathExtension:@"mp4"]];
    
    self.recorder = [[PKShortVideoRecorder alloc] initWithOutputFileURL:[NSURL fileURLWithPath:outputFilePath] outputSize:CGSizeMake(320, 240)];
    self.recorder.delegate = self;
    
    AVCaptureVideoPreviewLayer *previewLayer = [self.recorder previewLayer];
    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    previewLayer.frame = CGRectMake(0, 44, kScreenWidth, PKPreviewLayerHeight);
    [self.view.layer insertSublayer:previewLayer atIndex:0];
    
    self.progressBar = [[PKShortVideoProgressBar alloc] initWithFrame:CGRectMake(0, 44 + PKPreviewLayerHeight - 5, kScreenWidth, 5) themeColor:self.themeColor duration:self.videoDurationTime];
    [self.view addSubview:self.progressBar];
    
    self.recordButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.recordButton setTitle:@"按住录" forState:UIControlStateNormal];
    [self.recordButton setTitleColor:self.themeColor forState:UIControlStateNormal];
    self.recordButton.titleLabel.font = [UIFont systemFontOfSize:17.0f];
    self.recordButton.frame = CGRectMake(0, 0, PKRecordButtonWidth, PKRecordButtonWidth);
    self.recordButton.center = CGPointMake(kScreenWidth/2, PKRecordButtonVarticalHeight);
    self.recordButton.layer.cornerRadius = PKRecordButtonWidth/2;
    self.recordButton.layer.borderWidth = 2;
    self.recordButton.layer.borderColor = self.themeColor.CGColor;
    self.recordButton.layer.masksToBounds = YES;
    [self recordButtonAction];
    [self.view addSubview:self.recordButton];
    
    self.playButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.playButton setImage:[UIImage imageNamed:@"PK_Play"] forState:UIControlStateNormal];
    [self.playButton sizeToFit];
    self.playButton.center = CGPointMake((kScreenWidth-PKRecordButtonWidth)/2/2, PKOtherButtonVarticalHeight);
    [self.view addSubview:self.playButton];
    
    self.refreshButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.refreshButton setImage:[UIImage imageNamed:@"PK_Delete"] forState:UIControlStateNormal];
    [self.refreshButton sizeToFit];
    self.refreshButton.center = CGPointMake(kScreenWidth-(kScreenWidth-PKRecordButtonWidth)/2/2, PKOtherButtonVarticalHeight);
    [self.view addSubview:self.refreshButton];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.recorder startRunning];
    });
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}



#pragma mark - Private 

- (void)cancelShoot {
    [self dismissViewControllerAnimated:YES completion:NULL];
}

- (void)swapCamera {
    [self.recorder swapFrontAndBackCameras];
}

- (void)recordButtonAction {
    [self.recordButton removeTarget:self action:NULL forControlEvents:UIControlEventAllEvents];
    [self.recordButton addTarget:self action:@selector(toggleRecording) forControlEvents:UIControlEventTouchDown];
    [self.recordButton addTarget:self action:@selector(buttonStopRecording) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
}

- (void)sendButtonAction  {
    [self.recordButton removeTarget:self action:NULL forControlEvents:UIControlEventAllEvents];
    [self.recordButton addTarget:self action:@selector(sendVideo) forControlEvents:UIControlEventTouchUpInside];
    [self.refreshButton addTarget:self action:@selector(refreshView) forControlEvents:UIControlEventTouchUpInside];
    [self.playButton addTarget:self action:@selector(playVideo) forControlEvents:UIControlEventTouchUpInside];
}

- (void)refreshView {
    [[NSFileManager defaultManager] removeItemAtURL:self.outputFileURL error:nil];
    
    [self.recordButton setTitle:@"按住拍摄" forState:UIControlStateNormal];
    [self recordButtonAction ];
    [self.playButton removeFromSuperview];
    self.playButton = nil;
    [self.refreshButton removeFromSuperview];
    self.refreshButton = nil;
    
    [self.progressBar restore];
}

- (void)playVideo {
    PKFullScreenPlayerViewController *vc = [[PKFullScreenPlayerViewController alloc] initWithVideoURL:self.outputFileURL previewImage:nil];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)toggleRecording {

    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    self.beginRecordTime = [NSDate date].timeIntervalSince1970;

    [self.recorder startRecording];
    
    [self.progressBar play];
}

- (void)closeCamera {

    [_recorder stopRecording];
}

- (void)buttonStopRecording {
    [self closeCamera];
    [self.progressBar stop];
}

- (void)sendVideo {

}

#pragma mark - PKShortVideoRecorderDelegate

- (void)recorderDidBeginRecording:(PKShortVideoRecorder *)recorder {
    
}

- (void)recorder:(PKShortVideoRecorder *)recorder didFinishRecordingToOutputFileURL:(NSURL *)outputFileURL error:(NSError *)error {
    
}

@end
