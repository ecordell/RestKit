//
//  RKSyncManagerTest.m
//  RestKit
//
//  Created by Mark Makdad on 5/4/12.
//  Copyright (c) 2009-2012 RestKit. All rights reserved.
//

#import "RKTestEnvironment.h"
#import "RKSyncManager.h"

// For model testing
#import "RKHuman.h"
#import "RKCat.h"

@interface RKSyncManagerTest : RKTestCase
@property (strong) RKManagedObjectStore *store;
@property (strong) RKObjectManager *manager;
@property (strong) RKHuman *seededHuman;
@property (strong) RKManagedObjectMapping *transparentSyncMapping;
@property (strong) RKManagedObjectMapping *manualSyncMapping;
@property (strong) RKManagedObjectMapping *noSyncMapping;
@property (strong) RKManagedObjectMapping *intervalSyncMapping;
@end

@implementation RKSyncManagerTest
@synthesize store, manager, seededHuman;
@synthesize noSyncMapping, manualSyncMapping, transparentSyncMapping, intervalSyncMapping;

- (void)setUp {
    [RKTestFactory setUp];
    self.store = [RKTestFactory managedObjectStore];
    self.manager = [RKTestFactory objectManager];
    self.manager.objectStore = self.store;
  
    // Make an RKHuman entity in Core Data that we can update/delete
    RKHuman *human = [RKHuman object];
    human.name = @"Mark Makdad";
    human.railsID = [NSNumber numberWithInt:1];
    [self.manager.objectStore save:nil];
    self.seededHuman = human;
  
    // Transparent sync mapping for RKHuman
    self.transparentSyncMapping = [RKManagedObjectMapping mappingForClass:[RKHuman class] inManagedObjectStore:self.store];
    self.transparentSyncMapping.syncMode = RKSyncModeTransparent;
  
    // Regular mapping w/ no sync
    self.noSyncMapping = [RKManagedObjectMapping mappingForClass:[RKHuman class] inManagedObjectStore:self.store];
  
    // Manual sync
    self.manualSyncMapping = [RKManagedObjectMapping mappingForClass:[RKHuman class] inManagedObjectStore:self.store];
    self.manualSyncMapping.syncMode = RKSyncModeManual;
  
    // Interval sync
    self.intervalSyncMapping = [RKManagedObjectMapping mappingForClass:[RKHuman class] inManagedObjectStore:self.store];
    self.intervalSyncMapping.syncMode = RKSyncModeInterval;
  
    // Set up the routing for humans & cats
    [self.manager.router routeClass:[RKHuman class] toResourcePath:@"/human" forMethod:RKRequestMethodGET];
    [self.manager.router routeClass:[RKHuman class] toResourcePath:@"/human" forMethod:RKRequestMethodPUT];
    [self.manager.router routeClass:[RKHuman class] toResourcePath:@"/human" forMethod:RKRequestMethodPOST];
    [self.manager.router routeClass:[RKHuman class] toResourcePath:@"/human" forMethod:RKRequestMethodDELETE];
    [self.manager.router routeClass:[RKCat class] toResourcePath:@"/cat" forMethod:RKRequestMethodGET];
    [self.manager.router routeClass:[RKCat class] toResourcePath:@"/cat" forMethod:RKRequestMethodPUT];
    [self.manager.router routeClass:[RKCat class] toResourcePath:@"/cat" forMethod:RKRequestMethodPOST];
    [self.manager.router routeClass:[RKCat class] toResourcePath:@"/cat" forMethod:RKRequestMethodDELETE];
  
    // Get a serialization mapping - we're going to need this to get the requests out the door
    RKManagedObjectMapping *serializationMapping = [RKManagedObjectMapping mappingForClass:[RKHuman class]
                                                                      inManagedObjectStore:self.store];
  
    // Most of these test methods use this mapping - the test will need to switch explicitly otherwise
    [self.manager.mappingProvider setMapping:self.transparentSyncMapping forKeyPath:@"/human"];
    [self.manager.mappingProvider setSerializationMapping:serializationMapping forClass:[RKHuman class]];
}

- (void)tearDown {
    [RKTestFactory tearDown];
}

#pragma mark - Sync Queue Management Tests

