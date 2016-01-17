//
//  PKShortVideoWriter.m
//  DevelopWriterDemo
//
//  Created by jiangxincai on 16/1/14.
//  Copyright © 2016年 pepsikirk. All rights reserved.
//

#import "PKShortVideoWriter.h"
#import <AVFoundation/AVFoundation.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import "IDAssetWriterCoordinator.h"

typedef NS_ENUM( NSInteger, RecordingStatus ) {
    RecordingStatusIdle = 0,
    RecordingStatusStartingRecording,
    RecordingStatusRecording,
    RecordingStatusStoppingRecording,
}; // internal state machine

@interface PKShortVideoWriter() <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, IDAssetWriterCoordinatorDelegate>

@property (nonatomic, strong) NSURL *outputFileURL;
@property (nonatomic, assign) CGSize outputSize;

@property (nonatomic, strong) dispatch_queue_t delegateCallbackQueue;
@property (nonatomic, strong) dispatch_queue_t sessionQueue;

@property (nonatomic, strong) dispatch_queue_t videoDataOutputQueue;
@property (nonatomic, strong) dispatch_queue_t audioDataOutputQueue;

@property (nonatomic, strong) AVCaptureVideoDataOutput *videoDataOutput;
@property (nonatomic, strong) AVCaptureAudioDataOutput *audioDataOutput;

@property (nonatomic, strong) AVCaptureConnection *audioConnection;
@property (nonatomic, strong) AVCaptureConnection *videoConnection;

@property (nonatomic, strong) NSDictionary *videoCompressionSettings;
@property (nonatomic, strong) NSDictionary *audioCompressionSettings;

@property (nonatomic, strong) AVCaptureSession *captureSession;
@property (nonatomic, strong) AVCaptureDevice *cameraDevice;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;

@property (nonatomic, strong) AVAssetWriter *assetWriter;

@property (nonatomic, assign) RecordingStatus recordingStatus;
@property(nonatomic, retain) __attribute__((NSObject)) CMFormatDescriptionRef outputVideoFormatDescription;
@property(nonatomic, retain) __attribute__((NSObject)) CMFormatDescriptionRef outputAudioFormatDescription;

@property(nonatomic, retain) IDAssetWriterCoordinator *assetWriterCoordinator;

@end

@implementation PKShortVideoWriter

#pragma mark - Init

- (instancetype)initWithOutputFileURL:(NSURL *)outputFileURL outputSize:(CGSize)outputSize {
    self = [super init];
    if (self) {
        _outputFileURL = outputFileURL;
        _outputSize = outputSize;
        
        _sessionQueue = dispatch_queue_create( "com.example.capturepipeline.session", DISPATCH_QUEUE_SERIAL );
        _captureSession = [self setupCaptureSession];
        self.videoDataOutputQueue = dispatch_queue_create( "com.example.capturesession.videodata", DISPATCH_QUEUE_SERIAL );
        dispatch_set_target_queue( _videoDataOutputQueue, dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_HIGH, 0 ) );
        self.audioDataOutputQueue = dispatch_queue_create( "com.example.capturesession.audiodata", DISPATCH_QUEUE_SERIAL );
        [self addDataOutputsToCaptureSession:self.captureSession];
    }
    return self;
}



#pragma mark - Running Session

- (void)startRunning {
    dispatch_sync( _sessionQueue, ^{
        [_captureSession startRunning];
    } );
}

- (void)stopRunning {
    dispatch_sync( _sessionQueue, ^{
        // the captureSessionDidStopRunning method will stop recording if necessary as well, but we do it here so that the last video and audio samples are better aligned
        [self stopRecording]; // does nothing if we aren't currently recording
        [_captureSession stopRunning];
    } );
}



#pragma mark - Recording

