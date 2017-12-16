//
//  RegisterClient.h
//  AzurePushTest
//
//  Created by Для разработки on 10.12.2017.
//  Copyright © 2017 Dvok. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RegisterClient : NSObject

-(void) registerWithDeviceToken:(NSData*)token
                  installationId:(NSString*) installationId
                           tags:(NSSet*)tags
                  andCompletion:(void(^)(NSError*))completion;

-(instancetype) init;

-(NSString*) retrieveOrGenerateInstallationId;

@end
