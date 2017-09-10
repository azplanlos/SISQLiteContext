//
//  SISQLiteDatabase.m
//  Photoroute
//
//  Created by Andreas Zöllner on 20.12.14.
//  Copyright (c) 2014 Studio Istanbul Medya Hiz. Tic. Ltd. Sti. All rights reserved.
//

#import "SISQLiteContext.h"
#import "SISQLiteDatabase.h"
#import "SISQLiteObject.h"
#import "NSArray+containsString.h"
#import "AQProperties.h"
#import "NSString+CapitalizedString.h"
#import "NSArray+listOfKeys.h"
#import "NSArray+ArrayForKeypath.h"
#import "NSString+SQLQueryLanguage.h"

@interface SISQLiteDatabase () {
    NSMutableDictionary* tableUpdate;
}
@end

@implementation SISQLiteDatabase
@synthesize dbQueue, dbName, dbURL, availableClasses, initialized, idField, cacheItemSize;

-(SISQLiteDatabase*)init {
    self = [super init];
    initialized = NO;
    self.cacheItemSize = 10000;
    cacheStatements = [[NSMutableArray alloc] init];
    tableIndexNames = [NSMutableDictionary dictionary];
    idField = @"ID";
    return self;
}

-(SISQLiteDatabase*)initWithURL:(NSURL *)url andObjects:(NSArray *)availableObjectClasses {
    self = [self init];
    dbURL = url;
    if (self.dbQueue) {
        [self.dbQueue inDatabase:^(FMDatabase *db) {
            [db close];
        }];
        dbQueue = nil;
    }
    dbQueue = [FMDatabaseQueue databaseQueueWithPath:[url path]];
    availableClasses = availableObjectClasses;
    BOOL newDB = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
        newDB = YES;
    }
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        [db open];
    }];
    if (newDB) {
        [self.dbQueue inDatabase:^(FMDatabase *db) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:[[[NSBundle mainBundle] URLForResource:@"init_database" withExtension:@"sql"] path]])
                [db executeStatements:[NSString stringWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"init_database" withExtension:@"sql"] encoding:NSUTF8StringEncoding error:nil]];
        }];
    }
    [self initDatabaseWithTableObjects:availableObjectClasses];
    return self;
}

-(void)initDatabaseWithTableObjects:(NSArray*)tableObjects;
{
    tableUpdate = [NSMutableDictionary dictionaryWithCapacity:tableObjects.count];
    for (id obj in tableObjects) {
        NSString* stableName = [[obj className] lowercaseString];
        
        [tableUpdate setValue:[NSNumber numberWithBool:NO] forKey:stableName];
        
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
                NSString* query = [NSString stringWithFormat:@"CREATE TABLE '%@' ('ID' Integer NOT NULL PRIMARY KEY AUTOINCREMENT, 'parentRef' Integer, 'parentRefKey' TEXT, 'childRef' Integer, 'childRefKey' TEXT, 'childType' TEXT);", tableName];
                NSString* query2 = [NSString stringWithFormat:@"CREATE INDEX '%@_childRef' ON '%@' (childRef);", tableName, tableName];
                NSString* query3 = [NSString stringWithFormat:@"CREATE INDEX '%@_parentRef' ON '%@' (parentRef);", tableName, tableName];
                [self.dbQueue inDatabase:^(FMDatabase *db) {
                    [db executeUpdate:query];
                    [db executeUpdate:query2];
                    [db executeUpdate:query3];
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
                [tablePropNames addObject:[myResult stringForColumn:@"name"]];
            }
            query = [NSString stringWithFormat:@"PRAGMA index_list(%@);", stableName];
            myResult = [db executeQuery:query];
            while ([myResult next]) {
                NSString* indexName = [myResult stringForColumn:@"name"];
                query = [NSString stringWithFormat:@"PRAGMA index_info(%@);", indexName];
                FMResultSet* columnsResult = [db executeQuery:query];
                while ([columnsResult next]) {
                    NSString* columnName = [columnsResult stringForColumn:@"name"];
                    if (![tableIndexNames objectForKey:stableName]) [tableIndexNames setObject:[NSMutableArray array] forKey:stableName];
                    [[tableIndexNames objectForKey:stableName] addObject:columnName];
                }
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
            
            if (![[[SISQLiteContext SQLiteContext] availableClasses] containsString:NSStringFromClass([testObj class])]) {
                Class c = obj;
                
                __block NSString* xname = name;
                IMP setterIMP = imp_implementationWithBlock(^(id _self, id value){
                    [_self setValue:value forUndefinedKey:xname];
                });
                
                IMP getterIMP = imp_implementationWithBlock((id)^(id _self) {
                    return [_self valueForUndefinedKey:xname];
                });
                
                const char *greetingTypes =
                [[NSString stringWithFormat:@"%s%s%s",
                  @encode(void), @encode(id), @encode(SEL)] UTF8String];
                
                const char *types2 =
                [[NSString stringWithFormat:@"%s%s%s",
                  @encode(id), @encode(id), @encode(SEL)] UTF8String];
                
                if (!class_addMethod(c, NSSelectorFromString([NSString stringWithFormat:@"set%@:", [name stringWithFirstLetterCapitalized]]), setterIMP, greetingTypes)) {
                    Method m = class_getClassMethod(c, NSSelectorFromString([NSString stringWithFormat:@"set%@:", [name stringWithFirstLetterCapitalized]]));
                    if (m != NULL) {
                        method_setImplementation(m, setterIMP);
                    } else {
                        NSLog(@"could not set setter for method %@ on %@!", [NSString stringWithFormat:@"set%@:", [name stringWithFirstLetterCapitalized]], NSStringFromClass(obj));
                    }
                }
                if (!class_addMethod(c, NSSelectorFromString(name), getterIMP, types2)) {
                    Method m = class_getClassMethod(c, NSSelectorFromString(name));
                    if (m != NULL) {
                        method_setImplementation(m, getterIMP);
                    } else {
                        NSLog(@"could not set getter for method %@ on %@!", name, NSStringFromClass(obj));
                    }
                }
            }
        }
        [[[SISQLiteContext SQLiteContext] availableClasses] addObject:NSStringFromClass([testObj class])];
    }
    initialized = YES;
}

-(BOOL)hasContentsForClass:(Class)objectClass {
    return [availableClasses containsObject:objectClass];
}

-(void)addCachedStatement:(NSString *)statement {
    [cacheStatements addObject:statement];
    if (cacheStatements.count > self.cacheItemSize) {
        [self synchronize];
    }
}

-(void)synchronize {
    [self.dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        for (NSString* st in cacheStatements) [db executeStatements:st];
    }];
    [cacheStatements removeAllObjects];
}

