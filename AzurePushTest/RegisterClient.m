//
//  RegisterClient.m
//  AzurePushTest
//
//  Created by Для разработки on 10.12.2017.
//  Copyright © 2017 Dvok. All rights reserved.
//
// Code mostly taken from https://docs.microsoft.com/en-gb/azure/notification-hubs/notification-hubs-aspnet-backend-ios-apple-apns-notification

#import "RegisterClient.h"

@interface RegisterClient ()

@property (strong, nonatomic) NSURLSession* session;
@property (strong, nonatomic) NSString* endpoint;

-(void) tryToRegisterWithDeviceToken:(NSData*)token tags:(NSSet*)tags retry:(BOOL)retry
                       andCompletion:(void(^)(NSError*))completion;
-(void) retrieveOrRequestRegistrationIdWithDeviceToken:(NSString*)token
                                            completion:(void(^)(NSString*, NSError*))completion;
-(void) upsertRegistrationWithRegistrationId:(NSString*)registrationId deviceToken:(NSString*)token
                                        tags:(NSSet*)tags andCompletion:(void(^)(NSURLResponse*, NSError*))completion;

@end

@implementation RegisterClient

// Globals used by RegisterClient
NSString *const RegistrationIdLocalStorageKey = @"RegistrationId";

-(instancetype) initWithEndpoint:(NSString*)Endpoint
{
    self = [super init];
    if (self) {
        NSURLSessionConfiguration* config = [NSURLSessionConfiguration defaultSessionConfiguration];
        _session = [NSURLSession sessionWithConfiguration:config delegate:nil delegateQueue:nil];
        _endpoint = Endpoint;
    }
    return self;
}

-(void) registerWithDeviceToken:(NSData*)token
                           tags:(NSSet*)tags
                  andCompletion:(void(^)(NSError*))completion
{
    [self tryToRegisterWithDeviceToken:token tags:tags retry:YES andCompletion:completion];
}

-(void) tryToRegisterWithDeviceToken:(NSData*)token
                                tags:(NSSet*)tags
                               retry:(BOOL)retry
                       andCompletion:(void(^)(NSError*))completion
{
    NSSet* tagsSet = tags?tags:[[NSSet alloc] init];
    
    NSString *deviceTokenString = [[token description] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]];
    deviceTokenString = [[deviceTokenString stringByReplacingOccurrencesOfString:@" " withString:@""]
                         uppercaseString];
    
    [self retrieveOrRequestRegistrationIdWithDeviceToken: deviceTokenString
                                              completion:^(NSString* registrationId, NSError *error) {
                                                  NSLog(@"regId: %@", registrationId);
                                                  if (error) {
                                                      completion(error);
                                                      return;
                                                  }
                                                  
                                                  [self upsertRegistrationWithRegistrationId:registrationId deviceToken:deviceTokenString
                                                                                        tags:tagsSet andCompletion:^(NSURLResponse * response, NSError *error) {
                                                                                            if (error) {
                                                                                                completion(error);
                                                                                                return;
                                                                                            }
                                                                                            
                                                                                            NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
                                                                                            if (httpResponse.statusCode == 200) {
                                                                                                completion(nil);
                                                                                            } else if (httpResponse.statusCode == 410 && retry) {
                                                                                                [self tryToRegisterWithDeviceToken:token tags:tags retry:NO andCompletion:completion];
                                                                                            } else {
                                                                                                NSLog(@"Registration error with response status: %ld", (long)httpResponse.statusCode);
                                                                                                
                                                                                                completion([NSError errorWithDomain:@"Registration" code:httpResponse.statusCode
                                                                                                                           userInfo:nil]);
                                                                                            }
                                                                                            
                                                                                        }];
                                              }];
}

-(void) upsertRegistrationWithRegistrationId:(NSString*)registrationId
                                 deviceToken:(NSData*)token
                                        tags:(NSSet*)tags
                               andCompletion:(void(^)(NSURLResponse*, NSError*))completion
{
    NSDictionary* deviceRegistration = @{@"Platform" : @"apns",
                                         @"Handle": token,
                                         @"Tags": [tags allObjects]};
    
    NSData* jsonData = [NSJSONSerialization dataWithJSONObject:deviceRegistration
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:nil];
    
    NSLog(@"JSON registration: %@", [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]);
    
    NSString* endpoint = [NSString stringWithFormat:@"%@/api/register/%@", _endpoint, registrationId];
    NSURL* requestURL = [NSURL URLWithString:endpoint];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:requestURL];
    [request setHTTPMethod:@"PUT"];
    [request setHTTPBody:jsonData];
    NSString* authorizationHeaderValue = [NSString stringWithFormat:@"Basic %@", self.authenticationHeader];
    [request setValue:authorizationHeaderValue forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    
    NSURLSessionDataTask* dataTask = [self.session dataTaskWithRequest:request
                                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
                                      {
                                          if (!error)
                                          {
                                              completion(response, error);
                                          }
                                          else
                                          {
                                              NSLog(@"Error request: %@", error);
                                              completion(nil, error);
                                          }
                                      }];
    [dataTask resume];
}

-(void) retrieveOrRequestRegistrationIdWithDeviceToken:(NSString*)token
                                            completion:(void(^)(NSString*, NSError*))completion
{
    NSString* registrationId = [[NSUserDefaults standardUserDefaults] objectForKey:RegistrationIdLocalStorageKey];
    
    if (registrationId)
    {
        completion(registrationId, nil);
        return;
    }
    
    // request new one & save
    NSURL* requestURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/api/register?handle=%@", _endpoint, token]];
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:requestURL];
    
    [request setHTTPMethod:@"POST"];
    
    NSString* authorizationHeaderValue = [NSString stringWithFormat:@"Basic %@", self.authenticationHeader];
    [request setValue:authorizationHeaderValue forHTTPHeaderField:@"Authorization"];
    
    NSURLSessionDataTask* dataTask = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
                                      {
                                          NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*) response;
                                          if (!error && httpResponse.statusCode == 200)
                                          {
                                              NSString* registrationId = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                                              
                                              // remove quotes
                                              registrationId = [registrationId substringWithRange:NSMakeRange(1, [registrationId length]-2)];
                                              
                                              [[NSUserDefaults standardUserDefaults] setObject:registrationId forKey:RegistrationIdLocalStorageKey];
                                              [[NSUserDefaults standardUserDefaults] synchronize];
                                              
                                              completion(registrationId, nil);
                                          }
                                          else
                                          {
                                              NSLog(@"Error status: %ld, request: %@", (long)httpResponse.statusCode, error);
                                              
                                              if (error){
                                                  completion(nil, error);
                                              }
                                              else {
                                                  completion(nil, [NSError errorWithDomain:@"Registration" code:httpResponse.statusCode userInfo:nil]);
                                              }
                                          }
                                      }];
    [dataTask resume];
}

@end
