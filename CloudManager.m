//
//  CloudManager.m
//  ownCloudManager
//
//  Created by dev_iphone on 06/03/14.
//  Copyright (c) 2014 Level-App. All rights reserved.
//

#import "CloudManager.h"

#import "OCCommunication.h"
#import "OCFileDto.h"

static NSString * const kCloudRemoteServiceUrl = @"https://example.owncloud.com";
static NSString * const kCloudRemoteBaseUrl = @"/owncloud/remote.php/webdav/";
#define kCloudRemoteRootPath [NSString stringWithFormat:@"%@%@", kCloudRemoteServiceUrl, kCloudRemoteBaseUrl]

static NSString * const kCloudUser = @"username";
static NSString * const kCloudPassword = @"password";

static NSString * const kCloudLocalFolder = @"Caches/cloud";
#define kCloudLocalPath [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) \
objectAtIndex:0] stringByAppendingPathComponent:kCloudLocalFolder]

@interface CloudItem () {
    Boolean m_isDirectory;
    NSString * m_remotePath;
    NSString * m_localPath;
    NSDate * m_remoteCreationDate;
}

@end

@implementation CloudItem

@synthesize isDirectory = m_isDirectory;
@synthesize remotePath = m_remotePath;
@synthesize localPath = m_localPath;
@synthesize remoteCreationDate = m_remoteCreationDate;

- (instancetype)initWithRemotePath:(NSString *)remotePath
                         localPath:(NSString *)localPath
                remoteCreationDate:(NSDate *)remoteCreationDate
                       isDirectory:(Boolean)isDirectory {
    
    self = [super init];
    
    if (self) {
        m_isDirectory = isDirectory;
        m_remotePath = remotePath;
        m_localPath = localPath;
        m_remoteCreationDate = remoteCreationDate;
    }
    
    return self;
}


+ (CloudItem *)cloudItemWithRemotePath:(NSString *)remotePath
                             localPath:(NSString *)localPath
                    remoteCreationDate:(NSDate *)remoteCreationDate
                           isDirectory:(Boolean)isDirectory {
    
    CloudItem * item = [[CloudItem alloc] initWithRemotePath:remotePath
                                                   localPath:localPath
                                          remoteCreationDate:remoteCreationDate
                                                 isDirectory:isDirectory];
    return item;
}

@end

@interface CloudManager () {
    //ownCloud
    OCCommunication * m_communication;
    Boolean m_isSynced;
    Boolean m_errorOccured;
    
    //Folders
    NSMutableArray * m_folders;
    
    //Update
    NSMutableArray * m_newFolders;
    NSMutableArray * m_updateFiles;
    
    NSOperation * m_downloadOperation;
    NSInteger m_currentNbDownloadFiles;
    NSInteger m_totalDownloadFiles;
}

@end

@implementation CloudManager

@synthesize isSynced = m_isSynced;

#pragma mark - Init

+ (instancetype)sharedInstance; {
    static id s_cloudManagerInstance = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        s_cloudManagerInstance = [[self alloc] init];
    });
    
    return s_cloudManagerInstance;
}


- (instancetype)init {
    self = [super init];
    
    if (self) {
        m_communication = [[OCCommunication alloc] init];
        m_newFolders = [[NSMutableArray alloc] init];
        m_updateFiles = [[NSMutableArray alloc] init];
        m_folders = [[NSMutableArray alloc] init];
        
        //Create cloud local path if needed
        [self checkCloudPath];
        
        //Initialize credentials
        [m_communication setCredentialsWithUser:kCloudUser andPassword:kCloudPassword];
        [m_communication setCredentialsWithApiKey:kCloudAPIKey andMode:kCloudISMode];
    }
    
    return self;
}


#pragma mark - Paths

- (void)checkCloudPath {
    NSFileManager * fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:kCloudLocalPath]) {
        [fm createDirectoryAtPath:kCloudLocalPath withIntermediateDirectories:NO attributes:nil error:nil];
    }
}


