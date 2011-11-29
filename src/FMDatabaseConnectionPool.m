//
//  FMDatabaseConnectionPool.m
//  Pilot
//
//  Created by Brian Kramer on 11/3/11.
//  Copyright (c) 2011 Digital Cyclone. All rights reserved.
//

#import "FMDatabaseConnectionPool.h"

#import "FMDatabase.h"
#import <sqlite3.h>

const NSUInteger kFMDatabaseConnectionPoolInfiniteConnections = UINT_MAX;
const NSTimeInterval kFMDatabaseConnectionPoolInfiniteTimeToLive = -1;

static const NSUInteger DEFAULT_MIN_CONNECTIONS = 1;
static const NSTimeInterval DEFAULT_TIME_TO_LIVE = 5;
static const BOOL DEFAULT_SHOULD_CACHE_STATEMENTS = YES;

@interface FMDatabaseConnectionPoolDatabase : FMDatabase {
@private
    NSDate* creationTime;
}
@property (nonatomic,readonly) NSDate* creationTime;

- (id)initWithPath:(NSString*)aPath;
@end

@implementation FMDatabaseConnectionPoolDatabase
@synthesize creationTime;

-(id)initWithPath:(NSString *)aPath
{
    self = [super initWithPath:aPath];
    
    if (nil != self)
    {
        creationTime = [[NSDate date] retain];
    }
    
    return self;
}

-(void)dealloc
{
    
    [creationTime release];
    [super dealloc];
}

@end

@interface FMDatabaseConnectionPool()
-(void)cleanupOldConnections;
@end

@implementation FMDatabaseConnectionPool
@synthesize shouldCacheStatements;
@synthesize minimumCachedConnections;
@synthesize connectionTimeToLive;
@synthesize sharedCacheModeEnabled;
@synthesize delegate;

-(id)initWithDatabasePath:(NSString*)thePath
                openFlags:(NSNumber*)theOpenFlags
{
    self = [super init];
    
    if (nil != self)
    {
        databasePath = [thePath copy];
        openFlags = [theOpenFlags retain];
        minimumCachedConnections = DEFAULT_MIN_CONNECTIONS;
        connectionTimeToLive = DEFAULT_TIME_TO_LIVE;
        sharedCacheModeEnabled = NO;
        shouldCacheStatements = DEFAULT_SHOULD_CACHE_STATEMENTS;
        checkedOutConnections = [[NSMutableArray alloc] init];
        
        if (sharedCacheModeEnabled)
        {
            threadConnections = [[NSMutableDictionary alloc] init];
        }
        else
        {
            connections = [[NSMutableArray alloc] init];
        }
    }
    
    return self;
}

-(void)dealloc
{
    [checkedOutConnections release];
    [connections release];
    [threadConnections release];
    [openFlags release];
    [databasePath release];
    
    [super dealloc];
}

-(void)setConnectionTimeToLive:(NSTimeInterval)aConnectionTimeToLive
{
    connectionTimeToLive = aConnectionTimeToLive;
}

-(BOOL)openDatabase:(FMDatabase*)db
{
    BOOL opened = NO;
    if (nil == openFlags)
    {
        opened = [db open];
    }
    else
    {
        opened = [db openWithFlags:[openFlags intValue]];
    }
    
    [db setShouldCacheStatements:shouldCacheStatements];
    
    return opened;
}

-(FMDatabase*)checkoutConnection
{
    FMDatabaseConnectionPoolDatabase* retval = nil;
    
    @synchronized(self)
    {
        if (nil != connections)
        {
            if (0 < [connections count])
            {
                retval = [[connections lastObject] retain];
                if (nil != retval)
                {
                    [connections removeLastObject];
                }
            }
        }
        else
        {
            
        }
    }
    
    if (nil == retval)
    {
        // Create one
        FMDatabaseConnectionPoolDatabase* temp = [[FMDatabaseConnectionPoolDatabase alloc] initWithPath:databasePath];
        
        if ([self openDatabase:temp])
        {
            [delegate databaseConnectionCreated:temp];
            retval = temp;
        }
        else
        {
            int rc = [temp lastErrorCode];
            if ((SQLITE_CORRUPT == rc))// || (SQLITE_CORRUPT_VTAB == rc))
            {
                @synchronized(delegate)
                {
                    [delegate databaseCorruptionOccurredInPool:self];
                }
            }
            [temp release];
        }
    }
    
    if (nil != retval)
    {
        [checkedOutConnections addObject:retval];
        [retval autorelease];
    }
    
    return retval;
}

-(BOOL)isConnectionGood:(FMDatabaseConnectionPoolDatabase*)db
{
    BOOL retval = NO;
    
    if ((0 > connectionTimeToLive) ||
        (connectionTimeToLive > [[NSDate date] timeIntervalSinceDate:db.creationTime]))
    {
        retval = YES;
    }
    
    return retval;
}

-(void)checkinConnection:(FMDatabase*)connection
{
    if (nil != connection)
    {
        FMDatabaseConnectionPoolDatabase* internalConnection = (FMDatabaseConnectionPoolDatabase*)connection;
        
        @synchronized(self)
        {
            if ([checkedOutConnections containsObject:connection])
            {
                if (nil != connections)
                {
                    const NSUInteger count = [connections count];
                    BOOL shouldStartTimer = (0 == count) && (0 < connectionTimeToLive);
                    
                    if (((kFMDatabaseConnectionPoolInfiniteConnections == minimumCachedConnections) ||
                         (minimumCachedConnections > count)) &&
                        [self isConnectionGood:internalConnection])
                    {
                        [connections addObject:connection];
                        
                        if (shouldStartTimer)
                        {
                            dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, connectionTimeToLive * NSEC_PER_SEC);
                            dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^(void){
                                [self cleanupOldConnections];
                            });
                        }
                    }
                }
                else
                {
                    
                }
                
                [checkedOutConnections removeObject:connection];
            }
        }
    }
}

-(void)cleanupOldConnections
{
    @synchronized(self)
    {
        if (nil != connections)
        {
            // Copy so that any connections can be removed in the loop
            NSArray* tempConnections = [connections copy];
            
            for (FMDatabaseConnectionPoolDatabase* db in tempConnections)
            {
                if (![self isConnectionGood:db])
                {
                    [db close];
                    [connections removeObject:db];
                }
            }
            
            if ((0 < [connections count]) && (0 < connectionTimeToLive))
            {
                dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, connectionTimeToLive * NSEC_PER_SEC);
                dispatch_after(popTime, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^(void){
                    [self cleanupOldConnections];
                });
            }
            
            [tempConnections release];
        }
        else
        {
            
        }
    }
}

-(void)releaseConnections
{
    @synchronized(self)
    {
        [checkedOutConnections removeAllObjects];
        
        if (nil != connections)
        {
            [connections removeAllObjects];
        }
        else
        {
            [threadConnections removeAllObjects];
        }
    }
}

@end
