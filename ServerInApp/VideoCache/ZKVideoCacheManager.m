//
//  M3U8CacheManager.m
//  ServerInApp
//
//  Created by wansong on 12/31/16.
//  Copyright © 2016 zhike. All rights reserved.
//

#import "ZKVideoCacheManager.h"
#import "RequestUtils.h"
#import "GCDWebServer.h"
#import "GCDWebServerFileResponse.h"
#import "GCDWebServerDataResponse.h"
#import "ZKGCDWebServerStreamedResponse.h"
#import "ZKSimpleFIFO.h"
//
//@interface ZKRangeRequestAdapterServer: NSObject
//@end
//
//@implementation ZKRangeRequestAdapterServer
//@end


@interface ZKVideoCacheManager () <NSURLSessionDataDelegate>
@property (strong, nonatomic) GCDWebServer *webServer;
@property (strong, nonatomic) NSURLSession *urlSession;
@property (copy, nonatomic) NSString *reverseHost;
@property (strong, nonatomic) NSMutableDictionary<NSString *, NSMutableDictionary *> *proxyReqRecords;
@property (strong, nonatomic) dispatch_queue_t queue;
@property (strong, nonatomic) NSURLCache *cache;
@end


@implementation ZKVideoCacheManager
+ (instancetype)shareInstance {
  static dispatch_once_t onceToken;
  static ZKVideoCacheManager *ret = nil;
  dispatch_once(&onceToken, ^{
    ret = [[ZKVideoCacheManager alloc] init];
    ret.proxyReqRecords = [NSMutableDictionary dictionary];
    ret.queue = dispatch_queue_create("ZKVideoCacheManager", DISPATCH_QUEUE_SERIAL);
  });
  return ret;
}

+ (NSURLCache *) getCacheMemoryCap:(NSUInteger)memCap diskCap:(NSUInteger)diskCap {
  static dispatch_once_t onceToken;
  static NSURLCache *cache = nil;
  dispatch_once(&onceToken, ^{
    NSBundle *bd = [NSBundle mainBundle];
    NSString *bid = (NSString *)[bd objectForInfoDictionaryKey:(NSString *)kCFBundleIdentifierKey];
    NSString *cacheFilename = [NSString stringWithFormat:@"%@.cache", bid];
    NSString *cacheDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES)[0];
    NSString *cachePath = [cacheDir stringByAppendingPathComponent:cacheFilename];
    cache = [[NSURLCache alloc] initWithMemoryCapacity:memCap ?: (10 << 20)
                                          diskCapacity:diskCap ?: (100 << 20)
                                              diskPath:cachePath];
    [NSURLCache setSharedURLCache:cache];
  });
  return cache;
}

+ (void)startReverseHostImp:(NSString *)host
                      cache:(NSURLCache *)cache
                memCapacity:(NSUInteger)memCap
               diskCapacity:(NSUInteger)diskCap
                   listener:(CallbackBlock) listener {
  ZKVideoCacheManager *theInstance = [ZKVideoCacheManager shareInstance];
  theInstance.reverseHost = host;
  
  if (cache) {
    theInstance.cache = cache;
  } else {
    theInstance.cache = [self getCacheMemoryCap:memCap diskCap:diskCap];
  }
  
  ZKVideoCacheManager * __weak weakIns = theInstance;
  
  [theInstance.webServer
   addDefaultHandlerForMethod:@"GET"
   requestClass:GCDWebServerRequest.class
   asyncProcessBlock:^(GCDWebServerRequest *request, GCDWebServerCompletionBlock completion) {
     [weakIns handleClientRequest:request
                       onResponse:completion];
   }];
  
  dispatch_async(dispatch_get_main_queue(), ^{
    [theInstance.webServer startWithOptions:@{
                                              GCDWebServerOption_Port:@(4567),
                                              GCDWebServerOption_BindToLocalhost:@YES,
                                              } error:NULL];
  });
}

+ (void)startReverseHost:(NSString *)host
                   cache:(NSURLCache *)cache
             memCapacity:(NSUInteger)memCap
            diskCapacity:(NSUInteger)diskCap
                listener:(CallbackBlock) listener {
  ZKVideoCacheManager *theInstance = [ZKVideoCacheManager shareInstance];
  theInstance.webServer = [[GCDWebServer alloc] init];
  
  dispatch_async(theInstance.queue, ^{
    [self startReverseHostImp:host
                        cache:cache
                  memCapacity:memCap
                 diskCapacity:diskCap
                     listener:listener];
  });
}

