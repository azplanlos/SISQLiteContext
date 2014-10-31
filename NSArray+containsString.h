//
//  NSArray+containsString.h
//  Photoroute
//
//  Created by Programmierer on 5/9/2013.
//  Copyright (c) 2013 Studio Istanbul. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSArray (containsString)
-(BOOL)containsString:(NSString*)searchString;
-(NSInteger)indexOfString:(NSString*)searchString;
@end
