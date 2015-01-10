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
#import "NSObject+emphasize.h"

@implementation SISQLiteObject
@synthesize inDatabase, ID, isFaulted, referenceKey, referenceValue;

-(id)init {
    self = [super init];
    self.inDatabase = NO;
    isFaulted = NO;
    referenceKey = @"ID";
    for (NSString* relKey in self.toManyRelationshipProperties) {
        [self setValue:[NSMutableArray array] forKey:[NSString stringWithFormat:@"sql_%@", relKey]];
    }
    for (NSString* propKey in self.sqlProperties) {
        NSString* type = [NSString stringWithUTF8String:[self typeOfPropertyNamed:[NSString stringWithFormat:@"sql_%@", propKey]]];
        if ([type rangeOfString:@"String"].location != NSNotFound) {
            [self setValue:@"" forKey:[NSString stringWithFormat:@"sql_%@", propKey]];
        } else if ([type rangeOfString:@"Array"].location != NSNotFound) {
//
        } else {
            [self setValue:@(0) forKey:[NSString stringWithFormat:@"sql_%@", propKey]];
        }
    }
    return self;
}

+(id)faultedObjectWithReferenceKey:(NSString *)key andValue:(id)refValue {
    SISQLiteObject* myObj = [[[self class] alloc] initFaultedWithReferenceKey:key andValue:refValue];
    return myObj;
}

-(id)initFaultedWithReferenceKey:(NSString *)key andValue:(id)refValue {
    self = [self init];
    self.referenceKey = key;
    self.referenceValue = refValue;
    return self;
}

-(void)setReferenceValue:(id)newReferenceValue {
    referenceValue = newReferenceValue;
    [self setValue:newReferenceValue forKey:self.referenceKey];
    if (![self.referenceKey isEqualToString:@"ID"]) {
        [[SISQLiteContext SQLiteContext] indexValuesForKey:self.referenceKey forObject:[self class]];
    }
    isFaulted = YES;
}

-(id)referenceValue {
    return [self valueForKey:self.referenceKey];
}

-(void)setReferenceKey:(NSString *)newReferenceKey {
    referenceKey = newReferenceKey;
}

-(void)saveAndDestroy {
    if (!isFaulted) [[SISQLiteContext SQLiteContext] updateObject:self];
}

-(NSString*)insertStatement {
    if (!self.isFaulted) {
        NSMutableString* retStr = [NSMutableString string];
        [retStr appendFormat:@"INSERT INTO %@ (%@) VALUES (%@);", self.table, self.fullSqlProperties.commaSeparatedList,self.fullSqlValues.commaSeparatedList];
        for (NSString* rel in self.toManyRelationshipProperties) {
            NSString* tableName = [NSString stringWithFormat:@"%@-%@", self.table, rel];
            for (SISQLiteObject* child in [self valueForKey:rel]) {
                [retStr appendFormat:@" INSERT INTO '%@' (parentRef, parentRefKey, childRef, childRefKey, childType) VALUES (%@, '%@', %@, '%@', '%@');", tableName, [[self valueForKey:self.referenceKey] emphasizedDescription], self.referenceKey, [[child valueForKey:child.referenceKey] emphasizedDescription], child.referenceKey, [child className]];
            }
        }
        return retStr;
    }
    return @"";
}

-(NSString*)updateStatement {
    if (!self.isFaulted) {
        NSMutableString* setString = [[NSMutableString alloc] init];
        int i = 0;
        for (NSString* prop in self.fullSqlProperties) {
            if (i != 0) [setString appendString:@","];
            [setString appendFormat:@"%@=%@", prop, [[self sqlValues] objectAtIndex:[[self sqlProperties]indexOfString:prop]]];
            i++;
        }
        NSMutableString* retStr = [NSMutableString stringWithFormat:@"UPDATE %@ SET %@ WHERE ID = %li;", self.table, setString, self.ID];
        for (NSString* rel in self.toManyRelationshipProperties) {
            NSString* tableName = [NSString stringWithFormat:@"%@-%@", self.table, rel];
            [retStr appendFormat:@" DELETE FROM %@ WHERE parentRef = %@ AND parentRefKey = '%@';", tableName, [[self valueForKey:self.referenceKey] emphasizedDescription], self.referenceKey];
            for (SISQLiteObject* child in [self valueForKey:rel]) {
                [retStr appendFormat:@" INSERT INTO %@ (parentRef, parentRefKey, childRef, childRefKey, childType) VALUES (%@, '%@', %@, '%@', '%@');", tableName, [[self valueForKey:self.referenceKey] emphasizedDescription], self.referenceKey, [[child valueForKey:child.referenceKey] emphasizedDescription], child.referenceKey, [child className]];
            }
        }
        return retStr;
    }
    return @"";
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
        const char *typeChar = [self typeOfPropertyNamed:[NSString stringWithFormat:@"sql_%@", key]];
        if (typeChar && strlen(typeChar) > 0) {
            NSString* type = [NSString stringWithUTF8String:typeChar];
            if ([type rangeOfString:@"NSString"].location != NSNotFound) {
                //NSLog(@"string for undefined key %@", key);
                return @"";
            } else {
                //NSLog(@"number for undefined key %@", key);
                return @(0);
            }
        }
    }
    return nil;
}

