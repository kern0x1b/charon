// CharonFoundationProtocols.h — the Foundation protocols the SDK this package compiles against does not declare,
// transcribed by tools/transcribe-protocols.py from the SDK that declares them: the base list, each
// member with its kind, return type and parameter types, @required and @optional as sections, and
// API_AVAILABLE(ios(<introduced>)) so the lift and a band place the row by the release it arrived in.
// Facts only, and nothing written for a protocol or a member the generator refused by name below.
#import <Foundation/Foundation.h>
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

API_AVAILABLE(ios(7.0))
@protocol NSURLSessionDataDelegate <NSURLSessionTaskDelegate>
- ()URLSession:(NSURLSession * _Nonnull)session dataTask:(NSURLSessionDataTask * _Nonnull)dataTask didReceiveResponse:(NSURLResponse * _Nonnull)response completionHandler:(void (^ _Nonnull)(NSURLSessionResponseDisposition))completionHandler;
- ()URLSession:(NSURLSession * _Nonnull)session dataTask:(NSURLSessionDataTask * _Nonnull)dataTask didBecomeDownloadTask:(NSURLSessionDownloadTask * _Nonnull)downloadTask;
- ()URLSession:(NSURLSession * _Nonnull)session dataTask:(NSURLSessionDataTask * _Nonnull)dataTask didBecomeStreamTask:(NSURLSessionStreamTask * _Nonnull)streamTask;
- ()URLSession:(NSURLSession * _Nonnull)session dataTask:(NSURLSessionDataTask * _Nonnull)dataTask didReceiveData:(NSData * _Nonnull)data;
- ()URLSession:(NSURLSession * _Nonnull)session dataTask:(NSURLSessionDataTask * _Nonnull)dataTask willCacheResponse:(NSCachedURLResponse * _Nonnull)proposedResponse completionHandler:(void (^ _Nonnull)(NSCachedURLResponse * _Nullable))completionHandler;
@end

API_AVAILABLE(ios(7.0))
@protocol NSURLSessionDelegate <NSObject>
@end

API_AVAILABLE(ios(7.0))
@protocol NSURLSessionTaskDelegate <NSURLSessionDelegate>
@end

API_AVAILABLE(ios(13.0))
@protocol NSURLSessionWebSocketDelegate <NSURLSessionTaskDelegate>
- ()URLSession:(NSURLSession * _Nonnull)session webSocketTask:(NSURLSessionWebSocketTask * _Nonnull)webSocketTask didOpenWithProtocol:(NSString * _Nullable)protocol;
- ()URLSession:(NSURLSession * _Nonnull)session webSocketTask:(NSURLSessionWebSocketTask * _Nonnull)webSocketTask didCloseWithCode:(NSURLSessionWebSocketCloseCode)closeCode reason:(NSData * _Nullable)reason;
@end
