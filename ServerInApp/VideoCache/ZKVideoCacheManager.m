//
//  M3U8CacheManager.m
//  ServerInApp
//
//  Created by wansong on 12/31/16.
//  Copyright © 2016 zhike. All rights reserved.
//

#import "ZKVideoCacheManager.h"
#import "AFNetworking.h"
#import "RequestUtils.h"
#import "GCDWebServer.h"
#import "GCDWebServerFileResponse.h"
#import "GCDWebServerDataResponse.h"


@interface ZKVideoCacheManager ()

@property (strong, nonatomic) NSString *cacheRoot;
@property (strong, nonatomic) GCDWebServer *webServer;
@property (strong, nonatomic) AFURLSessionManager *requestManager;
@property (copy, nonatomic) NSString *reverseHost;
@end

@implementation ZKVideoCacheManager

+ (instancetype)shareInstance {
  static dispatch_once_t onceToken;
  static ZKVideoCacheManager *ret = nil;
  dispatch_once(&onceToken, ^{
    ret = [[ZKVideoCacheManager alloc] init];
  });
  return ret;
}

+ (void)startReverseHost:(NSString *)host listener: (CallbackBlock) listener {
//  ZKNetwork *downloader = [ZKNetwork sharedInstance];
//  [downloader start];
//  NSOperationQueue *opQueue = downloader.operationQueue;
  
  ZKVideoCacheManager *theInstance = [ZKVideoCacheManager shareInstance];
  theInstance.reverseHost = host;
//  theInstance.requestManager = [[AFHTTPSessionManager alloc] init];
//  theInstance.requestManager.responseSerializer = [AFHTTPResponseSerializer serializer];
  theInstance.webServer = [[GCDWebServer alloc] init];
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
#ifdef DEBUG
       NSLog(@"begin downloading original url: %@", fullUrl);
#endif
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
  
  
  [theInstance.webServer startWithOptions:@{
                                            GCDWebServerOption_Port:@(4567),
                                            GCDWebServerOption_BindToLocalhost:@YES,
                                            } error:NULL];
//  typeof (theInstance) __weak weakIns = theInstance;
//  [theInstance.webServer
//   addHandlerWithMatchBlock:
//   ^GCDWebServerRequest *(NSString *requestMethod,
//                          NSURL *requestURL,
//                          NSDictionary *requestHeaders,
//                          NSString *urlPath,
//                          NSDictionary *urlQuery) {
//    NSString *suffix = [[urlPath componentsSeparatedByString:@"."] lastObject];
//    if ([suffix isEqualToString:@"mp4"]) {
//      NSLog(
//            @"requestMethod: %@, url: %@, headers: %@, urlPath: %@, urlQuery: %@",
//            requestMethod,
//            requestURL,
//            requestHeaders,
//            urlPath,
//            urlQuery);
//      return [[GCDWebServerRequest alloc] initWithMethod:requestMethod
//                                                     url:requestURL
//                                                 headers:requestHeaders
//                                                    path:urlPath
//                                                   query:urlQuery];
//    }
//    return nil;
//  }
//   asyncProcessBlock:
//   ^(__kindof GCDWebServerRequest *request, GCDWebServerCompletionBlock completionBlock) {
//     NSURL *mediaUrl = [NSURL URLWithString:[self remoteHostUrl]];
//     NSURL *fullUrl = [mediaUrl URLByAppendingPathComponent:request.path];
//     AFHTTPRequestSerializer *serializer = [AFHTTPRequestSerializer serializer];
//     serializer.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
//     NSDictionary<NSString *, id> *headers = [request headers];
//     [headers enumerateKeysAndObjectsUsingBlock:
//      ^(NSString * _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
//       if (![key isEqualToString:@"Host"]) {
//         [serializer setValue:obj forHTTPHeaderField:key];
//       }
//     }];
//     [serializer setValue:@"media6.smartstudy.com" forHTTPHeaderField:@"Host"];
//     
//     NSString *rangeStr = [headers[@"Range"] componentsSeparatedByString:@"="].lastObject;
//     NSArray *fromTo = [rangeStr componentsSeparatedByString:@"-"];
//     int64_t from = [fromTo.firstObject longLongValue];
//     int64_t to = [fromTo.lastObject longLongValue];
//     int64_t refrainedTo = MIN(from + 512 * 1024 - 1, to);
//     [serializer setValue:[NSString stringWithFormat:@"bytes=%lld-%lld", from, refrainedTo]
//       forHTTPHeaderField:@"Range"];
//     
//     NSLog(
//           @"faking request from player, header: %@, url: %@",
//           [serializer HTTPRequestHeaders], fullUrl);
//     
//     NSError *error = nil;
//     NSURLRequest *req = [serializer requestWithMethod:@"GET"
//                                             URLString:[fullUrl absoluteString]
//                                            parameters:nil
//                                                 error:&error];
//     if (error) {
//       NSLog(
//             @"error when create request using serializer, url: %@, headers: %@, error: %@",
//             fullUrl,
//             [serializer HTTPRequestHeaders],
//             error);
//     }
//     NSMutableURLRequest *mutableReq = [req mutableCopy];
//     [mutableReq setNetworkServiceType:NSURLNetworkServiceTypeVideo];
//     if (mutableReq) {
//       NSURLSessionTask *task = [weakIns.requestManager
//                                 dataTaskWithRequest:mutableReq
//                                 completionHandler:
//                                 ^(NSURLResponse * _Nonnull response,
//                                   id  _Nullable responseObject,
//                                   NSError * _Nullable error) {
//                                   if (error) {
//                                     completionBlock(nil);
//                                     NSLog(@"dataTask failed with error: %@", error);
//                                     return;
//                                   }
//                                   NSData *data = (NSData*)responseObject;
//                                   NSDictionary<NSString*, id> *headers =
//                                   [(NSHTTPURLResponse*)response allHeaderFields];
//                                   GCDWebServerDataResponse *resp = [GCDWebServerDataResponse
//                                                                     responseWithData:data
//                                                                     contentType:headers[@"Content-Type"]];
//                                   resp.statusCode = [(NSHTTPURLResponse*)response statusCode];
//
//                                   [headers enumerateKeysAndObjectsUsingBlock:
//                                    ^(NSString * _Nonnull key,
//                                      id  _Nonnull obj,
//                                      BOOL * _Nonnull stop) {
//                                      [resp setValue:obj forAdditionalHeader:key];
//                                    }];
//                                   
//                                   [resp setValue:[NSString stringWithFormat:@"%lld", refrainedTo + 1 - from]
//                              forAdditionalHeader:@"Content-Length"];;
//                                   NSString *totalLenStr = [headers[@"Content-Range"] componentsSeparatedByString:@"/"].lastObject;
//                                   int64_t totalLen = [totalLenStr longLongValue];
//                                   [resp setValue:[NSString stringWithFormat:@"bytes %lld-%lld/%lld", from, to, totalLen]
//                              forAdditionalHeader:@"Content-Range"];
//                                   if (refrainedTo + 1 < totalLen) {
//                                     resp.statusCode = 206;
//                                   }
//                                   resp.contentLength = to + 1 - from;
//                                   
//                                   NSLog(
//                                         @"did get sever response: %@, relay to player using response: %@",
//                                         response,
//                                         resp);
//                                   completionBlock(resp);
//                                 }];
//       [task resume];
//     } else {
//       completionBlock(nil);
//     }
//   }];

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

- (void) download:(NSString *)urlStr
          toLocal:(NSString *) path
       onComplete:(CallbackBlock) OnComplete
          onError:(ErrorBlock) onError {
  if (!self.requestManager) {
    [self configRequestManager];
  }
  
  AFURLSessionManager *manager = self.requestManager;
  NSURL *URL = [NSURL URLWithString:urlStr];
  NSURLRequest *request = [NSURLRequest requestWithURL:URL];
  
  NSURLSessionDownloadTask *downloadTask =
  [manager
   downloadTaskWithRequest:request
   progress:nil
   destination:^NSURL *(NSURL *targetPath, NSURLResponse *response) { return [NSURL fileURLWithPath:path]; }
   completionHandler:^(NSURLResponse *response, NSURL *filePath, NSError *error) {
     if (error) {
       onError(error);
     } else {
       NSNull *nul = [NSNull null];
       OnComplete(@{ @"response": response ?: nul, @"filePath": filePath ?: nul });
     }
   }];
  
  [downloadTask resume];
}

- (void) configRequestManager {
  NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
  AFURLSessionManager *manager = [[AFURLSessionManager alloc] initWithSessionConfiguration:configuration];
  self.requestManager = manager;
}

- (void) dealloc {
  self.requestManager = nil;
}

@end
