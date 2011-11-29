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

@protocol FMDatabaseConnectionPoolDelegate <NSObject>

-(void)databaseConnectionCreated:(FMDatabase*)connection;
-(void)databaseCorruptionOccurredInPool:(id<FMDatabaseConnectionPooling>)pool;

@end

@protocol FMDatabaseConnectionPool <FMDatabaseConnectionPooling>

@property (nonatomic,assign) id<FMDatabaseConnectionPoolDelegate> delegate;

@end

@interface FMDatabaseConnectionPool : NSObject<FMDatabaseConnectionPool>
{
    NSMutableArray* checkedOutConnections;
    NSMutableArray* connections;
    NSMutableDictionary* threadConnections;
    NSString* databasePath;
    NSNumber* openFlags;
    NSUInteger minimumCachedConnections;
    NSTimeInterval connectionTimeToLive;
    BOOL sharedCacheModeEnabled;
    BOOL shouldCacheStatements;
    
    id<FMDatabaseConnectionPoolDelegate> delegate;
}

@property (nonatomic) BOOL shouldCacheStatements;
@property (nonatomic) NSUInteger minimumCachedConnections;
@property (nonatomic) NSTimeInterval connectionTimeToLive;
@property (nonatomic) BOOL sharedCacheModeEnabled;

-(id)initWithDatabasePath:(NSString*)thePath
                openFlags:(NSNumber*)theOpenFlags;

-(void)releaseConnections;

@end
