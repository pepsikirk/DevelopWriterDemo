//
//  PKAssetWriter.m
//  DevelopWriterDemo
//
//  Created by jiangxincai on 16/1/17.
//  Copyright © 2016年 pepsikirk. All rights reserved.
//

#import "PKShortVideoWriter.h"

typedef NS_ENUM(NSInteger, PKWriterStatus){
    PKWriterStatusIdle = 0,
    PKWriterStatusPreparingToRecord,
    PKWriterStatusRecording,
    PKWriterStatusFinishingRecordingPart1, // waiting for inflight buffers to be appended
    PKWriterStatusFinishingRecordingPart2, // calling finish writing on the asset writer
    PKWriterStatusFinished,
    PKWriterStatusFailed
};

@interface PKShortVideoWriter ()

@property (nonatomic, assign) PKWriterStatus status;

@property (nonatomic) dispatch_queue_t writingQueue;
@property (nonatomic) dispatch_queue_t delegateCallbackQueue;

@property (nonatomic) NSURL *outputFileURL;

@property (nonatomic) AVAssetWriter *assetWriter;
@property (nonatomic) BOOL haveStartedSession;

@property (nonatomic) CMFormatDescriptionRef audioTrackSourceFormatDescription;
@property (nonatomic) CMFormatDescriptionRef videoTrackSourceFormatDescription;

@property (nonatomic) NSDictionary *audioTrackSettings;
@property (nonatomic) NSDictionary *videoTrackSettings;

@property (nonatomic) AVAssetWriterInput *audioInput;
@property (nonatomic) AVAssetWriterInput *videoInput;

@property (nonatomic) CGAffineTransform videoTrackTransform;

@end

@implementation PKShortVideoWriter


- (instancetype)initWithOutputFileURL:(NSURL *)outputFileURL {
    if (!outputFileURL) {
        return nil;
    }
    
    self = [super init];
    if (self) {
        _delegateCallbackQueue = dispatch_queue_create( "com.PKShortVideoWriter.writerDelegateCallback", DISPATCH_QUEUE_SERIAL );
        _writingQueue = dispatch_queue_create( "com.PKShortVideoWriter.assetwriter", DISPATCH_QUEUE_SERIAL );
        
        _videoTrackTransform = CGAffineTransformMakeRotation(M_PI_2); //portrait orientation
        _outputFileURL = outputFileURL;
    }
    return self;
}

- (void)addVideoTrackWithSourceFormatDescription:(CMFormatDescriptionRef)formatDescription settings:(NSDictionary *)videoSettings {
    if (formatDescription == NULL){
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"NULL format description" userInfo:nil];
        return;
    }
    @synchronized(self) {
        if (self.status != PKWriterStatusIdle){
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Cannot add tracks while not idle" userInfo:nil];
            return;
        }
        
        if(self.videoTrackSourceFormatDescription ){
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Cannot add more than one video track" userInfo:nil];
            return;
        }
        
        self.videoTrackSourceFormatDescription = (CMFormatDescriptionRef)CFRetain( formatDescription );
        self.videoTrackSettings = [videoSettings copy];
    }
}

- (void)addAudioTrackWithSourceFormatDescription:(CMFormatDescriptionRef)formatDescription settings:(NSDictionary *)audioSettings {
    if (formatDescription == NULL) {
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"NULL format description" userInfo:nil];
        return;
    }
    
    @synchronized(self) {
        if (self.status != PKWriterStatusIdle) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Cannot add tracks while not idle" userInfo:nil];
            return;
        }
        
        if (self.audioTrackSourceFormatDescription) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Cannot add more than one audio track" userInfo:nil];
            return;
        }
        
        self.audioTrackSourceFormatDescription = (CMFormatDescriptionRef)CFRetain(formatDescription);
        self.audioTrackSettings = [audioSettings copy];
    }
}

- (void)prepareToRecord {
    @synchronized(self) {
        if (self.status != PKWriterStatusIdle){
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Already prepared, cannot prepare again" userInfo:nil];
            return;
        }
        [self transitionToStatus:PKWriterStatusPreparingToRecord error:nil];
    }
    
    dispatch_async( dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_LOW, 0 ), ^{
        @autoreleasepool {
            NSError *error = nil;
            // AVAssetWriter will not write over an existing file.
            [[NSFileManager defaultManager] removeItemAtURL:self.outputFileURL error:NULL];
            self.assetWriter = [[AVAssetWriter alloc] initWithURL:self.outputFileURL fileType:AVFileTypeMPEG4 error:&error];
            
            // Create and add inputs
            if (!error && self.videoTrackSourceFormatDescription) {
                [self setupAssetWriterVideoInputWithSourceFormatDescription:self.videoTrackSourceFormatDescription transform:self.videoTrackTransform settings:self.videoTrackSettings error:&error];
            }
            if(!error && _audioTrackSourceFormatDescription) {
                [self setupAssetWriterAudioInputWithSourceFormatDescription:self.audioTrackSourceFormatDescription settings:self.audioTrackSettings error:&error];
            }
            if(!error) {
                BOOL success = [self.assetWriter startWriting];
                if (!success) {
                    error = self.assetWriter.error;
                }
            }
            
            @synchronized(self) {
                if (error) {
                    [self transitionToStatus:PKWriterStatusFailed error:error];
                } else {
                    [self transitionToStatus:PKWriterStatusRecording error:nil];
                }
            }
        }
    } );
}

