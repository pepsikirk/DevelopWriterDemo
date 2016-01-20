//
//  PKAssetWriter.h
//  DevelopWriterDemo
//
//  Created by jiangxincai on 16/1/17.
//  Copyright © 2016年 pepsikirk. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>
#import <AVFoundation/AVFoundation.h>

@protocol PKAssetWriterDelegate;

@interface PKAssetWriter : NSObject

@property (nonatomic, weak) id<PKAssetWriterDelegate> delegate;

- (instancetype)initWithURL:(NSURL *)URL;
- (void)addVideoTrackWithSourceFormatDescription:(CMFormatDescriptionRef)formatDescription settings:(NSDictionary *)videoSettings;
- (void)addAudioTrackWithSourceFormatDescription:(CMFormatDescriptionRef)formatDescription settings:(NSDictionary *)audioSettings;

- (void)prepareToRecord;
- (void)appendVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)appendAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)finishRecording;

@end


@protocol PKAssetWriterDelegate <NSObject>

- (void)writerDidFinishPreparing:(PKAssetWriter *)writer;
- (void)writer:(PKAssetWriter *)writer didFailWithError:(NSError *)error;
- (void)writerDidFinishRecording:(PKAssetWriter *)writer;

@end