- (void)testSyncQueueEntityExistsWhenObjectStoreCreated {
    NSArray *entityNames = [self.store.managedObjectModel.entitiesByName allKeys];
    assertThat(entityNames, hasItem(@"RKManagedObjectSyncQueue"));
}

- (void)testSyncQueueStartsEmpty {
    NSArray *queueItems = [RKManagedObjectSyncQueue findAll];
    assertThat(queueItems, hasCountOf(0));
}

- (void)testSyncQueueIgnoredWhenSyncModeNotSet {
    // We are NOT setting the sync mode here on this mapping, so this should have no effect on the queue
    [self.manager.mappingProvider setMapping:self.noSyncMapping forKeyPath:@"/human"];
    
    // Create a new human
    RKHuman *human = [RKHuman object];
    human.name = @"Eric Cordell";
    human.railsID = [NSNumber numberWithInt:2];
    [self.manager.objectStore save:nil];
    
    // We should now have a queue item of that human's request
    NSArray *queueItems = [RKManagedObjectSyncQueue findAll];
    assertThat(queueItems,hasCountOf(0));
}

- (void)testSyncQueuePOSTItemCreatedWhenCoreDataObjectCreated {
    // Create a new human - we have a mapping w/ syncMode set so we expect sync behavior
    RKHuman *human = [RKHuman object];
    human.name = @"Eric Cordell";
    human.railsID = [NSNumber numberWithInt:2];
    [self.manager.objectStore save:nil];
    
    // We should now have a queue item of that human's request
    NSArray *queueItems = [RKManagedObjectSyncQueue findAll];
    assertThat(queueItems,hasCountOf(1));
    
    // Which should be a POST request
    RKManagedObjectSyncQueue *item = [queueItems objectAtIndex:0];
    assertThat(item.syncMethod,is(equalTo([NSNumber numberWithInteger:RKRequestMethodPOST])));
}

- (void)testSyncQueueItemCreatedWhenCoreDataObjectUpdated {
    // Make the change to the RKHuman object & save, we should now have a sync item.
    self.seededHuman.name = @"Blake Watters";
    [self.manager.objectStore save:nil];

    NSArray *queueItems = [RKManagedObjectSyncQueue findAll];
    assertThat(queueItems,hasCountOf(1));
    
    // Which should be a PUT request
    RKManagedObjectSyncQueue *item = [queueItems objectAtIndex:0];
    assertThat(item.syncMethod,is(equalTo([NSNumber numberWithInteger:RKRequestMethodPUT])));  
}

- (void)testSyncQueueItemCreatedWhenCoreDataObjectDeleted {
    // Delete, now we should have a DELETE request
    [self.seededHuman deleteEntity];
    [self.manager.objectStore save:nil];
  
    NSArray *queueItems = [RKManagedObjectSyncQueue findAll];
    assertThat(queueItems,hasCountOf(1));
    
    // Which should be a PUT request
    RKManagedObjectSyncQueue *item = [queueItems objectAtIndex:0];
    assertThat(item.syncMethod,is(equalTo([NSNumber numberWithInteger:RKRequestMethodDELETE])));
}

- (void)testSyncManagerBatchStrategyPrunesExtraUpdates {
    // First update
    self.seededHuman.name = @"Maaku Makudaddo";
    [self.manager.objectStore save:nil];
    assertThat([RKManagedObjectSyncQueue findAll],hasCountOf(1));
    
    // Second update - we should still only have 1 item in the queue as the manager realized there were 2 updates
    self.seededHuman.name = @"Mark Makdad";
    [self.manager.objectStore save:nil];
    assertThat([RKManagedObjectSyncQueue findAll],hasCountOf(1));
}

- (void)testSyncManagerProxyStrategyForMultipleUpdates {
    // Tell the RKSyncManager not to prune theoretically unnecessary UPDATE requests
    [self.manager.syncManager setDefaultSyncStrategy:RKSyncStrategyProxyOnly];
    
    // First update
    self.seededHuman.name = @"Maaku Makudaddo";
    [self.manager.objectStore save:nil];
    assertThat([RKManagedObjectSyncQueue findAll],hasCountOf(1));
    
    // Second update - we should now have 2 items in the queue
    self.seededHuman.name = @"Mark Makdad";
    [self.manager.objectStore save:nil];
    assertThat([RKManagedObjectSyncQueue findAll],hasCountOf(2));
}

