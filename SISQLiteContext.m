//
//  SISQLiteContext.m
//  Photoroute
//
//  Created by Andreas Zöllner on 31.10.14.
//  Copyright (c) 2014 Studio Istanbul Medya Hiz. Tic. Ltd. Sti. All rights reserved.
//

#import "SISQLiteContext.h"
#import "SISQLiteObject.h"
#import <objc/runtime.h>
#import "NSArray+containsString.h"
#import "AQProperties.h"
#import "NSArray+listOfKeys.h"

@implementation SISQLiteContext

static SISQLiteContext* _sisqlitecontext;

@synthesize cacheItemSize, idField;

+(SISQLiteContext*)SQLiteContext {
    @synchronized([SISQLiteContext class]) {
        if (!_sisqlitecontext) _sisqlitecontext = [[self alloc] init];
        return _sisqlitecontext;
    }
    
    return nil;
}

+(id)alloc {
    @synchronized([SISQLiteContext class]) {
        NSAssert(_sisqlitecontext == nil, @"Attempted to allocate a second instance of a singleton.");
        _sisqlitecontext = [super alloc];
        return _sisqlitecontext;
    }   return nil;
}

-(id)init {
    self = [super init];
    if (self != nil) {
        self.cacheItemSize = 10000;
        cacheStatements = [[NSMutableArray alloc] init];
        idField = @"ID";
        initialized = NO;
    }
    return self;
}

-(void)loadDatabaseFromURL:(NSURL*)fileUrl; {
    if (self.dbQueue) {
        [self.dbQueue inDatabase:^(FMDatabase *db) {
            [db close];
        }];
        self.dbQueue = nil;
    }
    NSString* dbFilePath = fileUrl.path;
    self.dbQueue = [FMDatabaseQueue databaseQueueWithPath:dbFilePath];
    BOOL newDB = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:dbFilePath]) {
        newDB = YES;
    }
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        [db open];
    }];
    if (newDB) {
        [self.dbQueue inDatabase:^(FMDatabase *db) {
            [db executeStatements:[NSString stringWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"init_database" withExtension:@"sql"] encoding:NSUTF8StringEncoding error:nil]];
        }];
    }
}

