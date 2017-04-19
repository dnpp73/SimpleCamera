#import "CIContext+Workaround.h"
#import <objc/runtime.h>

void swizzleInstanceMethod(Class class, SEL originalSelector, SEL alternativeSelector) {
    Method originalMethod = class_getInstanceMethod(class, originalSelector);
    Method alternativeMethod = class_getInstanceMethod(class, alternativeSelector);
    
    if (class_addMethod(class, originalSelector, method_getImplementation(alternativeMethod), method_getTypeEncoding(alternativeMethod))) {
        class_replaceMethod(class, alternativeSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, alternativeMethod);
    }
}

@implementation CIContext (Workaround)

+ (void)load
{
    @autoreleasepool {
        swizzleInstanceMethod([self class], @selector(initWithOptions:), @selector(_initWithOptions:));
    }
}

- (instancetype)_initWithOptions:(NSDictionary<NSString*, id>*)options
{
    if (NSFoundationVersionNumber >= NSFoundationVersionNumber_iOS_9_0) {
        return [self _initWithOptions:options];
    }
    else {
        return [[self class] contextWithOptions:options];
    }
}

@end
