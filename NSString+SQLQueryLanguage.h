//
//  NSString+SQLQueryLanguage.h
//  SISQLiteContext
//
//  Created by Andreas Zöllner on 10.03.15.
//  Copyright (c) 2015 Studio Istanbul Medya Hiz. Tic. Ltd. Sti. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSString (SQLQueryLanguage)

-(NSString*)stringByAppendingSqlPart:(NSString*)part;

@end
