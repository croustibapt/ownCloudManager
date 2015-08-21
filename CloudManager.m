//
//  CloudManager.m
//  libfindit
//
//  Created by dev_iphone on 06/03/14.
//  Copyright (c) 2014 Level-App. All rights reserved.
//

#import "CloudManager.h"

static CloudManager * s_cloudManagerInstance = nil;

#import "OCFileDto.h"
#import "Constants.h"

@implementation CloudItem

@synthesize isDirectory;
@synthesize remotePath = m_remotePath;
@synthesize localPath = m_localPath;
@synthesize remoteCreationDate = m_remoteCreationDate;

- (id)initWithDirectory:(Boolean)aIsDirectory andRemotePath:(NSString *)aRemotePath andLocalPath:(NSString *)aLocalPath andRemoteCreationDate:(NSDate *)aRemoteCreationDate {
    self = [super init];
    if (self) {
        [self setIsDirectory:aIsDirectory];
        [self setRemotePath:aRemotePath];
        [self setLocalPath:aLocalPath];
        [self setRemoteCreationDate:aRemoteCreationDate];
    }
    return self;
}

+ (CloudItem *)CloudItemWithDirectory:(Boolean)aIsDirectory andRemotePath:(NSString *)aRemotePath andLocalPath:(NSString *)aLocalPath andRemoteCreationDate:(NSDate *)aRemoteCreationDate {
    CloudItem * item = [[CloudItem alloc] initWithDirectory:aIsDirectory andRemotePath:aRemotePath andLocalPath:aLocalPath andRemoteCreationDate:aRemoteCreationDate];
    return item;
}

@end

@implementation CloudManager

@synthesize communication = m_communication;
@synthesize folders = m_folders;
@synthesize currentFolderPath = m_currentFolderPath;
@synthesize downloadOperation = m_downloadOperation;
@synthesize delegate;
@synthesize isSynced = m_isSynced;

+ (CloudManager *)instance; {
	if (s_cloudManagerInstance == nil) {
		s_cloudManagerInstance = [[CloudManager alloc] init];
	}
    
	return s_cloudManagerInstance;
}

- (id)init {
    self = [super init];
    if (self) {
        m_communication = [[OCCommunication alloc] init];
        m_newFolders = [[NSMutableArray alloc] init];
        m_updateFiles = [[NSMutableArray alloc] init];
        m_folders = [[NSMutableArray alloc] init];

        //Cloud path check
        [self checkCloudPath];
        
        //Connect
        [self connectWithUser:CLOUD_USERNAME andPassword:CLOUD_PASSWORD];
    }
    return self;
}

#pragma mark - Paths

+ (NSString *)cloudPath {
    NSString * documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString * cloudPath = [NSString stringWithFormat:@"%@/Caches/cloud", documentsDirectory];
    
    return cloudPath;
}

+ (NSString *)levelsPath {
    return [NSString stringWithFormat:@"%@/%@", [CloudManager cloudPath], LEVELS_DIRECTORY_NAME];
}

+ (NSString *)getLevelPath:(int)levelId {
    return [NSString stringWithFormat:@"%@/%@%d.json", [CloudManager levelsPath], LEVEL_PREFIX, levelId];
}

#pragma mark - Engine

- (void)synchronize:(id<PCloudDelegate>)aDelegate {
    [self setDelegate:aDelegate];
    m_errorOccured = NO;
    
    [m_newFolders removeAllObjects];
    [m_updateFiles removeAllObjects];
    [m_folders removeAllObjects];
    
    m_currentNbDownloadFiles = 0;
    
    [m_folders addObject:CLOUD_REMOTE_ROOT_PATH];
    
    [self readFolders];
}

- (void)checkCloudPath {
    NSFileManager * fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:[CloudManager cloudPath]]) {
        [fm createDirectoryAtPath:[CloudManager cloudPath] withIntermediateDirectories:NO attributes:nil error:nil];
    }
}

- (void)connectWithUser:(NSString *)user andPassword:(NSString *)password {
    [m_communication setCredentialsWithUser:user andPassword:password];
}

- (CloudItem *)isNewOrUpdated:(OCFileDto *)file {
    CloudItem * returnItem = nil;
    
    NSString * fileName = [file.fileName stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];

    NSString * remotePath = [NSString stringWithFormat:@"%@%@%@", CLOUD_REMOTE_SERVICE_URL, file.filePath, fileName];
    NSString * localPath = [remotePath stringByReplacingOccurrencesOfString:CLOUD_REMOTE_ROOT_PATH withString:[CloudManager cloudPath]];
    
    NSFileManager * fm = [NSFileManager defaultManager];
    
    BOOL isDirectory = NO;
    Boolean fileExists = [fm fileExistsAtPath:localPath isDirectory:&isDirectory];
    NSDate * remoteDate = [NSDate dateWithTimeIntervalSince1970:file.date];
    long remoteSize = file.size;

    if (!fileExists) {
        returnItem = [CloudItem CloudItemWithDirectory:file.isDirectory andRemotePath:remotePath andLocalPath:localPath andRemoteCreationDate:remoteDate];
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

        //Check creation dates
        if ((interval > 0) || (localSize != remoteSize)) {
            returnItem = [CloudItem CloudItemWithDirectory:isDirectory andRemotePath:remotePath andLocalPath:localPath andRemoteCreationDate:remoteDate];
        }
    }
    
    return returnItem;
}