-(BOOL)isDatabaseReady {
    __block BOOL goodConnection = NO;
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        goodConnection = db.goodConnection;
    }];
    if (goodConnection && initialized) return YES;
    return NO;
}

-(void)closeDB {
    [self synchronize];
    [self.dbQueue close];
}

-(void)deleteObjectsForObject:(Class)objectClass withKey:(NSString *)key andValue:(id)value {
    NSArray* delObjs = [self resultsForQuery:[NSString stringWithFormat:@"%@ = %@", key, value] withClass:objectClass];
    for (SISQLiteObject* object in delObjs) {
        [object deleteFromDatabase];
    }
    [self synchronize];
}

-(void)deleteUnreferencedObjectsForObject:(Class)objectClass withKey:(NSString *)key andValue:(id)value {
    
    NSMutableString* propQuery = [NSMutableString string];
    NSMutableString* childRelDelQuery = [NSMutableString string];
    for (Class availObjectClass in availableClasses) {
        SISQLiteObject* testObj = [[availObjectClass alloc] init];
        for (NSString* multipleProp in [testObj toManyRelationshipProperties]) {
            NSMutableString* xpropQuery = [NSMutableString string];
            [self.dbQueue inDatabase:^(FMDatabase *db) {
                FMResultSet* results = [db executeQuery:[NSString stringWithFormat:@"SELECT childRefKey FROM '%@-%@' GROUP BY childRefKey;", [NSStringFromClass(availObjectClass) lowercaseString], multipleProp]];
                while ([results next]) {
                    [propQuery appendFormat:@" AND %@ NOT IN (SELECT childRef FROM '%@-%@' WHERE childType = '%@' AND childRefKey = '%@' AND childRef = %@.%@)", [results stringForColumn:@"childRefKey"], [NSStringFromClass(availObjectClass) lowercaseString], multipleProp,[NSStringFromClass(objectClass) lowercaseString], [results stringForColumn:@"childRefKey"], [NSStringFromClass(objectClass) lowercaseString], [results stringForColumn:@"childRefKey"]];
                    [xpropQuery appendFormat:@" AND childRef NOT IN (SELECT %@ FROM %@ WHERE %@ = '%@-%@'.childRef) AND parentRef NOT IN (SELECT %@ FROM %@ WHERE %@ = '%@-%@'.parentRef)", [results stringForColumn:@"childRefKey"], [NSStringFromClass(objectClass) lowercaseString], [results stringForColumn:@"childRefKey"], [NSStringFromClass(availObjectClass) lowercaseString], multipleProp, [results stringForColumn:@"childRefKey"], [NSStringFromClass(objectClass) lowercaseString], [results stringForColumn:@"childRefKey"], [NSStringFromClass(availObjectClass) lowercaseString], multipleProp];
                }
            }];
            [childRelDelQuery appendFormat:@"DELETE FROM '%@-%@' WHERE %@;", [NSStringFromClass(availObjectClass) lowercaseString], multipleProp, xpropQuery];
        }
    }
    NSMutableString* parentRelDelQuery = [NSMutableString string];
    
    for (NSString* multipleProp in [[[objectClass alloc] init] toManyRelationshipProperties]) {
        NSMutableString* propQuery = [NSMutableString string];
        [self.dbQueue inDatabase:^(FMDatabase *db) {
            FMResultSet* results = [db executeQuery:[NSString stringWithFormat:@"SELECT parentRefKey FROM '%@-%@' GROUP BY childRefKey;", [NSStringFromClass(objectClass) lowercaseString], multipleProp]];
            while ([results next]) {
                if (propQuery.length > 0) [propQuery appendString:@" OR "];
                [propQuery appendFormat:@"(parentRefKey = '%@' AND parentRef NOT IN (SELECT %@ FROM %@))", [results stringForColumn:@"parentRefKey"], [results stringForColumn:@"parentRefKey"], [NSStringFromClass(objectClass) lowercaseString]];
            }
        }];
        [parentRelDelQuery appendFormat:@"DELETE FROM '%@-%@' WHERE parentType = '%@' AND %@;", [NSStringFromClass(objectClass) lowercaseString], multipleProp, [NSStringFromClass(objectClass) lowercaseString], propQuery];
    }
    
    NSString* queryString = [NSString stringWithFormat:@"DELETE FROM %@ WHERE %@ = %@ %@;",[NSStringFromClass(objectClass) lowercaseString], key, value, propQuery];
    
    [self.dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        if (![db executeUpdate:queryString]) {
            NSLog(@"error: %@", db.lastErrorMessage);
            *rollback = YES;
        };
        if (![db executeStatements:parentRelDelQuery]) {
            NSLog(@"error in deleting parent relations: %@", db.lastErrorMessage);
            *rollback = YES;
        }
        if (![db executeStatements:childRelDelQuery]) {
            NSLog(@"error in deleting child relations: %@", db.lastErrorMessage);
            *rollback = YES;
        }
    }];
    
    [self synchronize];
}