-(void)initDatabaseWithTableObjects:(NSArray*)tableObjects;
{
    for (id obj in tableObjects) {
        NSString* stableName = [[obj className] lowercaseString];
        NSLog(@"checking for table %@", stableName);
        
        SISQLiteObject* testObj = [[obj alloc] init];
        
        __block FMResultSet* tableResult;
        __block BOOL tableFound = NO;
        __block NSMutableArray* foundRelTables = [NSMutableArray array];
        [self.dbQueue inDatabase:^(FMDatabase *db) {
            tableResult = [db executeQueryWithFormat:@"SELECT name FROM sqlite_master WHERE type='table';"];
            while ([tableResult next]) {
                if ([[tableResult stringForColumnIndex:0] isEqualToString:stableName]) tableFound = YES;
                for (NSString* relProp in testObj.toManyRelationshipProperties) {
                    NSString* tableName = [NSString stringWithFormat:@"%@-%@", stableName, relProp];
                    if ([[tableResult stringForColumnIndex:0] isEqualToString:tableName]) {
                        [foundRelTables addObject:relProp];
                    }
                }
            }

        }]; 
                
        if (!tableFound) {
            NSString* query = [NSString stringWithFormat:@"CREATE TABLE '%@' ('ID' Integer NOT NULL PRIMARY KEY AUTOINCREMENT);", stableName];
            [self.dbQueue inDatabase:^(FMDatabase *db) {
                [db executeUpdate:query];
            }];
            NSLog(@"created table %@", stableName);
        } else {
            //NSString* query = [NSString stringWithFormat:@"delete from %@ where rowid not in (select  max(rowid) from %@ group by %@);", stableName, stableName, idField];
            //[self.database executeUpdate:query];
        }
        
        // check for relation table
        
        for (NSString* relProp in testObj.toManyRelationshipProperties) {
            NSString* tableName = [NSString stringWithFormat:@"%@-%@", stableName, relProp];
            if ([foundRelTables containsString:tableName]) {
                
            } else {
                NSString* query = [NSString stringWithFormat:@"CREATE TABLE '%@' ('ID' Integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'parentRef' TEXT, 'parentRefKey' TEXT, 'childRef' TEXT, 'childRefKey' TEXT, 'childType' TEXT);", tableName];
                [self.dbQueue inDatabase:^(FMDatabase *db) {
                    [db executeUpdate:query];
                }];
                NSLog(@"created table %@", tableName);
            }
        }
        
        // check for table contents
        __block NSMutableArray* tablePropNames = [[NSMutableArray alloc] init];
        [self.dbQueue inDatabase:^(FMDatabase *db) {
            NSString* query = [NSString stringWithFormat:@"PRAGMA table_info('%@');", stableName];
            FMResultSet* myResult = [db executeQuery:query];
            while ([myResult next]) {
                NSLog(@"row %@", [myResult stringForColumn:@"name"]);
                [tablePropNames addObject:[myResult stringForColumn:@"name"]];
            }
        }];
                
        for (NSString* name in testObj.fullSqlProperties) {
            if (![tablePropNames containsString:name]) {
                NSString* type = [NSString stringWithCString:[obj typeOfPropertyNamed:[NSString stringWithFormat:@"sql_%@",name]] encoding:NSUTF8StringEncoding];
                NSLog(@"creating property %@ of type %@", name, type);
                if ([type rangeOfString:@"Ts"].location != NSNotFound || [type rangeOfString:@"Tq"].location != NSNotFound || [type rangeOfString:@"Tc"].location != NSNotFound || [type rangeOfString:@"Ti"].location != NSNotFound || [type rangeOfString:@"Tl"].location != NSNotFound || [type rangeOfString:@"TI"].location != NSNotFound) {
                    type = @"INTEGER";
                } else if ([type rangeOfString:@"NSString"].location != NSNotFound) {
                    type = @"TEXT";
                } else if ([type rangeOfString:@"Tf"].location != NSNotFound || [type rangeOfString:@"Td"].location != NSNotFound) {
                    type = @"REAL";
                } else {
                    type = @"NONE";
                }
                NSString* updateQuery = [NSString stringWithFormat:@"ALTER TABLE %@ ADD COLUMN %@ %@;", stableName, name, type];
                [self.dbQueue inDatabase:^(FMDatabase *db) {
                    [db executeUpdate:updateQuery];
                }];
            }
        }
    }
    initialized = YES;
}

-(void)updateObject:(SISQLiteObject *)object {
    NSString* updString;
    if (!object.inDatabase) {
        updString = [object insertStatement];
    } else {
        updString = [object updateStatement];
    }
    [cacheStatements addObject:updString];
    if (cacheStatements.count > self.cacheItemSize) {
        [self synchronize];
    }
}

-(void)synchronize {
    NSLog(@"saving to db");
    NSMutableString* statements = [NSMutableString string];
    for (NSString* st in cacheStatements) [statements appendFormat:@" %@", st];
    [self.dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        [db executeStatements:statements];
    }];
    [cacheStatements removeAllObjects];
    NSLog(@"saved to db");
}

-(NSArray*)executeQuery:(NSString*)queryString withClass:(Class)objectClass {
    __block NSMutableArray* retArray = [NSMutableArray array];
    //NSLog(@"db query: %@", queryString);
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet* results = [db executeQuery:queryString];
        while ([results next]) {
            SISQLiteObject* obj = [[objectClass alloc] init];
            NSArray* sqlProps = [obj fullSqlProperties];
            for (NSString* key in sqlProps) {
                id val;
                NSString* type = [NSString stringWithUTF8String:[obj typeOfPropertyNamed:[NSString stringWithFormat:@"sql_%@", key]]];
                if ([type rangeOfString:@"String"].location != NSNotFound) {
                    val = [results stringForColumn:key];
                } else if ([type rangeOfString:@"Array"].location != NSNotFound) {
                    // resolve relations with faulted objects
                    val = [[NSMutableArray alloc] init];
                    NSArray* objectVals = [[results stringForColumn:key] componentsSeparatedByString:@","];
                    for (NSString* childObjString in objectVals) {
                        if (childObjString.length > 0 && [childObjString rangeOfString:@"/"].location != NSNotFound) {
                            NSArray* keyVal = [childObjString componentsSeparatedByString:@"="];
                            NSString* childRefVal = [keyVal lastObject];
                            NSArray* objRef = [[keyVal objectAtIndex:0] componentsSeparatedByString:@"/"];
                            NSString* childRefKey = objRef.lastObject;
                            NSString* childObjectClass = [objRef objectAtIndex:0];
                            SISQLiteObject* child = [NSClassFromString(childObjectClass)faultedObjectWithReferenceKey:childRefKey andValue:childRefVal];
                            [val addObject:child];
                        }
                    }
                } else {
                    val = [NSNumber numberWithDouble:[results doubleForColumn:key]];
                }
                [obj setValue:val forKey:key];
            }
            obj.inDatabase = YES;
            [retArray addObject:obj];
        }
    }];
    return [NSArray arrayWithArray:retArray];
}

