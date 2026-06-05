#import "ECHObjCExceptionCatcher.h"

NSString *const ECHObjCExceptionCatcherErrorDomain = @"io.littlecove.echo.objc-exception";
NSString *const ECHObjCExceptionNameErrorKey = @"ECHObjCExceptionName";
NSString *const ECHObjCExceptionReasonErrorKey = @"ECHObjCExceptionReason";

@implementation ECHObjCExceptionCatcher

+ (BOOL)tryBlock:(NS_NOESCAPE void (^)(void))block
           error:(NSError * _Nullable * _Nullable)error
{
  @try {
    if (block != nil) {
      block();
    }
    return YES;
  } @catch (NSException *exception) {
    if (error != nil) {
      NSString *name = exception.name ?: @"NSException";
      NSString *reason = exception.reason ?: @"No reason provided";
      NSDictionary<NSErrorUserInfoKey, id> *userInfo = @{
        NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@: %@", name, reason],
        ECHObjCExceptionNameErrorKey: name,
        ECHObjCExceptionReasonErrorKey: reason
      };
      *error = [NSError errorWithDomain:ECHObjCExceptionCatcherErrorDomain
                                   code:1
                               userInfo:userInfo];
    }
    return NO;
  }
}

@end
