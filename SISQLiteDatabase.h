//
//  SISQLiteDatabase.h
//  Photoroute
//
//  Created by Andreas Zöllner on 20.12.14.
//  Copyright (c) 2014 Studio Istanbul Medya Hiz. Tic. Ltd. Sti. All rights reserved.
//

#import "FMDB.h"

@class SISQLiteObject;

@interface SISQLiteDatabase : NSObject {
    NSMutableDictionary* tableIndexNames;
    NSMutableArray* cacheStatements;
}

@property (assign) NSUInteger cacheItemSize;
@property (strong) NSString* idField;
@property (strong) NSArray* availableClasses;
@property (strong) NSString* dbName;
@property (strong, readonly) NSURL* dbURL;
@property (strong, readonly) FMDatabaseQueue* dbQueue;
@property (assign, readonly) BOOL initialized;

-(SISQLiteDatabase*)initWithURL:(NSURL*)url andObjects:(NSArray*)availableObjectClasses;
-(void)addCachedStatement:(NSString*)statement;
-(void)synchronize;
-(BOOL)isDatabaseReady;
-(void)vacuum;
-(void)closeDB;

-(void)deleteObjectsForObject:(Class)objectClass withKey:(NSString *)key andValue:(id)value;
-(void)deleteUnreferencedObjectsForObject:(Class)objectClass withKey:(NSString *)key andValue:(id)value;
-(void)deleteObject:(SISQLiteObject *)object;

-(void)indexValuesForKey:(NSString *)key forObject:(Class)obj;
-(void)updateObject:(SISQLiteObject *)object;

-(NSArray*)executeQuery:(NSString*)queryString withClass:(Class)objectClass;
-(NSArray*)resultsForQuery:(NSString *)queryString withClass:(Class)objectClass;
-(NSArray*)resultsForHavingQuery:(NSString *)queryString withClass:(Class)objectClass;
-(NSArray*)faultedResultsForStatement:(NSString*)queryString withClass:(Class)objectClass andReferenceKey:(NSString*)referenceKey fromTableColumn:(NSString*)column;
-(NSArray*)faultedObjectsForObject:(Class)objectClass withRelationKey:(NSString *)key andReferenceKey:(NSString *)referenceKey withValues:(NSString *)values, ...;
-(NSArray*)faultedObjectsForObject:(Class)objectClass withRelationKey:(NSString *)key andReferenceKey:(NSString *)referenceKey withArrayValues:(NSArray *)values;
-(NSArray*)liveObjectsFromArrayOfFaultedObjects:(NSArray *)faultedObjects;
-(NSArray*)allObjectsForClass:(Class)objectClass;
-(SISQLiteObject*)objectWithHighestValueForKey:(NSString*)key inClass:(Class)objectClass;
-(SISQLiteObject*)objectWithLowestValueForKey:(NSString*)key inClass:(Class)objectClass;

-(long long)numberOfObjectsinClass:(Class)objectClass;

-(BOOL)hasContentsForClass:(Class)objectClass;

-(NSInteger)maxIDforClass:(Class)objectClass;

-(NSNumber*)lowestValueForClass:(Class)objectClass andKey:(NSString*)key andQuery:(NSString*)query;
-(NSNumber*)highestValueForClass:(Class)objectClass andKey:(NSString*)key andQuery:(NSString*)query;
-(id)mostUsedValueForClass:(Class)objectClass andKey:(NSString*)key forQuery:(NSString*)query;

-(void)cleanDeviationForClass:(Class)objectClass withMaxDeviation:(double)maxDevPercent excludeProperties:(NSArray*)excludeArray;

-(NSArray*)affectedClasses; // classes with updated objects since init

@end
