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
#import "FMDatabaseConnectionPoolObserver.h"

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
@synthesize enableSharedCacheMode;
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
        observers = [[NSMutableArray alloc] init];
        
        if (enableSharedCacheMode)
        {
            threadConnections = [[NSMutableDictionary alloc] init];
        }
        else
        {
            connections = [[NSMutableArray alloc] init];
        }
        
        if (kFMDatabaseConnectionPoolInfiniteTimeToLive != connectionTimeToLive)
        {
            cleanupQueue = dispatch_queue_create("fmdatabase.connection_cleanup", NULL);
            cleanupSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,
                                                   (uintptr_t)0,
                                                   0,
                                                   cleanupQueue);
            dispatch_source_set_event_handler(cleanupSource, ^{
                [self cleanupOldConnections];
            });
            
            
            uint64_t interval = connectionTimeToLive * NSEC_PER_SEC; // Change to nanoseconds
            
            dispatch_time_t startTime = dispatch_time(DISPATCH_TIME_NOW,
                                                      interval);
            
            
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
    [observers release];
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
    
    uint64_t interval = aConnectionTimeToLive * NSEC_PER_SEC; // Change to nanoseconds
    
    dispatch_time_t startTime = dispatch_time(DISPATCH_TIME_NOW, interval);
    
    dispatch_source_set_timer(cleanupSource,
                              startTime,
                              interval,
                              (interval*2)/3);
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
            [delegate databaseConnectionCreated:temp];
            retval = temp;
        }
        else
        {
            int rc = [temp lastErrorCode];
            if ((SQLITE_CORRUPT == rc) || (SQLITE_CORRUPT_VTAB == rc))
            {
                @synchronized(observers)
                {
                    NSArray* copy = [observers copy];
                    
                    for (id<FMDatabaseConnectionPoolObserver> observer in copy)
                    {
                        [observer corruptionOccurredInPool:self];
                    }
                    
                    [copy release];
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
    
    if ((kFMDatabaseConnectionPoolInfiniteTimeToLive == connectionTimeToLive) ||
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

-(void)addConnectionPoolObserver:(id<FMDatabaseConnectionPoolObserver>)observer
{
    @synchronized(observers)
    {
        [observers addObject:observer];
    }
}

-(void)removeConnectionPoolObserver:(id<FMDatabaseConnectionPoolObserver>)observer
{
    @synchronized(observers)
    {
        [observers removeObject:observer];
    }
}

@end