- (void)readFolder:(NSString *)path {
    //Remove escapes
    path = [path stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    [m_communication readFolder:path onCommunication:m_communication successRequest:^(NSHTTPURLResponse * response, NSArray * items, NSString * redirected) {
        //Success
        NSLog(@"success");
        NSMutableArray * newFolders = [NSMutableArray array];
        
        for (OCFileDto * file in items) {
            //Check parser
            NSLog(@"Item file name: %@, path: %@", file.fileName, file.filePath);
            
            if (file.fileName != nil) {
                //Follow reading
                if (file.isDirectory) {
                    [newFolders addObject:[NSString stringWithFormat:@"%@%@%@", CLOUD_REMOTE_SERVICE_URL, file.filePath, file.fileName]];
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
        [self readFolders];
        
    } failureRequest:^(NSHTTPURLResponse * response, NSError * error) {
        //Request failure
        NSLog(@"Error: %@", error);
        //TODO : error handling
        [self.delegate onCloudInitDoneWithSuccess:NO andError:nil andNbFiles:-1];
    }];
}

- (void)createNewDirectories {
    NSFileManager * fm = [NSFileManager defaultManager];
    
    for (CloudItem * item in m_newFolders) {
        [fm createDirectoryAtPath:item.localPath withIntermediateDirectories:NO attributes:nil error:nil];
    }
}

- (void)onDownloadFileError {
    [self.downloadOperation cancel];
//    [self.delegate onCloudSyncDoneWithSuccess:NO andError:nil];
    m_errorOccured = YES;
    
    //Remove failed file
    [m_updateFiles removeObjectAtIndex:0];
    [self downloadFiles];
}

- (void)downloadFile:(CloudItem *)item {
    self.downloadOperation = [m_communication downloadFile:item.remotePath toDestiny:item.localPath withLIFOSystem:NO onCommunication:m_communication progressDownload:^(NSUInteger bytesRead, long long totalBytesRead, long long totalExpectedBytesRead) {
        //Progress
        NSLog(@"%@", [NSString stringWithFormat:@"Downloading: %lld bytes", totalBytesRead]);
    } successRequest:^(NSHTTPURLResponse * response, NSString * redirectedServer) {
        //Success
//        NSLog(@"LocalFile : %@", localPath);
//        _pathOfDownloadFile = localPath;
//        UIImage *image = [[UIImage alloc]initWithContentsOfFile:localPath];
//        _downloadedImageView.image = image;
//        _progressLabel.text = @"Success";
//        _deleteLocalFile.enabled = YES;
        
        //Change file creation date
        NSFileManager * fm = [NSFileManager defaultManager];
        NSMutableDictionary * localAttributes = [NSMutableDictionary dictionaryWithDictionary:[fm attributesOfItemAtPath:item.localPath error:nil]];
        
        NSDate * remoteDate = item.remoteCreationDate;
        [localAttributes setValue:remoteDate forKey:NSFileCreationDate];
        [fm setAttributes:localAttributes ofItemAtPath:item.localPath error:nil];
        
        m_currentNbDownloadFiles++;
        [self.delegate onCloudSyncWithProgress:m_currentNbDownloadFiles andTotalProgress:m_totalDownloadFiles];

        //Remove downloaded file
        [m_updateFiles removeObjectAtIndex:0];
        [self downloadFiles];
    } failureRequest:^(NSHTTPURLResponse * response, NSError * error) {
        //Request failure
        NSLog(@"error while download a file: %@", error);
        [self onDownloadFileError];
    } shouldExecuteAsBackgroundTaskWithExpirationHandler:^{
        //No background handling wanted
        [self onDownloadFileError];
    }];
}

- (void)downloadFiles {
    if ([m_updateFiles count] > 0) {
        CloudItem * item = [m_updateFiles objectAtIndex:0];
        [self downloadFile:item];
    } else {
        NSLog(@"download finish");
        m_isSynced = YES;
        [self.delegate onCloudSyncDoneWithSuccess:!m_errorOccured andError:nil];
    }
}

- (void)readFolders {
    if ([m_folders count] > 0) {
        NSString * folderPath = [m_folders objectAtIndex:0];
        
        [self setCurrentFolderPath:folderPath];
        [self readFolder:self.currentFolderPath];
    } else {
        NSLog(@"sync finish");
        [self createNewDirectories];
        
        m_totalDownloadFiles = [m_updateFiles count];
        
        [self.delegate onCloudInitDoneWithSuccess:YES andError:nil andNbFiles:m_totalDownloadFiles];
        
        [self downloadFiles];
    }
}

@end
