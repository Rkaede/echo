#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const ECHObjCExceptionCatcherErrorDomain;
FOUNDATION_EXPORT NSString *const ECHObjCExceptionNameErrorKey;
FOUNDATION_EXPORT NSString *const ECHObjCExceptionReasonErrorKey;

@interface ECHObjCExceptionCatcher : NSObject

+ (BOOL)tryBlock:(NS_NOESCAPE void (^)(void))block
           error:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
