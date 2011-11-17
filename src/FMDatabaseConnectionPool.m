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

-(id)initWithDatabasePath:(NSString*)thePath
                openFlags:(NSNumber*)theOpenFlags
    shouldCacheStatements:(BOOL)cacheStatements
 minimumCachedConnections:(int)theMinimumCachedConnections
     connectionTimeToLive:(NSTimeInterval)theTimeToLive
    enableSharedCacheMode:(BOOL)enableSharedCacheMode
{
    self = [super init];
    
    if (nil != self)
    {
        databasePath = [thePath copy];
        openFlags = [theOpenFlags retain];
        minimumCachedConnections = theMinimumCachedConnections;
        connectionTTL = theTimeToLive;
        sharedCacheModeEnabled = enableSharedCacheMode;
        shouldCacheStatements = cacheStatements;
        checkedOutConnections = [[NSMutableArray alloc] init];
        
        if (enableSharedCacheMode)
        {
            threadConnections = [[NSMutableDictionary alloc] init];
        }
        else
        {
            connections = [[NSMutableArray alloc] init];
        }
        
        if (kFMDatabaseConnectionPoolInfiniteTimeToLive != theTimeToLive)
        {
            cleanupQueue = dispatch_queue_create("fmdatabase.connection_cleanup", NULL);
            cleanupSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                   (uintptr_t)0,
                                                   0,
                                                   cleanupQueue);
            dispatch_source_set_event_handler(cleanupSource, ^{
                [self cleanupOldConnections];
            });
            
            
            uint64_t interval = theTimeToLive * NSEC_PER_SEC; // Change to nanoseconds
            
            dispatch_time_t startTime = dispatch_time(DISPATCH_TIME_NOW,
                                                      theTimeToLive);
            
            
            // Give a leeway of 2/3 the interval time to allow for room when the
            // app is in the background.  The smaller the leeway, the more strict
            // the policy about when to service the timer if the fire time happened
            // while the app was in the background or the device asleep.
            dispatch_source_set_timer(cleanupSource,
                                      startTime,
                                      interval,
                                      (interval*2)/3);
            
            dispatch_resume(cleanupSource);
        }
    }
    
    return self;
}

-(void)dealloc
{
    if (NULL != cleanupQueue)
    {
        dispatch_source_cancel(cleanupSource);
        dispatch_release(cleanupSource);
        dispatch_release(cleanupQueue);
    }
    [checkedOutConnections release];
    [connections release];
    [threadConnections release];
    [openFlags release];
    [databasePath release];
    
    [super dealloc];
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
            retval = [[connections lastObject] retain];
            if (nil != retval)
            {
                [connections removeLastObject];
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
            retval = temp;
        }
        else
        {
            [temp release];
        }
    }
    
    if (nil != retval)
    {
        [checkedOutConnections addObject:retval];
        [retval release];
    }
    
    return retval;
}

-(BOOL)isConnectionGood:(FMDatabaseConnectionPoolDatabase*)db
{
    BOOL retval = NO;
    
    if ((kFMDatabaseConnectionPoolInfiniteTimeToLive == connectionTTL) ||
        (connectionTTL > [[NSDate date] timeIntervalSinceDate:db.creationTime]))
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
                    if (((kFMDatabaseConnectionPoolInfiniteConnections == minimumCachedConnections) ||
                         (minimumCachedConnections > [connections count])) &&
                        [self isConnectionGood:internalConnection])
                    {
                        [connections addObject:connection];
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
                    NSLog(@"Removing connection to %@ %d left", [db databasePath], [connections count] -1);
                    [db close];
                    [connections removeObject:db];
                }
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

-(BOOL)isDatabaseOk
{
    BOOL retval = NO;
    
    FMDatabase* db = [self checkoutConnection];
    retval = [db goodConnection];
    [self checkinConnection:db];
    
    return retval;
}

@end
