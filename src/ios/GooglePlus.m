#import "AppDelegate.h"
#import "objc/runtime.h"
#import "GooglePlus.h"

@implementation GooglePlus

- (void)pluginInitialize
{
    NSLog(@"GooglePlus pluginInitizalize");
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleOpenURL:) name:CDVPluginHandleOpenURLNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleOpenURLWithAppSourceAndAnnotation:) name:CDVPluginHandleOpenURLWithAppSourceAndAnnotationNotification object:nil];
}

- (void)handleOpenURL:(NSNotification*)notification
{
    // no need to handle this handler, we dont have an sourceApplication here, which is required by GIDSignIn handleURL
}

- (void)handleOpenURLWithAppSourceAndAnnotation:(NSNotification*)notification
{
    NSMutableDictionary * options = [notification object];

    NSURL* url = options[@"url"];

    NSString* possibleReversedClientId = [url.absoluteString componentsSeparatedByString:@":"].firstObject;

    if ([possibleReversedClientId isEqualToString:self.getreversedClientId] && self.isSigningIn) {
        self.isSigningIn = NO;
        [GIDSignIn.sharedInstance handleURL:url];
    }
}

- (void) isAvailable:(CDVInvokedUrlCommand*)command {
  CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:YES];
  [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

/** Configure GIDSignIn with client IDs from the app plist and command options.
    Returns YES on success, NO if the reversed client ID is missing (sends error to callback). */
- (BOOL) configureSignIn:(CDVInvokedUrlCommand*)command {
    _callbackId = command.callbackId;
    NSDictionary* options = command.arguments[0];
    NSString *reversedClientId = [self getreversedClientId];

    if (reversedClientId == nil) {
        CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:@"Could not find REVERSED_CLIENT_ID url scheme in app .plist"];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:_callbackId];
        return NO;
    }

    NSString *clientId = [self reverseUrlScheme:reversedClientId];
    NSString* serverClientId = options[@"webClientId"];
    BOOL offline = [options[@"offline"] boolValue];

    GIDConfiguration *config = [[GIDConfiguration alloc]
        initWithClientID:clientId
        serverClientID:(serverClientId != nil && offline) ? serverClientId : nil];
    GIDSignIn.sharedInstance.configuration = config;
    return YES;
}

- (void) login:(CDVInvokedUrlCommand*)command {
    if (![self configureSignIn:command]) return;

    NSDictionary* options = command.arguments[0];
    NSString *loginHint = options[@"loginHint"];

    self.isSigningIn = YES;
    [GIDSignIn.sharedInstance signInWithPresentingViewController:self.viewController
                                                           hint:loginHint
                                                     completion:^(GIDSignInResult * _Nullable signInResult,
                                                                  NSError * _Nullable error) {
        [self handleSignInResult:signInResult error:error];
    }];
}

- (void) trySilentLogin:(CDVInvokedUrlCommand*)command {
    if (![self configureSignIn:command]) return;

    [GIDSignIn.sharedInstance restorePreviousSignInWithCompletion:^(GIDGoogleUser * _Nullable user,
                                                                    NSError * _Nullable error) {
        [self handleUser:user serverAuthCode:nil error:error];
    }];
}

- (void)handleSignInResult:(GIDSignInResult *)signInResult error:(NSError *)error {
    if (error || !signInResult) {
        [self handleUser:nil serverAuthCode:nil error:error];
    } else {
        [self handleUser:signInResult.user serverAuthCode:signInResult.serverAuthCode error:nil];
    }
}

- (void)handleUser:(GIDGoogleUser *)user serverAuthCode:(NSString *)serverAuthCode error:(NSError *)error {
    if (error) {
        CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                         messageAsString:error.localizedDescription];
        [self.commandDelegate sendPluginResult:pluginResult callbackId:_callbackId];
        return;
    }

    NSString *email = user.profile.email;
    NSString *idToken = user.idToken.tokenString ?: @"";
    NSString *accessToken = user.accessToken.tokenString ?: @"";
    NSString *refreshToken = user.refreshToken.tokenString ?: @"";
    NSString *userId = user.userID;
    NSURL *imageUrl = [user.profile imageURLWithDimension:120];

    NSDictionary *result = @{
        @"email"          : email ?: [NSNull null],
        @"idToken"        : idToken,
        @"serverAuthCode" : serverAuthCode ?: @"",
        @"accessToken"    : accessToken,
        @"refreshToken"   : refreshToken,
        @"userId"         : userId ?: [NSNull null],
        @"displayName"    : user.profile.name ?: [NSNull null],
        @"givenName"      : user.profile.givenName ?: [NSNull null],
        @"familyName"     : user.profile.familyName ?: [NSNull null],
        @"imageUrl"       : imageUrl ? imageUrl.absoluteString : [NSNull null],
    };

    CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                 messageAsDictionary:result];
    [self.commandDelegate sendPluginResult:pluginResult callbackId:_callbackId];
}

- (NSString*) reverseUrlScheme:(NSString*)scheme {
  NSArray* originalArray = [scheme componentsSeparatedByString:@"."];
  NSArray* reversedArray = [[originalArray reverseObjectEnumerator] allObjects];
  NSString* reversedString = [reversedArray componentsJoinedByString:@"."];
  return reversedString;
}

- (NSString*) getreversedClientId {
  NSArray* URLTypes = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleURLTypes"];

  if (URLTypes != nil) {
    for (NSDictionary* dict in URLTypes) {
      NSString *urlName = dict[@"CFBundleURLName"];
      if ([urlName isEqualToString:@"REVERSED_CLIENT_ID"]) {
        NSArray* URLSchemes = dict[@"CFBundleURLSchemes"];
        if (URLSchemes != nil) {
          return URLSchemes[0];
        }
      }
    }
  }
  return nil;
}

- (void) logout:(CDVInvokedUrlCommand*)command {
  [GIDSignIn.sharedInstance signOut];
  CDVPluginResult * pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"logged out"];
  [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
}

- (void) disconnect:(CDVInvokedUrlCommand*)command {
  [GIDSignIn.sharedInstance disconnectWithCompletion:^(NSError * _Nullable error) {
      if (error) {
          CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                           messageAsString:error.localizedDescription];
          [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
      } else {
          CDVPluginResult *pluginResult = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK
                                                           messageAsString:@"disconnected"];
          [self.commandDelegate sendPluginResult:pluginResult callbackId:command.callbackId];
      }
  }];
}

@end
