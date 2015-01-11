//
//  SISQLiteContext.h
//  Photoroute
//
//  Created by Andreas Zöllner on 31.10.14.
//  Copyright (c) 2014 Studio Istanbul Medya Hiz. Tic. Ltd. Sti. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FMDB.h"
#import "NSArray+ArrayForKeypath.h"

@class SISQLiteObject, SISQLiteDatabase;

@interface SISQLiteContext : NSObject {
    BOOL initialized;
    NSMutableArray* dbQueues;
}

@property (readonly) BOOL isDatabaseReady;
@property (strong) NSMutableArray* availableClasses;

+(SISQLiteContext*)SQLiteContext;

-(SISQLiteDatabase*)attachDatabaseAtURL:(NSURL*)dbURL forObjectClasses:(NSArray*)objects;
-(void)synchronize;
-(void)detachDatabase:(SISQLiteDatabase*)db;

-(void)updateObject:(SISQLiteObject*)object;
-(void)deleteObject:(SISQLiteObject*)object;

-(void)vacuum;

-(NSArray*)resultsForQuery:(NSString*)queryString withClass:(Class) objectClass;
-(NSArray*)resultsForHavingQuery:(NSString *)queryString withClass:(Class)objectClass;
-(NSArray*)faultedResultsForStatement:(NSString*)queryString withClass:(Class)objectClass andReferenceKey:(NSString*)referenceKey fromTableColumn:(NSString*)column;
-(NSArray*)faultedObjectsForObject:(Class)objectClass withRelationKey:(NSString*)key andReferenceKey:(NSString*)referenceKey withValues:(NSString*)values,...;
-(NSArray*)faultedObjectsForObject:(Class)objectClass withRelationKey:(NSString*)key andReferenceKey:(NSString*)referenceKey withArrayValues:(NSArray*)values;
-(NSArray*)liveObjectsFromArrayOfFaultedObjects:(NSArray*)faultedObjects;
-(void)indexValuesForKey:(NSString*)key forObject:(Class)obj;
-(void)deleteObjectsForObject:(Class)objectClass withKey:(NSString*)key andValue:(id)value;
-(void)deleteUnreferencedObjectsForObject:(Class)objectClass withKey:(NSString*)key andValue:(id)value;
@end
