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
#import <sys/utsname.h> // For device name

@interface ViewController ()
@end

@implementation ViewController {
    
    ARAudioRecognizer *_audioRecognizer;
    
    CLLocationManager *_locationManager;
    
    BOOL isRecording;
    NSString *_sessionFileName; // Filename for this session--no extension
    //NSString *_logFilePathName;
    
    int _sampleIndex;
    int _audioSampleCountSinceLastLocation;
    
    float _averageAudioPowerSinceLastLocation;
    float _averageAudioPowerLowPassSinceLastLocation;
    
    double _latestLat, _latestLon;
}

- (void)viewDidLoad {
    [super viewDidLoad];

}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

/**
 * Callback from audio
 */
- (void)audioLevelUpdated:(ARAudioRecognizer *)recognizer
             averagePower:(float)averagePower
                peakPower:(float)peakPower
                  lowPass:(float)lowPassResults
{
//    NSLog(@"audioLevelUpdated averagePower: %f", averagePower);
    
    if (averagePower == -160.0) {
        // Invalid power, skip it
        return;
    }
    
    // Lowpass, weighting all samples equally
    _averageAudioPowerLowPassSinceLastLocation = ((_averageAudioPowerLowPassSinceLastLocation * _audioSampleCountSinceLastLocation) + lowPassResults) / (_audioSampleCountSinceLastLocation+1);

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
                           [NSNumber numberWithFloat:newLocation.course],
                           [dateFormat stringFromDate:[NSDate date]],
                           [timeFormat stringFromDate:[NSDate date]],
                           [NSNumber numberWithFloat:_averageAudioPowerSinceLastLocation],
                           [NSNumber numberWithFloat:_averageAudioPowerLowPassSinceLastLocation],
                           ];
    
    [self writeToLogFile:dataToLog];
    
    NSLog(@"Logged: %@", dataToLog);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        self.debugLabel.text = [dataToLog componentsJoinedByString:@"\n"];
    });
    
    // Remember latest
    _latestLat = newLocation.coordinate.latitude;
    _latestLon = newLocation.coordinate.longitude;
    
    // Reset audio info
    _averageAudioPowerSinceLastLocation = 0.0;
    _averageAudioPowerLowPassSinceLastLocation = 0.0;
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
        _sessionFileName = [documentsDirectory stringByAppendingPathComponent:[NSString stringWithFormat:@"log_%@_%d", @"test", timestamp]];
        _sampleIndex = 0;
        
        NSArray* dataToLog = @[@"No",
                               @"Latitude",
                               @"Longitude",
                               @"Altitude",
                               @"Speed",
                               @"Course",
                               @"Date",
                               @"Time",
                               @"dB-Avg",
                               @"dB-Lowpass",
                               ];

        [self writeToLogFile:dataToLog];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.debugKeyLabel.text = [dataToLog componentsJoinedByString:@"\n"];
        });
        
    }

}

- (void)stopLogging
{
    [self downloadWeatherForLat:_latestLat andLon:_latestLon];
    
    [_audioRecognizer stop];
    [_locationManager stopUpdatingLocation];
}

#pragma mark -
#pragma mark Send

- (IBAction)emailLogFileAction:(id)sender
{
    MFMailComposeViewController *picker = [[MFMailComposeViewController alloc] init];
    
    if (picker == nil) {
        NSLog(@"Cannot send mail");
    }
    
    picker.mailComposeDelegate = self;
    [picker setSubject:@"My speed and volume file"];
    
    // Set up recipients
     NSArray *toRecipients = [NSArray arrayWithObject:@"wanderingstan+tailwind_data@gmail.com"];
    // NSArray *ccRecipients = [NSArray arrayWithObjects:@"second@example.com", @"third@example.com", nil];
    // NSArray *bccRecipients = [NSArray arrayWithObject:@"fourth@example.com"];
    
     [picker setToRecipients:toRecipients];
    // [picker setCcRecipients:ccRecipients];
    // [picker setBccRecipients:bccRecipients];
    
    // Attach an image to the email
    {
        NSString* logFilePathName = [NSString stringWithFormat:@"%@.csv",_sessionFileName];
        NSData *data = [[NSFileManager defaultManager] contentsAtPath:logFilePathName];
        [picker addAttachmentData:data mimeType:@"text/csv" fileName:@"speed-volume-file.csv"];
    }
    {
        NSString* logFilePathName = [NSString stringWithFormat:@"%@_weather.xml", _sessionFileName];
        NSData *data = [[NSFileManager defaultManager] contentsAtPath:logFilePathName];
        [picker addAttachmentData:data mimeType:@"text/xml" fileName:@"weather.xml"];
    }

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
    NSString* logFilePathName = [NSString stringWithFormat:@"%@.csv",_sessionFileName];
    
    NSFileHandle *myHandle = [NSFileHandle fileHandleForWritingAtPath:logFilePathName];
    if (myHandle == nil) {
        // Doesn't exist. Create it
        NSLog(@"Created log file: %@", logFilePathName);
        [[NSFileManager defaultManager] createFileAtPath:logFilePathName contents:nil attributes:nil];
        myHandle = [NSFileHandle fileHandleForWritingAtPath:logFilePathName];
    }
    [myHandle seekToEndOfFile];
    NSString *dataString = [logDataArray componentsJoinedByString:@","];
    [myHandle writeData:[dataString dataUsingEncoding:NSUTF8StringEncoding]];
    [myHandle writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
}

#pragma mark - 
#pragma mark Download weather conditions

/**
 * Weather: http://stackoverflow.com/questions/951839/api-to-get-weather-based-on-longitude-and-latitude-coordinates
 * Download: http://stackoverflow.com/questions/16392420/how-to-download-files-from-url-and-store-in-document-folder
 */
-(void) downloadWeatherForLat:(double)lat andLon:(double)lon;{
    // Download the file in a seperate thread.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSLog(@"Downloading Started");
        NSString *urlToDownload = [NSString stringWithFormat:@"http://forecast.weather.gov/MapClick.php?lat=%.5f&lon=%.5f&FcstType=dwml", lat, lon];
        NSURL  *url = [NSURL URLWithString:urlToDownload];
        NSData *urlData = [NSData dataWithContentsOfURL:url];
        if (urlData) {
            NSString* weatherFilePathName = [NSString stringWithFormat:@"%@_weather.xml",_sessionFileName];
            
            //saving is done on main thread
            dispatch_async(dispatch_get_main_queue(), ^{
                [urlData writeToFile:weatherFilePathName atomically:YES];
                NSLog(@"File Saved !");
            });
        }
    });
}