- (void)createNewFolders:(NSArray *)folders {
    NSFileManager * fm = [NSFileManager defaultManager];
    for (CloudItem * item in folders) {
        [fm createDirectoryAtPath:item.localPath withIntermediateDirectories:NO attributes:nil error:nil];
    }
}


#pragma mark - Synchronize

- (void)synchronize:(id<PCloudDelegate>)delegate {
    [self setDelegate:delegate];
    
    //Reset
    m_errorOccured = NO;
    
    [m_newFolders removeAllObjects];
    [m_updateFiles removeAllObjects];
    [m_folders removeAllObjects];
    
    m_currentNbDownloadFiles = 0;
    
    //Start from root folder
    [m_folders addObject:kCloudRemoteRootPath];
    [self readFolders:m_folders];
}


#pragma mark - Read

- (void)readFolders:(NSArray *)folders {
    //Browse folders
    if ([folders count] > 0) {
        NSString * folderPath = [folders objectAtIndex:0];
        [self readFolder:folderPath];
        
    } else {
        //Browsing is over
        NSLog(@"sync finish");
        
        //Create new folders
        if ([m_newFolders count] > 0) {
            [self createNewFolders:m_newFolders];
        }
        
        m_totalDownloadFiles = [m_updateFiles count];
        
        //Notify delegate
        [self.delegate onCloudInitDoneWithSuccess:YES andError:nil andNbFiles:m_totalDownloadFiles];
        
        //Start download
        [self downloadFiles:m_updateFiles];
    }
}


