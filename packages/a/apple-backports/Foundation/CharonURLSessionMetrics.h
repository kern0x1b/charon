#import <Foundation/Foundation.h>

@interface NSURLSessionTaskTransactionMetrics (CharonWriting)
- (instancetype)initCharonWithRequest:(NSURLRequest *)request fetchType:(NSURLSessionTaskMetricsResourceFetchType)fetchType;
- (void)charon_receivedResponse:(NSURLResponse *)response;
- (void)charon_finished;
- (BOOL)charon_isFinished;
@end

@interface NSURLSessionTaskMetrics (CharonWriting)
- (instancetype)initCharonWithTransactions:(NSArray<NSURLSessionTaskTransactionMetrics *> *)transactions start:(NSDate *)start end:(NSDate *)end;
@end