- (void)appendVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    [self appendSampleBuffer:sampleBuffer ofMediaType:AVMediaTypeVideo];
}

- (void)appendAudioSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    [self appendSampleBuffer:sampleBuffer ofMediaType:AVMediaTypeAudio];
}

- (void)finishRecording {
    @synchronized(self) {
        BOOL shouldFinishRecording = NO;
        switch (self.status) {
            case PKWriterStatusIdle:
            case PKWriterStatusPreparingToRecord:
            case PKWriterStatusFinishingRecordingPart1:
            case PKWriterStatusFinishingRecordingPart2:
            case PKWriterStatusFinished:
                @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Not recording" userInfo:nil];
                break;
            case PKWriterStatusFailed:
                // From the client's perspective the movie recorder can asynchronously transition to an error state as the result of an append.
                // Because of this we are lenient when finishRecording is called and we are in an error state.
                NSLog( @"Recording has failed, nothing to do" );
                break;
            case PKWriterStatusRecording:
                shouldFinishRecording = YES;
                break;
        }
        
        if (shouldFinishRecording){
            [self transitionToStatus:PKWriterStatusFinishingRecordingPart1 error:nil];
        }
        else {
            return;
        }
    }
    
    dispatch_async( _writingQueue, ^{
        @autoreleasepool {
            @synchronized(self) {
                // We may have transitioned to an error state as we appended inflight buffers. In that case there is nothing to do now.
                if (self.status != PKWriterStatusFinishingRecordingPart1) {
                    return;
                }
                
                // It is not safe to call -[AVAssetWriter finishWriting*] concurrently with -[AVAssetWriterInput appendSampleBuffer:]
                // We transition to MovieRecorderStatusFinishingRecordingPart2 while on _writingQueue, which guarantees that no more buffers will be appended.
                [self transitionToStatus:PKWriterStatusFinishingRecordingPart2 error:nil];
            }
            [self.assetWriter finishWritingWithCompletionHandler:^{
                @synchronized(self) {
                    NSError *error = self.assetWriter.error;
                    if(error){
                        [self transitionToStatus:PKWriterStatusFailed error:error];
                    }
                    else {
                        [self transitionToStatus:PKWriterStatusFinished error:nil];
                    }
                }
            }];
        }
    } );
}


#pragma mark - Private methods

- (BOOL)setupAssetWriterAudioInputWithSourceFormatDescription:(CMFormatDescriptionRef)audioFormatDescription settings:(NSDictionary *)audioSettings error:(NSError **)errorOut {
    if (!audioSettings) {
        audioSettings = @{ AVFormatIDKey : @(kAudioFormatMPEG4AAC) };
    }
    
    if ( [self.assetWriter canApplyOutputSettings:audioSettings forMediaType:AVMediaTypeAudio] ){
        self.audioInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio outputSettings:audioSettings sourceFormatHint:audioFormatDescription];
        self.audioInput.expectsMediaDataInRealTime = YES;
        
        if ([self.assetWriter canAddInput:self.audioInput]){
            [self.assetWriter addInput:self.audioInput];
        } else {
            if (errorOut ) {
                *errorOut = [self cannotSetupInputError];
            }
            return NO;
        }
    }
    else {
        if (errorOut) {
            *errorOut = [self cannotSetupInputError];
        }
        return NO;
    }
    
    return YES;
}

- (BOOL)setupAssetWriterVideoInputWithSourceFormatDescription:(CMFormatDescriptionRef)videoFormatDescription transform:(CGAffineTransform)transform settings:(NSDictionary *)videoSettings error:(NSError **)errorOut {
    if (!videoSettings){
        videoSettings = [self fallbackVideoSettingsForSourceFormatDescription:videoFormatDescription];
    }
    
    if ([self.assetWriter canApplyOutputSettings:videoSettings forMediaType:AVMediaTypeVideo]){
        self.videoInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeVideo outputSettings:videoSettings sourceFormatHint:videoFormatDescription];
        self.videoInput.expectsMediaDataInRealTime = YES;
        self.videoInput.transform = transform;
        
        if ([self.assetWriter canAddInput:self.videoInput]){
            [self.assetWriter addInput:self.videoInput];
        } else {
            if ( errorOut ) {
                *errorOut = [self cannotSetupInputError];
            }
            return NO;
        }
    } else {
        if ( errorOut ) {
            *errorOut = [self cannotSetupInputError];
        }
        return NO;
    }
    return YES;
}