- (void)readFolder:(NSString *)path {
    //Remove escapes
    path = [path stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    [m_communication readFolder:path
                onCommunication:m_communication
                 successRequest:^(NSHTTPURLResponse * response, NSArray * items, NSString * redirected) {
                     //Success
                     NSLog(@"success");
                     NSMutableArray * newFolders = [NSMutableArray array];
                     
                     for (OCFileDto * file in items) {
                         //Check parser
                         NSLog(@"Item file name: %@, path: %@", file.fileName, file.filePath);
                         
                         if (file.fileName != nil) {
                             //Follow reading
                             if (file.isDirectory) {
                                 [newFolders addObject:[NSString stringWithFormat:@"%@%@%@", kCloudRemoteServiceUrl,
                                                        file.filePath, file.fileName]];
                             }
                             
                             //Update
                             CloudItem * updateItem = [self isNewOrUpdated:file];
                             if (updateItem != nil) {
                                 if (updateItem.isDirectory) {
                                     [m_newFolders addObject:updateItem];
                                     
                                 } else {
                                     [m_updateFiles addObject:updateItem];
                                 }
                             }
                         }
                     }
                     
                     //Add new folders
                     NSLog(@"found %ld new folders", (unsigned long)[newFolders count]);
                     [m_folders addObjectsFromArray:newFolders];
                     
                     //Remove one read
                     [m_folders removeObjectAtIndex:0];
                     [self readFolders:m_folders];
                     
                 } failureRequest:^(NSHTTPURLResponse * response, NSError * error) {
                     //Request failure
                     NSLog(@"Error: %@", error);
                     
                     //Notify delegate
                     [self.delegate onCloudInitDoneWithSuccess:NO andError:error andNbFiles:-1];
                 }];
}


- (CloudItem *)isNewOrUpdated:(OCFileDto *)file {
    CloudItem * returnItem = nil;
    
    NSString * fileName = [file.fileName stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString * remotePath = [NSString stringWithFormat:@"%@%@%@", kCloudRemoteServiceUrl, file.filePath, fileName];
    NSString * localPath = [remotePath stringByReplacingOccurrencesOfString:kCloudRemoteRootPath
                                                                 withString:kCloudLocalPath];
    
    NSFileManager * fm = [NSFileManager defaultManager];
    
    BOOL isDirectory = NO;
    Boolean fileExists = [fm fileExistsAtPath:localPath isDirectory:&isDirectory];
    NSDate * remoteDate = [NSDate dateWithTimeIntervalSince1970:file.date];
    long remoteSize = file.size;
    
    if (!fileExists) {
        returnItem = [CloudItem cloudItemWithRemotePath:remotePath
                                              localPath:localPath
                                     remoteCreationDate:remoteDate
                                            isDirectory:file.isDirectory];
        
    } else if (!file.isDirectory) {
        NSTimeInterval interval = 0;
        
        //Check update
        NSDate * localDate = nil;
        long localSize = 0;
        
        NSDictionary * localAttributes = [fm attributesOfItemAtPath:localPath error:nil];
        if (localAttributes != nil) {
            localDate = (NSDate *)[localAttributes objectForKey:NSFileCreationDate];
            localSize = [(NSNumber *)[localAttributes objectForKey:NSFileSize] longValue];
        }
        
        if (localDate != nil) {
            interval = [remoteDate timeIntervalSinceDate:localDate];
        }
        
        //Check creation dates and size to update if needed
        if (interval > 0 || localSize != remoteSize) {
            returnItem = [CloudItem cloudItemWithRemotePath:remotePath
                                                  localPath:localPath
                                         remoteCreationDate:remoteDate
                                                isDirectory:isDirectory];
        }
    }
    
    return returnItem;
}


#pragma mark - Download

- (void)downloadFile:(CloudItem *)item {
    m_downloadOperation = [m_communication downloadFile:item.remotePath
                                              toDestiny:item.localPath
                                         withLIFOSystem:NO
                                        onCommunication:m_communication
                                       progressDownload:
                           ^(NSUInteger bytesRead, long long totalBytesRead, long long totalExpectedBytesRead) {
                               //Progress
                               NSLog(@"%@", [NSString stringWithFormat:@"Downloading: %lld bytes", totalBytesRead]);
                               
                           } successRequest:
                           ^(NSHTTPURLResponse * response, NSString * redirectedServer) {
                               //Change file creation date
                               NSFileManager * fm = [NSFileManager defaultManager];
                               NSMutableDictionary * localAttributes = [NSMutableDictionary dictionaryWithDictionary:
                                                                        [fm attributesOfItemAtPath:item.localPath
                                                                                             error:nil]];
                               
                               [localAttributes setValue:item.remoteCreationDate forKey:NSFileCreationDate];
                               [fm setAttributes:localAttributes ofItemAtPath:item.localPath error:nil];
                               
                               //Notify delegate
                               m_currentNbDownloadFiles++;
                               [self.delegate onCloudSyncWithProgress:m_currentNbDownloadFiles
                                                     andTotalProgress:m_totalDownloadFiles];
                               
                               //Remove downloaded file
                               [m_updateFiles removeObjectAtIndex:0];
                               [self downloadFiles:m_updateFiles];
                               
                           } failureRequest:^(NSHTTPURLResponse * response, NSError * error) {
                               //Request failure
                               NSLog(@"error while download a file: %@", error);
                               [self onDownloadFileError];
                               
                           } shouldExecuteAsBackgroundTaskWithExpirationHandler:^{
                               //No background handling wanted
                               [self onDownloadFileError];
                           }];
}


- (void)downloadFiles:(NSArray *)files {
    //Download new file
    if ([files count] > 0) {
        CloudItem * item = [files objectAtIndex:0];
        [self downloadFile:item];
        
    } else {
        NSLog(@"download finish");
        m_isSynced = YES;
        
        //Notify delegate
        [self.delegate onCloudSyncDoneWithSuccess:!m_errorOccured andError:nil];
    }
}


- (void)onDownloadFileError {
    //Cancel operation
    [m_downloadOperation cancel];
    
    m_errorOccured = YES;
    
    //Remove failed file
    [m_updateFiles removeObjectAtIndex:0];
    
    //Continue download
    [self downloadFiles:m_updateFiles];
}

@end
