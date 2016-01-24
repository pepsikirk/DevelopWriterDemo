//
//  PKShortVideoViewController.m
//  DevelopWriterDemo
//
//  Created by jiangxincai on 16/1/14.
//  Copyright © 2016年 pepsikirk. All rights reserved.
//

#import "PKShortVideoViewController.h"
#import "PKShortVideoWriter.h"
#import "PKShortVideoProgressBar.h"
#import "PKUtiltiies.h"
#import <AVFoundation/AVFoundation.h>
#import "PKFullScreenPlayerViewController.h"

static CGFloat PKOtherButtonVarticalHeight = 0;
static CGFloat PKRecordButtonVarticalHeight = 0;
static CGFloat PKPreviewLayerHeight = 0;

static CGFloat const PKRecordButtonWidth = 90;

@interface PKShortVideoViewController()

@property (nonatomic, strong) NSURL *outputFileURL;
@property (nonatomic, assign) CGSize outputSize;

@property (nonatomic, assign) NSTimeInterval beginRecordTime;

@property (nonatomic, strong) UIButton *recordButton;
@property (nonatomic, strong) UIButton *refreshButton;
@property (nonatomic, strong) UIButton *playButton;

@property (nonatomic, strong) PKShortVideoProgressBar *progressBar;
@property (nonatomic, strong) PKShortVideoWriter *writer;

@end

@implementation PKShortVideoViewController

#pragma mark - Init 

- (instancetype)initWithOutputFileURL:(NSURL *)outputFileURL outputSize:(CGSize)outputSize {
    self = [super init];
    if (self) {
        _outputFileURL = outputFileURL;
        _outputSize = outputSize;
        _videoMaxTime = 6;
    }
    return self;
}



#pragma mark - LifeCycle

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    PKPreviewLayerHeight = 3/4.0 * kScreenWidth;
    CGFloat spaceHeight = (kScreenHeight - 44 - PKPreviewLayerHeight)/3;
    PKRecordButtonVarticalHeight = kScreenHeight - 2 * spaceHeight;
    PKOtherButtonVarticalHeight = kScreenHeight - spaceHeight;
    
    self.view.backgroundColor = [UIColor blackColor];
    
    UIToolbar *toolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, kScreenWidth, 44)];
    toolbar.barTintColor = [UIColor blackColor];
    toolbar.translucent = NO;
    [self.view addSubview:toolbar];
    UIBarButtonItem *cancelItem = [[UIBarButtonItem alloc] initWithTitle:@"取消" style:UIBarButtonItemStyleDone target:self action:@selector(cancelShoot)];
    cancelItem.tintColor = [UIColor whiteColor];
    
    UIBarButtonItem *flexible = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace target:self action:nil];
    
    UIBarButtonItem *transformItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCamera target:self action:@selector(transfromCamera)];
    
    [toolbar setItems:@[cancelItem,flexible,transformItem]];
    
    NSString *outputFileName = [NSProcessInfo processInfo].globallyUniqueString;
    NSString *outputFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:[outputFileName stringByAppendingPathExtension:@"mp4"]];
    
    self.writer = [[PKShortVideoWriter alloc] initWithOutputFileURL:[NSURL fileURLWithPath:outputFilePath] outputSize:CGSizeMake(320, 240)];
    
    AVCaptureVideoPreviewLayer *previewLayer = [self.writer previewLayer];
    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    previewLayer.frame = CGRectMake(0, 44, kScreenWidth, PKPreviewLayerHeight);
    [self.view.layer insertSublayer:previewLayer atIndex:0];
    
    self.recordButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.recordButton setTitle:@"按住录" forState:UIControlStateNormal];
    [self.recordButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.recordButton.titleLabel.font = [UIFont systemFontOfSize:15.0f];
    self.recordButton.frame = CGRectMake(0, 0, PKRecordButtonWidth, PKRecordButtonWidth);
    self.recordButton.center = CGPointMake(kScreenWidth/2, PKRecordButtonVarticalHeight);
    self.recordButton.layer.cornerRadius = PKRecordButtonWidth/2;
    self.recordButton.layer.borderWidth = 1;
    self.recordButton.layer.borderColor = [UIColor redColor].CGColor;
    self.recordButton.layer.masksToBounds = YES;
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
        [self.writer startRunning];
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
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)transfromCamera {
    
}

- (void)recordButtonTarget {
    [self.recordButton removeTarget:self action:NULL forControlEvents:UIControlEventAllEvents];
    [self.recordButton addTarget:self action:@selector(toggleRecording) forControlEvents:UIControlEventTouchDown];
    [self.recordButton addTarget:self action:@selector(buttonStopRecording) forControlEvents:UIControlEventTouchUpInside|UIControlEventTouchUpOutside];
}

- (void)sendButtonTarget {
    [self.recordButton removeTarget:self action:NULL forControlEvents:UIControlEventAllEvents];
    [self.recordButton addTarget:self action:@selector(sendVideo) forControlEvents:UIControlEventTouchUpInside];
    [self.refreshButton addTarget:self action:@selector(refreshView) forControlEvents:UIControlEventTouchUpInside];
    [self.playButton addTarget:self action:@selector(playVideo) forControlEvents:UIControlEventTouchUpInside];
}

- (void)refreshView {
    [[NSFileManager defaultManager] removeItemAtURL:self.outputFileURL error:nil];
    
    [self.recordButton setTitle:@"按住拍摄" forState:UIControlStateNormal];
    [self recordButtonTarget];
    [self.playButton removeFromSuperview];
    self.playButton = nil;
    [self.refreshButton removeFromSuperview];
    self.refreshButton = nil;
}

- (void)playVideo {
    PKFullScreenPlayerViewController *vc = [[PKFullScreenPlayerViewController alloc] initWithVideoURL:self.outputFileURL previewImage:nil];
    [self.navigationController pushViewController:vc animated:YES];
}

- (void)toggleRecording {

    [UIApplication sharedApplication].idleTimerDisabled = YES;
    
    self.beginRecordTime = [NSDate date].timeIntervalSince1970;

    [self.writer startRecording];
}

- (void)closeCamera {

    [_writer stopRecording];
}

- (void)buttonStopRecording {
    [self closeCamera];
}

- (void)sendVideo {

}

@end
