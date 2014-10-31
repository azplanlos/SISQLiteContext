//
//  NSArray+containsString.m
//  Photoroute
//
//  Created by Programmierer on 5/9/2013.
//  Copyright (c) 2013 Studio Istanbul. All rights reserved.
//

#import "NSArray+containsString.h"

@implementation NSArray (containsString)
-(BOOL)containsString:(NSString *)searchString {
    for (NSString* string in self) {
        if ([string isEqualToString:searchString]) return YES;
    }
    return NO;
}

-(NSInteger)indexOfString:(NSString*)searchString;
{
    NSInteger i = 0;
    for (NSString* string in self) {
        if ([string isEqualToString:searchString]) return i;
        i++;
    }
    return NSNotFound;
}
@end
