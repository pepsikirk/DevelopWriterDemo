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

@protocol PKShortVideoWriterDelegate;

@interface PKShortVideoWriter : NSObject

@property (nonatomic, weak) id<PKShortVideoWriterDelegate> delegate;

- (instancetype)initWithOutputFileURL:(NSURL *)outputFileURL;

- (void)addVideoTrackWithSourceFormatDescription:(CMFormatDescriptionRef)formatDescription settings:(NSDictionary *)videoSettings;
- (void)addAudioTrackWithSourceFormatDescription:(CMFormatDescriptionRef)formatDescription settings:(NSDictionary *)audioSettings;

- (void)appendVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer;
- (void)appendAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer;

- (void)prepareToRecord;
- (void)finishRecording;

@end


@protocol PKShortVideoWriterDelegate <NSObject>

- (void)writerDidFinishPreparing:(PKShortVideoWriter *)writer;
- (void)writer:(PKShortVideoWriter *)writer didFailWithError:(NSError *)error;
- (void)writerDidFinishRecording:(PKShortVideoWriter *)writer;

@end
