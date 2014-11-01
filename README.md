SISQLiteContext
===============

light-weight Core Data Alternative with SQLite datastore building and managing database according to Objective-C class properties.

This objective-c class is ment to fix the gap between performance of a native SQLite database and comfort of Core Data.

You don't need any separate data models for this storage class, all necessary adjustments and upgrades to your client's database files are done by analyzing of your custom subclasses at runtime.

Faulting and relational data models are supported.

How to use
----------

Subclass your database objects from SIPROSMObject and add as many properties as necessary. Name all SQLite stored properties beginning with "sql_" (f.ex. "sql_mydata")

Set your properties by assigning to the property's name or via KVO methods without "sql_" prefix (f.ex. -(void)setMydata:(id)data). Accessormethods are created automatically on runtime.

Use NSArray or NSMutableArray classes for relational properties.

Connect to a database:

	[[SISQLiteContext SQLiteContext] loadDatabaseFromURL:[NSURL fileURLWithPath:dbFilePath]];

Only one context possible at a time but different subclasses will be mapped to different tables in your SQLite database.

Init the database and check for compatibility. Changes will be made automatically to fit your current data model. Set ID field for eliminating duplicates on init then init the database.

	[[SISQLiteContext SQLiteContext] setIdField:@"identifier"];
    [[SISQLiteContext SQLiteContext] initDatabaseWithTableObjects:[NSArray arrayWithObjects:[objectClass1 class], [objectClass2 class], [objectClass3 class], nil]];
    
Check if database is initialized correctly:

	if ([[SISQLiteContext SQLiteContext] isDatabaseReady]) {
		// Do something with your database
	}
    
Now create your objects as normal. To save them to your database, call on your object:

	-(void)saveAndDestroy;

To commit your changes to the database file, make sure to call

	    [[SISQLiteContext SQLiteContext] synchronize];

If you add an object to a relational property set the referencing key on your child object first.

	myObject.referenceKey = @"ID";
	myObject.referenceValue = @"125";
	[myParentObject.mutableArrayProperty addObject:myObject];
	
If you want to add a reference without creating the actual object, just add a faulted object like this:

	SISQLiteObject* myObject = [SISQLiteObject faultedObjectWithReferenceKey:@"ID" andValue:@"125"];
	[myParentObject.mutableArrayProperty addObject:myObject];
	
Fetch some objects from database, child objects will be added faulted:

	NSArray* myObjects = [[SISQLiteContext SQLiteContext] resultsForQuery:@"name = 'test'" withClass:[MyObjectClass class]];
	
Load a faulted object from database:

	[myFaultedObject loadObjectFromStore];

Todo
----