- (void)handleClientRequest:(GCDWebServerRequest *)clientRequest
                 onResponse: (GCDWebServerCompletionBlock) completionBlock {
  
  NSURL *mediaUrl = [NSURL URLWithString:[self.class remoteHostUrl]];
  NSURL *fullUrl = [mediaUrl URLByAppendingPathComponent:clientRequest.path];
  NSDictionary<NSString *, id> *headers = [clientRequest headers];
  NSMutableURLRequest *mutableReq = [NSMutableURLRequest requestWithURL:fullUrl];
  
  [headers enumerateKeysAndObjectsUsingBlock:
   ^(NSString * _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
     if (![key isEqualToString:@"Host"]) {
       [mutableReq setValue:obj forHTTPHeaderField:key];
     }
   }];
  NSMutableDictionary *requestHeaders = [NSMutableDictionary dictionary];
  [[mutableReq allHTTPHeaderFields] enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
    requestHeaders[key] = [mutableReq valueForHTTPHeaderField:key];
  }];
  
  NSURLSession *session = self.urlSession;
  
  NSURLSessionDataTask *task = nil;
  task = [session dataTaskWithRequest:mutableReq];
  
  NSString *recKey = [self getProxyRecordForTask:task];
  NSMutableDictionary *rec = [NSMutableDictionary
                              dictionaryWithObjectsAndKeys:completionBlock,
                              @"responseCallback",
                              clientRequest, @"request", nil];
  [self addProxyRecord:rec forKey:recKey];
  [task resume];
}

- (void) addProxyRecord:(NSMutableDictionary *)rec forKey:(NSString *) recKey {
  NSMutableDictionary *proxyRecs = self.proxyReqRecords;
  proxyRecs[recKey] = rec;
}

- (NSString *)getProxyRecordForTask:(NSURLSessionTask *)task {
  return [NSString stringWithFormat:@"%lu", task.taskIdentifier];
}

- (void) clearProxyRecord:(NSString *) key {
  NSMutableDictionary *proxyRecs = self.proxyReqRecords;
  if (key && proxyRecs[key]) {
    [proxyRecs removeObjectForKey:key];
  }
}

+ (NSString*)serverUrl {
  NSMutableString *ret = [[[self shareInstance] webServer].serverURL.absoluteString mutableCopy];
  NSRange rg;
  rg.length = 1;
  rg.location = ret.length - 1;
  while ([[ret substringWithRange:rg] isEqualToString:@"/"]) {
    [ret deleteCharactersInRange:rg];
    rg.location = ret.length - 1;
  }
  return ret;
}

+ (NSString*)remoteHostUrl {
  return [ZKVideoCacheManager shareInstance].reverseHost;
}

+ (NSString*)getProxyUrl:(NSString*)origUrl {
  NSURL *serverNormalizedUrl = [NSURL URLWithString:[self serverUrl]];
  NSURL *originalUrl = [NSURL URLWithString:origUrl];
  NSString *path = [originalUrl path];
  NSURL *ret = [serverNormalizedUrl URLByAppendingPathComponent:path];
  return ret.absoluteString;
}

- (NSURLSession *)urlSession {
  if (!_urlSession) {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.networkServiceType = NSURLNetworkServiceTypeVideo;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config
                                                          delegate:self
                                                     delegateQueue:nil];
    _urlSession = session;
  }
  return _urlSession;
}

- (void) dealloc {
  self.urlSession = nil;
}

- (void) enqueueResponseData:(NSData *) data recKey:(NSString *)recKey {
  NSMutableDictionary *rec = self.proxyReqRecords[recKey];
  if (!rec) {
    return;
  }
  ZKSimpleFIFO *datas = rec[@"datas"];
  if (!datas) {
    datas = [[ZKSimpleFIFO alloc] init];
    rec[@"datas"] = datas;
  }
  
  NSMutableData *d = [datas peek];
  if (!d) {
    d = [NSMutableData dataWithBytes:data.bytes length:data.length];
    [datas enqueue:d];
  } else {
    [d appendBytes:data.bytes length:data.length];
  }
}

