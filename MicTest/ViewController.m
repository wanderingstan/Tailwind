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
    
    if (averagePower == -160.0) {
        // Invalid power, skip it
        return;
    }
    // Find average, weighting all samples equally
    _averageAudioPowerSinceLastLocation = ((_averageAudioPowerSinceLastLocation * _audioSampleCountSinceLastLocation) + averagePower) / (_audioSampleCountSinceLastLocation+1);
    _audioSampleCountSinceLastLocation++;
}

- (void)locationManager:(CLLocationManager *)manager
    didUpdateToLocation:(CLLocation *)newLocation
           fromLocation:(CLLocation *)oldLocation
{
    // Validity check
    {
        if (_averageAudioPowerSinceLastLocation == -120.0) {
            // We've lost our connection somehow, so restart
            [_audioRecognizer stop];
            _audioRecognizer = [[ARAudioRecognizer alloc] init];
            _audioRecognizer.delegate = self;
            NSLog(@"Restarting microphone");
        }
    }
    
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
        
        // Enable background updates
        // http://stackoverflow.com/a/33619182/59913
        if ([_locationManager respondsToSelector:@selector(setAllowsBackgroundLocationUpdates:)]) {
            [_locationManager setAllowsBackgroundLocationUpdates:YES];
        }
        
        [_locationManager startUpdatingLocation];
    }
    
    // Setup logging
    {
        int timestamp = [[NSDate date] timeIntervalSince1970];
        NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
        _logFilePathName = [documentsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"log_%@_%d.csv", @"test.csv", timestamp]];
        
        _sampleIndex = 0;
        
        NSArray* dataToLog = @[@"No",
                                @"Latitude",
                                @"Longitude",
                                @"Altitude",
                                @"Speed",
                                @"Date",
                                @"Time",
                                @"dB"];

        [self writeToLogFile:dataToLog];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.debugKeyLabel.text = [dataToLog componentsJoinedByString:@"\n"];
        });
        
    }

}

- (void)stopLogging
{
    [_audioRecognizer stop];
    [_locationManager stopUpdatingLocation];
}

#pragma mark -
#pragma mark Send

- (IBAction)emailLogFileAction:(id)sender
{
    MFMailComposeViewController *picker = [[MFMailComposeViewController alloc] init];
    picker.mailComposeDelegate = self;
    [picker setSubject:@"My speed and volume file"];
    
    // Set up recipients
     NSArray *toRecipients = [NSArray arrayWithObject:@"stan@wanderingstan.com"];
    // NSArray *ccRecipients = [NSArray arrayWithObjects:@"second@example.com", @"third@example.com", nil];
    // NSArray *bccRecipients = [NSArray arrayWithObject:@"fourth@example.com"];
    
     [picker setToRecipients:toRecipients];
    // [picker setCcRecipients:ccRecipients];
    // [picker setBccRecipients:bccRecipients];
    
    // Attach an image to the email
    NSData *data = [[NSFileManager defaultManager] contentsAtPath:_logFilePathName];
    [picker addAttachmentData:data mimeType:@"text/csv" fileName:@"speed-volume-file.csv"];
    
    // Fill out the email body text
    NSString *emailBody = @"My csv with gps, speed, and volume is attached";
    [picker setMessageBody:emailBody isHTML:NO];
    [self presentModalViewController:picker animated:YES];
}

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error
{
    // Notifies users about errors associated with the interface
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (result)
        {
                
            case MFMailComposeResultCancelled:
                NSLog(@"Result: canceled");
                break;
            case MFMailComposeResultSaved:
                NSLog(@"Result: saved");
                break;
            case MFMailComposeResultSent:
                NSLog(@"Result: sent");
                self.debugLabel.text = @"Log file sent.\nThank you!";
                break;
            case MFMailComposeResultFailed:
                self.debugLabel.text = @"Log file failed to send.";
                NSLog(@"Result: failed");
                break;
            default:
                self.debugLabel.text = @"Log file was not sent.";
                NSLog(@"Result: not sent");
                break;
        }
    });
    [self dismissModalViewControllerAnimated:YES];
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


@end