#pragma mark -
#pragma Get device name

- (NSString*) deviceName
{
    // See http://stackoverflow.com/questions/11197509/ios-how-to-get-device-make-and-model
    
    struct utsname systemInfo;
    
    uname(&systemInfo);
    
    NSString* code = [NSString stringWithCString:systemInfo.machine
                                        encoding:NSUTF8StringEncoding];
    
    static NSDictionary* deviceNamesByCode = nil;
    
    if (!deviceNamesByCode) {
        
        deviceNamesByCode = @{@"i386"      :@"Simulator",
                              @"x86_64"    :@"Simulator",
                              @"iPod1,1"   :@"iPod Touch",        // (Original)
                              @"iPod2,1"   :@"iPod Touch",        // (Second Generation)
                              @"iPod3,1"   :@"iPod Touch",        // (Third Generation)
                              @"iPod4,1"   :@"iPod Touch",        // (Fourth Generation)
                              @"iPod7,1"   :@"iPod Touch",        // (6th Generation)
                              @"iPhone1,1" :@"iPhone",            // (Original)
                              @"iPhone1,2" :@"iPhone",            // (3G)
                              @"iPhone2,1" :@"iPhone",            // (3GS)
                              @"iPad1,1"   :@"iPad",              // (Original)
                              @"iPad2,1"   :@"iPad 2",            //
                              @"iPad3,1"   :@"iPad",              // (3rd Generation)
                              @"iPhone3,1" :@"iPhone 4",          // (GSM)
                              @"iPhone3,3" :@"iPhone 4",          // (CDMA/Verizon/Sprint)
                              @"iPhone4,1" :@"iPhone 4S",         //
                              @"iPhone5,1" :@"iPhone 5",          // (model A1428, AT&T/Canada)
                              @"iPhone5,2" :@"iPhone 5",          // (model A1429, everything else)
                              @"iPad3,4"   :@"iPad",              // (4th Generation)
                              @"iPad2,5"   :@"iPad Mini",         // (Original)
                              @"iPhone5,3" :@"iPhone 5c",         // (model A1456, A1532 | GSM)
                              @"iPhone5,4" :@"iPhone 5c",         // (model A1507, A1516, A1526 (China), A1529 | Global)
                              @"iPhone6,1" :@"iPhone 5s",         // (model A1433, A1533 | GSM)
                              @"iPhone6,2" :@"iPhone 5s",         // (model A1457, A1518, A1528 (China), A1530 | Global)
                              @"iPhone7,1" :@"iPhone 6 Plus",     //
                              @"iPhone7,2" :@"iPhone 6",          //
                              @"iPhone8,1" :@"iPhone 6S",         //
                              @"iPhone8,2" :@"iPhone 6S Plus",    //
                              @"iPhone8,4" :@"iPhone SE",         //
                              @"iPhone9,1" :@"iPhone 7",          //
                              @"iPhone9,3" :@"iPhone 7",          //
                              @"iPhone9,2" :@"iPhone 7 Plus",     //
                              @"iPhone9,4" :@"iPhone 7 Plus",     //
                              
                              @"iPad4,1"   :@"iPad Air",          // 5th Generation iPad (iPad Air) - Wifi
                              @"iPad4,2"   :@"iPad Air",          // 5th Generation iPad (iPad Air) - Cellular
                              @"iPad4,4"   :@"iPad Mini",         // (2nd Generation iPad Mini - Wifi)
                              @"iPad4,5"   :@"iPad Mini",         // (2nd Generation iPad Mini - Cellular)
                              @"iPad4,7"   :@"iPad Mini",         // (3rd Generation iPad Mini - Wifi (model A1599))
                              @"iPad6,7"   :@"iPad Pro (12.9\")", // iPad Pro 12.9 inches - (model A1584)
                              @"iPad6,8"   :@"iPad Pro (12.9\")", // iPad Pro 12.9 inches - (model A1652)
                              @"iPad6,3"   :@"iPad Pro (9.7\")",  // iPad Pro 9.7 inches - (model A1673)
                              @"iPad6,4"   :@"iPad Pro (9.7\")"   // iPad Pro 9.7 inches - (models A1674 and A1675)
                              };
    }
    
    NSString* deviceName = [deviceNamesByCode objectForKey:code];
    
    if (!deviceName) {
        // Not found on database. At least guess main device type from string contents:
        
        if ([code rangeOfString:@"iPod"].location != NSNotFound) {
            deviceName = @"iPod Touch";
        }
        else if([code rangeOfString:@"iPad"].location != NSNotFound) {
            deviceName = @"iPad";
        }
        else if([code rangeOfString:@"iPhone"].location != NSNotFound){
            deviceName = @"iPhone";
        }
        else {
            deviceName = @"Unknown";
        }
    }
    
    return deviceName;
}

@end
