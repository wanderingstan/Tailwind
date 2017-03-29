//
//  ViewController.m
//  MicTest
//
//  Created by Stan on 3/27/17.
//  Copyright © 2017 Stan James. All rights reserved.
//

#import "ViewController.h"

@interface ViewController ()
@end

@implementation ViewController {
    
    ARAudioRecognizer *audioRecognizer;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    audioRecognizer = [[ARAudioRecognizer alloc] init];
    audioRecognizer.delegate = self;
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)audioRecognized:(ARAudioRecognizer *)recognizer
{
    NSLog(@"audioRecognized");
}

- (void)audioLevelUpdated:(ARAudioRecognizer *)recognizer level:(float)lowPassResults
{
    NSLog(@"audioLevelUpdated level");
    
}

- (void)audioLevelUpdated:(ARAudioRecognizer *)recognizer averagePower:(float)averagePower peakPower:(float)peakPower
{
    NSLog(@"audioLevelUpdated averagePower");
    
}

@end
