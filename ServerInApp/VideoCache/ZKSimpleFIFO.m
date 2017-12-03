//
//  ZKSimpleFIFO.m
//  ServerInApp
//
//  Created by wansong on 04/12/2017.
//  Copyright © 2017 zhike. All rights reserved.
//

#import "ZKSimpleFIFO.h"
@interface ZKSimpleFIFO ()

@property (strong, nonatomic) NSMutableArray *inStack;
@property (strong, nonatomic) NSMutableArray *outStack;

@end

@implementation ZKSimpleFIFO

- (instancetype) init {
  self = [super init];
  if (self) {
    _inStack = [NSMutableArray array];
    _outStack = [NSMutableArray array];
  }
  return self;
}

- (id) dequeue {
  if ([self isEmpty]) {
    @throw [NSException exceptionWithName:@"DequeueError"
                                   reason:@"queue is empty"
                                 userInfo:nil];
  }
  id ret;
  if (_outStack.count) {
    ret = [_outStack lastObject];
    [_outStack removeLastObject];
    return ret;
  }
  
  [_inStack enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
    [_outStack addObject:obj];
  }];
  [_inStack removeAllObjects];
  
  return [self dequeue];
}

- (void) enqueue:(id)elem {
  [_inStack addObject:elem];
}

- (NSUInteger) count {
  return _inStack.count + _outStack.count;
}

- (BOOL) isEmpty {
  return ![self count];
}

- (id) peek {
  if ([self isEmpty]) {
    return nil;
  }
  [_inStack enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
    [_outStack addObject:obj];
  }];
  [_inStack removeAllObjects];
  if (!_outStack.count) {
    @throw [NSException exceptionWithName:@"DequeueError"
                                   reason:@"queue is empty"
                                 userInfo:nil];
  }

  return [_outStack lastObject];
}
@end