-(void)deleteObject:(SISQLiteObject *)object {
    if (object.inDatabase) {
        [cacheStatements addObject:[NSString stringWithFormat:@"DELETE FROM %@ WHERE ID = %li;", [NSStringFromClass([object class]) lowercaseString], object.ID]];
        NSString* searchQuery = [object keyValuePairForParentRelation];
        NSString* searchQuery2 = [object keyValuePairForChildRelation];
        for (Class objectClass in availableClasses) {
            SISQLiteObject* testObj = [[objectClass alloc] init];
            for (NSString* multipleProp in [testObj toManyRelationshipProperties]) {
                NSString* testQuery = [NSString stringWithFormat:@"DELETE FROM '%@-%@' WHERE childType = '%@' AND (%@);\n", [NSStringFromClass([testObj class]) lowercaseString], multipleProp, NSStringFromClass([object class]), searchQuery];
                NSString* testQuery2 = [NSString stringWithFormat:@"DELETE FROM '%@-%@' WHERE %@;\n", [NSStringFromClass([testObj class]) lowercaseString], multipleProp, searchQuery2];
                [cacheStatements addObject:testQuery];
                [cacheStatements addObject:testQuery2];
            }
        }
    }
}

-(void)indexValuesForKey:(NSString *)key forObject:(Class)obj {
    NSMutableArray* arr = [tableIndexNames objectForKey:[NSStringFromClass(obj) lowercaseString]];
    if (!arr) {
        arr = [NSMutableArray array];
        [tableIndexNames setObject:arr forKey:[NSStringFromClass(obj) lowercaseString]];
    }
    if (arr) {
        if (![arr containsString:key]) {
            NSLog(@"creating index for key %@ on database %@", key, [NSStringFromClass(obj) lowercaseString]);
            NSString* query = [NSString stringWithFormat:@"CREATE UNIQUE INDEX %@_%@ ON %@ (%@);", [NSStringFromClass(obj) lowercaseString], key, [NSStringFromClass(obj) lowercaseString], key];
            [cacheStatements addObject:query];
            [arr addObject:key];
        }
    }
}

