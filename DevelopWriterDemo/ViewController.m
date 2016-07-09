//
//  ViewController.m
//  DevelopWriterDemo
//
//  Created by jiangxincai on 16/1/13.
//  Copyright © 2016年 pepsikirk. All rights reserved.
//

#import "ViewController.h"
#import "PKRecordShortVideoViewController.h"

@interface ViewController () <PKRecordShortVideoDelegate>

@end

@implementation ViewController

#pragma mark - LifeCycle

- (void)viewDidLoad {
    [super viewDidLoad]; 
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}



#pragma marl - IBAction

- (IBAction)clickShootVideo:(UIButton *)sender {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *fileName = [NSProcessInfo processInfo].globallyUniqueString;
    NSString *path = [paths[0] stringByAppendingPathComponent:[fileName stringByAppendingPathExtension:@"mp4"]];

    PKRecordShortVideoViewController *viewController = [[PKRecordShortVideoViewController alloc] initWithOutputFilePath:path outputSize:CGSizeMake(360, 640) themeColor:[UIColor colorWithRed:0/255.0 green:153/255.0 blue:255/255.0 alpha:1]];
    viewController.delegate = self;

    [self presentViewController:viewController animated:YES completion:nil];
}


#pragma mark - PKRecordShortVideoDelegate

- (void)didFinishRecordingToOutputFilePath:(NSString *)outputFilePath {
    
}


@end
