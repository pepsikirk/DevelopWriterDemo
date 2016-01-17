//
//  PKShortVideoWriter.h
//  DevelopWriterDemo
//
//  Created by jiangxincai on 16/1/14.
//  Copyright © 2016年 pepsikirk. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class PKShortVideoWriter;

@protocol PKShortWriterDelegate <NSObject>

@required

- (void)writerDidBeginRecording:(PKShortVideoWriter *)writer;
- (void)writer:(PKShortVideoWriter *)writer didFinishRecordingToOutputFileURL:(NSURL *)outputFileURL error:(NSError *)error;

@end



@class AVCaptureVideoPreviewLayer;

@interface PKShortVideoWriter : NSObject

@property (nonatomic, weak) id<PKShortWriterDelegate> delegate;

- (instancetype)initWithOutputFileURL:(NSURL *)outputFileURL outputSize:(CGSize)outputSize;

- (void)startRunning;
- (void)stopRunning;

- (void)startRecording;
- (void)stopRecording;

- (AVCaptureVideoPreviewLayer *)previewLayer;

@end
