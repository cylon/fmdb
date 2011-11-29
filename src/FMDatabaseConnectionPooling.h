//
//  FMDatabaseConnectionPooling.h
//  fmdb
//
//  Created by Brian Kramer on 11/16/11.
//  Copyright (c) 2011 Digital Cyclone. All rights reserved.
//

#import <Foundation/Foundation.h>

@class FMDatabase;

@protocol FMDatabaseConnectionPooling <NSObject>

-(FMDatabase*)checkoutConnection;
-(void)checkinConnection:(FMDatabase*)connection;

@end
