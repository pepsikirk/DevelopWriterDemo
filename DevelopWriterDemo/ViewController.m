//
//  ViewController.m
//  DevelopWriterDemo
//
//  Created by jiangxincai on 16/1/13.
//  Copyright © 2016年 pepsikirk. All rights reserved.
//

#import "ViewController.h"
#import "PKShortVideoViewController.h"

@interface ViewController ()

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
    NSString *path = [paths[0] stringByAppendingPathComponent:[@"PKShortVideo" stringByAppendingPathExtension:@"mp4"]];
    
    PKShortVideoViewController *viewController = [[PKShortVideoViewController alloc] initWithOutputFileURL:[NSURL fileURLWithPath:path] outputSize:CGSizeMake(320, 240)];
    [self.navigationController pushViewController:viewController animated:YES];
}

@end