- (void)startRecording
{
    @synchronized(self) {
        if(_recordingStatus != RecordingStatusIdle) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException reason:@"Already recording" userInfo:nil];
            return;
        }
        [self transitionToRecordingStatus:RecordingStatusStartingRecording error:nil];
    }
    
    self.assetWriterCoordinator = [[IDAssetWriterCoordinator alloc] initWithURL:self.outputFileURL];
    if(_outputAudioFormatDescription != nil){
        [_assetWriterCoordinator addAudioTrackWithSourceFormatDescription:self.outputAudioFormatDescription settings:_audioCompressionSettings];
    }
    [_assetWriterCoordinator addVideoTrackWithSourceFormatDescription:self.outputVideoFormatDescription settings:_videoCompressionSettings];
    
    dispatch_queue_t callbackQueue = dispatch_queue_create( "com.example.capturesession.writercallback", DISPATCH_QUEUE_SERIAL ); // guarantee ordering of callbacks with a serial queue
    [_assetWriterCoordinator setDelegate:self callbackQueue:callbackQueue];
    [_assetWriterCoordinator prepareToRecord]; // asynchronous, will call us back with recorderDidFinishPreparing: or recorder:didFailWithError: when done
}

- (void)stopRecording
{
    @synchronized(self)
    {
        if (_recordingStatus != RecordingStatusRecording){
            return;
        }
        [self transitionToRecordingStatus:RecordingStatusStoppingRecording error:nil];
    }
    [self.assetWriterCoordinator finishRecording]; // asynchronous, will call us back with
}



#pragma mark - Private methods

- (void)addDataOutputsToCaptureSession:(AVCaptureSession *)captureSession
{
    self.videoDataOutput = [AVCaptureVideoDataOutput new];
    _videoDataOutput.videoSettings = nil;
    _videoDataOutput.alwaysDiscardsLateVideoFrames = NO;
    
    [_videoDataOutput setSampleBufferDelegate:self queue:_videoDataOutputQueue];
    
    self.audioDataOutput = [AVCaptureAudioDataOutput new];
    [_audioDataOutput setSampleBufferDelegate:self queue:_audioDataOutputQueue];
    
    [self addOutput:_videoDataOutput toCaptureSession:self.captureSession];
    _videoConnection = [_videoDataOutput connectionWithMediaType:AVMediaTypeVideo];
    
    [self addOutput:_audioDataOutput toCaptureSession:self.captureSession];
    _audioConnection = [_audioDataOutput connectionWithMediaType:AVMediaTypeAudio];
    
    [self setCompressionSettings];
}

- (void)setupVideoPipelineWithInputFormatDescription:(CMFormatDescriptionRef)inputFormatDescription
{
    self.outputVideoFormatDescription = inputFormatDescription;
}

- (void)teardownVideoPipeline
{
    self.outputVideoFormatDescription = nil;
}

- (void)setCompressionSettings
{
    //    _videoCompressionSettings = [_videoDataOutput recommendedVideoSettingsForAssetWriterWithOutputFileType:AVFileTypeMPEG4];
    NSInteger numPixels = self.outputSize.width * self.outputSize.height;
    NSInteger bitsPerPixel = 6.0;
    NSInteger bitsPerSecond = numPixels * bitsPerPixel;
    
    NSDictionary *compressionProperties = @{ AVVideoAverageBitRateKey : @(bitsPerSecond),
                                             AVVideoExpectedSourceFrameRateKey : @(30),
                                             AVVideoMaxKeyFrameIntervalKey : @(30) };
    
    _videoCompressionSettings = @{ AVVideoCodecKey : AVVideoCodecH264,
                                   AVVideoWidthKey : @(self.outputSize.width),
                                   AVVideoHeightKey : @(self.outputSize.height),
                                   AVVideoCompressionPropertiesKey : compressionProperties };
    
    //    _audioCompressionSettings = [_audioDataOutput recommendedAudioSettingsForAssetWriterWithOutputFileType:AVFileTypeMPEG4];
    _audioCompressionSettings = @{ AVEncoderBitRatePerChannelKey : @(28000),
                                   AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                   AVNumberOfChannelsKey : @(1),
                                   AVSampleRateKey : @(22050) };
}

