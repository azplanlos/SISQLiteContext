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
#import "NSString+CapitalizedString.h"
#import "NSApplication+directories.h"

@implementation SISQLiteContext

@synthesize availableClasses;

static SISQLiteContext* _sisqlitecontext;

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
        initialized = NO;
        dbQueues = [NSMutableArray array];
        availableClasses = [NSMutableArray array];
    }
    return self;
}

-(SISQLiteDatabase*)attachDatabaseAtURL:(NSURL *)dbURL forObjectClasses:(NSArray *)objects {
    SISQLiteDatabase* db = [[SISQLiteDatabase alloc] initWithURL:dbURL andObjects:objects];
    [dbQueues addObject:db];
    initialized = YES;
    return db;
}

-(void)detachDatabase:(SISQLiteDatabase*)db {
    [db closeDB];
    [dbQueues removeObject:db];
}

-(NSArray*)performOnAllDatabasesWithClass:(Class)objectClass runBlock:(NSArray* (^)(SISQLiteDatabase *db))block {
    NSMutableArray* retArray = [NSMutableArray array];
    for (SISQLiteDatabase* db in dbQueues) {
        if ([db hasContentsForClass:objectClass]) {
            [retArray addObjectsFromArray:block(db)];
        }
    }
    return [NSArray arrayWithArray:retArray];
}

-(void)indexValuesForKey:(NSString *)key forObject:(Class)obj {
    // run on all databases
    [self performOnAllDatabasesWithClass:obj runBlock:^NSArray *(SISQLiteDatabase *db) {
        [db indexValuesForKey:key forObject:obj];
        return [NSArray array];
    }];
}

-(void)updateObject:(SISQLiteObject *)object {
    NSString* updString;
    if (!object.inDatabase) {
        updString = [object insertStatement];
    } else {
        updString = [object updateStatement];
    }
    if (dbQueues.count > 0) {
        if (!object.database) {
            object.database = dbQueues.lastObject;
        }
        [object.database addCachedStatement:updString];
    }
}

-(void)vacuum {
    for (SISQLiteDatabase* db in dbQueues) [db vacuum];
}

-(void)synchronize {
    for (SISQLiteDatabase* db in dbQueues) [db synchronize];
}

-(NSArray*)executeQuery:(NSString*)queryString withClass:(Class)objectClass {
    // run on all databases
    return [self performOnAllDatabasesWithClass:objectClass runBlock:^NSArray *(SISQLiteDatabase *db) {
        return [db executeQuery:queryString withClass:objectClass];
    }];
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
    return [self performOnAllDatabasesWithClass:objectClass runBlock:^NSArray *(SISQLiteDatabase *db) {
        return [db faultedResultsForStatement:queryString withClass:objectClass andReferenceKey:referenceKey fromTableColumn:column];
    }];
}

-(NSArray*)faultedObjectsForObject:(Class)objectClass withRelationKey:(NSString *)key andReferenceKey:(NSString *)referenceKey withValues:(NSString *)values, ... {
    // run on all databases
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
    // run on all databases
    return [self performOnAllDatabasesWithClass:objectClass runBlock:^NSArray *(SISQLiteDatabase *db) {
        return [db faultedObjectsForObject:objectClass withRelationKey:key andReferenceKey:referenceKey withArrayValues:values];
    }];
}

-(NSArray*)liveObjectsFromArrayOfFaultedObjects:(NSArray *)faultedObjects {
    // run on all databases
    return [self performOnAllDatabasesWithClass:[faultedObjects.lastObject class] runBlock:^NSArray *(SISQLiteDatabase *db) {
        return [db liveObjectsFromArrayOfFaultedObjects:faultedObjects];
    }];
}

-(BOOL)isDatabaseReady {
    BOOL goodConnection = YES;
    for (SISQLiteDatabase* db in dbQueues) {
        if (!db.isDatabaseReady) goodConnection = NO;
    }
    if (goodConnection && initialized) return YES;
    return NO;
}

-(void)deleteObjectsForObject:(Class)objectClass withKey:(NSString *)key andValue:(id)value {
    NSArray* delObjs = [self resultsForQuery:[NSString stringWithFormat:@"%@ = %@", key, value] withClass:objectClass];
    for (SISQLiteObject* object in delObjs) {
        [object deleteFromDatabase];
    }
    [self synchronize];
}

-(void)deleteUnreferencedObjectsForObject:(Class)objectClass withKey:(NSString *)key andValue:(id)value {
    //check containing databases and delete
    [self performOnAllDatabasesWithClass:objectClass runBlock:^NSArray *(SISQLiteDatabase *db) {
        [db deleteUnreferencedObjectsForObject:objectClass withKey:key andValue:value];
        return [NSArray array];
    }];
}

-(void)deleteObject:(SISQLiteObject *)object {
    if (object.inDatabase && object.database) {
        [object.database deleteObject:object];
    }
}

@end
