//
//  PKShortVideoWriter.h
//  DevelopWriterDemo
//
//  Created by jiangxincai on 16/1/14.
//  Copyright © 2016年 pepsikirk. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class PKShortVideoRecorder;

@protocol PKShortVideoRecorderDelegate <NSObject>

@required

- (void)recorderDidBeginRecording:(PKShortVideoRecorder *)recorder;
- (void)recorderDidEndRecording:(PKShortVideoRecorder *)recorder;
- (void)recorder:(PKShortVideoRecorder *)recorder didFinishRecordingToOutputFilePath:(NSString *)outputFilePath error:(NSError *)error;

@end



@class AVCaptureVideoPreviewLayer;

@interface PKShortVideoRecorder : NSObject

@property (nonatomic, weak) id<PKShortVideoRecorderDelegate> delegate;

- (instancetype)initWithOutputFilePath:(NSString *)outputFilePath outputSize:(CGSize)outputSize;

- (void)startRunning;
- (void)stopRunning;

- (void)startRecording;
- (void)stopRecording;

- (void)swapFrontAndBackCameras;

- (AVCaptureVideoPreviewLayer *)previewLayer;

@end
