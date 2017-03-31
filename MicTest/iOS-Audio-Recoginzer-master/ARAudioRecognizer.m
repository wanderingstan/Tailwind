//
//  ARAudioRecognizer.m
//  Audio Recognizer
//
//  Created by Anthony Picciano on 6/6/13.
//  Copyright (c) 2013 Anthony Picciano. All rights reserved.
//

#import "ARAudioRecognizer.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreAudio/CoreAudioTypes.h>

@interface ARAudioRecognizer ()

@property (nonatomic, strong) AVAudioRecorder *recorder;
@property (nonatomic, strong) AVAudioSession *session;
@property (nonatomic, strong) NSTimer *levelTimer;

- (void)initializeRecorder;
- (void)initializeLevelTimer;

@end

@implementation ARAudioRecognizer

@synthesize delegate = _delegate;
@synthesize sensitivity = _sensitivity, frequency = _frequency, lowPassResults = _lowPassResults;

- (id)init
{
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayAndRecord error:nil];

    return [self initWithSensitivity:AR_AUDIO_RECOGNIZER_SENSITIVITY_DEFAULT
                           frequency:AR_AUDIO_RECOGNIZER_FREQUENCY_DEFAULT];
}

-(void)stop
{
    [self.recorder stop];
}

- (id)initWithSensitivity:(float)sensitivity frequency:(float)frequency
{
    if (self = [super init]) {
        _sensitivity = sensitivity;
        _frequency = frequency;
        _lowPassResults = 0.0f;
    }
    
    [self initializeRecorder];
    [self initializeLevelTimer];
    
    return self;
}

- (void)initializeRecorder
{
    NSURL *url = [NSURL fileURLWithPath:@"/dev/null"];
    
    NSDictionary *settings = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithFloat: 44100.0],                 AVSampleRateKey,
                              [NSNumber numberWithInt: kAudioFormatAppleLossless], AVFormatIDKey,
                              [NSNumber numberWithInt: 3],                         AVNumberOfChannelsKey,
                              [NSNumber numberWithInt: AVAudioQualityMax],         AVEncoderAudioQualityKey,
                              nil];
    
  	NSError *error;
    
  	self.recorder = [[AVAudioRecorder alloc] initWithURL:url settings:settings error:&error];
    
    self.session = [AVAudioSession sharedInstance];

    // Turn off apple filters
    // http://stackoverflow.com/a/15526007/59913
    [self.session setMode: AVAudioSessionModeMeasurement error:NULL];

    // Switch to front mic
    [self demonstrateInputSelection];
    
  	if (self.recorder) {
  		[self.recorder prepareToRecord];
  		[self.recorder setMeteringEnabled:YES];
  		[self.recorder record];
  	} else
  		NSLog(@"Error in initializeRecorder: %@", [error description]);
}

- (void) demonstrateInputSelection
{
    NSError* theError = nil;
    BOOL result = YES;
    AVAudioSession* myAudioSession = [AVAudioSession sharedInstance];
    result = [myAudioSession setCategory:AVAudioSessionCategoryPlayAndRecord error:&theError];
    if (!result)
    {
        NSLog(@"setCategory failed");
    }
    result = [myAudioSession setActive:YES error:&theError];
    if (!result)
    {
        NSLog(@"setActive failed");
    }
    // Get the set of available inputs. If there are no audio accessories attached, there will be
    // only one available input -- the built in microphone.
    NSArray* inputs = [myAudioSession availableInputs];
    // Locate the Port corresponding to the built-in microphone.
    AVAudioSessionPortDescription* builtInMicPort = nil;
    for (AVAudioSessionPortDescription* port in inputs)
    {
        if ([port.portType isEqualToString:AVAudioSessionPortBuiltInMic])
        {
            builtInMicPort = port;
            break;
        }
    }
    // Print out a description of the data sources for the built-in microphone
    NSLog(@"There are %u data sources for port :\"%@\"", (unsigned)[builtInMicPort.dataSources count], builtInMicPort);
    NSLog(@"%@", builtInMicPort.dataSources);
    // loop over the built-in mic's data sources and attempt to locate the front microphone
    AVAudioSessionDataSourceDescription* frontDataSource = nil;
    for (AVAudioSessionDataSourceDescription* source in builtInMicPort.dataSources)
    {
        if ([source.orientation isEqual:AVAudioSessionOrientationFront])
        {
            frontDataSource = source;
            break;
        }
    } // end data source iteration
    if (frontDataSource)
    {
        NSLog(@"Currently selected source is \"%@\" for port \"%@\"", builtInMicPort.selectedDataSource.dataSourceName, builtInMicPort.portName);
        NSLog(@"Attempting to select source \"%@\" on port \"%@\"", frontDataSource, builtInMicPort.portName);
        // Set a preference for the front data source.
        theError = nil;
        result = [builtInMicPort setPreferredDataSource:frontDataSource error:&theError];
        if (!result)
        {
            // an error occurred. Handle it!
            NSLog(@"setPreferredDataSource failed");
        }
    }
    // Make sure the built-in mic is selected for input. This will be a no-op if the built-in mic is
    // already the current input Port.
    theError = nil;
    result = [myAudioSession setPreferredInput:builtInMicPort error:&theError];
    if (!result)
    {
        // an error occurred. Handle it!
        NSLog(@"setPreferredInput failed");
    }
}


- (void)initializeLevelTimer
{
    self.levelTimer = [NSTimer scheduledTimerWithTimeInterval: 0.03 target: self selector: @selector(levelTimerCallback:) userInfo: nil repeats: YES];
}

- (void)levelTimerCallback:(NSTimer *)timer
{
	[self.recorder updateMeters];
    
	const double ALPHA = 0.1;
	double peakPowerForChannel = pow(10, (0.05 * [self.recorder peakPowerForChannel:0]));
	_lowPassResults = ALPHA * peakPowerForChannel + (1.0 - ALPHA) * self.lowPassResults;
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(audioLevelUpdated:level:)]) {
        [self.delegate audioLevelUpdated:self level:self.lowPassResults];
    }
    
    if (self.delegate && [self.delegate respondsToSelector:@selector(audioLevelUpdated:averagePower:peakPower:)]) {
        [self.delegate audioLevelUpdated:self averagePower:[self.recorder averagePowerForChannel:0] peakPower:[self.recorder peakPowerForChannel:0]];
    }
    
	if (self.lowPassResults > 0.95 && self.delegate && [self.delegate respondsToSelector:@selector(audioRecognized:)]) {
        [self.delegate audioRecognized:self];
        _lowPassResults = 0.0f;
    }
}


@end
