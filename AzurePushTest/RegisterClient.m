//
//  RegisterClient.m
//  AzurePushTest
//
//  Created by Для разработки on 10.12.2017.
//  Copyright © 2017 Dvok. All rights reserved.
//
// Code mostly taken from https://docs.microsoft.com/en-gb/azure/notification-hubs/notification-hubs-aspnet-backend-ios-apple-apns-notification

#import "RegisterClient.h"
#import "HubInfo.h"

#import <CommonCrypto/CommonHMAC.h>


@interface RegisterClient ()

@property (strong, nonatomic) NSURLSession* session;

@property (strong, nonatomic) NSString* hubEndpoint;
@property (strong, nonatomic) NSString* hubSasKeyName;
@property (strong, nonatomic) NSString* hubSasKeyValue;

-(void) tryToRegisterWithDeviceToken:(NSData*)token
                      installationId:(NSString*) installationId
                                tags:(NSSet*)tags
                               retry:(BOOL)retry
                       andCompletion:(void(^)(NSError*))completion;


-(void) upsertRegistrationWithInstallationId:(NSString*)installationId
                           deviceTokenString:(NSString*)deviceTokenString
                                        tags:(NSSet*)tags
                               andCompletion:(void(^)(NSURLResponse*, NSError*))completion;

-(void) parseHubConnectionString:(NSString*) connString;

-(NSString *)CF_URLEncodedString:(NSString *)inputString;


@end

@implementation RegisterClient

// Globals used by RegisterClient
NSString *const InstallationIdLocalStorageKey = @"InstallationId";

-(instancetype) init
{
    self = [super init];
    
    if (self) {
        [self parseHubConnectionString:HUBLISTENACCESS];
        _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration]
                                                 delegate:nil
                                            delegateQueue:nil];
        
    }
    
    return self;
}

-(void)parseHubConnectionString:(NSString *)connString{
    NSArray* stringParts = [connString componentsSeparatedByString:@";"];
    if (stringParts.count < 3)
        @throw [NSException exceptionWithName:@"Invalid connection string." reason:@"Expected three parts." userInfo:nil];
    
    NSString* stringPart;
    
    stringPart = [stringParts objectAtIndex:0];
    if ([stringPart hasPrefix:@"Endpoint"]) {
        _hubEndpoint = [NSString stringWithFormat:@"https%@",[stringPart substringFromIndex:11]];
    } else {
        @throw [NSException exceptionWithName:@"Invalid connection string." reason:@"Couldn't parse Endpoint." userInfo:nil];
    }
    
    stringPart = [stringParts objectAtIndex:1];
    if ([stringPart hasPrefix:@"SharedAccessKeyName"]) {
        _hubSasKeyName = [stringPart substringFromIndex:20];
    } else {
        @throw [NSException exceptionWithName:@"Invalid connection string." reason:@"Couldn't parse SharedAccessKeyName." userInfo:nil];
    }
    
    stringPart = [stringParts objectAtIndex:2];
    if ([stringPart hasPrefix:@"SharedAccessKey"]) {
        _hubSasKeyValue = [stringPart substringFromIndex:16];
    } else {
        @throw [NSException exceptionWithName:@"Invalid connection string." reason:@"Couldn't parse SharedAccessKey." userInfo:nil];
    }
    
}

-(void) registerWithDeviceToken:(NSData*)token
                 installationId:(NSString*) installationId
                           tags:(NSSet*)tags
                  andCompletion:(void(^)(NSError*))completion
{
    [self tryToRegisterWithDeviceToken:token
                        installationId:installationId
                                  tags:tags
                                 retry:YES
                         andCompletion:completion];
}

-(void) tryToRegisterWithDeviceToken:(NSData*)token
                      installationId:(NSString*) installationId
                                tags:(NSSet*)tags
                               retry:(BOOL)retry
                       andCompletion:(void(^)(NSError*))completion
{
    NSSet* tagsSet = tags?tags:[[NSSet alloc] init];
    
    NSString *deviceTokenString = [[token description] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]];
    deviceTokenString = [[deviceTokenString stringByReplacingOccurrencesOfString:@" " withString:@""]
                         uppercaseString];
    
    [self upsertRegistrationWithInstallationId:installationId
                             deviceTokenString:deviceTokenString
                                          tags:tagsSet
                                 andCompletion:^(NSURLResponse * response, NSError *error) {
                                     if (error) {
                                         completion(error);
                                         return;
                                     }
                                     
                                     NSHTTPURLResponse* httpResponse = (NSHTTPURLResponse*)response;
                                     if (httpResponse.statusCode == 200) {
                                         completion(nil);
                                     } else if (httpResponse.statusCode == 410 && retry) {
                                         [self tryToRegisterWithDeviceToken:token
                                                             installationId:installationId
                                                                       tags:tags
                                                                      retry:NO
                                                              andCompletion:completion];
                                     } else {
                                         NSLog(@"Registration error with response status: %ld", (long)httpResponse.statusCode);
                                         completion([NSError errorWithDomain:@"Registration" code:httpResponse.statusCode userInfo:nil]);
                                     }
                                 }];
    
}

