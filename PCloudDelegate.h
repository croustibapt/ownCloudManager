//
//  PCloudDelegate.h
//  libfindit
//
//  Created by dev_iphone on 06/03/14.
//  Copyright (c) 2014 Level-App. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol PCloudDelegate <NSObject>

- (void)onCloudInitDoneWithSuccess:(Boolean)success andError:(NSError *)error andNbFiles:(NSInteger)nbFiles;

- (void)onCloudSyncDoneWithSuccess:(Boolean)success andError:(NSError *)error;

- (void)onCloudSyncWithProgress:(NSInteger)progress andTotalProgress:(NSInteger)totalProgress;

@end