-(void)updateObject:(SISQLiteObject *)object {
    NSString* updString;
    if (!object.inDatabase) {
        updString = [object insertStatement];
    } else {
        updString = [object updateStatement];
    }
    [tableUpdate setValue:[NSNumber numberWithBool:YES] forKey:[NSStringFromClass([object class])lowercaseString]];
    [cacheStatements addObject:updString];
    if (cacheStatements.count > self.cacheItemSize) {
        [self synchronize];
    }
}

-(void)vacuum {
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        [db executeUpdate:@"VACUUM;"];
    }];
}

-(NSArray*)executeQuery:(NSString*)queryString withClass:(Class)objectClass {
    __block NSMutableArray* retArray = [NSMutableArray array];
    //NSLog(@"db query: %@", queryString);
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet* results = [db executeQuery:queryString];
        while ([results next]) {
            SISQLiteObject* obj = [[objectClass alloc] init];
            obj.ID = [[results stringForColumn:@"ID"] integerValue];
            obj.database = self;
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
                } else if ([type rangeOfString:@"Date"].location != NSNotFound) {
                    NSDateFormatter* dateFormat = [NSDateFormatter new];
                    [dateFormat setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
                    val = [dateFormat dateFromString:[results stringForColumn:key]];
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

-(NSArray*)allObjectsForClass:(Class)objectClass {
    NSString* query = [NSString stringWithFormat:@"SELECT * FROM %@;", [NSStringFromClass(objectClass) lowercaseString]];
    return [self executeQuery:query withClass:objectClass];
}

-(SISQLiteObject*)objectWithHighestValueForKey:(NSString *)key inClass:(Class)objectClass {
    NSString* query = [NSString stringWithFormat:@"SELECT max(%@),* FROM %@;", key, [NSStringFromClass(objectClass) lowercaseString]];
    NSArray* result = [self executeQuery:query withClass:objectClass];
    if (result && result.count > 0) return result.firstObject;
    return nil;
}

-(SISQLiteObject*)objectWithLowestValueForKey:(NSString *)key inClass:(Class)objectClass {
    NSString* query = [NSString stringWithFormat:@"SELECT min(%@),* FROM %@;", key, [NSStringFromClass(objectClass) lowercaseString]];
    NSArray* result = [self executeQuery:query withClass:objectClass];
    if (result && result.count > 0) return result.firstObject;
    return nil;
}

-(NSArray*)faultedResultsForStatement:(NSString*)queryString withClass:(Class)objectClass andReferenceKey:(NSString*)referenceKey fromTableColumn:(NSString*)column {
    __block NSMutableArray* retArray = [[NSMutableArray alloc] init];
    [self.dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet* results = [db executeQuery:queryString];
        while ([results next]) {
            SISQLiteObject* obj = [[objectClass alloc] initFaultedWithReferenceKey:referenceKey andValue:[results stringForColumn:column]];
            obj.database = self;
            [retArray addObject:obj];
        }
    }];
    return retArray;
}

-(long long)numberOfObjectsinClass:(Class)objectClass {
    NSString* query = [NSString stringWithFormat:@"SELECT Count(*) FROM %@;", [NSStringFromClass(objectClass) lowercaseString]];
    __block long long numberofobjects = 0;
    [dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet* result = [db executeQuery:query];
        while ([result next]) {
            numberofobjects = [result longLongIntForColumnIndex:0];
        }
    }];
    return numberofobjects;
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

-(NSInteger)maxIDforClass:(Class)objectClass {
    __block NSInteger maxId = -1;
    [dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet* result = [db executeQuery:[NSString stringWithFormat:@"SELECT max(ID) FROM %@;", [NSStringFromClass(objectClass) lowercaseString]]];
        while ([result next]) {
            maxId = [result longLongIntForColumnIndex:0];
        }
    }];
    return maxId;
}

-(NSNumber*)lowestValueForClass:(Class)objectClass andKey:(NSString *)key andQuery:(NSString *)query {
    __block NSNumber* lowestNum;
    NSString* queryString = [NSString stringWithFormat:@"SELECT min(%@) FROM %@;", key, [NSStringFromClass(objectClass) lowercaseString]];
    if (query) {
        queryString = [queryString stringByAppendingSqlPart:[NSString stringWithFormat:@"WHERE %@", query]];
    }
    [dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet* result = [db executeQuery:queryString];
        while ([result next]) {
            lowestNum = [NSNumber numberWithDouble:[result doubleForColumnIndex:0]];
        }
    }];
    return lowestNum;
}

