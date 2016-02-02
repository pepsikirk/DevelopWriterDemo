//
//  PKShortVideoWriter.m
//  DevelopWriterDemo
//
//  Created by jiangxincai on 16/1/14.
//  Copyright © 2016年 pepsikirk. All rights reserved.
//

#import "PKShortVideoCaptureSession.h"
#import <AVFoundation/AVFoundation.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import "PKShortVideoWriter.h"

typedef NS_ENUM( NSInteger, PKRecordingStatus ) {
    PKRecordingStatusIdle = 0,
    PKRecordingStatusStartingRecording,
    PKRecordingStatusRecording,
    PKRecordingStatusStoppingRecording,
}; 

@interface PKShortVideoCaptureSession() <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, PKShortVideoWriterDelegate>

@property (nonatomic, strong) NSURL *outputFileURL;
@property (nonatomic, assign) CGSize outputSize;

@property (nonatomic, strong) dispatch_queue_t sessionQueue;

@property (nonatomic, strong) dispatch_queue_t videoDataOutputQueue;
@property (nonatomic, strong) dispatch_queue_t audioDataOutputQueue;

@property (nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
@property (nonatomic, strong) AVCaptureAudioDataOutput *audioDataOutput;

@property (nonatomic, strong) AVCaptureConnection *audioConnection;
@property (nonatomic, strong) AVCaptureConnection *videoConnection;

@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureDevice *cameraDevice;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;

@property (nonatomic, strong) NSDictionary *videoCompressionSettings;
@property (nonatomic, strong) NSDictionary *audioCompressionSettings;
@property(nonatomic, retain) __attribute__((NSObject)) CMFormatDescriptionRef outputVideoFormatDescription;
@property(nonatomic, retain) __attribute__((NSObject)) CMFormatDescriptionRef outputAudioFormatDescription;

@property (nonatomic, assign) PKRecordingStatus recordingStatus;

@property(nonatomic, retain) PKShortVideoWriter *assetWriter;

@end

@implementation PKShortVideoCaptureSession

#pragma mark - Init

- (instancetype)initWithOutputFileURL:(NSURL *)outputFileURL outputSize:(CGSize)outputSize {
    self = [super init];
    if (self) {
        _outputFileURL = outputFileURL;
        _outputSize = outputSize;
        
        _sessionQueue = dispatch_queue_create( "com.PKShortVideoWriter.sessionQueue", DISPATCH_QUEUE_SERIAL );
        
        _audioDataOutputQueue = dispatch_queue_create( "com.PKShortVideoWriter.audioOutput", DISPATCH_QUEUE_SERIAL );

        _videoDataOutputQueue = dispatch_queue_create( "com.PKShortVideoWriter.videoOutput", DISPATCH_QUEUE_SERIAL );
        dispatch_set_target_queue( _videoDataOutputQueue, dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_HIGH, 0 ) );
        
        _captureSession = [self setupCaptureSession];
        [self addDataOutputsToCaptureSession:self.captureSession];
    }
    return self;
}



#pragma mark - Running Session

- (void)startRunning {
    dispatch_sync( self.sessionQueue, ^{
        [self.captureSession startRunning];
    } );
}

- (void)stopRunning {
    dispatch_sync( self.sessionQueue, ^{
        [self stopRecording];
        [self.captureSession stopRunning];
    } );
}



#pragma mark - Recording

- (void)startRecording {
    @synchronized(self) {
        if(self.recordingStatus != PKRecordingStatusIdle) {
            return;
        }
        [self transitionToRecordingStatus:PKRecordingStatusStartingRecording error:nil];
    }
    
    self.assetWriter = [[PKShortVideoWriter alloc] initWithOutputFileURL:self.outputFileURL];
    if(self.outputAudioFormatDescription != nil){
        [self.assetWriter addAudioTrackWithSourceFormatDescription:self.outputAudioFormatDescription settings:self.audioCompressionSettings];
    }
    [self.assetWriter addVideoTrackWithSourceFormatDescription:self.outputVideoFormatDescription settings:self.videoCompressionSettings];
    self.assetWriter.delegate = self;
    [self.assetWriter prepareToRecord];
}

- (void)stopRecording {
    @synchronized(self) {
        if (self.recordingStatus != PKRecordingStatusRecording){
            return;
        }
        [self transitionToRecordingStatus:PKRecordingStatusStoppingRecording error:nil];
    }
    [self.assetWriter finishRecording];
}



