//
//  NSString+SQLQueryLanguage.m
//  SISQLiteContext
//
//  Created by Andreas Zöllner on 10.03.15.
//  Copyright (c) 2015 Studio Istanbul Medya Hiz. Tic. Ltd. Sti. All rights reserved.
//

#import "NSString+SQLQueryLanguage.h"

@implementation NSString (SQLQueryLanguage)

-(NSString*)stringByAppendingSqlPart:(NSString *)part {
    NSString* selfString = self;
    if ([self characterAtIndex:self.length-1] == ';') {
        selfString = [self substringWithRange:NSMakeRange(0, self.length-1)];
    }
    selfString = [NSString stringWithFormat:@"%@ %@;", selfString, part];
    return selfString;
}

@end
