//
//  ViewController.m
//  BlockKVO
//
//  Created by Eren on 2019/2/20.
//  Copyright © 2019 skyline. All rights reserved.
//

#import "ViewController.h"
#import "NSObject+KVOBlock.h"
#import <objc/runtime.h>
@implementation Student
@end
@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    Student *std = [Student new];
    // 直接用block回调来接受 KVO
    [std sw_addObserver:self forKeyPath:@"name" callback:^(id  _Nonnull observedObject, NSString * _Nonnull observedKeyPath, id  _Nonnull oldValue, id  _Nonnull newValue) {
        NSLog(@"old value is %@, new vaule is %@", oldValue, newValue);
    }];
    
    std.name = @"Hello";
    std.name = @"Lilhy";
    NSLog(@"class is %@, object_class is %@", [std class], object_getClass(std));
    [std sw_removeObserver:self forKeyPath:@"name"];
    NSLog(@"class is %@, object_class is %@", [std class], object_getClass(std));
    
}
@end
