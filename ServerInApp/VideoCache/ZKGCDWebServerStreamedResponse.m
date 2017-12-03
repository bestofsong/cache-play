//
//  ZKGCDWebServerStreamedResponse.m
//  ServerInApp
//
//  Created by wansong on 03/12/2017.
//  Copyright © 2017 zhike. All rights reserved.
//

#import "ZKGCDWebServerStreamedResponse.h"

@implementation ZKGCDWebServerStreamedResponse

- (void) close {
  dispatch_block_t onClose = self.onClose;
  if (onClose) {
    onClose();
  }
  [super close];
}

@end
