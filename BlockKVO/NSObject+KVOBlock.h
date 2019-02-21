//
//  NSObject+KVOBlock.h
//  BlockKVO
//
//  Created by Eren on 2019/2/20.
//  Copyright © 2019 skyline. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
typedef void(^sw_KVOObserverBlock)(id observedObject, NSString *observedKeyPath, id oldValue, id newValue);

@interface NSObject (KVOBlock)
- (void)sw_addObserver:(NSObject *)observer
            forKeyPath:(NSString *)keyPath
              callback:(sw_KVOObserverBlock)callback;

- (void)sw_removeObserver:(NSObject *)observer
               forKeyPath:(NSString *)keyPath;

@end

NS_ASSUME_NONNULL_END