-(void)setValue:(id)value forUndefinedKey:(NSString *)key {
    if ([value isKindOfClass:[NSString class]] && [[NSString stringWithUTF8String:[self typeOfPropertyNamed:[NSString stringWithFormat:@"sql_%@", key]]] rangeOfString:@"String"].location == NSNotFound) {
        //NSLog(@"type convert %@ to Number (%@ -> %f)", key, value, [value doubleValue]);
        value = [NSNumber numberWithDouble:[value doubleValue]];
        
    }
    if (value) [self setValue:value forKey:[NSString stringWithFormat:@"sql_%@", key]];
}

-(NSArray*)sqlProperties {
    NSMutableArray* retArray = [NSMutableArray array];
    for (NSString* prop in self.allPropertyNames) {
        if ([prop rangeOfString:@"sql_"].location == 0 && [[NSString stringWithUTF8String:[self typeOfPropertyNamed:prop]] rangeOfString:@"Array"].location == NSNotFound) {
            [retArray addObject:[prop substringFromIndex:4]];
        }
    }
    return retArray;
}

-(NSArray*)fullSqlProperties {
    return [self.sqlProperties arrayByAddingObjectsFromArray:self.toManyRelationshipProperties];
}

-(NSArray*)toManyRelationshipProperties {
    NSMutableArray* retArray = [NSMutableArray array];
    for (NSString* prop in self.allPropertyNames) {
        if ([prop rangeOfString:@"sql_"].location == 0 && [[NSString stringWithUTF8String:[self typeOfPropertyNamed:prop]] rangeOfString:@"Array"].location != NSNotFound) {
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
        } else if ([val isKindOfClass:[NSString class]]) {
            NSMutableCharacterSet *charactersToRemove = [NSMutableCharacterSet alphanumericCharacterSet];
            [charactersToRemove formUnionWithCharacterSet:[NSCharacterSet nonBaseCharacterSet]];
            [charactersToRemove removeCharactersInString:@"'´`;"];
            [charactersToRemove invert];
            val = [[val componentsSeparatedByCharactersInSet:charactersToRemove] componentsJoinedByString:@" "];
            val = [NSString stringWithFormat:@"'%@'", val];
        }
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

-(NSArray*)fullSqlValues {
    NSMutableArray* retArray = [NSMutableArray array];
    for (NSString* prop in self.fullSqlProperties) {
        id val = [self valueForKey:[NSString stringWithFormat:@"sql_%@", prop]];
        if ([val isKindOfClass:[NSNumber class]]) {
            //NSLog(@"number for %@", prop);
            if ([val isEqualToNumber:[NSNumber numberWithLongLong:188238674]]) {
                NSLog(@"number for prop %@ = %.8f (%lli)", prop, [val doubleValue], [val longLongValue]);
            }
            val = [NSString stringWithFormat:@"%.8f", [val doubleValue]];
        } else if ([val isKindOfClass:[NSString class]]) {
            NSMutableCharacterSet *charactersToRemove = [NSMutableCharacterSet alphanumericCharacterSet];
            [charactersToRemove formUnionWithCharacterSet:[NSCharacterSet nonBaseCharacterSet]];
            [charactersToRemove removeCharactersInString:@"'´`;\""];
            [charactersToRemove addCharactersInString:@"-_."];
            [charactersToRemove invert];
            val = [[val componentsSeparatedByCharactersInSet:charactersToRemove] componentsJoinedByString:@" "];
            val = [NSString stringWithFormat:@"'%@'", val];
        }
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
        //if (!val) val = @"''";
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
    inDatabase = YES;
}

-(NSArray*)parentObjectsWithClass:(Class)objectClass andReferenceKey:(NSString*)xreferenceKey {
    SISQLiteObject* testObj = [[objectClass alloc] init];
    NSMutableArray* objs = [NSMutableArray array];
    for (NSString* rels in testObj.toManyRelationshipProperties) {
        NSString* query = [NSString stringWithFormat:@"SELECT * FROM '%@-%@' WHERE childRef = '%@' AND childRefKey = '%@';", testObj.table, rels, [self valueForKey:xreferenceKey], xreferenceKey];
        [objs addObjectsFromArray:[[SISQLiteContext SQLiteContext] faultedResultsForStatement:query withClass:objectClass andReferenceKey:xreferenceKey fromTableColumn:@"parentRef"]];
    }
    return objs;
}

-(void)mapFaultedChildsWithKey:(NSString *)key withObjects:(NSArray *)liveObjects {
    if ([[self valueForKey:[NSString stringWithFormat:@"sql_%@",key]] isKindOfClass:[NSArray class]]) {
        NSMutableArray* childs = [self valueForKey:[NSString stringWithFormat:@"sql_%@",key]];
        NSString* childRefKey = [childs.lastObject referenceKey];
        NSArray* ids = [liveObjects stringArrayForValuesWithKey:childRefKey];
        for (NSInteger i = 0; i < childs.count; i++) {
            SISQLiteObject* child = [childs objectAtIndex:i];
            id childVal = [child valueForKey:childRefKey];
            if ([childVal isKindOfClass:[NSNumber class]]) childVal = [NSString stringWithFormat:@"%li", [childVal integerValue]];
            NSInteger indexOfLive = [ids indexOfString:childVal];
            if (indexOfLive != NSNotFound) {
                [childs replaceObjectAtIndex:i withObject:[liveObjects objectAtIndex:indexOfLive]];
            } else {
                //NSLog(@"child not found with %@='%@'", childRefKey, childVal);
                //[child loadObjectFromStore];
            }
        }
    } else {
        NSLog(@"invalid property %@ on class %@ - property class %@", key, NSStringFromClass([self class]), NSStringFromClass([[self valueForKey:key] class]));
    }
}

-(NSString*)keyValueStringWithSeparator:(NSString *)separator {
    NSMutableString* retString = [NSMutableString string];
    int i = 0;
    for (NSString* key in self.sqlProperties) {
        if (i != 0) [retString appendString:separator];
        id val = [self valueForKey:key];
        if ([val isKindOfClass:[NSNumber class]]) val = [NSString stringWithFormat:@"%f", [val doubleValue]];
        else if ([val isKindOfClass:[NSString class]]) val = [NSString stringWithFormat:@"'%@'", val];
        [retString appendFormat:@"%@ = %@", key, val];
        i++;
    }
    return [NSString stringWithString:retString];
}

-(void)deleteFromDatabase {
    [[SISQLiteContext SQLiteContext] deleteObject:self];
}

-(NSString*)keyValuePairForChildRelation {
    NSMutableString* retString = [NSMutableString string];
    int i = 0;
    for (NSString* key in self.sqlProperties) {
        if (i != 0) [retString appendString:@" OR "];
        id val = [self valueForKey:key];
        if ([val isKindOfClass:[NSNumber class]]) val = [NSString stringWithFormat:@"%f", [val doubleValue]];
        else if ([val isKindOfClass:[NSString class]]) val = [NSString stringWithFormat:@"'%@'", val];
        [retString appendFormat:@"(childRefKey = '%@' AND childRef = %@)", key, val];
        i++;
    }
    return [NSString stringWithString:retString];
}

-(NSString*)keyValuePairForParentRelation {
    NSMutableString* retString = [NSMutableString string];
    int i = 0;
    for (NSString* key in self.sqlProperties) {
        if (i != 0) [retString appendString:@" OR "];
        id val = [self valueForKey:key];
        if ([val isKindOfClass:[NSNumber class]]) val = [NSString stringWithFormat:@"%f", [val doubleValue]];
        else if ([val isKindOfClass:[NSString class]]) val = [NSString stringWithFormat:@"'%@'", val];
        [retString appendFormat:@"(parentRefKey = '%@' AND parentRef = %@)", key, val];
        i++;
    }
    return [NSString stringWithString:retString];
}


@end