#pragma mark - SampleBufferDelegate methods

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    CMFormatDescriptionRef formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer);
    
    if (connection == _videoConnection){
        if (self.outputVideoFormatDescription == nil) {
            // Don't render the first sample buffer.
            // This gives us one frame interval (33ms at 30fps) for setupVideoPipelineWithInputFormatDescription: to complete.
            // Ideally this would be done asynchronously to ensure frames don't back up on slower devices.
            
            //TODO: outputVideoFormatDescription should be updated whenever video configuration is changed (frame rate, etc.)
            //Currently we don't use the outputVideoFormatDescription in IDAssetWriterRecoredSession
            [self setupVideoPipelineWithInputFormatDescription:formatDescription];
        } else {
            self.outputVideoFormatDescription = formatDescription;
            @synchronized(self) {
                if(_recordingStatus == RecordingStatusRecording){
                    [_assetWriterCoordinator appendVideoSampleBuffer:sampleBuffer];
                }
            }
        }
    } else if ( connection == _audioConnection ){
        self.outputAudioFormatDescription = formatDescription;
        @synchronized( self ) {
            if(_recordingStatus == RecordingStatusRecording){
                [_assetWriterCoordinator appendAudioSampleBuffer:sampleBuffer];
            }
        }
    }
}


#pragma mark - Recording State Machine

// call under @synchonized( self )
- (void)transitionToRecordingStatus:(RecordingStatus)newStatus error:(NSError *)error
{
    RecordingStatus oldStatus = _recordingStatus;
    _recordingStatus = newStatus;
    
    if (newStatus != oldStatus){
        if (error && (newStatus == RecordingStatusIdle)){
            dispatch_async( self.delegateCallbackQueue, ^{
                @autoreleasepool
                {
                    [self.delegate writer:self didFinishRecordingToOutputFileURL:_outputFileURL error:error];
                }
            });
        } else {
            error = nil; // only the above delegate method takes an error
            if (oldStatus == RecordingStatusStartingRecording && newStatus == RecordingStatusRecording){
                dispatch_async( self.delegateCallbackQueue, ^{
                    @autoreleasepool
                    {
                        [self.delegate writerDidBeginRecording:self];
                    }
                });
            } else if (oldStatus == RecordingStatusStoppingRecording && newStatus == RecordingStatusIdle) {
                dispatch_async( self.delegateCallbackQueue, ^{
                    @autoreleasepool
                    {
                        [self.delegate writer:self didFinishRecordingToOutputFileURL:_outputFileURL error:nil];
                    }
                });
            }
        }
    }
}


#pragma mark - Capture Session Setup


- (AVCaptureSession *)setupCaptureSession
{
    AVCaptureSession *captureSession = [AVCaptureSession new];
    captureSession.sessionPreset = AVCaptureSessionPresetMedium;
    
    if(![self addDefaultCameraInputToCaptureSession:captureSession]){
        NSLog(@"failed to add camera input to capture session");
    }
    if(![self addDefaultMicInputToCaptureSession:captureSession]){
        NSLog(@"failed to add mic input to capture session");
    }
    
    return captureSession;
}

- (BOOL)addDefaultCameraInputToCaptureSession:(AVCaptureSession *)captureSession
{
    NSError *error;
    AVCaptureDeviceInput *cameraDeviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] error:&error];
    
    if(error){
        NSLog(@"error configuring camera input: %@", [error localizedDescription]);
        return NO;
    } else {
        BOOL success = [self addInput:cameraDeviceInput toCaptureSession:captureSession];
        _cameraDevice = cameraDeviceInput.device;
        return success;
    }
}

//Not used in this project, but illustration of how to select a specific camera
- (BOOL)addCameraAtPosition:(AVCaptureDevicePosition)position toCaptureSession:(AVCaptureSession *)captureSession
{
    NSError *error;
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput *cameraDeviceInput;
    for(AVCaptureDevice *device in devices){
        if(device.position == position){
            cameraDeviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:device error:&error];
        }
    }
    if(!cameraDeviceInput){
        NSLog(@"No capture device found for requested position");
        return NO;
    }
    
    if(error){
        NSLog(@"error configuring camera input: %@", [error localizedDescription]);
        return NO;
    } else {
        BOOL success = [self addInput:cameraDeviceInput toCaptureSession:captureSession];
        _cameraDevice = cameraDeviceInput.device;
        [self setFrameRateWithDuration:CMTimeMake(1,30) OnCaptureDevice:cameraDeviceInput.device];
        return success;
    }
}