- (void)testSyncManagerBatchStrategyPrunesLocalOnlyObjects {
    // Create a new human - we have a mapping w/ syncMode set so we expect sync behavior
    RKHuman *human = [RKHuman object];
    human.name = @"Eric Cordell";
    human.railsID = [NSNumber numberWithInt:2];
    [self.manager.objectStore save:nil];
    assertThat([RKManagedObjectSyncQueue findAll],hasCountOf(1));
  
    // Never mind, we wanted to delete this guy.  Don't bother sending anything with batch strategy
    [human deleteEntity];
    [self.manager.objectStore save:nil];
    assertThat([RKManagedObjectSyncQueue findAll],hasCountOf(0));
}

- (void)testSyncManagerProxyStrategyDoesNotPruneLocalOnlyObjects {
    // Tell the RKSyncManager not to prune theoretically unnecessary UPDATE/POST requests
    [self.manager.syncManager setDefaultSyncStrategy:RKSyncStrategyProxyOnly];
  
    // Create a new human - we have a mapping w/ syncMode set so we expect sync behavior
    RKHuman *human = [RKHuman object];
    human.name = @"Eric Cordell";
    human.railsID = [NSNumber numberWithInt:2];
    [self.manager.objectStore save:nil];
    assertThat([RKManagedObjectSyncQueue findAll],hasCountOf(1));
    
    // Never mind, we wanted to delete this guy.  The queue should now contain both items - POST & DELETE.
    [human deleteEntity];
    [self.manager.objectStore save:nil];
    assertThat([RKManagedObjectSyncQueue findAll],hasCountOf(2));
}

#pragma mark - Sync Mode Tests

- (void)testTransparentSyncModeDoesStartAutomatically {
    [self.manager.syncManager setDefaultSyncDirection:RKSyncDirectionPush];
  
    // Create a new human - we have a mapping w/ syncMode set so we expect sync behavior
    RKHuman *human = [RKHuman object];
    human.name = @"Eric Cordell";
    human.railsID = [NSNumber numberWithInt:2];
    [self.manager.objectStore save:nil];
    
    // There should already be a request in the queue w/o us doing anything.
    NSNumber *numRequests = [NSNumber numberWithUnsignedInteger:self.manager.requestQueue.loadingCount];
    assertThat(numRequests,equalToUnsignedInt(1));
}

- (void)testManualSyncModeDoesNotStartUntilPushIsCalled {
    [self.manager.mappingProvider setMapping:self.manualSyncMapping forKeyPath:@"/human"];
    
    // Create a new human
    RKHuman *human = [RKHuman object];
    human.name = @"Eric Cordell";
    human.railsID = [NSNumber numberWithInt:2];
    [self.manager.objectStore save:nil];
    
    // We are in manual sync mode, so no requests should happen automatically.
    NSNumber *numRequests = [NSNumber numberWithUnsignedInteger:self.manager.requestQueue.loadingCount];
    assertThat(numRequests,equalToUnsignedInt(0));
    
    // Now after a manual "push" call it should have 1
    [self.manager.syncManager push];
    numRequests = [NSNumber numberWithUnsignedInteger:self.manager.requestQueue.loadingCount];
    assertThat(numRequests,equalToUnsignedInt(1));
}

- (void)testManualSyncModeOnlyPushesWhatItIsTold {
    [self.manager.mappingProvider setMapping:self.manualSyncMapping forKeyPath:@"/human"];
    
    // Create a new human
    RKHuman *human = [RKHuman object];
    human.name = @"Eric Cordell";
    human.railsID = [NSNumber numberWithInt:2];
    [self.manager.objectStore save:nil];

    // Here we're syncing cats, not humans
    [self.manager.syncManager syncObjectsOfClass:[RKCat class]];
    NSNumber *numRequests = [NSNumber numberWithUnsignedInteger:self.manager.requestQueue.loadingCount];
    assertThat(numRequests,equalToUnsignedInt(0));

    // Let's try that again with humans - push & pull request expected
    [self.manager.syncManager syncObjectsOfClass:[RKHuman class]];
    numRequests = [NSNumber numberWithUnsignedInteger:self.manager.requestQueue.loadingCount];
    assertThat(numRequests,equalToUnsignedInt(2));
}

