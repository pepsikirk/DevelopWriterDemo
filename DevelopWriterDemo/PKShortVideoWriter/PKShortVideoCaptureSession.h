//
//  PKShortVideoWriter.h
//  DevelopWriterDemo
//
//  Created by jiangxincai on 16/1/14.
//  Copyright © 2016年 pepsikirk. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class PKShortVideoCaptureSession;

@protocol PKShortVideoCaptureSessionDelegate <NSObject>

@required

- (void)sessionDidBeginRecording:(PKShortVideoCaptureSession *)session;
- (void)session:(PKShortVideoCaptureSession *)session didFinishRecordingToOutputFileURL:(NSURL *)outputFileURL error:(NSError *)error;

@end



@class AVCaptureVideoPreviewLayer;

@interface PKShortVideoCaptureSession : NSObject

@property (nonatomic, weak) id<PKShortVideoCaptureSessionDelegate> delegate;

- (instancetype)initWithOutputFileURL:(NSURL *)outputFileURL outputSize:(CGSize)outputSize;

- (void)startRunning;
- (void)stopRunning;

- (void)startRecording;
- (void)stopRecording;

- (void)swapFrontAndBackCameras;

- (AVCaptureVideoPreviewLayer *)previewLayer;

@end
