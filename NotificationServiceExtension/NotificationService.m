//
//  NotificationService.m
//  NotificationServiceExtension
//
//  Created by Для разработки on 23.12.2017.
//  Copyright © 2017 Dvok. All rights reserved.
//

#import "NotificationService.h"

@interface NotificationService ()

@property (nonatomic, strong) void (^contentHandler)(UNNotificationContent *contentToDeliver);
@property (nonatomic, strong) UNMutableNotificationContent *bestAttemptContent;

@property (nonatomic, strong) NSURLSessionDownloadTask *downloadTask;

@end

@implementation NotificationService

- (void)didReceiveNotificationRequest:(UNNotificationRequest *)request withContentHandler:(void (^)(UNNotificationContent * _Nonnull))contentHandler {
    self.contentHandler = contentHandler;
    self.bestAttemptContent = [request.content mutableCopy];
    
    // Modify the notification content here...
    [self handleRichNotificationAttachements:self.bestAttemptContent withResponse:^(UNMutableNotificationContent * _Nullable content) {
        self.bestAttemptContent = content;
        self.contentHandler(self.bestAttemptContent);
    }];
}

- (void)serviceExtensionTimeWillExpire {
    // Called just before the extension will be terminated by the system.
    // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
    [self.downloadTask cancel];
    self.contentHandler(self.bestAttemptContent);
}

- (void)handleRichNotificationAttachements:(UNMutableNotificationContent *)originalContent withResponse:(nullable void(^)(UNMutableNotificationContent *__nullable modifiedContent))block  {
    
    NSString *imageURL = originalContent.userInfo[@"aps"][@"imageUrl"];

    NSURL *attachmentURL = nil;
    if (![imageURL isKindOfClass:[NSNull class]]) {
        attachmentURL = [NSURL URLWithString:imageURL];
    }
    else {
        block(originalContent); //Nothing to add to the push, return early.
        return;
    }
    
    NSURLSession *session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]];
    self.downloadTask = [session downloadTaskWithURL:attachmentURL completionHandler:^(NSURL *fileLocation, NSURLResponse *response, NSError *error) {
        if (error != nil) {
            block(originalContent); //Nothing to add to the push, return early.
            return;
        }
        else {
            NSFileManager *fileManager = [NSFileManager defaultManager];
            NSString *fileSuffix = attachmentURL.lastPathComponent;
            
            NSURL *typedAttachmentURL = [NSURL fileURLWithPath:[(NSString *_Nonnull)fileLocation.path stringByAppendingString:fileSuffix]];
            [fileManager moveItemAtURL:fileLocation toURL:typedAttachmentURL error:&error];
            
            NSError *attachError = nil;
            UNNotificationAttachment *attachment = [UNNotificationAttachment attachmentWithIdentifier:@"" URL:typedAttachmentURL options:nil error:&attachError];
            
            if (attachment == nil) {
                block(originalContent); //Nothing to add to the push, return early.
                return;
            }
            
            UNMutableNotificationContent *modifiedContent = originalContent.mutableCopy;
            [modifiedContent setAttachments:[NSArray arrayWithObject:attachment]];
            block(modifiedContent);
        }
    }];
    [self.downloadTask resume];
}

@end
