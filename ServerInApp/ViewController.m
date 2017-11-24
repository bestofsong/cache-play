//
//  ViewController.m
//  ServerInApp
//
//  Created by wansong on 12/29/16.
//  Copyright © 2016 zhike. All rights reserved.
//

#import "ViewController.h"
#import <MediaPlayer/MediaPlayer.h>
#import "ZKVideoCacheManager.h"
#import "TableViewController.h"


@interface ViewController ()

- (IBAction)push:(id)sender;
- (IBAction)removeCachedVideos:(id)sender;

@end

@implementation ViewController

- (void)viewDidLoad {
  [super viewDidLoad];
//  NSString *m3u8UrlStr = @"http://media6.smartstudy.com/eb/43/95205/2/dest.m3u8";
//  NSURL *url = [NSURL URLWithString:m3u8UrlStr];
//  NSString *urlStr = [ZKM3U8CacheManager cacheUrlForM3u8:m3u8UrlStr];
//
//  NSURL *cachedUrl = [NSURL URLWithString:urlStr];
//  NSLog(@"playing cached video: %@", cachedUrl.absoluteString);
//  self.playerController = [[MPMoviePlayerController alloc] initWithContentURL:cachedUrl];
//  self.playerController.view.frame = CGRectMake(0, 20, 300, 200);
//  [self.view addSubview:self.playerController.view];
//  [self.playerController play];
//  
//  if (![ZKM3U8CacheManager isM3u8Cached:m3u8UrlStr]) {
//    [ZKM3U8CacheManager beginCacheM3u8:m3u8UrlStr];
//  }
}

- (void)push:(id)sender {
  TableViewController *tableViewController = [TableViewController new];
  [self.navigationController pushViewController:tableViewController animated:YES];
}

- (IBAction)removeCachedVideos:(id)sender {
  NSError *error = nil;
  if (![ZKVideoCacheManager clearM3u8Cache:&error]) {
    NSLog(@"failed to clear m3u8 cache, error: %@", error);
  }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
  return UIStatusBarStyleLightContent;
}

@end
