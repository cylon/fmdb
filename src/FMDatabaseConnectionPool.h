//
//  FMDatabaseConnectionPool.h
//  Pilot
//
//  Created by Brian Kramer on 11/3/11.
//  Copyright (c) 2011 Digital Cyclone. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "FMDatabaseConnectionPooling.h"

@class FMDatabase;

extern const NSUInteger kFMDatabaseConnectionPoolInfiniteConnections;
extern const NSTimeInterval kFMDatabaseConnectionPoolInfiniteTimeToLive;

@interface FMDatabaseConnectionPool : NSObject<FMDatabaseConnectionPooling>
{
    NSMutableArray* checkedOutConnections;
    NSMutableArray* connections;
    NSMutableDictionary* threadConnections;
    NSString* databasePath;
    NSNumber* openFlags;
    NSUInteger minimumCachedConnections;
    NSTimeInterval connectionTTL;
    BOOL sharedCacheModeEnabled;
    BOOL shouldCacheStatements;
    dispatch_queue_t cleanupQueue;
    dispatch_source_t cleanupSource;
}

-(id)initWithDatabasePath:(NSString*)thePath
                openFlags:(NSNumber*)theOpenFlags
    shouldCacheStatements:(BOOL)cacheStatements
 minimumCachedConnections:(int)theMinimumCachedConnections
     connectionTimeToLive:(NSTimeInterval)theTimeToLive
    enableSharedCacheMode:(BOOL)enableSharedCacheMode;

-(void)releaseConnections;

@end
