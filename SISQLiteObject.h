//
//  SISQLiteObject.h
//  Photoroute
//
//  Created by Andreas Zöllner on 31.10.14.
//  Copyright (c) 2014 Studio Istanbul Medya Hiz. Tic. Ltd. Sti. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NSObject+Properties.h"
#import "SISQLiteDatabase.h"

@interface SISQLiteObject : NSObject
@property (assign) BOOL inDatabase;
@property (assign) NSInteger ID;
@property (strong, readonly) NSString* table;
@property (strong, nonatomic) NSString* referenceKey;
@property (strong, nonatomic) id referenceValue;
@property (assign, readonly) BOOL isFaulted;
@property (strong) SISQLiteDatabase* database;

+(id)faultedObjectWithReferenceKey:(NSString*)string andValue:(id)refValue;
-(id)initFaultedWithReferenceKey:(NSString*)string andValue:(id)refValue;

-(void)saveAndDestroy;
-(NSString*)insertStatement;
-(NSString*)updateStatement;
-(NSArray*)sqlProperties;
-(NSArray*)sqlValues;
-(NSArray*)fullSqlProperties;
-(NSArray*)fullSqlValues;
-(NSArray*)toManyRelationshipProperties;
-(NSString*)keyValueStringWithSeparator:(NSString*)separator;
-(NSString*)keyValuePairForChildRelation;
-(NSString*)keyValuePairForParentRelation;

-(void)loadObjectFromStore;
-(void)unfaultChilds;
-(NSArray*)parentObjectsWithClass:(Class)objectClass andReferenceKey:(NSString*)xreferenceKey;
-(void)mapFaultedChildsWithKey:(NSString*)key withObjects:(NSArray*)liveObjects;

-(void)willSaveObject;

-(void)deleteFromDatabase;

#pragma mark pseudo functions used internally!
@end
