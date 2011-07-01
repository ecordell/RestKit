//
//  RKManagedObjectSyncObserver.h
//  RestKit
//
//  Created by Evan Cordell on 6/29/11.
//  Copyright 2011 Two Toasters. All rights reserved.
//

#import "../Network/Network.h"
#import "../ObjectMapping/RKObjectManager.h"
#import "NSManagedObject+ActiveRecord.h"
#import "RKManagedObjectStore.h"

typedef enum {
	RKSyncStatusShouldNotSync,
	RKSyncStatusShouldPost,
	RKSyncStatusShouldPut,
	RKSyncStatusShouldDelete
} RKSyncStatus;

@interface RKManagedObjectSyncObserver : NSObject <RKObjectLoaderDelegate> {
    NSMutableArray *_registeredClasses; 
    BOOL _isSyncing;
}

@property (nonatomic, retain) NSMutableArray *registeredClasses;
@property (nonatomic, assign) BOOL isSyncing;

+ (RKManagedObjectSyncObserver*)sharedSyncObserver;
+ (void)setSharedSyncObserver:(RKManagedObjectSyncObserver*)observer;

- (void)registerClassForSyncing:(Class<RKObjectSync>)someClass;
- (void)unregisterClassForSyncing:(Class<RKObjectSync>)someClass;

- (void)enteredOnlineMode;
- (void)enteredOfflineMode;

- (void)shouldNotSyncObject:(NSManagedObject*)object error:(NSError**)error;
- (void)shouldPostObject:(NSManagedObject*)object error:(NSError**)error;
- (void)shouldPutObject:(NSManagedObject*)object error:(NSError**)error;
- (void)shouldDeleteObject:(NSManagedObject*)object error:(NSError**)error;


@end
