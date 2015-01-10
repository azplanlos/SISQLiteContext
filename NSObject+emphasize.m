//
//  NSObject+emphasize.m
//  Photoroute
//
//  Created by Andreas Zöllner on 05.01.15.
//  Copyright (c) 2015 Studio Istanbul Medya Hiz. Tic. Ltd. Sti. All rights reserved.
//

#import "NSObject+emphasize.h"

@implementation NSObject (emphasize)
-(NSString*)emphasizedDescription {
    if ([self isKindOfClass:[NSNumber class]]) {
        return [NSString stringWithFormat:@"%0.5f", ((NSNumber*)self).floatValue];
    } else if ([self isKindOfClass:[NSString class]]) {
        return [NSString stringWithFormat:@"'%@'", self];
    }
    return [NSString stringWithFormat:@"'%@'", self.description];
}
@end
