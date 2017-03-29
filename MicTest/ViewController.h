//
//  ViewController.h
//  MicTest
//
//  Created by Stan on 3/27/17.
//  Copyright © 2017 Stan James. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "iOS-Audio-Recoginzer-master/ARAudioRecognizerDelegate.h"
#import "iOS-Audio-Recoginzer-master/ARAudioRecognizer.h"
#import <CoreLocation/CoreLocation.h>

@interface ViewController : UIViewController <ARAudioRecognizerDelegate, CLLocationManagerDelegate>

- (void)audioRecognized:(ARAudioRecognizer *)recognizer;
- (void)audioLevelUpdated:(ARAudioRecognizer *)recognizer level:(float)lowPassResults;
- (void)audioLevelUpdated:(ARAudioRecognizer *)recognizer averagePower:(float)averagePower peakPower:(float)peakPower;

// UI
@property (weak, nonatomic) IBOutlet UILabel *debugLabel;
- (IBAction)startStopLoggingAction:(id)sender;

@end

