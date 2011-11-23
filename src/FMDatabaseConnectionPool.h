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
@protocol FMDatabaseConnectionPoolObserver;

extern const NSUInteger kFMDatabaseConnectionPoolInfiniteConnections;
extern const NSTimeInterval kFMDatabaseConnectionPoolInfiniteTimeToLive;

@protocol FMDatabaseConnectionPoolDelegate <NSObject>

-(void)databaseConnectionCreated:(FMDatabase*)connection;

@end

@interface FMDatabaseConnectionPool : NSObject<FMDatabaseConnectionPooling>
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
    
    NSMutableArray* observers;
}

@property (nonatomic) BOOL shouldCacheStatements;
@property (nonatomic) NSUInteger minimumCachedConnections;
@property (nonatomic) NSTimeInterval connectionTimeToLive;
@property (nonatomic) BOOL sharedCacheModeEnabled;
@property (nonatomic,assign) id<FMDatabaseConnectionPoolDelegate> delegate;

-(id)initWithDatabasePath:(NSString*)thePath
                openFlags:(NSNumber*)theOpenFlags;

-(void)releaseConnections;

@end