-(NSNumber*)highestValueForClass:(Class)objectClass andKey:(NSString *)key andQuery:(NSString *)query {
    __block NSNumber* highestNum;
    NSString* queryString = [NSString stringWithFormat:@"SELECT max(%@) FROM %@;", key, [NSStringFromClass(objectClass) lowercaseString]];
    if (query) {
        queryString = [queryString stringByAppendingSqlPart:[NSString stringWithFormat:@"WHERE %@", query]];
    }
    [dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet* result = [db executeQuery:queryString];
        while ([result next]) {
            highestNum = [NSNumber numberWithDouble:[result doubleForColumnIndex:0]];
        }
    }];
    return highestNum;
}

//SELECT mode FROM chargedataset GROUP BY mode ORDER BY count(mode) ASC LIMIT 1;

-(id)mostUsedValueForClass:(Class)objectClass andKey:(NSString *)key forQuery:(NSString *)query {
    __block id mostUsed;
    NSString* queryString = [NSString stringWithFormat:@"SELECT %@ FROM %@;", key, [NSStringFromClass(objectClass) lowercaseString]];
    if (query) {
        queryString = [queryString stringByAppendingSqlPart:[NSString stringWithFormat:@"WHERE %@", query]];
    }
    queryString = [queryString stringByAppendingSqlPart:[NSString stringWithFormat:@"GROUP BY %@ ORDER BY count(%@) DESC LIMIT 1", key, key]];
    [dbQueue inDatabase:^(FMDatabase *db) {
        FMResultSet* result = [db executeQuery:queryString];
        while ([result next]) {
            mostUsed = [result objectForColumnIndex:0];
        }
    }];
    return mostUsed;
}

-(void)cleanDeviationForClass:(Class)objectClass withMaxDeviation:(double)maxDevPercent excludeProperties:(NSArray *)excludeArray {
    SISQLiteObject* testObj = [[objectClass alloc] init];
    for (NSString* prop in [testObj sqlProperties]) {
        if (!excludeArray || [excludeArray containsString:prop] == NO) {
            __block int num;
            do {
                num = 0;
                [dbQueue inDatabase:^(FMDatabase *db) {
                    NSString* queryString = [NSString stringWithFormat:@"CREATE TEMPORARY TABLE temp_%@ AS SELECT *, (SELECT %@ FROM %@ b WHERE b.ID < d.ID ORDER BY ID DESC LIMIT 1) AS prev_val, (SELECT  %@ FROM %@ c WHERE c.ID > d.ID ORDER BY ID ASC LIMIT 1) AS next_val, (SELECT AVG(%@) FROM %@) AS avg_val FROM %@ d WHERE abs(prev_val - d.%@) > abs(avg_val*%0.2f) AND d.%@ != 0 AND abs(prev_val - d.%@) > abs(avg_val*%0.2f) AND prev_val != 0 AND next_val != 0 ORDER BY d.ID;", [NSStringFromClass(objectClass) lowercaseString], prop, [NSStringFromClass(objectClass) lowercaseString], prop, [NSStringFromClass(objectClass) lowercaseString], prop, [NSStringFromClass(objectClass) lowercaseString], [NSStringFromClass(objectClass) lowercaseString], prop, maxDevPercent, prop, prop, maxDevPercent];
                    [db executeUpdate:queryString];
                    //NSLog(@"query: %@", queryString);
                    if ([db executeUpdate:[NSString stringWithFormat:@"DELETE FROM %@ WHERE ID IN (SELECT ID FROM temp_%@);", [NSStringFromClass(objectClass) lowercaseString], [NSStringFromClass(objectClass) lowercaseString]]]) {
                        num = [db changes];
                        NSLog(@"deleted %i deviated values for %@ on %@", num, prop, [NSStringFromClass(objectClass) lowercaseString]);
                    }
                    [db executeUpdate:[NSString stringWithFormat:@"DROP TABLE temp_%@;", [NSStringFromClass(objectClass) lowercaseString]]];
                }];
            } while (num != 0);
        }
    }
}

-(void)dealloc {
    [self.dbQueue close];
}

-(NSArray*)affectedClasses {
    NSMutableArray* arr = [NSMutableArray array];
    for (NSString* key in tableUpdate.allKeys) {
        if ([[tableUpdate valueForKey:key] boolValue]) [arr addObject:key];
    }
    NSLog(@"%li classes affected", arr.count);
    return [NSArray arrayWithArray:arr];
}



@end
