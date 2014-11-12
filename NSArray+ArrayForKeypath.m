//
//  NSArray+ArrayForKeypath.m
//  Photoroute
//
//  Created by Andreas Zöllner on 12.11.14.
//  Copyright (c) 2014 Studio Istanbul Medya Hiz. Tic. Ltd. Sti. All rights reserved.
//

#import "NSArray+ArrayForKeypath.h"

@implementation NSArray (ArrayForKeypath)

-(NSArray*)arrayForValuesWithKey:(NSString *)key {
    NSMutableArray* keyPathArray = [NSMutableArray array];
    for (id elem in self) {
        if ([elem valueForKey:key]) [keyPathArray addObject:[elem valueForKey:key]];
    }
    return [NSArray arrayWithArray:keyPathArray];
}

@end