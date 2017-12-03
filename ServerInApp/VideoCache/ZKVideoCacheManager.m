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


@interface ZKVideoCacheManager () <NSURLSessionDataDelegate>

@property (strong, nonatomic) NSString *cacheRoot;
@property (strong, nonatomic) GCDWebServer *webServer;
@property (strong, nonatomic) NSURLSession *urlSession;
@property (copy, nonatomic) NSString *reverseHost;
@property (strong, nonatomic) NSMutableDictionary<NSString *, NSMutableDictionary *> *proxyReqRecords;
@property (strong, nonatomic) dispatch_queue_t queue;
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

+ (void)startReverseHost:(NSString *)host listener: (CallbackBlock) listener {
  ZKVideoCacheManager *theInstance = [ZKVideoCacheManager shareInstance];
  theInstance.reverseHost = host;
  theInstance.webServer = [[GCDWebServer alloc] init];
  CallbackBlock mainQueueListener = ^(NSDictionary *info) {
    dispatch_async(dispatch_get_main_queue(), ^{
      listener(info);
    });
  };
  dispatch_async(theInstance.queue, ^{
    [ZKVideoCacheManager startReverseHostImp:host listener:mainQueueListener];
  });
}

+ (void)startReverseHostImp:(NSString *)host listener: (CallbackBlock) listener {
  ZKVideoCacheManager *theInstance = [ZKVideoCacheManager shareInstance];
  ZKVideoCacheManager * __weak weakIns = theInstance;
  
  [theInstance.webServer
   addDefaultHandlerForMethod:@"GET"
   requestClass:GCDWebServerRequest.class
   asyncProcessBlock:^(GCDWebServerRequest *request, GCDWebServerCompletionBlock completion) {
     NSURL *mediaUrl = [NSURL URLWithString:[self remoteHostUrl]];
     NSURL *fullUrl = [mediaUrl URLByAppendingPathComponent:request.path];
     NSString *localPath = [ZKVideoCacheManager _cachePathForUrl:[fullUrl absoluteString]];
     if (listener) {
       listener(@{ @"request": @{ @"path": request.path ?: @"" } });
     }
     if ([[NSFileManager defaultManager] fileExistsAtPath:localPath]) {
       if (listener) {
         listener(@{ @"response": @{ @"status": @"reuse", @"name": [localPath lastPathComponent] ?: @"" } });
       }
       completion([GCDWebServerFileResponse responseWithFile:localPath]);
     } else {
       [ZKVideoCacheManager _mkdirForM3u8PlaylistUrl:[fullUrl absoluteString]];
       [weakIns download:fullUrl.absoluteString
                     toLocal:localPath
                  onComplete:^(NSDictionary *res) {
                    if (listener) {
                      listener(@{ @"response": @{ @"status": @"normal", @"name": [localPath lastPathComponent] ?: @"" } });
                    }
                    completion([GCDWebServerFileResponse responseWithFile:localPath]);
                  }
                     onError:^(NSError *err) {
                       NSLog(@"error download file: %@, err: %@", fullUrl, err);
                       if (listener) {
                         listener(@{ @"response": @{ @"status": @"fail", @"error": err ?: @"", @"name": [localPath lastPathComponent] ?: @"" } });
                       }
                       completion(nil);
                     }];
     }
   }];
  
  
  [theInstance.webServer
   addHandlerWithMatchBlock:
   ^GCDWebServerRequest *(NSString *requestMethod,
                          NSURL *requestURL,
                          NSDictionary *requestHeaders,
                          NSString *urlPath,
                          NSDictionary *urlQuery) {
    NSString *suffix = [[urlPath componentsSeparatedByString:@"."] lastObject];
    if ([suffix isEqualToString:@"mp4"]) {
      return [[GCDWebServerRequest alloc] initWithMethod:requestMethod
                                                     url:requestURL
                                                 headers:requestHeaders
                                                    path:urlPath
                                                   query:urlQuery];
    }
    return nil;
  }
   asyncProcessBlock:
   ^(__kindof GCDWebServerRequest *request, GCDWebServerCompletionBlock completionBlock) {
     [weakIns handleClientRequest:request
                       onResponse:completionBlock];
   }];
  
  dispatch_async(dispatch_get_main_queue(), ^{
    [theInstance.webServer startWithOptions:@{
                                              GCDWebServerOption_Port:@(4567),
                                              GCDWebServerOption_BindToLocalhost:@YES,
                                              } error:NULL];
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

- (void)getDataUrl:(NSString*)url
          fromByte:(int64_t)fromByte
            toByte:(int64_t)toByte
      onComplete:(void(^)(NSData *))onComplete
           onFail:(void(^)(NSError *))onFail {
  
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

+ (NSString*)_decodeM3u8Url:(NSString*)m3u8Url {
  // todo:
  return m3u8Url;
}

+ (NSString*)cacheUrlForM3u8:(NSString*)m3u8Url {
  m3u8Url = [self _decodeM3u8Url:m3u8Url];
  NSURL *serverNormalizedUrl = [NSURL URLWithString:[self serverUrl]];
  NSURL *originalUrl = [NSURL URLWithString:m3u8Url];
  NSString *path = [originalUrl path];
  NSURL *ret = [serverNormalizedUrl URLByAppendingPathComponent:path];
  return ret.absoluteString;
}


+ (void)_mkdirForM3u8PlaylistUrl:(NSString*)m3u8Url {
  NSString *path = [self _cachePathForUrl:m3u8Url];
  NSString *dir = [path stringByDeletingLastPathComponent];
  NSFileManager *fm = [NSFileManager defaultManager];
  NSError *error = nil;
  if (![fm createDirectoryAtPath:dir
     withIntermediateDirectories:YES
                      attributes:nil
                           error:&error]) {
    NSLog(@"failed to createDirectory:%@ for playlist url: %@, error: %@", dir, m3u8Url, error);
  }
}

- (NSString*)cacheRoot {
  NSArray<NSString *> *dirs = NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES);
  NSString *libDir = dirs[0];
  if (!_cacheRoot) {
    _cacheRoot = [libDir stringByAppendingPathComponent:@"M3U8Cache"];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:_cacheRoot]) {
      NSError *error = nil;
      if (![fm createDirectoryAtPath:_cacheRoot
         withIntermediateDirectories:YES
                          attributes:nil
                               error:&error]) {
        NSLog(@"failed to crteate directory: %@, error: %@", _cacheRoot, error);
        _cacheRoot = nil;
      }
    }
  }
  return _cacheRoot;
}

+ (NSString*)cacheRoot {
  return [[self shareInstance] cacheRoot];
}

+ (NSString*)_cachePathForUrl:(NSString*)url {
  NSString *root = [[self shareInstance] cacheRoot];
  NSString *relativePart = [self encodeRemoteUrlToLocalPath:url];
  return [root stringByAppendingPathComponent:relativePart];
}

+ (NSString*)encodeRemoteUrlToLocalPath:(NSString*)urlStr {
  NSMutableString *ret = [NSMutableString stringWithString:@""];
  NSURL *url = urlStr ? [NSURL URLWithString:urlStr] : nil;
  if (url.scheme) {
    NSString *lastChar = ret.length ? [ret substringFromIndex:ret.length - 1] : nil;
    if ([lastChar isEqualToString:@"/"]) {
      [ret appendFormat:@"%@", url.scheme];
    } else {
      [ret appendFormat:@"/%@", url.scheme];
    }
  }
  
  if (url.host) {
    [ret appendFormat:@"/%@", url.host];
  }
  if (url.port) {
    [ret appendFormat:@"/%@", url.port];
  }
  
  if (url.user || url.password) {
    [ret appendFormat:@"/%@-%@", url.user, url.password];
  }
  
  if (url.parameterString) {
    [ret appendFormat:@"/%@", url.parameterString];
  }
  
  if (url.query) {
    NSDictionary<NSString*, NSString*> *queryParams = [url.query URLQueryParameters];
    [queryParams
     enumerateKeysAndObjectsUsingBlock:
     ^(NSString * _Nonnull key, NSString * _Nonnull obj, BOOL * _Nonnull stop) {
       
       [ret appendFormat:@"/%@-%@", key, obj];
     }];
  }
  
  if (url.fragment) {
    [ret appendFormat:@"/%@", url.fragment];
  }
  
  NSString *lastChar = ret.length ? [ret substringFromIndex:ret.length - 1] : nil;
  if ([lastChar isEqualToString:@"/"]) {
    NSRange rg;
    rg.location = ret.length - 1;
    rg.length = 1;
    [ret deleteCharactersInRange:rg];
  }
  if (url.path) {
    [ret appendFormat:@"%@", url.path];
  }
  
  return ret;
}

+ (BOOL)clearM3u8Cache:(NSError *__autoreleasing *)perror {
  NSError *error = perror ? *perror : nil;
  NSString *cacheRoot = [[self shareInstance] cacheRoot];
  NSFileManager *fm = [NSFileManager defaultManager];
  BOOL ret = [fm removeItemAtPath:cacheRoot error:&error];
  if (!ret) {
    NSLog(@"failed to removeItemAtPath: %@, error: %@", cacheRoot, error);
  }
  return ret;
}

+ (unsigned long long)cacheSize {
  return [self sizeOfDirectory:[self cacheRoot]];
}

+ (unsigned long long)sizeOfDirectory:(NSString*)root {
  if (!root) {
    return 0;
  }
  NSURL *rootUrl = [NSURL fileURLWithPath:root];
  unsigned long long ret = 0;
  NSFileManager *fm = [NSFileManager defaultManager];
  NSDirectoryEnumerator *directoryEnumerator =
  [fm enumeratorAtURL:rootUrl
includingPropertiesForKeys:@[NSURLIsRegularFileKey,
                             NSURLFileSizeKey]
              options: NSDirectoryEnumerationSkipsHiddenFiles
         errorHandler:nil];
  for (NSURL *file in directoryEnumerator) {
    NSError *error = nil;
    NSDictionary *values = nil;
    if ((values = [file resourceValuesForKeys:@[NSURLIsRegularFileKey, NSURLFileSizeKey] error:&error])) {
      if ([values[NSURLIsRegularFileKey] boolValue]) {
        ret += [values[NSURLFileSizeKey] longLongValue];
      }
    } else {
      NSLog(@"failed to getResourceValue for file: %@, error: %@", file, error);
    }
  }
  return ret;
}

// utils
+ (NSArray<NSNumber *> *) parseRange:(NSString *)rangeHeaderValue {
  // todo: range may be of other format?: like bytes=111
  NSString *rangeStr = [rangeHeaderValue componentsSeparatedByString:@"="].lastObject;
  NSArray *fromTo = [rangeStr componentsSeparatedByString:@"-"];
  int64_t from = [fromTo.firstObject longLongValue];
  int64_t to = [fromTo.lastObject longLongValue];
  return @[@(from), @(to)];
}

+ (NSString *) assembleRangeStr: (NSArray<NSNumber *> *) range {
  int64_t from = [range.firstObject longLongValue];
  int64_t to = [range.lastObject longLongValue];
  return [NSString stringWithFormat:@"bytes=%lld-%lld", from, to];
}

+ (NSArray<NSNumber *> *) restrictedRange: (NSArray<NSNumber *> *) rg {
  return rg;
  int64_t from = [rg.firstObject longLongValue];
  int64_t to = [rg.lastObject longLongValue];
  int64_t refrainedTo = MIN(from + 512 * 1024 - 1, to);
  return @[@(from), @(refrainedTo)];
}

+ (void) handleOrigRequest:(GCDWebServerRequest *)request
            remoteResponse:(NSURLResponse *)response
        remoteResponseData:(id)responseObject
                  callback:(GCDWebServerCompletionBlock) callback {
  NSData *data = (NSData*)responseObject;
  NSDictionary<NSString*, id> *headers =
  [(NSHTTPURLResponse*)response allHeaderFields];
  GCDWebServerDataResponse *resp = [GCDWebServerDataResponse
                                    responseWithData:data
                                    contentType:headers[@"Content-Type"]];
  resp.statusCode = [(NSHTTPURLResponse*)response statusCode];
  
  [headers enumerateKeysAndObjectsUsingBlock:
   ^(NSString * _Nonnull key,
     id  _Nonnull obj,
     BOOL * _Nonnull stop) {
     [resp setValue:obj forAdditionalHeader:key];
   }];
  
//  [resp setValue:[NSString stringWithFormat:@"%lld", refrainedTo + 1 - from]
//forAdditionalHeader:@"Content-Length"];
//
//  NSString *totalLenStr = [headers[@"Content-Range"] componentsSeparatedByString:@"/"].lastObject;
//  int64_t totalLen = [totalLenStr longLongValue];
//
//  [resp setValue:[NSString stringWithFormat:@"bytes %lld-%lld/%lld", from, to, totalLen]
//forAdditionalHeader:@"Content-Range"];
//
//  if (refrainedTo + 1 < totalLen) {
//    resp.statusCode = 206;
//  }
//  resp.contentLength = to + 1 - from;
  callback(resp);
}

- (void) download:(NSString *)urlStr
          toLocal:(NSString *) path
       onComplete:(CallbackBlock) OnComplete
          onError:(ErrorBlock) onError {
  
  NSURLSession *manager = self.urlSession;
  NSURL *URL = [NSURL URLWithString:urlStr];
  NSURLRequest *request = [NSURLRequest requestWithURL:URL];
  
  NSURLSessionDownloadTask *task = nil;
  task = [manager
          downloadTaskWithRequest:request
          completionHandler:
          ^(NSURL * _Nullable location,
            NSURLResponse * _Nullable response,
            NSError * _Nullable error) {
            
            NSURL *pathUrl = [NSURL fileURLWithPath:path];
            BOOL moveFileRc = [[NSFileManager defaultManager] moveItemAtURL:location toURL:pathUrl error:&error];
            if (error || !moveFileRc) {
              onError(error);
            } else {
              NSNull *nul = [NSNull null];
              OnComplete(@{ @"response": response ?: nul });
            }
          }];
  [task resume];
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
    NSLog(@"dataCallback: data length(%u)", d.length);
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
    NSLog(@"dataCallback: finish, will clear rec");
  } else {
    NSLog(@"dataCallback: no data yet, will wait");
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
      // other kind of request, not in a proxy record
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
    resp.contentLength = [headers[@"Content-Length"] longLongValue];
    resp.statusCode = [remoteResp statusCode];
    
    NSLog(@"did receive response(%@), headers(%@)", response, headers);
    
    onComplete(resp);
    completionHandler(NSURLSessionResponseAllow);
  });
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data {
  dispatch_async(self.queue, ^{
    NSLog(@"task(%@) receeive data(length: %u)", dataTask, data.length);
    NSString *key = [self getProxyRecordForTask:dataTask];
    [self enqueueResponseData:data recKey:key];
    [self flushQueuedDataForKey:key dataCallback:nil];
  });
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
  dispatch_async(self.queue, ^{
    NSLog(@"task(%@) complete error(%@)", task, error);
    NSString *key = [self getProxyRecordForTask:task];
    [self finishProxyRecord:key error:error];
    [self flushQueuedDataForKey:key dataCallback:nil];
  });
}
@end
