//
//  TableViewController.m
//  ServerInApp
//
//  Created by wansong on 1/12/17.
//  Copyright © 2017 zhike. All rights reserved.
//

#import "TableViewController.h"
#import <AVKit/AVKit.h>
#import "ZKVideoCacheManager.h"
#import "TableViewCell.h"
#import "ZKVideoCacheManager+Private.h"
#import "ZKVideoViewController.h"

@interface TableViewController ()
@property (strong, nonatomic) NSArray<NSMutableDictionary*> *dataSource;
@property (assign, nonatomic) NSInteger lastPlaying;
@end

@implementation TableViewController

- (void)viewDidLoad {
  [super viewDidLoad];
  [self.tableView registerClass:TableViewCell.class forCellReuseIdentifier:@"Cell"];
  self.lastPlaying = -1;
  
  self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"preview"
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(previewVideo:)];
  
  NSArray<NSString*> *urls = @[@"https://raw.githubusercontent.com/bestofsong/bestofsong.github.io/master/assets/dest.m3u8"];
  NSMutableArray<NSMutableDictionary*> *dataSource = [NSMutableArray array];
  [urls enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
    [dataSource addObject:[@{
                            @"url": [ZKVideoCacheManager cacheUrlForM3u8:obj],
                            @"on": @NO,
                            } mutableCopy]];
  }];
  self.dataSource = dataSource;
}

- (void)viewWillAppear:(BOOL)animated {
  NSAssert(self.navigationController, @"");
  NSAssert(self.navigationController.navigationItem, @"");
  self.navigationController.navigationItem.rightBarButtonItem =
  [[UIBarButtonItem alloc] initWithTitle:@"Clear"
                                   style:UIBarButtonItemStylePlain
                                  target:self
                                  action:@selector(clearM3u8Cache:)];
}

- (void)refresh {
  [self.tableView reloadData];
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
    [self refresh];
  });
}

- (void)previewVideo:(id)sender {
  NSString *urlString = self.dataSource[0][@"url"];
  ZKVideoViewController *vc = [[ZKVideoViewController alloc] initWithBeginTime:0 fromRect:CGRectZero customPresentAnimation:NO];
  vc.videoView.source = urlString;
  vc.videoView.playerState = PlayerStatePlaying;
  [self presentViewController:vc animated:YES completion:nil];
}

#pragma mark - Table view data source
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
  return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return self.dataSource.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  TableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
  cell.videoView.containerVC = self;
  cell.videoInfo = self.dataSource[indexPath.row];
  return cell;
}

#pragma mark -- Table view delegate
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
  return 200;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
  NSMutableDictionary *currentItem = self.dataSource[indexPath.row];
  NSMutableDictionary *lastItem = nil;
  if (self.lastPlaying != -1 && self.lastPlaying != indexPath.row) {
    lastItem = self.dataSource[self.lastPlaying];
    TableViewCell *lastCell = [tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:self.lastPlaying inSection:0]];
    lastItem[@"on"] = @NO;
    lastCell.videoInfo = lastItem;
  }
  currentItem[@"on"] = @(![currentItem[@"on"] boolValue]);
  TableViewCell *currentCell = [tableView cellForRowAtIndexPath:indexPath];
  [tableView deselectRowAtIndexPath:indexPath animated:YES];
  currentCell.videoInfo = currentItem;
}

- (UIStatusBarStyle)preferredStatusBarStyle {
  return UIStatusBarStyleLightContent;
}
@end
