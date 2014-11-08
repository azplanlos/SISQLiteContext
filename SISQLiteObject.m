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
@synthesize inDatabase, ID, isFaulted, referenceKey, referenceValue;

-(id)init {
    self = [super init];
    self.inDatabase = NO;
    isFaulted = NO;
    referenceKey = @"ID";
    //NSLog(@"properties: %@", [self allPropertyNames]);
    return self;
}

+(id)faultedObjectWithReferenceKey:(NSString *)key andValue:(id)refValue {
    SISQLiteObject* myObj = [[[self class] alloc] init];
    myObj.referenceValue = refValue;
    myObj.referenceKey = key;
    [myObj setValue:refValue forKey:key];
    return myObj;
}

-(void)setReferenceValue:(id)newReferenceValue {
    referenceValue = newReferenceValue;
    isFaulted = YES;
}

-(void)saveAndDestroy {
    if (!isFaulted) [[SISQLiteContext SQLiteContext] updateObject:self];
}

-(NSString*)insertStatement {
    NSString* retStr = [NSString stringWithFormat:@"INSERT INTO %@ (%@) VALUES (%@);", self.table, self.sqlProperties.commaSeparatedList,self.sqlValues.commaSeparatedList];
    //NSLog(@"sql %@", retStr);
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
    //NSLog(@"sql %@", retStr);
    return retStr;
}

-(id)valueForUndefinedKey:(NSString *)key {
    if ([key rangeOfString:@"sql_"].location != 0 && [self valueForKey:[NSString stringWithFormat:@"sql_%@", key]]) {
        NSString* type = [NSString stringWithUTF8String:[self typeOfPropertyNamed:[NSString stringWithFormat:@"sql_%@", key]]];
        if ([type rangeOfString:@"String"].location != NSNotFound) {
            //NSLog(@"string for undefined key %@", key);
            return [self valueForKey:[NSString stringWithFormat:@"sql_%@", key]];
        } else if ([type rangeOfString:@"Array"].location != NSNotFound) {
            return [self valueForKey:[NSString stringWithFormat:@"sql_%@", key]];
        } else {
            //NSLog(@"number for undefined key %@", key);
            return [NSNumber numberWithDouble:[[self valueForKey:[NSString stringWithFormat:@"sql_%@", key]] doubleValue]];
        }
        
    } else if ([key rangeOfString:@"sql_"].location != 0) {
        NSString* type = [NSString stringWithUTF8String:[self typeOfPropertyNamed:[NSString stringWithFormat:@"sql_%@", key]]];
        if ([type rangeOfString:@"NSString"].location != NSNotFound) {
            //NSLog(@"string for undefined key %@", key);
            return @"";
        } else {
            //NSLog(@"number for undefined key %@", key);
            return @(0);
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
            //NSLog(@"number for %@", prop);
            val = [NSString stringWithFormat:@"%27.8f", [val doubleValue]];
        } else if ([val isKindOfClass:[NSString class]]) val = [NSString stringWithFormat:@"'%@'", val];
        else if ([val isKindOfClass:[NSArray class]]) {
            NSMutableString* val2 = [[NSMutableString alloc] init];
            int i = 0;
            for (SISQLiteObject* child in (NSArray*)val) {
                if (i != 0) [val2 appendString:@","];
                [val2 appendFormat:@"%@/%@=%@", child.className, child.referenceKey, child.referenceValue];
                i++;
            }
            val = [NSString stringWithFormat:@"'%@'", val2];
        }
        [retArray addObject:val];
    }
    return retArray;
}

-(NSString*)table {
    return [[self className] lowercaseString];
}

-(void)loadObjectFromStore {
    NSString* query;
    if ([[NSString stringWithUTF8String:[self typeOfPropertyNamed:[NSString stringWithFormat:@"sql_%@", referenceKey]]] rangeOfString:@"String"].location != NSNotFound) {
        query = [NSString stringWithFormat:@"%@ = '%@'", self.referenceKey, self.referenceValue];
    } else {
        query = [NSString stringWithFormat:@"%@ = %f", self.referenceKey, [self.referenceValue doubleValue]];
    }
    SISQLiteObject* tempObject = [[SISQLiteContext SQLiteContext] resultsForQuery:query withClass:[self class]].lastObject;
    for (NSString* key in [tempObject sqlProperties]) {
        [self setValue:[tempObject valueForKey:key] forKey:key];
    }
    isFaulted = NO;
}

-(NSArray*)parentObjectsWithClass:(Class)objectClass andReferenceKey:(NSString*)xreferenceKey {
    NSString* query;
    if ([[NSString stringWithUTF8String:[self typeOfPropertyNamed:[NSString stringWithFormat:@"sql_%@", referenceKey]]] rangeOfString:@"String"].location != NSNotFound) {
        query = [NSString stringWithFormat:@"* LIKE '%%%@/%@=%@%%'", NSStringFromClass(objectClass), xreferenceKey, [self valueForKey:xreferenceKey]];
    } else {
        query = [NSString stringWithFormat:@"* LIKE '%%%@/%@=%f%%'", NSStringFromClass(objectClass), xreferenceKey, [[self valueForKey:xreferenceKey] doubleValue]];
    }
    return [[SISQLiteContext SQLiteContext] resultsForQuery:query withClass:objectClass];
}

@end