- (NSDictionary *)fallbackVideoSettingsForSourceFormatDescription:(CMFormatDescriptionRef)videoFormatDescription {
    float bitsPerPixel;
    CMVideoDimensions dimensions = CMVideoFormatDescriptionGetDimensions(videoFormatDescription);
    int numPixels = dimensions.width * dimensions.height;
    int bitsPerSecond;
    
    NSLog( @"No video settings provided, using default settings" );
    
    // Assume that lower-than-SD resolutions are intended for streaming, and use a lower bitrate
    if ( numPixels < ( 640 * 480 ) ) {
        bitsPerPixel = 4.05; // This bitrate approximately matches the quality produced by AVCaptureSessionPresetMedium or Low.
    }
    else {
        bitsPerPixel = 10.1; // This bitrate approximately matches the quality produced by AVCaptureSessionPresetHigh.
    }
    
    bitsPerSecond = numPixels * bitsPerPixel;
    
    NSDictionary *compressionProperties = @{ AVVideoAverageBitRateKey : @(bitsPerSecond),
                                             AVVideoExpectedSourceFrameRateKey : @(30),
                                             AVVideoMaxKeyFrameIntervalKey : @(30) };
    
    return @{ AVVideoCodecKey : AVVideoCodecH264,
                       AVVideoWidthKey : @(dimensions.width),
                       AVVideoHeightKey : @(dimensions.height),
                       AVVideoCompressionPropertiesKey : compressionProperties };

}

- (void)appendSampleBuffer:(CMSampleBufferRef)sampleBuffer ofMediaType:(NSString *)mediaType {
    if(sampleBuffer == NULL){
        @throw [NSException exceptionWithName:NSInvalidArgumentException reason:@"NULL sample buffer" userInfo:nil];
        return;
    }
    
    @synchronized(self){
        if (self.status < PKWriterStatusRecording){
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Not ready to record yet" userInfo:nil];
            return;
        }
    }
    
    CFRetain(sampleBuffer);
    dispatch_async( self.writingQueue, ^{
        @autoreleasepool {
            @synchronized(self) {
                // From the client's perspective the movie recorder can asynchronously transition to an error state as the result of an append.
                // Because of this we are lenient when samples are appended and we are no longer recording.
                // Instead of throwing an exception we just release the sample buffers and return.
                if (self.status > PKWriterStatusFinishingRecordingPart1){
                    CFRelease(sampleBuffer);
                    return;
                }
            }
            
            if(!self.haveStartedSession && mediaType == AVMediaTypeVideo) {
                [self.assetWriter startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
                self.haveStartedSession = YES;
            }
            
            AVAssetWriterInput *input = ( mediaType == AVMediaTypeVideo ) ? self.videoInput : self.audioInput;
            
            if(input.readyForMoreMediaData){
                BOOL success = [input appendSampleBuffer:sampleBuffer];
                if (!success){
                    NSError *error = self.assetWriter.error;
                    @synchronized(self){
                        [self transitionToStatus:PKWriterStatusFailed error:error];
                    }
                }
            } else {
                NSLog( @"%@ input not ready for more media data, dropping buffer", mediaType );
            }
            CFRelease(sampleBuffer);
        }
    } );
}

- (void)transitionToStatus:(PKWriterStatus)newStatus error:(NSError *)error {
    BOOL shouldNotifyDelegate = NO;
    
    if (newStatus != self.status){
        if ((newStatus == PKWriterStatusFinished) || (newStatus == PKWriterStatusFailed)){
            shouldNotifyDelegate = YES;
            
            dispatch_async(self.writingQueue, ^{
                self.assetWriter = nil;
                self.videoInput = nil;
                self.audioInput = nil;
                if (newStatus == PKWriterStatusFailed) {//失败删除
                    [[NSFileManager defaultManager] removeItemAtURL:self.outputFileURL error:NULL];
                }
            } );
        } else if (newStatus == PKWriterStatusRecording){
            shouldNotifyDelegate = YES;
        }
        self.status = newStatus;
    }
    
    if (shouldNotifyDelegate && self.delegate){
        dispatch_async( self.delegateCallbackQueue, ^{
            
            @autoreleasepool {
                switch(newStatus){
                    case PKWriterStatusRecording:
                        [self.delegate writerDidFinishPreparing:self];
                        break;
                    case PKWriterStatusFinished:
                        [self.delegate writerDidFinishRecording:self];
                        break;
                    case PKWriterStatusFailed:
                        [self.delegate writer:self didFailWithError:error];
                        break;
                    default:
                        break;
                }
            }
        });
    }
}

- (NSError *)cannotSetupInputError {
    NSDictionary *errorDict = @{ NSLocalizedDescriptionKey : @"Recording cannot be started",
                                 NSLocalizedFailureReasonErrorKey : @"Cannot setup asset writer input." };
    return [NSError errorWithDomain:@"com.PKShortVideoWriter" code:0 userInfo:errorDict];
}

@end
