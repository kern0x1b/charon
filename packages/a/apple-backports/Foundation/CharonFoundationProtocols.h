// CharonFoundationProtocols.h — the Foundation protocols the SDK this package compiles against does not declare,
// transcribed from the SDK that does, by .agent-work/probe/transcribe-protocols.py: the base list,
// the member names, their types and whether each is required or optional, as the compiler reports
// them. Facts only, and API_AVAILABLE(ios(<introduced>)) so the lift and a band place the row by the
// release it arrived in. A protocol a band's own header already declares is not here.
#import <Foundation/Foundation.h>
#import <objc/NSObject.h>

API_AVAILABLE(ios(13.0))
@protocol NSURLSessionWebSocketDelegate <NSURLSessionTaskDelegate>
- (void)URLSession:(NSURLSession * _Nonnull)session webSocketTask:(NSURLSessionWebSocketTask * _Nonnull)webSocketTask didOpenWithProtocol:(NSString * _Nullable)protocol;
- (void)URLSession:(NSURLSession * _Nonnull)session webSocketTask:(NSURLSessionWebSocketTask * _Nonnull)webSocketTask didCloseWithCode:(NSURLSessionWebSocketCloseCode)closeCode reason:(NSData * _Nullable)reason;
@end

API_AVAILABLE(ios(7.0))
@protocol NSURLSessionDataDelegate <NSURLSessionTaskDelegate>
- (void)URLSession:(NSURLSession * _Nonnull)session dataTask:(NSURLSessionDataTask * _Nonnull)dataTask didReceiveResponse:(NSURLResponse * _Nonnull)response completionHandler:(void (^ _Nonnull)(NSURLSessionResponseDisposition))completionHandler;
- (void)URLSession:(NSURLSession * _Nonnull)session dataTask:(NSURLSessionDataTask * _Nonnull)dataTask didBecomeDownloadTask:(NSURLSessionDownloadTask * _Nonnull)downloadTask;
- (void)URLSession:(NSURLSession * _Nonnull)session dataTask:(NSURLSessionDataTask * _Nonnull)dataTask didBecomeStreamTask:(NSURLSessionStreamTask * _Nonnull)streamTask;
- (void)URLSession:(NSURLSession * _Nonnull)session dataTask:(NSURLSessionDataTask * _Nonnull)dataTask didReceiveData:(NSData * _Nonnull)data;
- (void)URLSession:(NSURLSession * _Nonnull)session dataTask:(NSURLSessionDataTask * _Nonnull)dataTask willCacheResponse:(NSCachedURLResponse * _Nonnull)proposedResponse completionHandler:(void (^ _Nonnull)(NSCachedURLResponse * _Nullable))completionHandler;
@end

API_AVAILABLE(ios(7.0))
@protocol NSURLSessionDelegate <NSObject>
@end

API_AVAILABLE(ios(7.0))
@protocol NSURLSessionDownloadDelegate <NSURLSessionTaskDelegate>
- (void)URLSession:(NSURLSession * _Nonnull)session downloadTask:(NSURLSessionDownloadTask * _Nonnull)downloadTask didFinishDownloadingToURL:(NSURL * _Nonnull)location;
- (void)URLSession:(NSURLSession * _Nonnull)session downloadTask:(NSURLSessionDownloadTask * _Nonnull)downloadTask didWriteData:(int64_t)bytesWritten totalBytesWritten:(int64_t)totalBytesWritten totalBytesExpectedToWrite:(int64_t)totalBytesExpectedToWrite;
- (void)URLSession:(NSURLSession * _Nonnull)session downloadTask:(NSURLSessionDownloadTask * _Nonnull)downloadTask didResumeAtOffset:(int64_t)fileOffset expectedTotalBytes:(int64_t)expectedTotalBytes;
@end

API_AVAILABLE(ios(7.0))
@protocol NSURLSessionTaskDelegate <NSObject>
@end