- (void)testIntervalSyncModeStartsAfterInterval {
    [self.manager.mappingProvider setMapping:self.intervalSyncMapping forKeyPath:@"/human"];
    [self.manager.syncManager setDefaultSyncDirection:RKSyncDirectionPush];

    // Create a new human
    RKHuman *human = [RKHuman object];
    human.name = @"Eric Cordell";
    human.railsID = [NSNumber numberWithInt:2];
    [self.manager.objectStore save:nil];
    
    // The default interval is 1 minute, so a 1.5 second delay here should have no impact.
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.5]];
    NSNumber *numRequests = [NSNumber numberWithUnsignedInteger:self.manager.requestQueue.loadingCount];
    assertThat(numRequests,equalToUnsignedInt(0));
    
    // Suspend the request queue just in case the request happens fast (e.g. fully completes w/in the 1.5 seconds)
    self.manager.requestQueue.suspended = YES;
    
    // Change the timer to be quite quick - 0.5 seconds, then let it run for 1.5 seconds
    [self.manager.syncManager setSyncInterval:0.5];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1.5]];
    
    // Now unleash any queued requests from suspension and confirm that we have 1
    self.manager.requestQueue.suspended = NO;
    numRequests = [NSNumber numberWithUnsignedInteger:self.manager.requestQueue.loadingCount];
    assertThat(numRequests,equalToUnsignedInt(1));
}

#pragma mark - Sync Direction

- (void) testBothRequestsWhenSyncDirectionIsBoth {
    // (The default behavior is both so we don't need to explicitly set it here)
    self.seededHuman.name = @"Blake Watters";
    [self.manager.objectStore save:nil];
    
    // Only 1 item in the queue -- a push (the queue only ever holds pushes)
    NSArray *queueItems = [RKManagedObjectSyncQueue findAll];
    assertThat(queueItems,hasCountOf(1));
    
    // But there should be 2 requests - a push and a pull
    NSNumber *numRequests = [NSNumber numberWithUnsignedInteger:self.manager.requestQueue.loadingCount];
    assertThat(numRequests,equalToUnsignedInt(2));
}

- (void)testShouldPushRequestsOnlyWhenSyncDirectionIsPush {
    // We only want to sync pushes by default
    [self.manager.syncManager setDefaultSyncDirection:RKSyncDirectionPush];
  
    self.seededHuman.name = @"Blake Watters";
    [self.manager.objectStore save:nil];
    
    // Only 1 item in the queue -- a push (the queue only ever holds pushes)
    NSArray *queueItems = [RKManagedObjectSyncQueue findAll];
    assertThat(queueItems,hasCountOf(1));
    
    // And there should be 1 requests - a push.
    NSNumber *numRequests = [NSNumber numberWithUnsignedInteger:self.manager.requestQueue.loadingCount];
    assertThat(numRequests,equalToUnsignedInt(1));
}

- (void)testShoulPullRequestsOnlyWhenSyncDirectionIsPull {
    // We only want to sync pulls by default
    [self.manager.syncManager setDefaultSyncDirection:RKSyncDirectionPull];
    
    self.seededHuman.name = @"Blake Watters";
    [self.manager.objectStore save:nil];
    
    // No items in the queue -- we aren't pushing up any changes.
    NSArray *queueItems = [RKManagedObjectSyncQueue findAll];
    assertThat(queueItems,hasCountOf(0));
    
    // And there should be 1 requests - a pull.
    NSNumber *numRequests = [NSNumber numberWithUnsignedInteger:self.manager.requestQueue.loadingCount];
    assertThat(numRequests,equalToUnsignedInt(1));
}

-(void)testDifferentObjectsShouldNotInterfereWithSyncDirections {
    [self.manager.syncManager setSyncDirection:RKSyncDirectionPush forClass:[RKHuman class]];
    [self.manager.syncManager setSyncDirection:RKSyncDirectionPull forClass:[RKCat class]];
  
    // Make a new cat & update a human
    RKCat *newCat = [RKCat object];
    newCat.name = @"Nyan";
    self.seededHuman.name = @"Blake Watters";
    [self.manager.objectStore save:nil];

    // 1 items in the queue -- we are pushing the human.
    NSArray *queueItems = [RKManagedObjectSyncQueue findAll];
    assertThat(queueItems,hasCountOf(1));
    RKManagedObjectSyncQueue *item = [queueItems objectAtIndex:0];
    assertThat(item.className,equalTo(@"RKHuman"));
  
    // And there should be 2 requests - a pull AND a push.
    NSNumber *numRequests = [NSNumber numberWithUnsignedInteger:self.manager.requestQueue.loadingCount];
    assertThat(numRequests,equalToUnsignedInt(2));
}