#pragma mark - SwapCamera

- (void)swapFrontAndBackCameras {
    NSArray *inputs = self.captureSession.inputs;
    for ( AVCaptureDeviceInput *input in inputs ) {
        AVCaptureDevice *device = input.device;
        if ( [device hasMediaType:AVMediaTypeVideo] ) {
            AVCaptureDevicePosition position = device.position;
            AVCaptureDevice *newCamera = nil;
            AVCaptureDeviceInput *newInput = nil;
            
            if (position == AVCaptureDevicePositionFront)
                newCamera = [self cameraWithPosition:AVCaptureDevicePositionBack];
            else
                newCamera = [self cameraWithPosition:AVCaptureDevicePositionFront];
            newInput = [AVCaptureDeviceInput deviceInputWithDevice:newCamera error:nil];
            
            // beginConfiguration 确保改变不会立刻应用
            [self.captureSession beginConfiguration];
            
            [self.captureSession removeInput:input];
            [self.captureSession addInput:newInput];
            
            // 开始生效
            [self.captureSession commitConfiguration];
            break;
        }
    }
}



#pragma mark - Private methods

- (void)addDataOutputsToCaptureSession:(AVCaptureSession *)captureSession {
    self.videoDataOutput = [AVCaptureVideoDataOutput new];
    self.videoDataOutput.videoSettings = nil;
    self.videoDataOutput.alwaysDiscardsLateVideoFrames = NO;
    
    [self.videoDataOutput setSampleBufferDelegate:self queue:self.videoDataOutputQueue];
    
    self.audioDataOutput = [AVCaptureAudioDataOutput new];
    [self.audioDataOutput setSampleBufferDelegate:self queue:self.audioDataOutputQueue];
    
    [self addOutput:self.videoDataOutput toCaptureSession:self.captureSession];
    self.videoConnection = [self.videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    
    [self addOutput:self.audioDataOutput toCaptureSession:self.captureSession];
    self.audioConnection = [self.audioDataOutput connectionWithMediaType:AVMediaTypeAudio];
    
    [self setCompressionSettings];
}

- (void)setCompressionSettings {
    NSInteger numPixels = self.outputSize.width * self.outputSize.height;
    NSInteger bitsPerPixel = 6.0;
    NSInteger bitsPerSecond = numPixels * bitsPerPixel;
    
    // 码率和帧率设置
    NSDictionary *compressionProperties = @{ AVVideoAverageBitRateKey : @(bitsPerSecond),
                                    AVVideoExpectedSourceFrameRateKey : @(30),
                                        AVVideoMaxKeyFrameIntervalKey : @(30) };
    
    self.videoCompressionSettings = @{ AVVideoCodecKey : AVVideoCodecH264,
                                       AVVideoWidthKey : @(self.outputSize.width),
                                      AVVideoHeightKey : @(self.outputSize.height),
                       AVVideoCompressionPropertiesKey : compressionProperties };
    
    // 音频设置
    self.audioCompressionSettings = @{ AVEncoderBitRatePerChannelKey : @(28000),
                                   AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                   AVNumberOfChannelsKey : @(1),
                                   AVSampleRateKey : @(22050) };
}

#pragma mark - SampleBufferDelegate methods

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    
    if (connection == self.videoConnection){
        if (self.outputVideoFormatDescription == nil) {
            //不渲染首帧
            self.outputVideoFormatDescription = formatDescription;
        } else {
            self.outputVideoFormatDescription = formatDescription;
            @synchronized(self) {
                if(self.recordingStatus == PKRecordingStatusRecording){
                    [self.assetWriter appendVideoSampleBuffer:sampleBuffer];
                }
            }
        }
    } else if ( connection == self.audioConnection ){
        self.outputAudioFormatDescription = formatDescription;
        @synchronized( self ) {
            if(self.recordingStatus == PKRecordingStatusRecording){
                [self.assetWriter appendAudioSampleBuffer:sampleBuffer];
            }
        }
    }
}

#pragma mark - PKAssetWriterDelegate methods

- (void)writerDidFinishPreparing:(PKShortVideoCaptureSession *)writer {
    @synchronized(self) {
        if(self.recordingStatus != PKRecordingStatusStartingRecording){
            return;
        }
        [self transitionToRecordingStatus:PKRecordingStatusRecording error:nil];
    }
}

