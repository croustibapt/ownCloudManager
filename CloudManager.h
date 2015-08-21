//
//  CloudManager.h
//  libfindit
//
//  Created by dev_iphone on 06/03/14.
//  Copyright (c) 2014 Level-App. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "OCCommunication.h"
#import "PCloudDelegate.h"

@interface CloudItem : NSObject {
    NSString * m_remotePath;
    NSString * m_localPath;
    NSDate * m_remoteCreationDate;
}

@property (nonatomic, readwrite) Boolean isDirectory;

@property (nonatomic, retain) NSString * remotePath;

@property (nonatomic, retain) NSString * localPath;

@property (nonatomic, retain) NSDate * remoteCreationDate;

+ (CloudItem *)CloudItemWithDirectory:(Boolean)isDirectory andRemotePath:(NSString *)remotePath andLocalPath:(NSString *)localPath andRemoteCreationDate:(NSDate *)remoteCreationDate;

@end

@interface CloudManager : NSObject {
    OCCommunication * m_communication;
    NSMutableArray * m_folders;
    NSString * m_currentFolderPath;
    
    NSMutableArray * m_newFolders;
    NSMutableArray * m_updateFiles;
    
    NSOperation * m_downloadOperation;
    NSInteger m_currentNbDownloadFiles;
    NSInteger m_totalDownloadFiles;
    
    Boolean m_isSynced;
    Boolean m_errorOccured;
}

@property (nonatomic, retain) OCCommunication * communication;

@property (nonatomic, retain) NSMutableArray * folders;

@property (nonatomic, retain) NSString * currentFolderPath;

@property (nonatomic, retain) NSOperation * downloadOperation;

@property (assign) id<PCloudDelegate> delegate;

@property (nonatomic, readonly) Boolean isSynced;

+ (CloudManager *)instance;

#pragma mark - Paths

+ (NSString *)levelsPath;

+ (NSString *)getLevelPath:(int)levelId;

#pragma mark - Connect

- (void)connectWithUser:(NSString *)user andPassword:(NSString *)password;

- (void)readFolder:(NSString *)path;

- (void)synchronize:(id<PCloudDelegate>)delegate;

@end