#pragma mark - Delegate Testing

- (void)testShouldCallAllDelegateMethodsWhenSyncing {
    id syncDelegate = [OCMockObject niceMockForProtocol:@protocol(RKSyncManagerDelegate)];
    self.manager.syncManager.delegate = syncDelegate;
    
    // We are syncing everything, so the delegate won't have any specific class type
    [[syncDelegate expect] syncManager:self.manager.syncManager willSyncWithSyncMode:RKSyncModeManual andClass:nil];
    [[syncDelegate expect] syncManager:self.manager.syncManager didSyncWithSyncMode:RKSyncModeManual andClass:nil];

    // Configure RestKit to handle cat objects
    RKManagedObjectMapping *catMapping = [RKManagedObjectMapping mappingForClass:[RKCat class] inManagedObjectStore:self.store];
    catMapping.syncMode = RKSyncModeManual;
    [self.manager.mappingProvider setSerializationMapping:catMapping forClass:[RKCat class]];
    [self.manager.mappingProvider setMapping:catMapping forKeyPath:@"/cat"];

    // Now create a human and see that the delegates are called when we manually sync
    [self.manager.mappingProvider setMapping:self.manualSyncMapping forKeyPath:@"/human"];
    RKHuman *human = [RKHuman object];
    human.name = @"Eric Cordell";
    human.railsID = [NSNumber numberWithInt:2];
  
    // Create the cat & save both
    RKCat *cat = [RKCat object];
    cat.name = @"Nyanko";
    [self.manager.objectStore save:nil];

    // Also, we'll end up pushing 1 human.
    NSSet *objs = [NSSet setWithObjects:cat,human,nil];
    [[syncDelegate expect] syncManager:self.manager.syncManager willPushObjects:objs withSyncMode:RKSyncModeManual];
    [[syncDelegate expect] syncManager:self.manager.syncManager didPushObjects:objs withSyncMode:RKSyncModeManual];
  
    // And pulling all humans.
    [[syncDelegate expect] syncManager:self.manager.syncManager willPullObjectsOfClass:nil withSyncMode:RKSyncModeManual];
    [[syncDelegate expect] syncManager:self.manager.syncManager didPullObjectsOfClass:nil withSyncMode:RKSyncModeManual];

    [self.manager.syncManager sync];
    
    [syncDelegate verify];
}

- (void)testShouldCallPushDelegateMethods {
    id syncDelegate = [OCMockObject niceMockForProtocol:@protocol(RKSyncManagerDelegate)];
    self.manager.syncManager.delegate = syncDelegate;
    
    // Now create a human (with manual syncing) and see that the delegates are called
    [self.manager.mappingProvider setMapping:self.manualSyncMapping forKeyPath:@"/human"];
    RKHuman *human = [RKHuman object];
    human.name = @"Eric Cordell";
    human.railsID = [NSNumber numberWithInt:2];

    NSSet *objs = [NSSet setWithObject:human];
    [[syncDelegate expect] syncManager:self.manager.syncManager willPushObjects:objs withSyncMode:RKSyncModeManual];
    [[syncDelegate expect] syncManager:self.manager.syncManager didPushObjects:objs withSyncMode:RKSyncModeManual];

    [self.manager.objectStore save:nil];
    [self.manager.syncManager push];
    
    [syncDelegate verify];
}

- (void)testShouldCallPullDelegateMethods {
    id syncDelegate = [OCMockObject niceMockForProtocol:@protocol(RKSyncManagerDelegate)];
    self.manager.syncManager.delegate = syncDelegate;
    
    [[syncDelegate expect] syncManager:self.manager.syncManager willPullObjectsOfClass:nil withSyncMode:RKSyncModeManual];
    [[syncDelegate expect] syncManager:self.manager.syncManager didPullObjectsOfClass:nil withSyncMode:RKSyncModeManual];

    // Now call the pull to make the delegate call back
    [self.manager.syncManager pull];
    
    [syncDelegate verify];
}