- (void)writer:(PKShortVideoCaptureSession *)writer didFailWithError:(NSError *)error {
    @synchronized( self ) {
        self.assetWriter = nil;
        [self transitionToRecordingStatus:PKRecordingStatusIdle error:error];
    }
}

- (void)writerDidFinishRecording:(PKShortVideoCaptureSession *)writer {
    @synchronized( self ) {
        if ( self.recordingStatus != PKRecordingStatusStoppingRecording ) {
            return;
        }
    }
    self.assetWriter = nil;
    
    @synchronized( self ) {
        [self transitionToRecordingStatus:PKRecordingStatusIdle error:nil];
    }
}


#pragma mark - Recording State Machine

- (void)transitionToRecordingStatus:(PKRecordingStatus)newStatus error:(NSError *)error {
    PKRecordingStatus oldStatus = self.recordingStatus;
    self.recordingStatus = newStatus;
    
    if (newStatus != oldStatus){
        if (error && (newStatus == PKRecordingStatusIdle)){
            dispatch_async( dispatch_get_main_queue(), ^{
                @autoreleasepool {
                    [self.delegate session:self didFinishRecordingToOutputFileURL:self.outputFileURL error:error];
                }
            });
        } else {
            error = nil;
            if (oldStatus == PKRecordingStatusStartingRecording && newStatus == PKRecordingStatusRecording){
                dispatch_async( dispatch_get_main_queue(), ^{
                    @autoreleasepool {
                        [self.delegate sessionDidBeginRecording:self];
                    }
                });
            } else if (oldStatus == PKRecordingStatusStoppingRecording && newStatus == PKRecordingStatusIdle) {
                dispatch_async( dispatch_get_main_queue(), ^{
                    @autoreleasepool {
                        [self.delegate session:self didFinishRecordingToOutputFileURL:self.outputFileURL error:nil];
                    }
                });
            }
        }
    }
}


#pragma mark - Capture Session Setup


- (AVCaptureSession *)setupCaptureSession {
    AVCaptureSession *captureSession = [AVCaptureSession new];
    captureSession.sessionPreset = AVCaptureSessionPresetMedium;
    
    if (![self addDefaultCameraInputToCaptureSession:captureSession]){
        NSLog(@"加载摄像头失败");
    }
    if (![self addDefaultMicInputToCaptureSession:captureSession]){
        NSLog(@"加载麦克风失败");
    }
    
    return captureSession;
}

- (BOOL)addDefaultCameraInputToCaptureSession:(AVCaptureSession *)captureSession {
    NSError *error;
    AVCaptureDeviceInput *cameraDeviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] error:&error];
    
    if (error) {
        NSLog(@"配置摄像头输入错误: %@", [error localizedDescription]);
        return NO;
    } else {
        BOOL success = [self addInput:cameraDeviceInput toCaptureSession:captureSession];
        self.cameraDevice = cameraDeviceInput.device;
        return success;
    }
}

- (BOOL)addDefaultMicInputToCaptureSession:(AVCaptureSession *)captureSession {
    NSError *error;
    AVCaptureDeviceInput *micDeviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio] error:&error];
    if (error){
        NSLog(@"配置麦克风输入错误: %@", [error localizedDescription]);
        return NO;
    } else {
        BOOL success = [self addInput:micDeviceInput toCaptureSession:captureSession];
        return success;
    }
}

- (BOOL)addInput:(AVCaptureDeviceInput *)input toCaptureSession:(AVCaptureSession *)captureSession {
    if ([captureSession canAddInput:input]){
        [captureSession addInput:input];
        return YES;
    } else {
        NSLog(@"不能添加输入: %@", [input description]);
    }
    return NO;
}


- (BOOL)addOutput:(AVCaptureOutput *)output toCaptureSession:(AVCaptureSession *)captureSession {
    if ([captureSession canAddOutput:output]){
        [captureSession addOutput:output];
        return YES;
    } else {
        NSLog(@"不能添加输出 %@", [output description]);
    }
    return NO;
}

- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition)position {
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    for ( AVCaptureDevice *device in devices ) {
        if ( device.position == position ) {
            return device;
        }
    }
    return nil;
}


#pragma mark - Getter

- (AVCaptureVideoPreviewLayer *)previewLayer {
    if(!_previewLayer && _captureSession){
        _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_captureSession];
    }
    return _previewLayer;
}

@end
