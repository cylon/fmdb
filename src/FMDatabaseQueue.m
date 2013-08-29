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
@property (nonatomic, strong) NSString *queueUUID;
@end

/*
 
 Note: we call [self retain]; before using dispatch_sync, just incase
 FMDatabaseQueue is released on another thread and we're in the middle of doing
 something in dispatch_sync
 
 */

@implementation FMDatabaseQueue

@synthesize path = _path;

+ (id)databaseQueueWithPath:(NSString*)aPath {
    
    FMDatabaseQueue *q = [[self alloc] initWithPath:aPath];
    
    FMDBAutorelease(q);
    
    return q;
}

- (id)initWithPath:(NSString*)aPath {
    
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
        
        _queue = dispatch_queue_create([[NSString stringWithFormat:@"fmdb.%@", self] UTF8String], NULL);
        _queueUUID = FMDBReturnRetained([FMDatabaseQueue generateUniqueIdentifier]);
    }
    
    return self;
}

- (void)dealloc {
    
    FMDBRelease(_db);
    FMDBRelease(_path);
    FMDBRelease(_queueUUID);
    if (_queue) {
        FMDBDispatchQueueRelease(_queue);
        _queue = 0x00;
    }
#if ! __has_feature(objc_arc)
    [super dealloc];
#endif
}

- (void)close {
    FMDBRetain(self);
    dispatch_sync(_queue, ^() {
        [_db close];
        FMDBRelease(_db);
        _db = 0x00;
    });
    FMDBRelease(self);
}

- (FMDatabase*)database {
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

- (void)inDatabase:(void (^)(FMDatabase *db))block {
    FMDBRetain(self);
    // Check for buggy reentrant code
    NSString *threadId = [[[NSThread currentThread] threadDictionary] objectForKey:THREAD_ID_KEY];
    if ([_queueUUID isEqualToString:threadId])
    {
#ifdef DEBUG
        NSAssert(NO, @"FMDB dispatch_sync called while already on the target queue!");
#endif
        FMDatabase *db = [self database];
        block(db);
    }
    else {
        dispatch_sync(_queue, ^() {
            [[[NSThread currentThread] threadDictionary] setObject:_queueUUID forKey:THREAD_ID_KEY];
            FMDatabase *db = [self database];
            block(db);
            [[[NSThread currentThread] threadDictionary] removeObjectForKey:THREAD_ID_KEY];
//            if ([db hasOpenResultSets]) {
//                NSLog(@"Warning: there is at least one open result set around after performing [FMDatabaseQueue inDatabase:]");
//            }
        });
    }
    
    FMDBRelease(self);
}


- (void)beginTransaction:(BOOL)useDeferred withBlock:(void (^)(FMDatabase *db, BOOL *rollback))block {
    FMDBRetain(self);
    // Check for buggy reentrant code
    NSString *threadId = [[[NSThread currentThread] threadDictionary] objectForKey:THREAD_ID_KEY];
    if ([_queueUUID isEqualToString:threadId])
    {
#ifdef DEBUG
        NSAssert(NO, @"FMDB dispatch_sync called while already on the target queue!");
#endif
        FMDatabase *db = [self database];
        [self performTransactionBlock:block withDatabase:db useDeferred:useDeferred];
    }
    else {
        dispatch_sync(_queue, ^() {
            [[[NSThread currentThread] threadDictionary] setObject:_queueUUID forKey:THREAD_ID_KEY];
            FMDatabase *db = [self database];
            [self performTransactionBlock:block withDatabase:db useDeferred:useDeferred];
            [[[NSThread currentThread] threadDictionary] removeObjectForKey:THREAD_ID_KEY];
        });
    }
    
    FMDBRelease(self);
}

- (void)performTransactionBlock:(void (^)(FMDatabase *db, BOOL *rollback))block withDatabase:(FMDatabase *)db useDeferred:(BOOL)useDeferred
{
    BOOL shouldRollback = NO;
    
    if (useDeferred) {
        [[self database] beginDeferredTransaction];
    }
    else {
        [[self database] beginTransaction];
    }
    
    block([self database], &shouldRollback);
    
    if (shouldRollback) {
        [[self database] rollback];
    }
    else {
        [[self database] commit];
    }

}

- (void)inDeferredTransaction:(void (^)(FMDatabase *db, BOOL *rollback))block {
    [self beginTransaction:YES withBlock:block];
}

- (void)inTransaction:(void (^)(FMDatabase *db, BOOL *rollback))block {
    [self beginTransaction:NO withBlock:block];
}

#if SQLITE_VERSION_NUMBER >= 3007000
- (NSError*)inSavePoint:(void (^)(FMDatabase *db, BOOL *rollback))block {
    
    static unsigned long savePointIdx = 0;
    __block NSError *err = 0x00;
    FMDBRetain(self);
    dispatch_sync(_queue, ^() {
        
        NSString *name = [NSString stringWithFormat:@"savePoint%ld", savePointIdx++];
        
        BOOL shouldRollback = NO;
        
        if ([[self database] startSavePointWithName:name error:&err]) {
            
            block([self database], &shouldRollback);
            
            if (shouldRollback) {
                [[self database] rollbackToSavePointWithName:name error:&err];
            }
            else {
                [[self database] releaseSavePointWithName:name error:&err];
            }
            
        }
    });
    FMDBRelease(self);
    return err;
}
#endif

+ (NSString *)generateUniqueIdentifier
{
    // Make the compiler happy, we only use this under ARC anyways.
    NSString *uuid = nil;
    CFUUIDRef uuidCreator = CFUUIDCreate(kCFAllocatorDefault);
    CFStringRef uuidStringRef = CFUUIDCreateString(kCFAllocatorDefault, uuidCreator);
    CFRelease(uuidCreator);
#if __has_feature(objc_arc)
    uuid = (__bridge_transfer NSString *)uuidStringRef;
#else
    uuid = [(NSString *)uuidStringRef autorelease];
#endif
    return uuid;
}
@end