- (void)testShouldCallPullDelegateMethodsWithClass {
    id syncDelegate = [OCMockObject niceMockForProtocol:@protocol(RKSyncManagerDelegate)];
    self.manager.syncManager.delegate = syncDelegate;
    
    // Only manually pull humans
    Class aClass = [RKHuman class];
    [[syncDelegate expect] syncManager:self.manager.syncManager willPullObjectsOfClass:aClass withSyncMode:RKSyncModeManual];
    [[syncDelegate expect] syncManager:self.manager.syncManager didPullObjectsOfClass:aClass withSyncMode:RKSyncModeManual];
    
    // Now call the pull to make the delegate call back
    [self.manager.syncManager pullObjectsWithSyncMode:RKSyncModeManual andClass:aClass];
    
    [syncDelegate verify];
  
}

- (void)testShouldCallErrorDelegateMethod {
  id syncDelegate = [OCMockObject niceMockForProtocol:@protocol(RKSyncManagerDelegate)];
  self.manager.syncManager.delegate = syncDelegate;
  
  NSError *error = nil;
  [[syncDelegate expect] syncManager:self.manager.syncManager didFailSyncingWithError:error];

  [self.manager.syncManager pullObjectsWithSyncMode:RKSyncModeManual andClass:[RKHuman class]];
  
  // Let it run long enough for the server to fail because we don't know this route.
  [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:3]];
  
  [syncDelegate verify];
}

#pragma mark - Network

- (void)testShouldStartSyncAfterReachabilityIsEstablished {
  RKURL *bogusUrl = [RKURL URLWithBaseURL:[NSURL URLWithString:@"http://10.1.1.1/"]];
  [RKTestFactory setBaseURL:bogusUrl];
  
  self.manager = [RKTestFactory objectManager];
  self.manager.objectStore = self.store;
  
  // Now try to create a human & confirm he's added to the queue, but not yet running.
  RKHuman *human = [RKHuman object]; 
  human.name = @"Foo Bar";
  [self.manager.objectStore save:nil];
  NSArray *queueItems = [RKManagedObjectSyncQueue findAll];
  assertThat(queueItems,hasCountOf(1));
  NSNumber *numRequests = [NSNumber numberWithUnsignedInteger:self.manager.requestQueue.loadingCount];
  assertThat(numRequests,equalToUnsignedInt(0));
  
  // Now go ahead and change to a legitimate base URL -- this alone should trigger the notification
  RKURL *goodUrl = [RKURL URLWithBaseURLString:@"http://127.0.0.1:4567/"];
  [RKTestFactory setBaseURL:goodUrl];
  self.manager = [RKTestFactory objectManager];
  [self.manager.router routeClass:[RKHuman class] toResourcePath:@"/human" forMethod:RKRequestMethodGET];
  [self.manager.router routeClass:[RKHuman class] toResourcePath:@"/human" forMethod:RKRequestMethodPOST];
  // Get a serialization mapping - we're going to need this to get the requests out the door
  RKManagedObjectMapping *serializationMapping = [RKManagedObjectMapping mappingForClass:[RKHuman class]
                                                                    inManagedObjectStore:self.store];
  
  // Most of these test methods use this mapping - the test will need to switch explicitly otherwise
  [self.manager.mappingProvider setMapping:self.transparentSyncMapping forKeyPath:@"/human"];
  [self.manager.mappingProvider setSerializationMapping:serializationMapping forClass:[RKHuman class]];
  self.manager.objectStore = self.store;
  
  // Wow, look at that - we have 2 requests (a pull & a push)
  numRequests = [NSNumber numberWithUnsignedInteger:self.manager.requestQueue.loadingCount];
  assertThat(numRequests,equalToUnsignedInt(2));
}

- (void)testRequestQueueExecutesSerially {
  // TODO:
  // In proxy strategy, we just want to send the requests one by one, just as they would have happened otherwise.
  // In batch strategy, we may want to do some clever batching, etc., but that doesn't change the fact that there
  // may be some really nasty issues if 2 related are changed simultaneously (at the moment we have no way of
  // understanding the relationships between Core Data objects)
  // To avoid all hell breaking loose, it's probably better to limit to 1 request a time (whether that request is a
  // single object or a complex collection, though, is up to the Sync Manager).
}

@end