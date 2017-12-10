//
//  AppDelegate.m
//  AzurePushTest
//
//  Created by Для разработки on 10.12.2017.
//  Copyright © 2017 Dvok. All rights reserved.
//

#import "AppDelegate.h"
#import "RegisterClient.h"

@interface AppDelegate ()

@property (strong, nonatomic) NSData* deviceToken;
@property (strong, nonatomic) RegisterClient* registerClient;

// create the Authorization header to perform Basic authentication with your app back-end
-(void) createAndSetAuthenticationHeaderWithUsername:(NSString*)username
                                         AndPassword:(NSString*)password;

@end

@implementation AppDelegate



- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    
    UIUserNotificationSettings *settings = [UIUserNotificationSettings
                                            settingsForTypes:UIUserNotificationTypeSound |
                                            UIUserNotificationTypeAlert |
                                            UIUserNotificationTypeBadge categories:nil];
    
    [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
    [[UIApplication sharedApplication] registerForRemoteNotifications];
    
    return YES;
}


- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *) deviceToken {
    
    [self.registerClient registerWithDeviceToken:deviceToken tags:nil andCompletion:^(NSError* error) {
        if (error != nil) {
            NSLog(@"Error registering for notifications: %@", error);
        }
        else {
            NSLog(@"%@", deviceToken);
            [self MessageBox:@"Registration Status" message:@"Registered"];
        }
    }];
}
     


-(void)MessageBox:(NSString *)title message:(NSString *)messageText
{
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:title message:messageText delegate:self
                                          cancelButtonTitle:@"OK" otherButtonTitles: nil];
    [alert show];
}

- (void)application:(UIApplication *)application didReceiveRemoteNotification: (NSDictionary *)userInfo {
    NSLog(@"%@", userInfo);
    [self MessageBox:@"Notification" message:[[userInfo objectForKey:@"aps"] valueForKey:@"alert"]];
}

-(void) createAndSetAuthenticationHeaderWithUsername:(NSString*)username
                                         AndPassword:(NSString*)password;
{
    NSString* headerValue = [NSString stringWithFormat:@"%@:%@", username, password];
    
    NSData* encodedData = [[headerValue dataUsingEncoding:NSUTF8StringEncoding] base64EncodedDataWithOptions:NSDataBase64EncodingEndLineWithCarriageReturn];
    
    self.registerClient.authenticationHeader = [[NSString alloc] initWithData:encodedData
                                                                     encoding:NSUTF8StringEncoding];
}


@end
