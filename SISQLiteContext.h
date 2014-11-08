//
//  SISQLiteContext.h
//  Photoroute
//
//  Created by Andreas Zöllner on 31.10.14.
//  Copyright (c) 2014 Studio Istanbul Medya Hiz. Tic. Ltd. Sti. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FMDB.h"

@class SISQLiteObject;

@interface SISQLiteContext : NSObject {
    NSMutableArray* cacheStatements;
    BOOL initialized;
}

@property (strong) FMDatabase* database;
@property (assign) NSUInteger cacheItemSize;
@property (strong) NSString* idField;
@property (readonly) BOOL isDatabaseReady;

+(SISQLiteContext*)SQLiteContext;

-(void)loadDatabaseFromURL:(NSURL*)fileUrl;
-(void)initDatabaseWithTableObjects:(NSArray*)tableObjects;
-(void)synchronize;

-(void)updateObject:(SISQLiteObject*)object;

-(NSArray*)resultsForQuery:(NSString*)queryString withClass:(Class) objectClass;
-(NSArray*)resultsForHavingQuery:(NSString *)queryString withClass:(Class)objectClass;

@end