-(void) upsertRegistrationWithInstallationId:(NSString*)installationId
                           deviceTokenString:(NSString*)deviceTokenString
                                        tags:(NSSet*)tags
                               andCompletion:(void(^)(NSURLResponse*, NSError*))completion
{
    installationId = [installationId lowercaseString];
    
    NSDictionary* deviceRegistration = @{
                                         @"installationId": installationId,
                                         @"platform" : @"apns",
                                         @"pushChannel" : deviceTokenString
                                         };
    
    NSData* jsonData = [NSJSONSerialization dataWithJSONObject:deviceRegistration
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:nil];
    
    NSLog(@"JSON registration: %@", [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding]);
    
    NSURL* requestURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@/installations/%@%@", _hubEndpoint, HUBNAME, installationId, API_VERSION]];
    NSLog(@"%@", requestURL);
    NSString* authorizationToken = [self generateSasToken:[requestURL absoluteString]];
    NSLog(@"%@", authorizationToken);
    
    NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:requestURL];
    [request setHTTPMethod:@"PUT"];
    [request setHTTPBody:jsonData];
    [request setValue:authorizationToken forHTTPHeaderField:@"Authorization"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"2015-01" forHTTPHeaderField:@"x-ms-version"];
    
    NSURLSessionDataTask* dataTask = [_session dataTaskWithRequest:request
                                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *error)
                                      {
                                          NSString* responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                                          NSLog(@"Response data %@", responseString);
                                          
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

//Example code from https://docs.microsoft.com/en-us/azure/notification-hubs/notification-hubs-ios-apple-push-notification-apns-get-started#checking-if-your-app-can-receive-push-notifications to construct a SaS token from the access key to authenticate a request.
-(NSString*) generateSasToken:(NSString*)uri
{
    NSString *targetUri;
    NSString* utf8LowercasedUri = NULL;
    NSString *signature = NULL;
    NSString *token = NULL;
    
    @try
    {
        // Add expiration
        uri = [uri lowercaseString];
        utf8LowercasedUri = [self CF_URLEncodedString:uri];
        targetUri = [utf8LowercasedUri lowercaseString];
        NSTimeInterval expiresOnDate = [[NSDate date] timeIntervalSince1970];
        int expiresInMins = 60*24; // 1 day
        expiresOnDate += expiresInMins * 60;
        UInt64 expires = trunc(expiresOnDate);
        NSString* toSign = [NSString stringWithFormat:@"%@\n%qu", targetUri, expires];
        
        // Get an hmac_sha1 Mac instance and initialize with the signing key
        const char *cKey  = [_hubSasKeyValue cStringUsingEncoding:NSUTF8StringEncoding];
        const char *cData = [toSign cStringUsingEncoding:NSUTF8StringEncoding];
        unsigned char cHMAC[CC_SHA256_DIGEST_LENGTH];
        CCHmac(kCCHmacAlgSHA256, cKey, strlen(cKey), cData, strlen(cData), cHMAC);
        NSData *rawHmac = [[NSData alloc] initWithBytes:cHMAC length:sizeof(cHMAC)];
        signature = [self CF_URLEncodedString:[rawHmac base64EncodedStringWithOptions:0]];
        
        // Construct authorization token string
        token = [NSString stringWithFormat:@"SharedAccessSignature sig=%@&se=%qu&skn=%@&sr=%@",
                 signature, expires,_hubSasKeyName, targetUri];
    }
    @catch (NSException *exception)
    {
        NSLog(@"Error generating SaSToken: %@", [exception reason]);
    }
    @finally
    {
        if (utf8LowercasedUri != NULL)
            CFRelease((CFStringRef)utf8LowercasedUri);
        if (signature != NULL)
            CFRelease((CFStringRef)signature);
    }
    
    return token;
}

-(NSString *)CF_URLEncodedString:(NSString *)inputString
{
    return (__bridge NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (CFStringRef)inputString,
                                                                        NULL, (CFStringRef)@"!*'();:@&=+$,/?%#[]", kCFStringEncodingUTF8);
}

// For testing purposes installation Id is generated randomly.
-(NSString*) retrieveOrGenerateInstallationId
{
    NSString* installationId = [[NSUserDefaults standardUserDefaults] objectForKey:InstallationIdLocalStorageKey];
    
    if (installationId)
    {
        return installationId;
    }
    
    installationId = [[NSUUID UUID] UUIDString];;
    
    [[NSUserDefaults standardUserDefaults] setObject:installationId forKey:InstallationIdLocalStorageKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    return installationId;
}

@end
