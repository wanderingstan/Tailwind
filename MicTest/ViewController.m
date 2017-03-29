//
//  ViewController.m
//  MicTest
//
//  Created by Stan on 3/27/17.
//  Copyright © 2017 Stan James. All rights reserved.
//

// http://gis.stackexchange.com/questions/202455/how-to-extract-the-speed-from-a-gpx-file

#import "ViewController.h"
#include <AudioToolbox/AudioToolbox.h>

@interface ViewController ()
@end

@implementation ViewController {
    
    ARAudioRecognizer *_audioRecognizer;
    
    CLLocationManager *_locationManager;
    
    BOOL isRecording;
    NSString *_logFilePathName;
    int _sampleIndex;
    int _audioSampleCountSinceLastLocation;
    
    float _averageAudioPowerSinceLastLocation;
}

- (void)viewDidLoad {
    [super viewDidLoad];

}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)audioRecognized:(ARAudioRecognizer *)recognizer
{
//    NSLog(@"audioRecognized");
}

- (void)audioLevelUpdated:(ARAudioRecognizer *)recognizer
                    level:(float)lowPassResults
{
//    NSLog(@"audioLevelUpdated level");
}

- (void)audioLevelUpdated:(ARAudioRecognizer *)recognizer
             averagePower:(float)averagePower peakPower:(float)peakPower
{
//    NSLog(@"audioLevelUpdated averagePower: %f", averagePower);
    
    // Find average, weighting all samples equally
    _averageAudioPowerSinceLastLocation = ((_averageAudioPowerSinceLastLocation * _audioSampleCountSinceLastLocation) + averagePower) / (_audioSampleCountSinceLastLocation+1);
    _audioSampleCountSinceLastLocation++;
}

- (void)locationManager:(CLLocationManager *)manager
    didUpdateToLocation:(CLLocation *)newLocation
           fromLocation:(CLLocation *)oldLocation
{
    NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
    [dateFormat setDateFormat:@"YYYY/MM/dd"];
    NSDateFormatter *timeFormat = [[NSDateFormatter alloc] init];
    [timeFormat setDateFormat:@"HH:mm:ss"];
    
    _sampleIndex++;
    NSArray* dataToLog = @[
                           [NSNumber numberWithInt:_sampleIndex],
                           [NSNumber numberWithDouble:newLocation.coordinate.latitude],
                           [NSNumber numberWithDouble:newLocation.coordinate.longitude],
                           [NSNumber numberWithDouble:newLocation.altitude],
                           [NSNumber numberWithFloat:newLocation.speed],
                           [dateFormat stringFromDate:[NSDate date]],
                           [timeFormat stringFromDate:[NSDate date]],
                           [NSNumber numberWithFloat:_averageAudioPowerSinceLastLocation],
                           ];
    
    [self writeToLogFile:dataToLog];
    
    NSLog(@"Logged: %@", dataToLog);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.debugLabel.text = [dataToLog componentsJoinedByString:@"\n"];
    });
    
    // Reset audio info
    _averageAudioPowerSinceLastLocation = 0.0;
    _audioSampleCountSinceLastLocation = 0;
}

/**
 *  Converts NSArry to a line of elements in csv file
 */
- (void)writeToLogFile:(NSArray*)logDataArray
{
    NSFileHandle *myHandle = [NSFileHandle fileHandleForWritingAtPath:_logFilePathName];
    if (myHandle == nil) {
        // Doesn't exist. Create it
        NSLog(@"Created log file: %@", _logFilePathName);
        [[NSFileManager defaultManager] createFileAtPath:_logFilePathName contents:nil attributes:nil];
        myHandle = [NSFileHandle fileHandleForWritingAtPath:_logFilePathName];
    }
    [myHandle seekToEndOfFile];
    NSString *dataString = [logDataArray componentsJoinedByString:@","];
    [myHandle writeData:[dataString dataUsingEncoding:NSUTF8StringEncoding]];
    [myHandle writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
}

- (IBAction)startStopLoggingAction:(id)sender
{
    UIButton *button = (UIButton*)sender;
    if (isRecording) {
        isRecording = NO;
        [self stopLogging];
        [button setTitle:@"Start" forState:UIControlStateNormal];
        AudioServicesPlaySystemSound (1114); // end_record.caf
    }
    else {
        isRecording = YES;
        [self startLogging];
        [button setTitle:@"Stop" forState:UIControlStateNormal];
        AudioServicesPlaySystemSound (1113); // begin_record.caf
    }
}


- (void)startLogging
{
    // Setup mic
    {
        _audioRecognizer = [[ARAudioRecognizer alloc] init];
        _audioRecognizer.delegate = self;
    }
    
    // Setup location
    {
        _locationManager = [[CLLocationManager alloc] init];
        _locationManager.delegate = self;
        _locationManager.distanceFilter = kCLDistanceFilterNone;
        _locationManager.desiredAccuracy = kCLLocationAccuracyBest;
        
        if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0) {
            [_locationManager requestWhenInUseAuthorization];
        }
        
        [_locationManager startUpdatingLocation];
    }
    
    // Setup logging
    {
        int timestamp = [[NSDate date] timeIntervalSince1970];
        NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        _logFilePathName = [documentsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"log_%@_%d.csv", @"test.csv", timestamp]];
        
        _sampleIndex = 0;
        [self writeToLogFile:
         @[@"No",
           @"Latitude",
           @"Longitude",
           @"Altitude",
           @"Speed",
           @"Date",
           @"Time",
           @"_averageAudioPowerSinceLastLocation"]
         ];
    }

}

- (void)stopLogging
{
    _audioRecognizer = nil;  // Is this enough to kill it?
    [_locationManager stopUpdatingLocation];
}

@end
