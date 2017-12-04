#import "AppDelegate.h"
#import "ZKVideoCacheManager.h"
#import <UIKit/UIKit.h>

@interface AppDelegate () <UITableViewDataSource, UITableViewDelegate>
@property (strong, nonatomic) NSMutableArray *events;
@property (strong, nonatomic) UITableView *eventList;
@end

@implementation AppDelegate

- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)launchOptions {
  [ZKVideoCacheManager startReverseHost:@"http://media6.smartstudy.com"
                                  cache:nil
                            memCapacity:-1
                           diskCapacity:-1
                               listener:^(NSDictionary *info) {
                                 dispatch_async(dispatch_get_main_queue(), ^{
                                   [self showServerEvent:info];
                                 });
                               }];
  return YES;
}

- (void) showServerEvent: (NSDictionary *)e {
  if (!self.events) {
    self.events = [NSMutableArray array];
  }
  [self.events addObject:e];
  
  if (!self.eventList) {
    [self installEventList];
  }
  [self.eventList reloadData];
}

- (void) installEventList {
  CGRect listFrame = [UIScreen mainScreen].bounds;
  listFrame.origin.y = listFrame.size.height / 2.0;
  listFrame.size.height /= 2.0;
  UITableView *list = [[UITableView alloc] initWithFrame:listFrame style:UITableViewStylePlain];
  
  UIWindow *window = [[UIApplication sharedApplication] keyWindow];
  [window addSubview:list];
  self.eventList = list;
  list.delegate = self;
  list.dataSource = self;
}

- (NSInteger) numberOfSectionsInTableView:(UITableView *)tableView {
  return 1;
}

- (NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
  return self.events.count;
}

- (UITableViewCell *) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
  NSInteger idx = indexPath.row;
  UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cell"];
  if (!cell) {
    cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"cell"];
  }
  NSDictionary *e = self.events[idx];
  BOOL isReq = e[@"request"] ? YES : NO;
  cell.textLabel.text = isReq ? @"request" : @"response";
  cell.detailTextLabel.text = isReq ? [self requestDetail:e[@"request"]] : [self responseDetail:e[@"response"]];
  return cell;
}

- (NSString *) requestDetail:(NSDictionary *) e {
  return [NSString stringWithFormat:@"path: %@", e[@"path"]];
}

- (NSString *) responseDetail: (NSDictionary *) e {
  if (e[@"error"]) {
    return [NSString stringWithFormat:@"name: %@, status: %@, error: %@", e[@"name"], e[@"status"], e[@"error"]];
  } else {
    return [NSString stringWithFormat:@"name: %@, status: %@", e[@"name"], e[@"status"]];
  }
}

- (void)applicationWillResignActive:(UIApplication *)application {
  // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
  // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
}

- (void)applicationWillTerminate:(UIApplication *)application {
  // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
  return UIInterfaceOrientationMaskPortrait;
}
@end
