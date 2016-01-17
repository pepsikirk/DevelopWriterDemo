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

static CGFloat PKAllButtonVarticalHeight = 0;
static CGFloat PKPreviewLayerHeight = 0;

static CGFloat const PKRecordButtonWidth = 80;

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
    PKAllButtonVarticalHeight = kScreenHeight/2 + PKPreviewLayerHeight/2;
    
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
    previewLayer.frame = CGRectMake(0, 0, kScreenWidth, PKPreviewLayerHeight);
    [self.view.layer insertSublayer:previewLayer atIndex:0];
    
    self.recordButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.recordButton setTitle:@"按住录" forState:UIControlStateNormal];
    [self.recordButton setTitleColor:[UIColor redColor] forState:UIControlStateNormal];
    self.recordButton.titleLabel.font = [UIFont systemFontOfSize:15.0f];
    self.recordButton.frame = CGRectMake(0, 0, PKRecordButtonWidth, PKRecordButtonWidth);
    self.recordButton.center = CGPointMake(kScreenWidth/2, PKAllButtonVarticalHeight);
    self.recordButton.layer.cornerRadius = PKRecordButtonWidth/2;
    self.recordButton.layer.borderWidth = 1;
    self.recordButton.layer.borderColor = [UIColor redColor].CGColor;
    self.recordButton.layer.masksToBounds = YES;
    [self.view addSubview:self.recordButton];
    
    self.playButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.playButton setImage:[UIImage imageNamed:@"Play"] forState:UIControlStateNormal];
    [self.playButton sizeToFit];
    self.playButton.center = CGPointMake(kScreenWidth/4, PKAllButtonVarticalHeight);
    [self.view addSubview:self.playButton];
    
    self.refreshButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [self.refreshButton setImage:[UIImage imageNamed:@"Refresh"] forState:UIControlStateNormal];
    [self.refreshButton sizeToFit];
    self.refreshButton.center = CGPointMake(kScreenWidth/4 *3, PKAllButtonVarticalHeight);
    [self.view addSubview:self.refreshButton];
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

@end
