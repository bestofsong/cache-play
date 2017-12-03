//
//  ZKGCDWebServerStreamedResponse.h
//  ServerInApp
//
//  Created by wansong on 03/12/2017.
//  Copyright © 2017 zhike. All rights reserved.
//

#import <GCDWebServer/GCDWebServer.h>
#import "GCDWebServerStreamedResponse.h"

@interface ZKGCDWebServerStreamedResponse : GCDWebServerStreamedResponse
@property (copy, nonatomic) dispatch_block_t onClose;
@end
