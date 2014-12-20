//
//  SISQLiteDatabase.m
//  Photoroute
//
//  Created by Andreas Zöllner on 20.12.14.
//  Copyright (c) 2014 Studio Istanbul Medya Hiz. Tic. Ltd. Sti. All rights reserved.
//

#import "SISQLiteDatabase.h"
#import "SISQLiteObject.h"
#import "NSArray+containsString.h"
#import "AQProperties.h"
#import "NSString+CapitalizedString.h"
#import "NSArray+listOfKeys.h"
#import "NSArray+ArrayForKeypath.h"

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
                    NSLog(@"found index for %@ and column %@", stableName, columnName);
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
    NSLog(@"saved to db");
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
                    [propQuery appendFormat:@" AND NOT EXISTS (SELECT parentRef FROM '%@-%@' WHERE childType = '%@' AND childRefKey = '%@' AND childRef = %@.%@)", [NSStringFromClass(availObjectClass) lowercaseString], multipleProp,NSStringFromClass(objectClass), [results stringForColumn:@"childRefKey"], [NSStringFromClass(objectClass) lowercaseString], [results stringForColumn:@"childRefKey"]];
                    [xpropQuery appendFormat:@" AND NOT EXISTS (SELECT ID FROM %@ WHERE %@ = '%@-%@'.childRef)", [NSStringFromClass(objectClass) lowercaseString], [results stringForColumn:@"childRefKey"], [NSStringFromClass(availObjectClass) lowercaseString], multipleProp];
                }
            }];
            [childRelDelQuery appendFormat:@"DELETE FROM '%@-%@' WHERE childType = '%@' %@;", [NSStringFromClass(availObjectClass) lowercaseString], multipleProp, NSStringFromClass(objectClass), xpropQuery];
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
        [parentRelDelQuery appendFormat:@"DELETE FROM '%@-%@' WHERE %@;", [NSStringFromClass(objectClass) lowercaseString], multipleProp, propQuery];
    }
    
    NSString* queryString = [NSString stringWithFormat:@"DELETE FROM %@ WHERE %@ = %@ %@;",[NSStringFromClass(objectClass) lowercaseString], key, value, propQuery];
    
    [self.dbQueue inTransaction:^(FMDatabase *db, BOOL *rollback) {
        [db executeUpdate:queryString];
        [db executeStatements:parentRelDelQuery];
        [db executeStatements:childRelDelQuery];
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
            obj.database = self;
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

-(void)dealloc {
    [self.dbQueue close];
}

@end
