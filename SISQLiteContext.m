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
    }
    return self;
}

-(void)loadDatabaseFromURL:(NSURL*)fileUrl; {
    if (self.database) {
        [self.database close];
        self.database = nil;
    }
    NSString* dbFilePath = fileUrl.path;
    self.database = [FMDatabase databaseWithPath:dbFilePath];
    BOOL newDB = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:dbFilePath]) {
        newDB = YES;
    }
    [self.database open];
    if (newDB) {
        [self.database executeStatements:[NSString stringWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"init_database" withExtension:@"sql"] encoding:NSUTF8StringEncoding error:nil]];
    }
}

-(void)initDatabaseWithTableObjects:(NSArray*)tableObjects;
{
    for (id obj in tableObjects) {
        NSString* stableName = [[obj className] lowercaseString];
        NSLog(@"checking for table %@", stableName);
        FMResultSet* tableResult = [self.database executeQueryWithFormat:@"SELECT name FROM sqlite_master WHERE type='table';"];
        BOOL tableFound = NO;
        while ([tableResult next]) {
            if ([[tableResult stringForColumnIndex:0] isEqualToString:stableName]) tableFound = YES;
        }
        
        if (!tableFound) {
            NSString* query = [NSString stringWithFormat:@"CREATE TABLE '%@' ('ID' Integer NOT NULL PRIMARY KEY AUTOINCREMENT);", stableName];
            [self.database executeUpdate:query];
            NSLog(@"created table %@", stableName);
        } else {
            NSString* query = [NSString stringWithFormat:@"delete from %@ where rowid not in (select  min(rowid) from %@ group by %@);", stableName, stableName, idField];
            [self.database executeUpdate:query];
        }
        
        NSString* query = [NSString stringWithFormat:@"PRAGMA table_info('%@');", stableName];
        FMResultSet* myResult = [self.database executeQuery:query];
        NSMutableArray* tablePropNames = [[NSMutableArray alloc] init];
        while ([myResult next]) {
            NSLog(@"row %@", [myResult stringForColumn:@"name"]);
            [tablePropNames addObject:[myResult stringForColumn:@"name"]];
        }
        
        unsigned count;
        objc_property_t *properties = class_copyPropertyList(obj, &count);
        unsigned i;
        for (i = 0; i < count; i++)
        {
            objc_property_t property = properties[i];
            NSString *name = [NSString stringWithUTF8String:property_getName(property)];
            if ([name rangeOfString:@"sql_"].location == 0) {
                name = [name substringFromIndex:4];
                //NSLog(@"checking for property %@", name);
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
                    [self.database executeUpdate:updateQuery];
                }
            }
        }
        
        free(properties);
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

-(void)synchronize {
    NSLog(@"saving to db");
    NSMutableString* statements = [NSMutableString string];
    for (NSString* st in cacheStatements) [statements appendFormat:@" %@", st];
    [self.database executeUpdate:@"BEGIN TRANSACTION;"];
    [self.database executeStatements:statements];
    [self.database executeUpdate:@"COMMIT TRANSACTION;"];
    [cacheStatements removeAllObjects];
    NSLog(@"saved to db");
}

@end
