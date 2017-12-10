//
//  RegisterClient.h
//  AzurePushTest
//
//  Created by Для разработки on 10.12.2017.
//  Copyright © 2017 Dvok. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface RegisterClient : NSObject

@property (strong, nonatomic) NSString* authenticationHeader;

-(void) registerWithDeviceToken:(NSData*)token tags:(NSSet*)tags
                  andCompletion:(void(^)(NSError*))completion;

-(instancetype) initWithEndpoint:(NSString*)Endpoint;

@end
