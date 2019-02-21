//
//  NSObject+KVOBlock.m
//  BlockKVO
//
//  Created by Eren on 2019/2/20.
//  Copyright © 2019 skyline. All rights reserved.
//
#import <objc/runtime.h>
#import <objc/message.h>
#import "NSObject+KVOBlock.h"
#import "SWKVOObserverItem.h"

static void *const sw_KVOObserverAssociatedKey = (void *)&sw_KVOObserverAssociatedKey;
static NSString *sw_KVOClassPrefix = @"sw_KVONotifing_";


@implementation NSObject (KVOBlock)
- (void)sw_addObserver:(NSObject *)observer
            forKeyPath:(NSString *)keyPath
              callback:(sw_KVOObserverBlock)callback {
    // 1. 通过keyPath获取当前类对应的setter方法，如果获取不到，说明setter 方法即不存在与KVO类，也不存在与原始类，这总情况正常情况下是不会发生的，触发Exception
    NSString *setterString = sw_setterByGetter(keyPath);
    SEL setterSEL = NSSelectorFromString(setterString);
    Method method = class_getInstanceMethod(object_getClass(self), setterSEL);
    
    if (method) {
        // 2. 查看当前实例对应的类是否是KVO类，如果不是，则生成对应的KVO类，并设置当前实例对应的class是KVO类
        Class objectClass = object_getClass(self);
        NSString *objectClassName = NSStringFromClass(objectClass);
        if (![objectClassName hasPrefix:sw_KVOClassPrefix]) {
            Class kvoClass = [self makeKvoClassWithOriginalClassName:objectClassName];
            object_setClass(self, kvoClass);
        }
        
        // 3. 在KVO类中查找是否重写过keyPath 对应的setter方法，如果没有，则添加setter方法到KVO类中
        if (![self hasMethodWithMethodName:setterString]) {
            class_addMethod(object_getClass(self), NSSelectorFromString(setterString), (IMP)sw_kvoSetter, method_getTypeEncoding(method));
        }
        
        // 4. 注册Observer
        NSMutableArray<SWKVOObserverItem *> *observerArray = objc_getAssociatedObject(self, sw_KVOObserverAssociatedKey);
        if (observerArray == nil) {
            observerArray = [NSMutableArray new];
            objc_setAssociatedObject(self, sw_KVOObserverAssociatedKey, observerArray, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        SWKVOObserverItem *item = [SWKVOObserverItem new];
        item.keyPath = keyPath;
        item.observer = observer;
        item.callback = callback;
        [observerArray addObject:item];
        
        
    }else {
        NSString *exceptionReason = [NSString stringWithFormat:@"%@ Class %@ setter SEL not found.", NSStringFromClass([self class]), keyPath];
        NSException *exception = [NSException exceptionWithName:@"NotExistKeyExceptionName" reason:exceptionReason userInfo:nil];
        [exception raise];
    }
}

- (void)sw_removeObserver:(NSObject *)observer
               forKeyPath:(NSString *)keyPath {
    NSMutableArray<SWKVOObserverItem *> *observerArray = objc_getAssociatedObject(self, sw_KVOObserverAssociatedKey);
    [observerArray enumerateObjectsUsingBlock:^(SWKVOObserverItem * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        if (obj.observer == observer && [obj.keyPath isEqualToString:keyPath]) {
            [observerArray removeObject:obj];
        }
    }];
    
    if (observerArray.count == 0) { // 如果已经没有了observer，则把isa复原，销毁临时的KVO类
        Class originalClass = [self class];
        Class kvoClass = object_getClass(self);
        object_setClass(self, originalClass);
        objc_disposeClassPair(kvoClass);
    }
    
}



#pragma mark - static method for KVO class overwrite or added
static void sw_kvoSetter(id self, SEL selector, id value) {
    // 1. 获取旧值
    NSString *getterString = sw_getterBySetter(selector);
    if (getterString) {
        id (*getterMsgSend)(id , SEL) = (void *)objc_msgSend;
        id oldValue = getterMsgSend(self, NSSelectorFromString(getterString));
        // 2. 设置新值（注意这里会调用原始类的setter方法，来设置到原始类的属性中）
        id (*superSetterMsgSend)(void *, SEL, id newVaule) = (void *)objc_msgSendSuper;
        struct objc_super objcSuper= {
            .receiver = self,
            .super_class = class_getSuperclass(object_getClass(self)),
        };
        superSetterMsgSend(&objcSuper, selector, value);
        
        // 3. 用block回调给所有相关的Observer
        NSMutableArray<SWKVOObserverItem *> *observerArray = objc_getAssociatedObject(self, sw_KVOObserverAssociatedKey);
        if (observerArray == nil) {
            observerArray = [NSMutableArray new];
            objc_setAssociatedObject(self, sw_KVOObserverAssociatedKey, observerArray, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        [observerArray enumerateObjectsUsingBlock:^(SWKVOObserverItem * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if ([obj.keyPath isEqualToString:getterString]) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                     obj.callback(self, getterString, oldValue, value);
                });
            }
        }];
    }
}

static Class sw_class(id self, SEL selector) {
    return class_getSuperclass(object_getClass(self));  // 因为我们将原始类设置为了KVO类的super class，所以直接返回KVO类的super class即可得到原始类Class
}

#pragma mark - helper method
static NSString *sw_getterBySetter(SEL setter) {
    NSString *setterString = NSStringFromSelector(setter);
    if (![setterString hasPrefix:@"set"]) {
        return nil;
    }
    
    // 下面根据setAge 方法生成 age NSString
    NSString *firstString = [setterString substringWithRange:NSMakeRange(3, 1)];
    firstString = [firstString lowercaseString];
    if (setterString.length < 5) {
        return firstString;
    }
    NSString *getterString = [setterString substringWithRange:NSMakeRange(4, setterString.length - 5)];
    getterString = [NSString stringWithFormat:@"%@%@", firstString, getterString];
    return getterString;
}

static NSString * sw_setterByGetter(NSString* getterString) {
    NSString *firstString = [getterString substringToIndex:1];
    firstString = [firstString uppercaseString];
    NSString *lastString = [getterString substringFromIndex:1];
    NSString *setterString = [NSString stringWithFormat:@"set%@%@:", firstString, lastString];
    return setterString;
}

- (Class)makeKvoClassWithOriginalClassName:(NSString *)originalClassName {
    // 1. 检查KVO类是否已经存在, 如果存在，直接返回
    NSString *kvoClassName = [NSString stringWithFormat:@"%@%@", sw_KVOClassPrefix, originalClassName];
    Class kvoClass = objc_getClass(kvoClassName.UTF8String);
    if (kvoClass) {
        return kvoClass;
    }
    
    // 2. 创建KVO类，并将原始class设置为KVO类的super class
    kvoClass = objc_allocateClassPair(object_getClass(self), kvoClassName.UTF8String, 0);
    objc_registerClassPair(kvoClass);
    
    // 3. 重写KVO类的class方法，使其指向我们自定义的IMP,实现KVO class的‘伪装’
    Method classMethod = class_getInstanceMethod(object_getClass(self), @selector(class));
    const char* types = method_getTypeEncoding(classMethod);
    class_addMethod(kvoClass, @selector(class), (IMP)sw_class, types);
    return kvoClass;
}

- (BOOL)hasMethodWithMethodName:(NSString *)methodName {
    unsigned int methodCount = 0;
    Method *methodList = class_copyMethodList(object_getClass(self), &methodCount);
    for (int i = 0; i < methodCount; ++i) {
        Method method = methodList[i];
        SEL sel = method_getName(method);
        NSString *name = NSStringFromSelector(sel);
        if ([name isEqualToString:methodName]) {
            return YES;
        }
    }
    return NO;
}


@end
