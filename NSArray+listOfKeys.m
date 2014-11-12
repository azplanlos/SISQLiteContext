//
//  NSArray+listOfKeys.m
//  Photoroute
//
//  Created by Andreas Zöllner on 31.10.14.
//  Copyright (c) 2014 Studio Istanbul Medya Hiz. Tic. Ltd. Sti. All rights reserved.
//

#import "NSArray+listOfKeys.h"

@implementation NSArray (listOfKeys)

-(NSString*)commaSeparatedListWithQuoteString:(NSString *)quote {
    NSMutableString* retStr = [NSMutableString string];
    int i = 0;
    for (NSString* prop in self) {
        if (i != 0) {
            [retStr appendString:@","];
        }
        [retStr appendFormat:@"%@%@%@", quote, prop, quote];
        i++;
    }
    return retStr;
}

-(NSString*)commaSeparatedList {
    return [self commaSeparatedListWithQuoteString:@""];
}

@end