- (BOOL)addDefaultMicInputToCaptureSession:(AVCaptureSession *)captureSession
{
    NSError *error;
    AVCaptureDeviceInput *micDeviceInput = [[AVCaptureDeviceInput alloc] initWithDevice:[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio] error:&error];
    if(error){
        NSLog(@"error configuring mic input: %@", [error localizedDescription]);
        return NO;
    } else {
        BOOL success = [self addInput:micDeviceInput toCaptureSession:captureSession];
        return success;
    }
}

- (BOOL)addInput:(AVCaptureDeviceInput *)input toCaptureSession:(AVCaptureSession *)captureSession
{
    if([captureSession canAddInput:input]){
        [captureSession addInput:input];
        return YES;
    } else {
        NSLog(@"can't add input: %@", [input description]);
    }
    return NO;
}


- (BOOL)addOutput:(AVCaptureOutput *)output toCaptureSession:(AVCaptureSession *)captureSession
{
    if([captureSession canAddOutput:output]){
        [captureSession addOutput:output];
        return YES;
    } else {
        NSLog(@"can't add output: %@", [output description]);
    }
    return NO;
}


#pragma mark - Methods discussed in the article but not used in this demo app

- (void)setFrameRateWithDuration:(CMTime)frameDuration OnCaptureDevice:(AVCaptureDevice *)device
{
    NSError *error;
    NSArray *supportedFrameRateRanges = [device.activeFormat videoSupportedFrameRateRanges];
    BOOL frameRateSupported = NO;
    for(AVFrameRateRange *range in supportedFrameRateRanges){
        if(CMTIME_COMPARE_INLINE(frameDuration, >=, range.minFrameDuration) && CMTIME_COMPARE_INLINE(frameDuration, <=, range.maxFrameDuration)){
            frameRateSupported = YES;
        }
    }
    
    if(frameRateSupported && [device lockForConfiguration:&error]){
        [device setActiveVideoMaxFrameDuration:frameDuration];
        [device setActiveVideoMinFrameDuration:frameDuration];
        [device unlockForConfiguration];
    }
}


- (void)listCamerasAndMics
{
    NSLog(@"%@", [[AVCaptureDevice devices] description]);
    NSError *error;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    if(error){
        NSLog(@"%@", [error localizedDescription]);
    }
    [audioSession setActive:YES error:&error];
    
    NSArray *availableAudioInputs = [audioSession availableInputs];
    NSLog(@"audio inputs: %@", [availableAudioInputs description]);
    for(AVAudioSessionPortDescription *portDescription in availableAudioInputs){
        NSLog(@"data sources: %@", [[portDescription dataSources] description]);
    }
    if([availableAudioInputs count] > 0){
        AVAudioSessionPortDescription *portDescription = [availableAudioInputs firstObject];
        if([[portDescription dataSources] count] > 0){
            NSError *error;
            AVAudioSessionDataSourceDescription *dataSource = [[portDescription dataSources] lastObject];
            
            [portDescription setPreferredDataSource:dataSource error:&error];
            [self logError:error];
            
            [audioSession setPreferredInput:portDescription error:&error];
            [self logError:error];
            
            NSArray *availableAudioInputs = [audioSession availableInputs];
            NSLog(@"audio inputs: %@", [availableAudioInputs description]);
            
        }
    }
}

- (void)logError:(NSError *)error
{
    if(error){
        NSLog(@"%@", [error localizedDescription]);
    }
}

- (void)configureFrontMic
{
    NSError *error;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:&error];
    if(error){
        NSLog(@"%@", [error localizedDescription]);
    }
    [audioSession setActive:YES error:&error];
    
    NSArray* inputs = [audioSession availableInputs];
    AVAudioSessionPortDescription *builtInMic = nil;
    for (AVAudioSessionPortDescription* port in inputs){
        if ([port.portType isEqualToString:AVAudioSessionPortBuiltInMic]){
            builtInMic = port;
            break;
        }
    }
    
    for (AVAudioSessionDataSourceDescription* source in builtInMic.dataSources){
        if ([source.orientation isEqual:AVAudioSessionOrientationFront]){
            [builtInMic setPreferredDataSource:source error:nil];
            [audioSession setPreferredInput:builtInMic error:&error];
            break;
        }
    }
}



#pragma mark - Getter

- (AVCaptureVideoPreviewLayer *)previewLayer {
    if(!_previewLayer && _captureSession){
        _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_captureSession];
    }
    return _previewLayer;
}

@end