-(NSArray*)resultsForQuery:(NSString *)queryString withClass:(Class)objectClass {
    NSString* query = [NSString stringWithFormat:@"SELECT * FROM %@ WHERE %@;", [NSStringFromClass(objectClass) lowercaseString], queryString];
    return [self executeQuery:query withClass:objectClass];
}

-(NSArray*)resultsForHavingQuery:(NSString *)queryString withClass:(Class)objectClass {
    NSString* query = [NSString stringWithFormat:@"SELECT * FROM %@ GROUP BY ID HAVING %@;", [NSStringFromClass(objectClass) lowercaseString], queryString];
    return [self executeQuery:query withClass:objectClass];
}

-(NSArray*)faultedResultsForStatement:(NSString*)queryString withClass:(Class)objectClass andReferenceKey:(NSString*)referenceKey fromTableColumn:(NSString*)column {
    __block NSMutableArray* retArray = [[NSMutableArray alloc] init];
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet* results = [db executeQuery:queryString];
        while ([results next]) {
            SISQLiteObject* obj = [[objectClass alloc] initFaultedWithReferenceKey:referenceKey andValue:[results stringForColumn:column]];
            [retArray addObject:obj];
        }
    }];
    return retArray;
}

-(NSArray*)faultedObjectsForObject:(Class)objectClass withRelationKey:(NSString *)key andReferenceKey:(NSString *)referenceKey withValues:(NSString *)values, ... {
    id eachObject;
    va_list argumentList;
    NSMutableArray* valuesArray = [NSMutableArray array];
    if (values) {
        va_start(argumentList, values);
        while ((eachObject = va_arg(argumentList, id))) {
            [valuesArray addObject:eachObject];
        }
        va_end(argumentList);
    }
    return [self faultedObjectsForObject:objectClass withRelationKey:key andReferenceKey:referenceKey withArrayValues:valuesArray];
}

-(NSArray*)faultedObjectsForObject:(Class)objectClass withRelationKey:(NSString *)key andReferenceKey:(NSString *)referenceKey withArrayValues:(NSArray *)values {
    NSMutableString* valueString = [NSMutableString string];
    int i = 0;
    for (id value in values) {
        if (i != 0) [valueString appendString:@","];
        if ([value isKindOfClass:[NSString class]]) [valueString appendFormat:@"'%@'",value];
        else if ([value isKindOfClass:[NSNumber class]]) [valueString appendFormat:@"'%@'",[value stringValue]];
        else [valueString appendFormat:@"'%@'",[value description]];
        i++;
    }
    NSString* query = [NSString stringWithFormat:@"SELECT DISTINCT parentRef FROM '%@-%@' WHERE childRefKey = '%@' AND childRef IN (%@);", NSStringFromClass(objectClass).lowercaseString, key, referenceKey, valueString];
    //NSLog(@"query %@", query);
    return [self faultedResultsForStatement:query withClass:objectClass andReferenceKey:referenceKey fromTableColumn:@"parentRef"];
}

-(NSArray*)liveObjectsFromArrayOfFaultedObjects:(NSArray *)faultedObjects {
    if (faultedObjects.count > 0) {
        NSString* query = [NSString stringWithFormat:@"%@ IN (%@)", [faultedObjects.lastObject referenceKey], [[faultedObjects arrayForValuesWithKey:[faultedObjects.lastObject referenceKey]] commaSeparatedList]];
        NSArray* retObjs = [self resultsForQuery:query withClass:[faultedObjects.lastObject class]];
        return retObjs;
    }
    return faultedObjects;
}

-(BOOL)isDatabaseReady {
    __block BOOL goodConnection = NO;
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        goodConnection = db.goodConnection;
    }];
    if (goodConnection && initialized) return YES;
    return NO;
}

@end