- (void) flushQueuedDataForKey:(NSString *) recKey
                  dataCallback:(GCDWebServerBodyReaderCompletionBlock) dataCallback {
  NSMutableDictionary *rec = self.proxyReqRecords[recKey];
  if (!rec) {
    return;
  }
  BOOL finished = [rec[@"finished"] boolValue];
  NSError *error = rec[@"error"];
  
  GCDWebServerBodyReaderCompletionBlock savedDataCallback = rec[@"dataCallback"];
  if (dataCallback && savedDataCallback) {
    NSAssert(NO, @"");
    NSLog(@"Should not happen because dataCallback is serial, means sth bad happened! Will ignore the savedOne");
    [rec removeObjectForKey:@"dataCallback"];
  } else if (!dataCallback && !savedDataCallback) {
    return;
  } else if (!dataCallback) {
    dataCallback = savedDataCallback;
    [rec removeObjectForKey:@"dataCallback"];
  }
  
  ZKSimpleFIFO *q = rec[@"datas"];
  NSData *d = q ? [q peek] : nil;

  if (d && !error) { // assume d will not be empty
    dataCallback(d, nil);
    if (rec[@"dataCallback"]) {
      [rec removeObjectForKey:@"dataCallback"];
    }
    [q dequeue];
  } else if (error) {
    dataCallback(nil, error);
    [self clearProxyRecord:recKey];
    NSLog(@"dataCallback: error(%@), will clear rec", error);
  } else if (finished) {
    dataCallback([NSData data], nil);
    [self clearProxyRecord:recKey];
  } else {
    NSAssert(!rec[@"dataCallback"], @"");
    rec[@"dataCallback"] = dataCallback;
  }
}

- (void)finishProxyRecord:(NSString *) key error: (NSError *) error {
  NSMutableDictionary *rec = self.proxyReqRecords[key];
  rec[@"finished"] = @(YES);
  if (error) {
    rec[@"error"] = error;
  }
}

// implements: NSURLSessionDataTask
- (void)URLSession:(NSURLSession *)session
          dataTask:(NSURLSessionDataTask *)dataTask
didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
  dispatch_async(self.queue, ^{
    NSAssert([response isKindOfClass:NSHTTPURLResponse.class], @"");
    NSHTTPURLResponse *remoteResp = (NSHTTPURLResponse *)response;
    NSDictionary *headers = [remoteResp allHeaderFields];
    NSString *contentType = headers[@"Content-Type"];
    NSString *fatalErrorMsg = [NSString stringWithFormat:@"no Content-Type in header: %@", headers];
    NSAssert(contentType, fatalErrorMsg);
    NSString *recKey = [self getProxyRecordForTask:dataTask];
    NSMutableDictionary *rec = self.proxyReqRecords[recKey];
    if (!rec) {
      // fixme: make sure this does not happen ? other kind of request, not in a proxy record
      completionHandler(NSURLSessionResponseAllow);
      return;
    }
    
    GCDWebServerCompletionBlock onComplete = rec[@"responseCallback"];
    ZKGCDWebServerStreamedResponse *resp;
    resp = [ZKGCDWebServerStreamedResponse
            responseWithContentType:contentType
            asyncStreamBlock:^(GCDWebServerBodyReaderCompletionBlock completionBlock) {
              dispatch_async(self.queue, ^{
                [self flushQueuedDataForKey:recKey dataCallback:completionBlock];
              });
            }];
    resp.onClose = ^{
      // todo
      [dataTask cancel];
      [self clearProxyRecord:recKey];
    };
    
    [headers enumerateKeysAndObjectsUsingBlock:
     ^(NSString * _Nonnull key,
       id  _Nonnull obj,
       BOOL * _Nonnull stop) {
       if (![[key lowercaseString] isEqualToString:@"host"]) {
         [resp setValue:obj forAdditionalHeader:key];
       }
     }];
    resp.contentType = contentType;
    resp.contentLength = (NSUInteger)[headers[@"Content-Length"] integerValue];
    resp.statusCode = [remoteResp statusCode];
    
    onComplete(resp);
    completionHandler(NSURLSessionResponseAllow);
  });
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
  dispatch_async(self.queue, ^{
    if (dataTask.state == NSURLSessionTaskStateCanceling) {
      return;
    }
    NSString *key = [self getProxyRecordForTask:dataTask];
    [self enqueueResponseData:data recKey:key];
    [self flushQueuedDataForKey:key dataCallback:nil];
  });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
  dispatch_async(self.queue, ^{
    if (task.state == NSURLSessionTaskStateCanceling) {
      return;
    }
    NSString *key = [self getProxyRecordForTask:task];
    [self finishProxyRecord:key error:error];
    [self flushQueuedDataForKey:key dataCallback:nil];
  });
}
@end
