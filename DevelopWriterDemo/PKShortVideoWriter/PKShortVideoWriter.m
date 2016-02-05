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
        
        _videoTrackTransform = CGAffineTransformMakeRotation(M_PI_2);//人像方向
        _outputFileURL = outputFileURL;
    }
    return self;
}


#pragma mark - Public

- (void)addVideoTrackWithSourceFormatDescription:(CMFormatDescriptionRef)formatDescription settings:(NSDictionary *)videoSettings {
    if (formatDescription == NULL){
        NSLog(@"formatDescription 不能为空");
        return;
    }
    
    @synchronized(self) {
        if (self.status != PKWriterStatusIdle){
            NSLog(@"当状态不是限制时不能修改");
            return;
        }
        
        if (self.videoTrackSourceFormatDescription ){
            NSLog(@"videoTrackSourceFormatDescription 已经有值");
            return;
        }
        
        self.videoTrackSourceFormatDescription = (CMFormatDescriptionRef)CFRetain( formatDescription );
        self.videoTrackSettings = [videoSettings copy];
    }
}

- (void)addAudioTrackWithSourceFormatDescription:(CMFormatDescriptionRef)formatDescription settings:(NSDictionary *)audioSettings {
    if (formatDescription == NULL){
        NSLog(@"formatDescription 不能为空");
        return;
    }
    
    @synchronized(self) {
        if (self.status != PKWriterStatusIdle) {
            NSLog(@"当状态不是限制时不能修改");
            return;
        }
        
        if (self.audioTrackSourceFormatDescription) {
            NSLog(@"audioTrackSourceFormatDescription 已经有值");
            return;
        }
        
        self.audioTrackSourceFormatDescription = (CMFormatDescriptionRef)CFRetain(formatDescription);
        self.audioTrackSettings = [audioSettings copy];
    }
}

- (void)prepareToRecord {
    @synchronized(self) {
        if (self.status != PKWriterStatusIdle){
            NSLog(@"已经开始准备不需要再准备");
            return;
        }
        [self transitionToStatus:PKWriterStatusPreparingToRecord error:nil];
    }
    
    dispatch_async( dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_LOW, 0 ), ^{
        @autoreleasepool {
            NSError *error = nil;
            [[NSFileManager defaultManager] removeItemAtURL:self.outputFileURL error:NULL];
            self.assetWriter = [[AVAssetWriter alloc] initWithURL:self.outputFileURL fileType:AVFileTypeMPEG4 error:&error];
            
            //创建和添加输入
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
                NSLog(@"还没有开始记录");
                break;
            case PKWriterStatusFailed:
                NSLog( @"记录失败" );
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
                if (self.status != PKWriterStatusFinishingRecordingPart1) {
                    return;
                }
                
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
    dispatch_async(self.writingQueue, ^{
        @autoreleasepool {
            @synchronized(self) {
                if (self.status > PKWriterStatusFinishingRecordingPart1){
                    CFRelease(sampleBuffer);
                    return;
                }
            }
            
            if(!self.haveStartedSession && mediaType == AVMediaTypeVideo) {
                [self.assetWriter startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
                self.haveStartedSession = YES;
            }
            
            AVAssetWriterInput *input = (mediaType == AVMediaTypeVideo) ? self.videoInput : self.audioInput;
            
            if(input.readyForMoreMediaData){
                BOOL success = [input appendSampleBuffer:sampleBuffer];
                if (!success){
                    NSError *error = self.assetWriter.error;
                    @synchronized(self){
                        [self transitionToStatus:PKWriterStatusFailed error:error];
                    }
                }
            } else {
                NSLog( @"%@ 输入不能添加更多数据了抛弃 buffer", mediaType );
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
    NSDictionary *errorDict = @{ NSLocalizedDescriptionKey : @"记录不能开始",
                                 NSLocalizedFailureReasonErrorKey : @"不能初始化writer" };
    return [NSError errorWithDomain:@"com.PKShortVideoWriter" code:0 userInfo:errorDict];
}

@end
