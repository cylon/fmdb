//
//  FMDatabaseConnectionPoolObserver.h
//  Pilot
//
//  Created by Brian Kramer on 11/3/11.
//  Copyright (c) 2011 Digital Cyclone. All rights reserved.
//

#import <Foundation/Foundation.h>

@class FMDatabaseConnectionPool;

@protocol FMDatabaseConnectionPoolObserver <NSObject>
-(void)corruptionOccurredInPool:(FMDatabaseConnectionPool*)pool;
@end
