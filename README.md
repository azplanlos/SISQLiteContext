SISQLiteContext
===============

light-weight Core Data Alternative with SQLite datastore building and managing database according to Objective-C class properties.

This objective-c class is meant to fix the gap between performance of a native SQLite database and comfort of Core Data.

SISQLiteContext now supports dynamically ataching and detaching of database files, so you can split your database to several files.

You don't need any separate data models for this storage class, all necessary adjustments and upgrades to your client's database files are done by analyzing of your custom subclasses at runtime.

Faulting and relational data models are supported.

How to use
----------

###Class preparations

Subclass your database objects from SISQLiteObject and add as many properties as necessary. Name all SQLite stored properties beginning with **"sql_"** (f.ex. "sql_mydata")
If you declare the property a second time (with "assign" argument) you can use this property as well with the same values. Be aware that getter and setter method creation has to be declared as **@dynamic** in order to be overwritten. For example with an example class called OSMWay and the following interface:
	
	#import "SISQLiteObject.h"
	
	@interface OSMWay : SISQLiteObject

	@property (nonatomic) int16_t sql_adminlevel;
	@property (assign) int64_t adminlevel;
	
	@end
	
	@implementation OSMWay
	@dynamic adminlevel;
	@end

Set your properties by assigning to the property's name or via KVO methods without "sql_" prefix (f.ex. -(void)setMydata:(id)data). Accessormethods are created automatically on runtime. For example:

	OSMWay* myWay = [[OSMWay alloc] init];
	myWay.adminlevel = 1;
	NSLog(@"adminlevel %i", myWay.adminlevel);

Use **NSMutableArray** classes for relational child properties. You *DON'T* have to allocate and initialize these properties!

###Connect to a database:

	SISQLiteDatabase* myDatabase = [[SISQLiteContext SQLiteContext] attachDatabaseAtURL:[NSURL fileURLWithPath:dbFilePath] forObjectClasses:[NSArray arrayWithObjects:[Object1 class], [Object2 class], [Object3 class], nil]];

Only one context is possible at a time but different subclasses will be mapped to different tables in your SQLite database. You can attach as many database files as you need. If classes exist in several database files results will be merged automatically on executing queries. If you don't want this behaviour make sure to execute your query on your attached database not on the general SISQLiteContext.

Init the database and check for compatibility. Changes will be made automatically to fit your current data model. Set ID field for eliminating duplicates on init then init the database.

	[[SISQLiteContext SQLiteContext] setIdField:@"identifier"];
    
Check if all database are initialized correctly:

	if ([[SISQLiteContext SQLiteContext] isDatabaseReady]) {
		// Do something with your database
	}
    
###Create and save objects

Now create your objects as normal. To save them to your database, call on your object:

	-(void)saveAndDestroy;

To commit your changes to the database files, make sure to call

	[[SISQLiteContext SQLiteContext] synchronize];

If you add an object to a relational property set the referencing key on your child object first.

	myObject.referenceKey = @"ID";
	myObject.referenceValue = @"125";
	[myParentObject.mutableArrayProperty addObject:myObject];
	
If you want to add a reference without creating the actual object, just add a faulted object like this:

	SISQLiteObject* myObject = [SISQLiteObject faultedObjectWithReferenceKey:@"ID" andValue:@"125"];
	[myParentObject.mutableArrayProperty addObject:myObject];

###Fetch objects from database

Fetch some objects from database, child objects will be added faulted:

	NSArray* myObjects = [[SISQLiteContext SQLiteContext] resultsForQuery:@"name = 'test'" withClass:[MyObjectClass class]];
	
###Load a faulted object from database

	[myFaultedObject loadObjectFromStore];
	
###Fetch from spezific database file

You can also use the query functions on your database object. Queries will be limited to this database only.

	NSArray* myObjects = [myDatabase resultsForQuery:@"name = 'test'" withClass:[MyObjectClass class]];

##ARC

This project uses ARC and is not usable without ARC.

License
-------
Feel free to use this class in your commercial or non-commercial projects. If you need to make changes or fix bugs, please make sure to fork it on github.com and create a pull request. If possible, please add credit in your about screen as follows:
	
	This application uses SISQLiteContext created by Studio Istanbul.
	
This class is provided completely without warranty.

Todo
----
