//
//  ZKSimpleFIFO.h
//  ServerInApp
//
//  Created by wansong on 04/12/2017.
//  Copyright © 2017 zhike. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface ZKSimpleFIFO : NSObject

- (void) enqueue:(nonnull id) elem;
- (nonnull id) dequeue;
- (BOOL) isEmpty;
- (nullable id) peek;

@end
