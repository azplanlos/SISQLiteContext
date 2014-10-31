//
//  SISQLiteObject.m
//  Photoroute
//
//  Created by Andreas Zöllner on 31.10.14.
//  Copyright (c) 2014 Studio Istanbul Medya Hiz. Tic. Ltd. Sti. All rights reserved.
//

#import "SISQLiteObject.h"
#import "SISQLiteContext.h"
#import "NSArray+listOfKeys.h"
#import "AQProperties.h"
#import "NSArray+containsString.h"

@implementation SISQLiteObject
@synthesize inDatabase, ID;

-(id)init {
    self = [super init];
    self.inDatabase = NO;
    NSLog(@"properties: %@", [self allPropertyNames]);
    return self;
}

-(void)saveAndDestroy {
    [[SISQLiteContext SQLiteContext] updateObject:self];
}

-(NSString*)insertStatement {
    NSString* retStr = [NSString stringWithFormat:@"INSERT INTO %@ (%@) VALUES (%@);", self.table, self.sqlProperties.commaSeparatedList,self.sqlValues.commaSeparatedList];
    NSLog(@"sql %@", retStr);
    return retStr;
}

-(NSString*)updateStatement {
    NSMutableString* setString = [[NSMutableString alloc] init];
    int i = 0;
    for (NSString* prop in self.sqlProperties) {
        if (i != 0) [setString appendString:@","];
        [setString appendFormat:@"%@=%@", prop, [[self sqlValues] objectAtIndex:[[self sqlProperties]indexOfString:prop]]];
        i++;
    }
    NSString* retStr = [NSString stringWithFormat:@"UPDATE %@ SET %@ WHERE ID = %li;", self.table, setString, self.ID];
    NSLog(@"sql %@", retStr);
    return retStr;
}

-(id)valueForUndefinedKey:(NSString *)key {
    if ([key rangeOfString:@"sql_"].location != 0 && [self valueForKey:[NSString stringWithFormat:@"sql_%@", key]]) {
        NSString* type = [NSString stringWithUTF8String:[self typeOfPropertyNamed:[NSString stringWithFormat:@"sql_%@", key]]];
        if ([type rangeOfString:@"NSString"].location != NSNotFound) {
            NSLog(@"string for undefined key %@", key);
            return [self valueForKey:[NSString stringWithFormat:@"sql_%@", key]];
        } else {
            NSLog(@"number for undefined key %@", key);
            return [NSNumber numberWithFloat:[[self valueForKey:[NSString stringWithFormat:@"sql_%@", key]] floatValue]];
        }
        
    }
    return nil;
}

-(void)setValue:(id)value forUndefinedKey:(NSString *)key {
    [self setValue:value forKey:[NSString stringWithFormat:@"sql_%@", key]];
}

-(NSArray*)sqlProperties {
    NSMutableArray* retArray = [NSMutableArray array];
    for (NSString* prop in self.allPropertyNames) {
        if ([prop rangeOfString:@"sql_"].location == 0) {
            [retArray addObject:[prop substringFromIndex:4]];
        }
    }
    return retArray;
}

-(NSArray*)sqlValues {
    NSMutableArray* retArray = [NSMutableArray array];
    for (NSString* prop in self.sqlProperties) {
        id val = [self valueForKey:prop];
        if ([val isKindOfClass:[NSNumber class]]) {
            NSLog(@"number for %@", prop);
            val = [val stringValue];
        } else if ([val isKindOfClass:[NSString class]]) val = [NSString stringWithFormat:@"'%@'", val];
        [retArray addObject:val];
    }
    return retArray;
}

-(NSString*)table {
    return [[self className] lowercaseString];
}

@end
