//
//  FMDatabaseQueue.m
//  fmdb
//
//  Created by August Mueller on 6/22/11.
//  Copyright 2011 Flying Meat Inc. All rights reserved.
//

#import "FMDatabaseQueue.h"
#import "FMDatabase.h"

#define THREAD_ID_KEY @"FMDB_THREAD_ID"

@interface FMDatabaseQueue ()
@property (nonatomic, strong) NSRecursiveLock *lock;
@end

@implementation FMDatabaseQueue

@synthesize path = _path;

+ (id)databaseQueueWithPath:(NSString*)aPath
{
    FMDatabaseQueue *q = [[self alloc] initWithPath:aPath];
    FMDBAutorelease(q);
    return q;
}

- (id)initWithPath:(NSString*)aPath
{
    self = [super init];
    if (self != nil) {
        _db = [FMDatabase databaseWithPath:aPath];
        FMDBRetain(_db);
        
        if (![_db open]) {
            NSLog(@"Could not create database queue for path %@", aPath);
            FMDBRelease(self);
            return 0x00;
        }
        
        _path = FMDBReturnRetained(aPath);
        _lock = [[NSRecursiveLock alloc] init];
    }
    
    return self;
}

- (void)dealloc
{
    FMDBRelease(_db);
    FMDBRelease(_path);
    FMDBRelease(_lock);
#if ! __has_feature(objc_arc)
    [super dealloc];
#endif
}

- (void)close
{
    [_lock lock];
    [_db close];
    FMDBRelease(_db);
    _db = 0x00;
    [_lock unlock];
}

- (FMDatabase*)database
{
    if (!_db) {
        _db = FMDBReturnRetained([FMDatabase databaseWithPath:_path]);
        
        if (![_db open]) {
            NSLog(@"FMDatabaseQueue could not reopen database for path %@", _path);
            FMDBRelease(_db);
            _db  = 0x00;
            return 0x00;
        }
    }
    
    return _db;
}

- (void)inDatabase:(void (^)(FMDatabase *db))block
{
    [_lock lock];
    FMDatabase *db = [self database];
    block(db);
    [db closeOpenResultSets];
    [_lock unlock];
}


- (void)beginTransaction:(BOOL)useDeferred withBlock:(void (^)(FMDatabase *db, BOOL *rollback))block
{
    [_lock lock];
    FMDatabase *db = [self database];
    [self performTransactionBlock:block withDatabase:db useDeferred:useDeferred];
    [db closeOpenResultSets];
    [_lock unlock];
}

- (void)performTransactionBlock:(void (^)(FMDatabase *db, BOOL *rollback))block withDatabase:(FMDatabase *)db useDeferred:(BOOL)useDeferred
{
    BOOL shouldRollback = NO;
    
    if (useDeferred) {
        [db beginDeferredTransaction];
    }
    else {
        [db beginTransaction];
    }
    
    block(db, &shouldRollback);
    
    if (shouldRollback) {
        [db rollback];
    }
    else {
        [db commit];
    }

}

- (void)inDeferredTransaction:(void (^)(FMDatabase *db, BOOL *rollback))block
{
    [self beginTransaction:YES withBlock:block];
}

- (void)inTransaction:(void (^)(FMDatabase *db, BOOL *rollback))block
{
    [self beginTransaction:NO withBlock:block];
}

#if SQLITE_VERSION_NUMBER >= 3007000
- (NSError*)inSavePoint:(void (^)(FMDatabase *db, BOOL *rollback))block
{
    NSError *err = 0x00;
    [_lock lock];
    static unsigned long savePointIdx = 0;
    NSString *name = [NSString stringWithFormat:@"savePoint%ld", savePointIdx++];
    FMDatabase *db = [self database];

    if ([db startSavePointWithName:name error:&err]) {
        BOOL shouldRollback = NO;
        block(db, &shouldRollback);
        [db closeOpenResultSets];

        if (shouldRollback) {
            [db rollbackToSavePointWithName:name error:&err];
        }
        else {
            [db releaseSavePointWithName:name error:&err];
        }
    }

    [_lock unlock];
    return err;
}
#endif

@end