//
//  CloudManager.h
//  ownCloudManager
//
//  Created by dev_iphone on 06/03/14.
//  Copyright (c) 2014 Level-App. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CloudItem : NSObject

@property (nonatomic, assign, readonly) Boolean isDirectory;

@property (nonatomic, strong, readonly) NSString * remotePath;

@property (nonatomic, strong, readonly) NSString * localPath;

@property (nonatomic, strong, readonly) NSDate * remoteCreationDate;

+ (CloudItem *)cloudItemWithRemotePath:(NSString *)remotePath
                          localPath:(NSString *)localPath
                 remoteCreationDate:(NSDate *)remoteCreationDate
                        isDirectory:(Boolean)isDirectory;

@end

@protocol PCloudDelegate <NSObject>

- (void)onCloudInitDoneWithSuccess:(Boolean)success andError:(NSError *)error andNbFiles:(NSInteger)nbFiles;

- (void)onCloudSyncDoneWithSuccess:(Boolean)success andError:(NSError *)error;

- (void)onCloudSyncWithProgress:(NSInteger)progress andTotalProgress:(NSInteger)totalProgress;

@end

@interface CloudManager : NSObject

@property (nonatomic, weak) id<PCloudDelegate> delegate;

@property (nonatomic, assign, readonly) Boolean isSynced;

+ (instancetype)sharedInstance;

#pragma mark - Synchronize

- (void)synchronize:(id<PCloudDelegate>)delegate;

@end
