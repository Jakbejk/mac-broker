#import "MacBrokerBridge.h"
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>
#import <CommonCrypto/CommonDigest.h>
#include <wchar.h>

// ============================================================================
// Internal Data Structures
// ============================================================================

typedef struct {
    LogCallback callback;
    int32_t callbackData;
} LogCallbackContext;

typedef struct {
    AuthResultCallback callback;
    int32_t callbackData;
} AuthResultContext;

typedef struct {
    ReadAccountResultCallback callback;
    int32_t callbackData;
} ReadAccountResultContext;

typedef struct {
    SignOutResultCallback callback;
    int32_t callbackData;
} SignOutResultContext;

// ============================================================================
// Global State Management
// ============================================================================

static MSALMacErrorHandle gLastError = {0};
static LogCallbackContext *gLogCallbackContext = NULL;
static NSMutableDictionary *gAsyncOperations = nil;
static NSMutableDictionary *gAuthParameters = nil;
static NSMutableDictionary *gAccounts = nil;
static NSMutableDictionary *gAuthResults = nil;
static NSMutableDictionary *gReadAccountResults = nil;
static NSMutableDictionary *gSignOutResults = nil;
static NSMutableDictionary *gErrors = nil;
static dispatch_queue_t gBrokerQueue = nil;
static NSObject *gSyncLock = nil;
static int64_t gHandleCounter = 1000;
static NSString *const kMockJwt =
    @"eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6Ik1vY2sgVXNlciIsImlhdCI6MTUxNjIzOTAyMn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c";
static NSString *const kMockClientInfo =
    @"eyJ1aWQiOiIxMjM0NTY3ODkwIiwidXRpZCI6InRlc3QtdGVuYW50In0";
static NSSet<NSString *> *kReservedAuthParameterKeys = nil;

static void ensureRuntimeStateInitialized(void);
static NSDictionary *performInteractiveMicrosoftSignIn(NSDictionary *authParams, NSString *accountHint, NSString *correlationId);

@interface MSALInteractiveAuthWindowController : NSWindowController <WKNavigationDelegate, NSWindowDelegate>
@property(nonatomic, retain) WKWebView *webView;
@property(nonatomic, retain) NSString *redirectUri;
@property(nonatomic, retain) NSString *expectedState;
@property(nonatomic, retain) NSDictionary *result;
@property(nonatomic, assign) BOOL finished;
- (instancetype)initWithAuthorizeURL:(NSURL *)authorizeURL
                         redirectUri:(NSString *)redirectUri
                       expectedState:(NSString *)expectedState;
- (NSDictionary *)runModalAuthWindow;
@end

// ============================================================================
// Helper Functions
// ============================================================================

static int64_t generateHandle(void) {
    ensureRuntimeStateInitialized();
    @synchronized(gSyncLock) {
        return gHandleCounter++;
    }
}

static void ensureRuntimeStateInitialized(void) {
    if (gSyncLock == nil) {
        gSyncLock = [[NSObject alloc] init];
    }

    @synchronized(gSyncLock) {
        if (gAsyncOperations == nil) {
            // Use owned instances for global state to avoid lifetime issues without ARC.
            gAsyncOperations = [[NSMutableDictionary alloc] init];
            gAuthParameters = [[NSMutableDictionary alloc] init];
            gAccounts = [[NSMutableDictionary alloc] init];
            gAuthResults = [[NSMutableDictionary alloc] init];
            gReadAccountResults = [[NSMutableDictionary alloc] init];
            gSignOutResults = [[NSMutableDictionary alloc] init];
            gErrors = [[NSMutableDictionary alloc] init];
            gBrokerQueue = dispatch_queue_create("com.microsoft.msal.broker", DISPATCH_QUEUE_SERIAL);
            kReservedAuthParameterKeys = [[NSSet alloc] initWithArray:@[
                @"clientId",
                @"authority",
                @"scopes",
                @"redirectUri",
                @"claims",
                @"popParams"
            ]];
        } else if (gErrors == nil) {
            gErrors = [[NSMutableDictionary alloc] init];
        }
    }
}

static void logMessage(int32_t level, const wchar_t *message) {
    if (gLogCallbackContext != NULL && gLogCallbackContext->callback != NULL) {
        gLogCallbackContext->callback(level, message, gLogCallbackContext->callbackData);
    }
}

static void setError(MSALMacResponseStatus status, int64_t errorCode, int32_t tag, const char *context) {
    ensureRuntimeStateInitialized();

    @synchronized(gSyncLock) {
        gLastError.status = status;
        
        // Store detailed error information
        NSMutableDictionary *errorDetails = [NSMutableDictionary dictionary];
        errorDetails[@"status"] = @(status);
        errorDetails[@"code"] = @(errorCode);
        errorDetails[@"tag"] = @(tag);
        if (context) {
            errorDetails[@"context"] = [NSString stringWithUTF8String:context];
        }
        errorDetails[@"timestamp"] = [NSDate date];
        
        int64_t errorHandle = generateHandle();
        gErrors[@(errorHandle)] = errorDetails;
    }
}

static NSString *wstringToNSString(const wchar_t *wstr) {
    if (wstr == NULL) {
        return @"";
    }
    return [[NSString alloc] initWithBytes:wstr 
                                   length:wcslen(wstr) * sizeof(wchar_t)
                                 encoding:NSUTF32LittleEndianStringEncoding];
}

static wchar_t *nsstringToWstring(NSString *str) {
    if (str == nil || [str length] == 0) {
        wchar_t *empty = malloc(sizeof(wchar_t));
        empty[0] = L'\0';
        return empty;
    }
    
    NSData *data = [str dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
    wchar_t *wstr = malloc([data length] + sizeof(wchar_t));
    [data getBytes:wstr length:[data length]];
    wstr[[data length] / sizeof(wchar_t)] = L'\0';
    return wstr;
}

static NSString *stringValue(id obj) {
    if (obj == nil || obj == [NSNull null]) {
        return @"";
    }
    if ([obj isKindOfClass:[NSString class]]) {
        return (NSString *)obj;
    }
    if ([obj respondsToSelector:@selector(stringValue)]) {
        return [obj stringValue];
    }
    return [obj description];
}

static NSString *normalizeAuthority(NSString *authority) {
    NSString *value = stringValue(authority);
    while ([value hasSuffix:@"/"]) {
        value = [value substringToIndex:value.length - 1];
    }
    return value;
}

static NSString *base64UrlEncode(NSData *data) {
    NSString *base64 = [data base64EncodedStringWithOptions:0];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    return [base64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
}

static NSData *base64UrlDecode(NSString *value) {
    NSString *base64 = [value stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    base64 = [base64 stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    NSUInteger remainder = base64.length % 4;
    if (remainder > 0) {
        base64 = [base64 stringByPaddingToLength:(base64.length + 4 - remainder)
                                       withString:@"="
                                  startingAtIndex:0];
    }
    return [[NSData alloc] initWithBase64EncodedString:base64 options:0];
}

static NSString *randomBase64UrlString(NSUInteger byteCount) {
    NSMutableData *randomData = [NSMutableData dataWithLength:byteCount];
    int randomStatus = SecRandomCopyBytes(kSecRandomDefault, byteCount, randomData.mutableBytes);
    if (randomStatus != errSecSuccess) {
        return nil;
    }
    return base64UrlEncode(randomData);
}

static NSString *sha256Base64Url(NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (data == nil) {
        return nil;
    }

    uint8_t digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSData *digestData = [NSData dataWithBytes:digest length:CC_SHA256_DIGEST_LENGTH];
    return base64UrlEncode(digestData);
}

static NSDictionary *parseParameters(NSString *rawParameters) {
    NSMutableDictionary *parsed = [NSMutableDictionary dictionary];
    if (rawParameters.length == 0) {
        return parsed;
    }

    NSArray *pairs = [rawParameters componentsSeparatedByString:@"&"];
    for (NSString *pair in pairs) {
        NSRange separatorRange = [pair rangeOfString:@"="];
        if (separatorRange.location == NSNotFound) {
            continue;
        }

        NSString *rawKey = [pair substringToIndex:separatorRange.location];
        NSString *rawValue = [pair substringFromIndex:separatorRange.location + 1];
        NSString *key = [rawKey stringByRemovingPercentEncoding] ?: rawKey;
        NSString *value = [rawValue stringByRemovingPercentEncoding] ?: rawValue;
        parsed[key] = value;
    }
    return parsed;
}

static NSDictionary *extractOAuthResponseParameters(NSURL *url) {
    NSMutableDictionary *combined = [NSMutableDictionary dictionary];
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];

    for (NSURLQueryItem *item in components.queryItems) {
        if (item.name != nil && item.value != nil) {
            combined[item.name] = item.value;
        }
    }

    NSDictionary *fragmentParams = parseParameters(components.fragment ?: @"");
    [combined addEntriesFromDictionary:fragmentParams];

    return combined;
}

static NSDictionary *parseJwtPayload(NSString *jwt) {
    NSArray<NSString *> *parts = [jwt componentsSeparatedByString:@"."];
    if (parts.count < 2) {
        return nil;
    }

    NSData *payloadData = base64UrlDecode(parts[1]);
    if (payloadData == nil) {
        return nil;
    }

    NSError *error = nil;
    id payload = [NSJSONSerialization JSONObjectWithData:payloadData options:0 error:&error];
    if (error != nil || ![payload isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    return (NSDictionary *)payload;
}

static NSString *formUrlEncode(NSString *value) {
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [stringValue(value) stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

static NSDictionary *exchangeCodeForTokens(NSString *authority,
                                           NSString *clientId,
                                           NSString *scope,
                                           NSString *redirectUri,
                                           NSString *code,
                                           NSString *codeVerifier) {
    NSString *tokenEndpoint = [NSString stringWithFormat:@"%@/oauth2/v2.0/token", normalizeAuthority(authority)];
    NSURL *tokenUrl = [NSURL URLWithString:tokenEndpoint];
    if (tokenUrl == nil) {
        return @{
            @"status": @"error",
            @"context": @"Invalid token endpoint URL."
        };
    }

    NSArray<NSString *> *bodyParts = @[
        [NSString stringWithFormat:@"client_id=%@", formUrlEncode(clientId)],
        [NSString stringWithFormat:@"scope=%@", formUrlEncode(scope)],
        @"grant_type=authorization_code",
        [NSString stringWithFormat:@"code=%@", formUrlEncode(code)],
        [NSString stringWithFormat:@"redirect_uri=%@", formUrlEncode(redirectUri)],
        [NSString stringWithFormat:@"code_verifier=%@", formUrlEncode(codeVerifier)]
    ];
    NSString *bodyString = [bodyParts componentsJoinedByString:@"&"];
    NSData *bodyData = [bodyString dataUsingEncoding:NSUTF8StringEncoding];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:tokenUrl];
    request.HTTPMethod = @"POST";
    request.timeoutInterval = 60.0;
    request.HTTPBody = bodyData;
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];

    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *responseData = nil;
    __block NSInteger responseCode = 0;
    __block NSError *requestError = nil;

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                  completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        responseData = data;
        requestError = error;
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            responseCode = ((NSHTTPURLResponse *)response).statusCode;
        }
        dispatch_semaphore_signal(semaphore);
    }];
    [task resume];

    long waitResult = dispatch_semaphore_wait(semaphore, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(90 * NSEC_PER_SEC)));
    if (waitResult != 0) {
        return @{
            @"status": @"error",
            @"context": @"Timed out while exchanging authorization code for tokens."
        };
    }

    if (requestError != nil) {
        return @{
            @"status": @"error",
            @"context": [NSString stringWithFormat:@"Token request failed: %@", requestError.localizedDescription]
        };
    }

    if (responseData == nil || responseData.length == 0) {
        return @{
            @"status": @"error",
            @"context": @"Token response was empty."
        };
    }

    NSError *jsonError = nil;
    id payload = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:&jsonError];
    if (jsonError != nil || ![payload isKindOfClass:[NSDictionary class]]) {
        return @{
            @"status": @"error",
            @"context": @"Token response was not valid JSON."
        };
    }

    NSDictionary *tokenPayload = (NSDictionary *)payload;
    NSString *tokenError = stringValue(tokenPayload[@"error"]);
    if (responseCode >= 400 || tokenError.length > 0) {
        NSString *description = stringValue(tokenPayload[@"error_description"]);
        NSString *context = description.length > 0 ? description : tokenError;
        return @{
            @"status": @"error",
            @"context": [NSString stringWithFormat:@"Token endpoint returned error (%ld): %@", (long)responseCode, context]
        };
    }

    return @{
        @"status": @"success",
        @"payload": tokenPayload
    };
}

static NSDictionary *buildAccountInfo(NSDictionary *tokenPayload, NSString *idToken, NSString *accountHint) {
    NSDictionary *jwtPayload = parseJwtPayload(idToken);
    NSString *preferredUsername = stringValue(jwtPayload[@"preferred_username"]);
    NSString *upn = stringValue(jwtPayload[@"upn"]);
    NSString *email = stringValue(jwtPayload[@"email"]);
    NSString *oid = stringValue(jwtPayload[@"oid"]);
    NSString *tid = stringValue(jwtPayload[@"tid"]);
    NSString *name = stringValue(jwtPayload[@"name"]);

    NSString *accountId = preferredUsername.length > 0 ? preferredUsername :
        (upn.length > 0 ? upn : (email.length > 0 ? email : (stringValue(accountHint).length > 0 ? stringValue(accountHint) : oid)));
    if (accountId.length == 0) {
        accountId = @"unknown-account";
    }

    NSString *clientInfo = stringValue(tokenPayload[@"client_info"]);
    if (clientInfo.length == 0 && oid.length > 0 && tid.length > 0) {
        NSDictionary *fallbackClientInfo = @{
            @"uid": oid,
            @"utid": tid
        };
        NSData *jsonData = [NSJSONSerialization dataWithJSONObject:fallbackClientInfo options:0 error:nil];
        clientInfo = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
    }
    if (clientInfo.length == 0) {
        clientInfo = kMockClientInfo;
    }

    NSString *displayName = name.length > 0 ? name : accountId;
    return @{
        @"accountId": accountId,
        @"displayName": displayName,
        @"clientInfo": clientInfo
    };
}

@implementation MSALInteractiveAuthWindowController

- (instancetype)initWithAuthorizeURL:(NSURL *)authorizeURL
                         redirectUri:(NSString *)redirectUri
                       expectedState:(NSString *)expectedState {
    NSLog(@"[MSAL Broker][AuthWindow] initWithAuthorizeURL started (mainThread=%@, redirectUri=%@, expectedState=%@)",
          [NSThread isMainThread] ? @"YES" : @"NO",
          redirectUri ?: @"",
          expectedState ?: @"");
    NSRect frame = NSMakeRect(0, 0, 520, 700);
    NSUInteger styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable;
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                    styleMask:styleMask
                                                      backing:NSBackingStoreBuffered
                                                        defer:NO];

    self = [super initWithWindow:window];
    if (self) {
        self.redirectUri = redirectUri;
        self.expectedState = expectedState;
        self.finished = NO;

        WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
        self.webView = [[WKWebView alloc] initWithFrame:window.contentView.bounds configuration:configuration];
        self.webView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        self.webView.navigationDelegate = self;
        [window.contentView addSubview:self.webView];
        window.delegate = self;
        window.title = @"Microsoft Sign In";

        NSURLRequest *request = [NSURLRequest requestWithURL:authorizeURL];
        NSLog(@"[MSAL Broker][AuthWindow] loading authorize URL (scheme=%@, host=%@, path=%@)",
              authorizeURL.scheme ?: @"",
              authorizeURL.host ?: @"",
              authorizeURL.path ?: @"");
        [self.webView loadRequest:request];
        NSLog(@"[MSAL Broker][AuthWindow] initWithAuthorizeURL finished");
    } else {
        NSLog(@"[MSAL Broker][AuthWindow] initWithAuthorizeURL failed (self is nil)");
    }

    return self;
}

- (void)finishWithResult:(NSDictionary *)result {
    NSLog(@"[MSAL Broker][AuthWindow] finishWithResult called (alreadyFinished=%@, status=%@)",
          self.finished ? @"YES" : @"NO",
          stringValue(result[@"status"]));
    if (self.finished) {
        NSLog(@"[MSAL Broker][AuthWindow] finishWithResult ignored because controller is already finished");
        return;
    }
    self.finished = YES;
    self.result = result;

    NSLog(@"[MSAL Broker][AuthWindow] stopping modal loop and closing window");
    [NSApp stopModal];
    [self.window orderOut:nil];
    [self.window close];
    NSLog(@"[MSAL Broker][AuthWindow] finishWithResult completed");
}

- (NSDictionary *)runModalAuthWindow {
    NSLog(@"[MSAL Broker][AuthWindow] runModalAuthWindow started (mainThread=%@)",
          [NSThread isMainThread] ? @"YES" : @"NO");
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

    [self.window center];
    [self showWindow:nil];
    [NSApp activateIgnoringOtherApps:YES];
    NSLog(@"[MSAL Broker][AuthWindow] entering modal loop");
    [NSApp runModalForWindow:self.window];
    NSLog(@"[MSAL Broker][AuthWindow] modal loop exited (hasResult=%@)", self.result != nil ? @"YES" : @"NO");

    if (self.result == nil) {
        NSLog(@"[MSAL Broker][AuthWindow] returning cancelled result because no auth result was set");
        return @{
            @"status": @"cancelled",
            @"context": @"User closed the sign-in window."
        };
    }
    NSLog(@"[MSAL Broker][AuthWindow] returning auth result with status=%@", stringValue(self.result[@"status"]));
    return self.result;
}

- (void)windowWillClose:(NSNotification *)notification {
    NSLog(@"[MSAL Broker][AuthWindow] windowWillClose received (finished=%@)",
          self.finished ? @"YES" : @"NO");
    if (!self.finished) {
        NSLog(@"[MSAL Broker][AuthWindow] window closed before completion; finishing with cancelled status");
        [self finishWithResult:@{
            @"status": @"cancelled",
            @"context": @"User closed the sign-in window."
        }];
    }
}

- (void)webView:(WKWebView *)webView
decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = navigationAction.request.URL;
    NSString *absoluteUrl = stringValue(url.absoluteString);
    NSLog(@"[MSAL Broker][AuthWindow] decidePolicyForNavigationAction (scheme=%@, host=%@, path=%@)",
          url.scheme ?: @"",
          url.host ?: @"",
          url.path ?: @"");

    if (self.redirectUri.length > 0 && [absoluteUrl hasPrefix:self.redirectUri]) {
        NSLog(@"[MSAL Broker][AuthWindow] redirect URI detected; parsing OAuth response");
        NSDictionary *oauthParameters = extractOAuthResponseParameters(url);
        NSString *error = stringValue(oauthParameters[@"error"]);
        NSString *errorDescription = stringValue(oauthParameters[@"error_description"]);

        if (error.length > 0) {
            NSString *status = [error isEqualToString:@"access_denied"] ? @"cancelled" : @"error";
            NSLog(@"[MSAL Broker][AuthWindow] OAuth redirect returned error=%@ (status=%@)", error, status);
            [self finishWithResult:@{
                @"status": status,
                @"context": errorDescription.length > 0 ? errorDescription : error
            }];
        } else {
            NSString *authorizationCode = stringValue(oauthParameters[@"code"]);
            NSString *state = stringValue(oauthParameters[@"state"]);
            NSLog(@"[MSAL Broker][AuthWindow] OAuth redirect returned codePresent=%@ statePresent=%@",
                  authorizationCode.length > 0 ? @"YES" : @"NO",
                  state.length > 0 ? @"YES" : @"NO");

            if (authorizationCode.length == 0) {
                NSLog(@"[MSAL Broker][AuthWindow] OAuth redirect missing authorization code");
                [self finishWithResult:@{
                    @"status": @"error",
                    @"context": @"Authorization response did not contain a code."
                }];
            } else if (self.expectedState.length > 0 && ![state isEqualToString:self.expectedState]) {
                NSLog(@"[MSAL Broker][AuthWindow] OAuth state mismatch (expected=%@, actual=%@)",
                      self.expectedState ?: @"",
                      state ?: @"");
                [self finishWithResult:@{
                    @"status": @"error",
                    @"context": @"OAuth state mismatch."
                }];
            } else {
                NSLog(@"[MSAL Broker][AuthWindow] OAuth redirect validated successfully");
                [self finishWithResult:@{
                    @"status": @"success",
                    @"code": authorizationCode
                }];
            }
        }

        NSLog(@"[MSAL Broker][AuthWindow] cancelling navigation because redirect URI was handled");
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }

    NSLog(@"[MSAL Broker][AuthWindow] allowing navigation");
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    NSLog(@"[MSAL Broker][AuthWindow] webView didStartProvisionalNavigation currentURL=%@",
          stringValue(webView.URL.absoluteString));
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    NSLog(@"[MSAL Broker][AuthWindow] webView didFinishNavigation currentURL=%@",
          stringValue(webView.URL.absoluteString));
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"[MSAL Broker][AuthWindow] webView didFailNavigation error=%@", error.localizedDescription);
    if (!self.finished) {
        [self finishWithResult:@{
            @"status": @"error",
            @"context": [NSString stringWithFormat:@"Navigation failed on sign-in page: %@", error.localizedDescription]
        }];
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    NSLog(@"[MSAL Broker][AuthWindow] webView didFailProvisionalNavigation error=%@", error.localizedDescription);
    if (!self.finished) {
        [self finishWithResult:@{
            @"status": @"error",
            @"context": [NSString stringWithFormat:@"Failed to load sign-in page: %@", error.localizedDescription]
        }];
    }
}

@end

static NSDictionary *performInteractiveMicrosoftSignIn(NSDictionary *authParams, NSString *accountHint, NSString *correlationId) {
    NSString *clientId = stringValue(authParams[@"clientId"]);
    NSString *authority = normalizeAuthority(authParams[@"authority"]);
    NSString *redirectUri = [NSString stringWithFormat:@"msauth.%@://auth", clientId];

    if (clientId.length == 0 || authority.length == 0 || redirectUri.length == 0) {
        return @{
            @"status": @"error",
            @"context": @"Missing required auth parameters (clientId, authority, or redirectUri)."
        };
    }

    NSArray *configuredScopes = [authParams[@"scopes"] isKindOfClass:[NSArray class]] ? authParams[@"scopes"] : @[];
    NSMutableOrderedSet *scopes = [NSMutableOrderedSet orderedSet];
    for (id scope in configuredScopes) {
        NSString *scopeValue = stringValue(scope);
        if (scopeValue.length > 0) {
            [scopes addObject:scopeValue];
        }
    }
    [scopes addObject:@"openid"];
    [scopes addObject:@"profile"];
    [scopes addObject:@"offline_access"];
    NSString *scopeString = [[scopes array] componentsJoinedByString:@" "];

    NSString *state = [[NSUUID UUID] UUIDString];
    NSString *codeVerifier = randomBase64UrlString(64);
    NSString *codeChallenge = sha256Base64Url(codeVerifier ?: @"");
    if (codeVerifier.length == 0 || codeChallenge.length == 0) {
        return @{
            @"status": @"error",
            @"context": @"Could not generate PKCE values."
        };
    }

    NSURLComponents *authorizeComponents = [NSURLComponents componentsWithString:
        [NSString stringWithFormat:@"%@/oauth2/v2.0/authorize", authority]];
    if (authorizeComponents == nil) {
        return @{
            @"status": @"error",
            @"context": @"Invalid authority URL."
        };
    }

    NSMutableArray<NSURLQueryItem *> *queryItems = [NSMutableArray arrayWithArray:@[
        [NSURLQueryItem queryItemWithName:@"client_id" value:clientId],
        [NSURLQueryItem queryItemWithName:@"response_type" value:@"code"],
        [NSURLQueryItem queryItemWithName:@"redirect_uri" value:redirectUri],
        [NSURLQueryItem queryItemWithName:@"response_mode" value:@"query"],
        [NSURLQueryItem queryItemWithName:@"scope" value:scopeString],
        [NSURLQueryItem queryItemWithName:@"state" value:state],
        [NSURLQueryItem queryItemWithName:@"code_challenge" value:codeChallenge],
        [NSURLQueryItem queryItemWithName:@"code_challenge_method" value:@"S256"],
        [NSURLQueryItem queryItemWithName:@"client_info" value:@"1"]
    ]];

    NSString *loginHint = stringValue(accountHint);
    if (loginHint.length > 0) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"login_hint" value:loginHint]];
    }

    NSString *claims = stringValue(authParams[@"claims"]);
    if (claims.length > 0) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"claims" value:claims]];
    }

    if (correlationId.length > 0) {
        [queryItems addObject:[NSURLQueryItem queryItemWithName:@"client-request-id" value:correlationId]];
    }

    for (NSString *key in authParams) {
        if ([kReservedAuthParameterKeys containsObject:key]) {
            continue;
        }

        id value = authParams[key];
        if ([value isKindOfClass:[NSString class]] && stringValue(value).length > 0) {
            [queryItems addObject:[NSURLQueryItem queryItemWithName:key value:stringValue(value)]];
        }
    }

    authorizeComponents.queryItems = queryItems;
    NSURL *authorizeUrl = authorizeComponents.URL;
    if (authorizeUrl == nil) {
        return @{
            @"status": @"error",
            @"context": @"Failed to create authorization URL."
        };
    }
    NSLog(@"[MSAL Broker] Broker window initialization\n\tauthorizeUrl: %@\n\tredirectUri: %@\n\tstate: %@",
          authorizeUrl.absoluteString,
          redirectUri,
          state);
    __block NSDictionary *uiResult = nil;
    dispatch_sync(dispatch_get_main_queue(), ^{
        MSALInteractiveAuthWindowController *windowController = [[MSALInteractiveAuthWindowController alloc]
            initWithAuthorizeURL:authorizeUrl
                      redirectUri:redirectUri
                    expectedState:state];
        uiResult = [windowController runModalAuthWindow];
    });

    NSString *uiStatus = stringValue(uiResult[@"status"]);
    if (![uiStatus isEqualToString:@"success"]) {
        return uiResult ?: @{
            @"status": @"cancelled",
            @"context": @"User cancelled sign-in."
        };
    }

    NSString *authorizationCode = stringValue(uiResult[@"code"]);
    NSDictionary *tokenResult = exchangeCodeForTokens(authority, clientId, scopeString, redirectUri, authorizationCode, codeVerifier);
    if (![stringValue(tokenResult[@"status"]) isEqualToString:@"success"]) {
        return tokenResult;
    }

    NSDictionary *tokenPayload = tokenResult[@"payload"];
    NSString *accessToken = stringValue(tokenPayload[@"access_token"]);
    NSString *idToken = stringValue(tokenPayload[@"id_token"]);
    if (accessToken.length == 0) {
        return @{
            @"status": @"error",
            @"context": @"Token response did not include an access token."
        };
    }

    NSDictionary *account = buildAccountInfo(tokenPayload, idToken, accountHint);
    NSTimeInterval expiresIn = [stringValue(tokenPayload[@"expires_in"]) doubleValue];
    if (expiresIn <= 0) {
        expiresIn = 3600;
    }

    return @{
        @"status": @"success",
        @"accessToken": accessToken,
        @"idToken": idToken.length > 0 ? idToken : @"",
        @"account": account,
        @"expiresOn": @([[NSDate date] timeIntervalSince1970] + expiresIn)
    };
}

// ============================================================================
// MSALRuntime Core API Implementation
// ============================================================================

MSALMacErrorHandle MSALMACRUNTIME_Startup(void) {
    @autoreleasepool {
        ensureRuntimeStateInitialized();

        @synchronized(gSyncLock) {
            NSLog(@"[MSAL Broker] MSALRuntime startup completed successfully");
            gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
            return gLastError;
        }
    }
}

void MSALMACRUNTIME_Shutdown(void) {
    @autoreleasepool {
        @synchronized(gSyncLock) {
            // Cancel all pending async operations
            for (NSNumber *key in [gAsyncOperations allKeys]) {
                // Operations will be cleaned up automatically
            }
            
            // Clear all dictionaries
            [gAsyncOperations removeAllObjects];
            [gAuthParameters removeAllObjects];
            [gAccounts removeAllObjects];
            [gAuthResults removeAllObjects];
            [gReadAccountResults removeAllObjects];
            [gSignOutResults removeAllObjects];
            [gErrors removeAllObjects];
            
            if (gLogCallbackContext != NULL) {
                free(gLogCallbackContext);
                gLogCallbackContext = NULL;
            }
            
            NSLog(@"[MSAL Broker] MSALRuntime shutdown completed");
        }
    }
}

MSALMacErrorHandle MSALMACRUNTIME_ReadAccountByIdAsync(
    const wchar_t *accountId,
    const wchar_t *correlationId,
    ReadAccountResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle) {
    
    @autoreleasepool {
        if (callback == NULL || asyncHandle == NULL) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 1, 1, "Invalid callback or handle pointer");
            return gLastError;
        }
        
        NSString *accountIdStr = wstringToNSString(accountId);
        NSString *correlationIdStr = wstringToNSString(correlationId);
        
        int64_t operationHandle = generateHandle();
        asyncHandle->value = operationHandle;
        
        dispatch_async(gBrokerQueue, ^{
            @autoreleasepool {
                @try {
                    // Simulate account lookup with a slight delay
                    [NSThread sleepForTimeInterval:0.1];
                    
                    @synchronized(gSyncLock) {
                        // Create mock read account result
                        NSMutableDictionary *accountData = [NSMutableDictionary dictionary];
                        accountData[@"accountId"] = accountIdStr;
                        accountData[@"displayName"] = @"Test User";
                        accountData[@"homeAccountId"] = [NSString stringWithFormat:@"%@.%@", accountIdStr, @"tenant-id"];
                        accountData[@"clientInfo"] = kMockClientInfo;
                        
                        int64_t readAccountResultHandle = generateHandle();
                        gReadAccountResults[@(readAccountResultHandle)] = accountData;
                        
                        callback(readAccountResultHandle, callbackData, MSALMAC_RESPONSE_STATUS_SUCCESS);
                    }
                    
                    NSLog(@"[MSAL Broker] ReadAccountById completed for account: %@", accountIdStr);
                } @catch (NSException *exception) {
                    NSLog(@"[MSAL Broker] Error reading account: %@", exception.reason);
                    callback(0, callbackData, MSALMAC_RESPONSE_STATUS_ERROR);
                }
            }
        });
        
        gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
        return gLastError;
    }
}

MSALMacErrorHandle MSALMACRUNTIME_SignInAsync(
    int64_t parentWindowHandle,
    int64_t authParametersHandle,
    const wchar_t *correlationId,
    const wchar_t *accountHint,
    AuthResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle) {
    
    @autoreleasepool {
        if (callback == NULL || asyncHandle == NULL) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 2, 2, "Invalid callback or handle pointer");
            return gLastError;
        }
        
        if (gAuthParameters[@(authParametersHandle)] == nil) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 3, 3, "Auth parameters not found");
            return gLastError;
        }
        
        int64_t operationHandle = generateHandle();
        asyncHandle->value = operationHandle;
        
        NSString *correlationIdStr = wstringToNSString(correlationId);
        NSString *accountHintStr = wstringToNSString(accountHint);
        
        dispatch_async(gBrokerQueue, ^{
            @autoreleasepool {
                @try {
                    [NSThread sleepForTimeInterval:0.2];
                    
                    @synchronized(gSyncLock) {
                        NSMutableDictionary *authParams = gAuthParameters[@(authParametersHandle)];
                        NSMutableDictionary *authResult = [NSMutableDictionary dictionary];
                        
                        authResult[@"accessToken"] = @"mock_access_token_for_signin";
                        authResult[@"idToken"] = kMockJwt;
                        authResult[@"accountId"] = accountHintStr;
                        authResult[@"scope"] = authParams[@"scopes"];
                        authResult[@"expiresOn"] = @([[NSDate date] timeIntervalSince1970] + 3600);
                        authResult[@"correlationId"] = correlationIdStr;
                        
                        NSMutableDictionary *accountInfo = [NSMutableDictionary dictionary];
                        accountInfo[@"accountId"] = accountHintStr;
                        accountInfo[@"displayName"] = @"Test User";
                        accountInfo[@"clientInfo"] = kMockClientInfo;
                        
                        authResult[@"account"] = accountInfo;
                        
                        int64_t authResultHandle = generateHandle();
                        gAuthResults[@(authResultHandle)] = authResult;
                        
                        callback(authResultHandle, callbackData, MSALMAC_RESPONSE_STATUS_SUCCESS);
                    }
                    
                    NSLog(@"[MSAL Broker] SignIn completed for account: %@", accountHintStr);
                } @catch (NSException *exception) {
                    NSLog(@"[MSAL Broker] SignIn failed: %@", exception.reason);
                    callback(0, callbackData, MSALMAC_RESPONSE_STATUS_ERROR);
                }
            }
        });
        
        gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
        return gLastError;
    }
}

MSALMacErrorHandle MSALMACRUNTIME_SignInSilentlyAsync(
    int64_t authParametersHandle,
    const wchar_t *correlationId,
    AuthResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle) {
    
    @autoreleasepool {
        if (callback == NULL || asyncHandle == NULL) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 4, 4, "Invalid callback or handle pointer");
            return gLastError;
        }
        
        if (gAuthParameters[@(authParametersHandle)] == nil) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 5, 5, "Auth parameters not found");
            return gLastError;
        }
        
        int64_t operationHandle = generateHandle();
        asyncHandle->value = operationHandle;
        
        NSString *correlationIdStr = wstringToNSString(correlationId);
        
        dispatch_async(gBrokerQueue, ^{
            @autoreleasepool {
                @try {
                    [NSThread sleepForTimeInterval:0.1];
                    
                    @synchronized(gSyncLock) {
                        NSMutableDictionary *authParams = gAuthParameters[@(authParametersHandle)];
                        NSMutableDictionary *authResult = [NSMutableDictionary dictionary];
                        
                        authResult[@"accessToken"] = @"mock_access_token_silent";
                        authResult[@"idToken"] = kMockJwt;
                        authResult[@"scope"] = authParams[@"scopes"];
                        authResult[@"expiresOn"] = @([[NSDate date] timeIntervalSince1970] + 3600);
                        authResult[@"correlationId"] = correlationIdStr;
                        
                        int64_t authResultHandle = generateHandle();
                        gAuthResults[@(authResultHandle)] = authResult;
                        
                        callback(authResultHandle, callbackData, MSALMAC_RESPONSE_STATUS_SUCCESS);
                    }
                    
                    NSLog(@"[MSAL Broker] SignInSilently completed");
                } @catch (NSException *exception) {
                    NSLog(@"[MSAL Broker] Silent sign-in failed: %@", exception.reason);
                    callback(0, callbackData, MSALMAC_RESPONSE_STATUS_ERROR);
                }
            }
        });
        
        gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
        return gLastError;
    }
}

MSALMacErrorHandle MSALMACRUNTIME_SignInInteractivelyAsync(
    int64_t parentWindowHandle,
    int64_t authParametersHandle,
    const wchar_t *correlationId,
    const wchar_t *accountHint,
    AuthResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle) {
    
    @autoreleasepool {
        if (callback == NULL || asyncHandle == NULL) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 6, 6, "Invalid callback or handle pointer");
            return gLastError;
        }
        
        if (gAuthParameters[@(authParametersHandle)] == nil) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 7, 7, "Auth parameters not found");
            return gLastError;
        }
        
        int64_t operationHandle = generateHandle();
        asyncHandle->value = operationHandle;
        
        NSString *correlationIdStr = wstringToNSString(correlationId);
        NSString *accountHintStr = wstringToNSString(accountHint);
        
        dispatch_async(gBrokerQueue, ^{
            @autoreleasepool {
                @try {
                    NSDictionary *authParams = nil;
                    @synchronized(gSyncLock) {
                        NSDictionary *storedParams = gAuthParameters[@(authParametersHandle)];
                        if (storedParams != nil) {
                            authParams = [storedParams copy];
                        }
                    }

                    if (authParams == nil) {
                        setError(MSALMAC_RESPONSE_STATUS_ERROR, 70, 70, "Auth parameters not found");
                        callback(0, callbackData, MSALMAC_RESPONSE_STATUS_ERROR);
                        return;
                    }

                    NSDictionary *interactiveResult = performInteractiveMicrosoftSignIn(authParams, accountHintStr, correlationIdStr);
                    NSString *resultStatus = stringValue(interactiveResult[@"status"]);

                    if ([resultStatus isEqualToString:@"success"]) {
                        @synchronized(gSyncLock) {
                            NSMutableDictionary *authResult = [NSMutableDictionary dictionary];
                            authResult[@"accessToken"] = stringValue(interactiveResult[@"accessToken"]);
                            authResult[@"idToken"] = stringValue(interactiveResult[@"idToken"]);
                            authResult[@"accountId"] = stringValue(interactiveResult[@"account"][@"accountId"]);
                            authResult[@"scope"] = authParams[@"scopes"] ?: @[];
                            authResult[@"expiresOn"] = interactiveResult[@"expiresOn"] ?: @([[NSDate date] timeIntervalSince1970] + 3600);
                            authResult[@"correlationId"] = correlationIdStr;
                            authResult[@"account"] = interactiveResult[@"account"] ?: @{
                                @"accountId": accountHintStr.length > 0 ? accountHintStr : @"unknown-account",
                                @"displayName": @"Microsoft User",
                                @"clientInfo": kMockClientInfo
                            };

                            int64_t authResultHandle = generateHandle();
                            gAuthResults[@(authResultHandle)] = authResult;
                            callback(authResultHandle, callbackData, MSALMAC_RESPONSE_STATUS_SUCCESS);
                        }

                        NSLog(@"[MSAL Broker] SignInInteractively completed for account: %@", stringValue(interactiveResult[@"account"][@"accountId"]));
                    } else if ([resultStatus isEqualToString:@"cancelled"]) {
                        NSLog(@"[MSAL Broker] Interactive sign-in cancelled");
                        callback(0, callbackData, MSALMAC_RESPONSE_STATUS_CANCELLED);
                    } else {
                        NSString *context = stringValue(interactiveResult[@"context"]);
                        setError(MSALMAC_RESPONSE_STATUS_ERROR, 71, 71, context.length > 0 ? context.UTF8String : "Interactive sign-in failed");
                        NSLog(@"[MSAL Broker] Interactive sign-in failed: %@", context);
                        callback(0, callbackData, MSALMAC_RESPONSE_STATUS_ERROR);
                    }
                } @catch (NSException *exception) {
                    NSLog(@"[MSAL Broker] Interactive sign-in failed: %@", exception.reason);
                    callback(0, callbackData, MSALMAC_RESPONSE_STATUS_ERROR);
                }
            }
        });
        
        gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
        return gLastError;
    }
}

MSALMacErrorHandle MSALMACRUNTIME_AcquireTokenSilentlyAsync(
    int64_t authParametersHandle,
    const wchar_t *correlationId,
    int64_t accountHandle,
    AuthResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle) {
    
    @autoreleasepool {
        if (callback == NULL || asyncHandle == NULL) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 8, 8, "Invalid callback or handle pointer");
            return gLastError;
        }
        
        int64_t operationHandle = generateHandle();
        asyncHandle->value = operationHandle;
        
        NSString *correlationIdStr = wstringToNSString(correlationId);
        
        dispatch_async(gBrokerQueue, ^{
            @autoreleasepool {
                @try {
                    [NSThread sleepForTimeInterval:0.1];
                    
                    @synchronized(gSyncLock) {
                        NSMutableDictionary *authResult = [NSMutableDictionary dictionary];
                        
                        authResult[@"accessToken"] = @"mock_access_token_acquired_silent";
                        authResult[@"idToken"] = kMockJwt;
                        authResult[@"expiresOn"] = @([[NSDate date] timeIntervalSince1970] + 3600);
                        authResult[@"correlationId"] = correlationIdStr;
                        authResult[@"account"] = gAccounts[@(accountHandle)] ?: @{
                            @"accountId": @"mock-account-id",
                            @"displayName": @"Test User",
                            @"clientInfo": kMockClientInfo
                        };
                        
                        int64_t authResultHandle = generateHandle();
                        gAuthResults[@(authResultHandle)] = authResult;
                        
                        callback(authResultHandle, callbackData, MSALMAC_RESPONSE_STATUS_SUCCESS);
                    }
                    
                    NSLog(@"[MSAL Broker] AcquireTokenSilently completed");
                } @catch (NSException *exception) {
                    NSLog(@"[MSAL Broker] Token acquisition failed: %@", exception.reason);
                    callback(0, callbackData, MSALMAC_RESPONSE_STATUS_ERROR);
                }
            }
        });
        
        gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
        return gLastError;
    }
}

MSALMacErrorHandle MSALMACRUNTIME_AcquireTokenInteractivelyAsync(
    int64_t parentWindowHandle,
    int64_t authParametersHandle,
    const wchar_t *correlationId,
    int64_t accountHandle,
    AuthResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle) {
    
    @autoreleasepool {
        if (callback == NULL || asyncHandle == NULL) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 9, 9, "Invalid callback or handle pointer");
            return gLastError;
        }
        
        int64_t operationHandle = generateHandle();
        asyncHandle->value = operationHandle;
        
        NSString *correlationIdStr = wstringToNSString(correlationId);
        
        dispatch_async(gBrokerQueue, ^{
            @autoreleasepool {
                @try {
                    [NSThread sleepForTimeInterval:0.3];
                    
                    @synchronized(gSyncLock) {
                        NSMutableDictionary *authResult = [NSMutableDictionary dictionary];
                        
                        authResult[@"accessToken"] = @"mock_access_token_acquired_interactive";
                        authResult[@"idToken"] = kMockJwt;
                        authResult[@"expiresOn"] = @([[NSDate date] timeIntervalSince1970] + 3600);
                        authResult[@"correlationId"] = correlationIdStr;
                        authResult[@"account"] = gAccounts[@(accountHandle)] ?: @{
                            @"accountId": @"mock-account-id",
                            @"displayName": @"Test User",
                            @"clientInfo": kMockClientInfo
                        };
                        
                        int64_t authResultHandle = generateHandle();
                        gAuthResults[@(authResultHandle)] = authResult;
                        
                        callback(authResultHandle, callbackData, MSALMAC_RESPONSE_STATUS_SUCCESS);
                    }
                    
                    NSLog(@"[MSAL Broker] AcquireTokenInteractively completed");
                } @catch (NSException *exception) {
                    NSLog(@"[MSAL Broker] Interactive token acquisition failed: %@", exception.reason);
                    callback(0, callbackData, MSALMAC_RESPONSE_STATUS_ERROR);
                }
            }
        });
        
        gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
        return gLastError;
    }
}

MSALMacErrorHandle MSALMACRUNTIME_SignOutSilentlyAsync(
    const wchar_t *clientId,
    const wchar_t *correlationId,
    int64_t accountHandle,
    SignOutResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle) {
    
    @autoreleasepool {
        if (callback == NULL || asyncHandle == NULL) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 10, 10, "Invalid callback or handle pointer");
            return gLastError;
        }
        
        int64_t operationHandle = generateHandle();
        asyncHandle->value = operationHandle;
        
        NSString *correlationIdStr = wstringToNSString(correlationId);
        
        dispatch_async(gBrokerQueue, ^{
            @autoreleasepool {
                @try {
                    [NSThread sleepForTimeInterval:0.1];
                    
                    @synchronized(gSyncLock) {
                        NSMutableDictionary *signOutResult = [NSMutableDictionary dictionary];
                        signOutResult[@"success"] = @YES;
                        signOutResult[@"correlationId"] = correlationIdStr;
                        
                        int64_t signOutResultHandle = generateHandle();
                        gSignOutResults[@(signOutResultHandle)] = signOutResult;
                        
                        callback(signOutResultHandle, callbackData, MSALMAC_RESPONSE_STATUS_SUCCESS);
                    }
                    
                    NSLog(@"[MSAL Broker] SignOutSilently completed");
                } @catch (NSException *exception) {
                    NSLog(@"[MSAL Broker] Sign-out failed: %@", exception.reason);
                    callback(0, callbackData, MSALMAC_RESPONSE_STATUS_ERROR);
                }
            }
        });
        
        gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
        return gLastError;
    }
}

// ============================================================================
// MSALRuntimeAccount API Implementation
// ============================================================================

MSALMacErrorHandle MSALMACRUNTIME_ReleaseAccount(int64_t accountHandle) {
    @synchronized(gSyncLock) {
        [gAccounts removeObjectForKey:@(accountHandle)];
    }
    gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
    return gLastError;
}

MSALMacErrorHandle MSALMACRUNTIME_GetAccountId(
    int64_t accountHandle,
    wchar_t *accountId,
    int32_t *bufferSize) {
    
    @autoreleasepool {
        @synchronized(gSyncLock) {
            NSMutableDictionary *account = gAccounts[@(accountHandle)];
            if (account == nil) {
                setError(MSALMAC_RESPONSE_STATUS_ERROR, 11, 11, "Account not found");
                return gLastError;
            }
            
            NSString *idStr = account[@"accountId"] ?: @"";
            wchar_t *id = nsstringToWstring(idStr);
            int32_t requiredSize = (int32_t)(wcslen(id) + 1) * sizeof(wchar_t);
            
            if (*bufferSize < requiredSize) {
                *bufferSize = requiredSize;
                free(id);
                gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
                return gLastError;
            }
            
            wcscpy(accountId, id);
            *bufferSize = requiredSize;
            free(id);
            
            gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
            return gLastError;
        }
    }
}

MSALMacErrorHandle MSALMACRUNTIME_GetClientInfo(
    int64_t accountHandle,
    wchar_t *clientInfo,
    int32_t *bufferSize) {
    
    @autoreleasepool {
        @synchronized(gSyncLock) {
            NSMutableDictionary *account = gAccounts[@(accountHandle)];
            if (account == nil) {
                setError(MSALMAC_RESPONSE_STATUS_ERROR, 12, 12, "Account not found");
                return gLastError;
            }
            
            NSString *infoStr = account[@"clientInfo"] ?: @"{}";
            wchar_t *info = nsstringToWstring(infoStr);
            int32_t requiredSize = (int32_t)(wcslen(info) + 1) * sizeof(wchar_t);
            
            if (*bufferSize < requiredSize) {
                *bufferSize = requiredSize;
                free(info);
                gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
                return gLastError;
            }
            
            wcscpy(clientInfo, info);
            *bufferSize = requiredSize;
            free(info);
            
            gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
            return gLastError;
        }
    }
}

// ============================================================================
// MSALRuntimeAuthParameters API Implementation
// ============================================================================

MSALMacErrorHandle MSALMACRUNTIME_CreateAuthParameters(
    const wchar_t *clientId,
    const wchar_t *authority,
    AuthParametersHandle *authParametersHandle) {
    
    @autoreleasepool {
        if (clientId == NULL || authority == NULL || authParametersHandle == NULL) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 13, 13, "Null parameters");
            return gLastError;
        }
        
        @synchronized(gSyncLock) {
            NSMutableDictionary *params = [NSMutableDictionary dictionary];
            params[@"clientId"] = wstringToNSString(clientId);
            params[@"authority"] = wstringToNSString(authority);
            params[@"scopes"] = @[];
            params[@"redirectUri"] = @"";
            params[@"claims"] = @"";
            
            int64_t paramHandle = generateHandle();
            authParametersHandle->value = paramHandle;
            gAuthParameters[@(paramHandle)] = params;
            
            gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
            return gLastError;
        }
    }
}

MSALMacErrorHandle MSALMACRUNTIME_ReleaseAuthParameters(int64_t authParametersHandle) {
    @synchronized(gSyncLock) {
        [gAuthParameters removeObjectForKey:@(authParametersHandle)];
    }
    gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
    return gLastError;
}

MSALMacErrorHandle MSALMACRUNTIME_SetRequestedScopes(
    int64_t authParametersHandle,
    const wchar_t *scopes) {
    
    @autoreleasepool {
        @synchronized(gSyncLock) {
            NSMutableDictionary *params = gAuthParameters[@(authParametersHandle)];
            if (params == nil) {
                setError(MSALMAC_RESPONSE_STATUS_ERROR, 14, 14, "Auth parameters not found");
                return gLastError;
            }
            
            NSString *scopesStr = wstringToNSString(scopes);
            NSArray *scopeArray = [scopesStr componentsSeparatedByString:@" "];
            params[@"scopes"] = scopeArray;
            
            gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
            return gLastError;
        }
    }
}

MSALMacErrorHandle MSALMACRUNTIME_SetRedirectUri(
    int64_t authParametersHandle,
    const wchar_t *redirectUri) {
    
    @autoreleasepool {
        @synchronized(gSyncLock) {
            NSMutableDictionary *params = gAuthParameters[@(authParametersHandle)];
            if (params == nil) {
                setError(MSALMAC_RESPONSE_STATUS_ERROR, 15, 15, "Auth parameters not found");
                return gLastError;
            }
            
            params[@"redirectUri"] = wstringToNSString(redirectUri);
            
            gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
            return gLastError;
        }
    }
}

MSALMacErrorHandle MSALMACRUNTIME_SetDecodedClaims(
    int64_t authParametersHandle,
    const wchar_t *claims) {
    
    @autoreleasepool {
        @synchronized(gSyncLock) {
            NSMutableDictionary *params = gAuthParameters[@(authParametersHandle)];
            if (params == nil) {
                setError(MSALMAC_RESPONSE_STATUS_ERROR, 16, 16, "Auth parameters not found");
                return gLastError;
            }
            
            params[@"claims"] = wstringToNSString(claims);
            
            gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
            return gLastError;
        }
    }
}

MSALMacErrorHandle MSALMACRUNTIME_SetAdditionalParameter(
    int64_t authParametersHandle,
    const wchar_t *key,
    const wchar_t *value) {
    
    @autoreleasepool {
        @synchronized(gSyncLock) {
            NSMutableDictionary *params = gAuthParameters[@(authParametersHandle)];
            if (params == nil) {
                setError(MSALMAC_RESPONSE_STATUS_ERROR, 17, 17, "Auth parameters not found");
                return gLastError;
            }
            
            NSString *keyStr = wstringToNSString(key);
            NSString *valueStr = wstringToNSString(value);
            params[keyStr] = valueStr;
            
            gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
            return gLastError;
        }
    }
}

MSALMacErrorHandle MSALMACRUNTIME_SetPopParams(
    int64_t authParametersHandle,
    const wchar_t *httpMethod,
    const wchar_t *uriHost,
    const wchar_t *uriPath,
    const wchar_t *nonce) {
    
    @autoreleasepool {
        @synchronized(gSyncLock) {
            NSMutableDictionary *params = gAuthParameters[@(authParametersHandle)];
            if (params == nil) {
                setError(MSALMAC_RESPONSE_STATUS_ERROR, 18, 18, "Auth parameters not found");
                return gLastError;
            }
            
            NSMutableDictionary *popParams = [NSMutableDictionary dictionary];
            popParams[@"httpMethod"] = wstringToNSString(httpMethod);
            popParams[@"uriHost"] = wstringToNSString(uriHost);
            popParams[@"uriPath"] = wstringToNSString(uriPath);
            popParams[@"nonce"] = wstringToNSString(nonce);
            
            params[@"popParams"] = popParams;
            
            gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
            return gLastError;
        }
    }
}

// ============================================================================
// MSALRuntimeCancel API Implementation
// ============================================================================

MSALMacErrorHandle MSALMACRUNTIME_ReleaseAsyncHandle(int64_t asyncHandle) {
    @synchronized(gSyncLock) {
        [gAsyncOperations removeObjectForKey:@(asyncHandle)];
    }
    gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
    return gLastError;
}

MSALMacErrorHandle MSALMACRUNTIME_CancelAsyncOperation(MSALMacAsyncHandle *asyncHandle) {
    if (asyncHandle == NULL) {
        setError(MSALMAC_RESPONSE_STATUS_ERROR, 19, 19, "Null async handle");
        return gLastError;
    }
    
    @synchronized(gSyncLock) {
        [gAsyncOperations removeObjectForKey:@(asyncHandle->value)];
    }
    gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
    return gLastError;
}

// ============================================================================
// MSALRuntimeError API Implementation
// ============================================================================

MSALMacErrorHandle MSALMACRUNTIME_ReleaseError(int64_t errorHandle) {
    @synchronized(gSyncLock) {
        [gErrors removeObjectForKey:@(errorHandle)];
    }
    gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
    return gLastError;
}

MSALMacErrorHandle MSALMACRUNTIME_GetStatus(
    MSALMacErrorHandle errorHandle,
    MSALMacResponseStatus *responseStatus) {
    
    if (responseStatus == NULL) {
        setError(MSALMAC_RESPONSE_STATUS_ERROR, 20, 20, "Null response status pointer");
        return gLastError;
    }
    
    @synchronized(gSyncLock) {
        NSMutableDictionary *error = gErrors[@(errorHandle.status)];
        *responseStatus = error ? [error[@"status"] intValue] : MSALMAC_RESPONSE_STATUS_SUCCESS;
    }
    
    gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
    return gLastError;
}

MSALMacErrorHandle MSALMACRUNTIME_GetStatusFromInt64(
    int64_t errorHandle,
    MSALMacResponseStatus *responseStatus) {
    
    if (responseStatus == NULL) {
        setError(MSALMAC_RESPONSE_STATUS_ERROR, 21, 21, "Null response status pointer");
        return gLastError;
    }
    
    @synchronized(gSyncLock) {
        NSMutableDictionary *error = gErrors[@(errorHandle)];
        *responseStatus = error ? [error[@"status"] intValue] : MSALMAC_RESPONSE_STATUS_SUCCESS;
    }
    
    gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
    return gLastError;
}

MSALMacErrorHandle MSALMACRUNTIME_GetErrorCode(
    int64_t errorHandle,
    int64_t *responseErrorCode) {
    
    if (responseErrorCode == NULL) {
        setError(MSALMAC_RESPONSE_STATUS_ERROR, 22, 22, "Null error code pointer");
        return gLastError;
    }
    
    @synchronized(gSyncLock) {
        NSMutableDictionary *error = gErrors[@(errorHandle)];
        *responseErrorCode = error ? [error[@"code"] longLongValue] : 0;
    }
    
    gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
    return gLastError;
}

MSALMacErrorHandle MSALMACRUNTIME_GetTag(
    int64_t errorHandle,
    int32_t *responseErrorTag) {
    
    if (responseErrorTag == NULL) {
        setError(MSALMAC_RESPONSE_STATUS_ERROR, 23, 23, "Null error tag pointer");
        return gLastError;
    }
    
    @synchronized(gSyncLock) {
        NSMutableDictionary *error = gErrors[@(errorHandle)];
        *responseErrorTag = error ? [error[@"tag"] intValue] : 0;
    }
    
    gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
    return gLastError;
}

MSALMacErrorHandle MSALMACRUNTIME_GetContext(
    MSALMacErrorHandle errorHandle,
    wchar_t *context,
    int32_t *bufferSize) {
    
    @autoreleasepool {
        if (bufferSize == NULL) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 24, 24, "Null buffer size pointer");
            return gLastError;
        }
        
        @synchronized(gSyncLock) {
            NSMutableDictionary *error = gErrors[@(errorHandle.status)];
            NSString *contextStr = error[@"context"] ?: @"";
            wchar_t *ctx = nsstringToWstring(contextStr);
            int32_t requiredSize = (int32_t)(wcslen(ctx) + 1) * sizeof(wchar_t);
            
            if (context == NULL || *bufferSize < requiredSize) {
                *bufferSize = requiredSize;
                free(ctx);
                gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
                return gLastError;
            }
            
            wcscpy(context, ctx);
            *bufferSize = requiredSize;
            free(ctx);
            
            gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
            return gLastError;
        }
    }
}

// ============================================================================
// MSALRuntimeAuthResult API Implementation
// ============================================================================

MSALMacErrorHandle MSALMACRUNTIME_ReleaseAuthResult(int64_t authResultHandle) {
    @synchronized(gSyncLock) {
        [gAuthResults removeObjectForKey:@(authResultHandle)];
    }
    gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
    return gLastError;
}

MSALMacErrorHandle MSALMACRUNTIME_GetAccount(
    MSALMacAuthResultHandle authResultHandle,
    MSALMacAccountHandle *accountHandle) {
    
    if (accountHandle == NULL) {
        setError(MSALMAC_RESPONSE_STATUS_ERROR, 25, 25, "Null account handle pointer");
        return gLastError;
    }
    
    @synchronized(gSyncLock) {
        NSMutableDictionary *authResult = gAuthResults[@(authResultHandle.value)];
        if (authResult == nil) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 26, 26, "Auth result not found");
            return gLastError;
        }
        
        NSMutableDictionary *accountInfo = authResult[@"account"];
        int64_t acctHandle = generateHandle();
        gAccounts[@(acctHandle)] = accountInfo ?: [NSMutableDictionary dictionary];
        accountHandle->value = acctHandle;
        
        gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
        return gLastError;
    }
}

MSALMacErrorHandle MSALMACRUNTIME_GetRawIdToken(
    MSALMacAuthResultHandle authResultHandle,
    wchar_t *rawIdToken,
    int32_t *bufferSize) {
    
    @autoreleasepool {
        if (bufferSize == NULL) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 27, 27, "Null buffer size pointer");
            return gLastError;
        }
        
        @synchronized(gSyncLock) {
            NSMutableDictionary *authResult = gAuthResults[@(authResultHandle.value)];
            if (authResult == nil) {
                setError(MSALMAC_RESPONSE_STATUS_ERROR, 28, 28, "Auth result not found");
                return gLastError;
            }
            
            NSString *tokenStr = authResult[@"idToken"] ?: @"";
            wchar_t *token = nsstringToWstring(tokenStr);
            int32_t requiredSize = (int32_t)(wcslen(token) + 1) * sizeof(wchar_t);
            
            if (rawIdToken == NULL || *bufferSize < requiredSize) {
                *bufferSize = requiredSize;
                free(token);
                gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
                return gLastError;
            }
            
            wcscpy(rawIdToken, token);
            *bufferSize = requiredSize;
            free(token);
            
            gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
            return gLastError;
        }
    }
}

MSALMacErrorHandle MSALMACRUNTIME_GetAccessToken(
    MSALMacAuthResultHandle authResultHandle,
    wchar_t *accessToken,
    int32_t *bufferSize) {
    
    @autoreleasepool {
        if (bufferSize == NULL) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 29, 29, "Null buffer size pointer");
            return gLastError;
        }
        
        @synchronized(gSyncLock) {
            NSMutableDictionary *authResult = gAuthResults[@(authResultHandle.value)];
            if (authResult == nil) {
                setError(MSALMAC_RESPONSE_STATUS_ERROR, 30, 30, "Auth result not found");
                return gLastError;
            }
            
            NSString *tokenStr = authResult[@"accessToken"] ?: @"";
            wchar_t *token = nsstringToWstring(tokenStr);
            int32_t requiredSize = (int32_t)(wcslen(token) + 1) * sizeof(wchar_t);
            
            if (accessToken == NULL || *bufferSize < requiredSize) {
                *bufferSize = requiredSize;
                free(token);
                gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
                return gLastError;
            }
            
            wcscpy(accessToken, token);
            *bufferSize = requiredSize;
            free(token);
            
            gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
            return gLastError;
        }
    }
}

MSALMacErrorHandle MSALMACRUNTIME_GetError(
    MSALMacAuthResultHandle authResultHandle,
    MSALMacErrorHandleValue *errorHandle) {
    
    if (errorHandle == NULL) {
        setError(MSALMAC_RESPONSE_STATUS_ERROR, 31, 31, "Null error handle pointer");
        return gLastError;
    }
    
    @synchronized(gSyncLock) {
        NSMutableDictionary *authResult = gAuthResults[@(authResultHandle.value)];
        if (authResult == nil || authResult[@"error"] == nil) {
            errorHandle->value = 0;
            gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
            return gLastError;
        }
        
        int64_t errHandle = generateHandle();
        errorHandle->value = errHandle;
        gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
        return gLastError;
    }
}

MSALMacErrorHandle MSALMACRUNTIME_IsPopAuthorization(
    MSALMacAuthResultHandle authResult,
    int32_t *isPopAuthorization) {
    
    if (isPopAuthorization == NULL) {
        setError(MSALMAC_RESPONSE_STATUS_ERROR, 32, 32, "Null PoP flag pointer");
        return gLastError;
    }
    
    @synchronized(gSyncLock) {
        NSMutableDictionary *result = gAuthResults[@(authResult.value)];
        *isPopAuthorization = (result[@"popParams"] != nil) ? 1 : 0;
    }
    
    gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
    return gLastError;
}

MSALMacErrorHandle MSALMACRUNTIME_GetAuthorizationHeader(
    MSALMacAuthResultHandle authResult,
    wchar_t *authHeader,
    int32_t *bufferSize) {
    
    @autoreleasepool {
        if (bufferSize == NULL) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 33, 33, "Null buffer size pointer");
            return gLastError;
        }
        
        @synchronized(gSyncLock) {
            NSMutableDictionary *result = gAuthResults[@(authResult.value)];
            NSString *token = result[@"accessToken"] ?: @"";
            NSString *headerStr = [NSString stringWithFormat:@"Bearer %@", token];
            wchar_t *header = nsstringToWstring(headerStr);
            int32_t requiredSize = (int32_t)(wcslen(header) + 1) * sizeof(wchar_t);
            
            if (authHeader == NULL || *bufferSize < requiredSize) {
                *bufferSize = requiredSize;
                free(header);
                gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
                return gLastError;
            }
            
            wcscpy(authHeader, header);
            *bufferSize = requiredSize;
            free(header);
            
            gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
            return gLastError;
        }
    }
}

// ============================================================================
// MSALRuntimeReadAccountResult API Implementation
// ============================================================================

MSALMacErrorHandle MSALMACRUNTIME_ReleaseReadAccountResult(int64_t readAccountResultHandle) {
    @synchronized(gSyncLock) {
        [gReadAccountResults removeObjectForKey:@(readAccountResultHandle)];
    }
    gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
    return gLastError;
}

MSALMacErrorHandle MSALMACRUNTIME_GetReadAccount(
    MSALMacReadAccountResultHandle readAccountResultHandle,
    MSALMacAccountHandle *account) {
    
    if (account == NULL) {
        setError(MSALMAC_RESPONSE_STATUS_ERROR, 34, 34, "Null account handle pointer");
        return gLastError;
    }
    
    @synchronized(gSyncLock) {
        NSMutableDictionary *readResult = gReadAccountResults[@(readAccountResultHandle.value)];
        if (readResult == nil) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 35, 35, "Read account result not found");
            return gLastError;
        }
        
        int64_t acctHandle = generateHandle();
        gAccounts[@(acctHandle)] = readResult;
        account->value = acctHandle;
        
        gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
        return gLastError;
    }
}

MSALMacErrorHandle MSALMACRUNTIME_GetReadAccountError(
    MSALMacReadAccountResultHandle readAccountResultHandle,
    MSALMacErrorHandleValue *errorHandle) {
    
    if (errorHandle == NULL) {
        setError(MSALMAC_RESPONSE_STATUS_ERROR, 36, 36, "Null error handle pointer");
        return gLastError;
    }
    
    @synchronized(gSyncLock) {
        NSMutableDictionary *readResult = gReadAccountResults[@(readAccountResultHandle.value)];
        if (readResult == nil || readResult[@"error"] == nil) {
            errorHandle->value = 0;
            gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
            return gLastError;
        }
        
        int64_t errHandle = generateHandle();
        errorHandle->value = errHandle;
        gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
        return gLastError;
    }
}

// ============================================================================
// MSALRuntimeSignoutResult API Implementation
// ============================================================================

MSALMacErrorHandle MSALMACRUNTIME_ReleaseSignOutResult(int64_t signOutResultHandle) {
    @synchronized(gSyncLock) {
        [gSignOutResults removeObjectForKey:@(signOutResultHandle)];
    }
    gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
    return gLastError;
}

MSALMacErrorHandle MSALMACRUNTIME_GetSignOutError(
    MSALMacSignOutResultHandle signOutResultHandle,
    MSALMacErrorHandleValue *errorHandle) {
    
    if (errorHandle == NULL) {
        setError(MSALMAC_RESPONSE_STATUS_ERROR, 37, 37, "Null error handle pointer");
        return gLastError;
    }
    
    @synchronized(gSyncLock) {
        NSMutableDictionary *signOutResult = gSignOutResults[@(signOutResultHandle.value)];
        if (signOutResult == nil || signOutResult[@"error"] == nil) {
            errorHandle->value = 0;
            gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
            return gLastError;
        }
        
        int64_t errHandle = generateHandle();
        errorHandle->value = errHandle;
        gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
        return gLastError;
    }
}

// ============================================================================
// MSALRuntimeLogging API Implementation
// ============================================================================

MSALMacErrorHandle MSALMACRUNTIME_RegisterLogCallback(
    LogCallback callback,
    int32_t callbackData,
    LogCallbackHandle *logCallbackHandle) {
    
    if (callback == NULL || logCallbackHandle == NULL) {
        setError(MSALMAC_RESPONSE_STATUS_ERROR, 38, 38, "Null callback or handle pointer");
        return gLastError;
    }
    
    @synchronized(gSyncLock) {
        if (gLogCallbackContext != NULL) {
            free(gLogCallbackContext);
        }
        
        gLogCallbackContext = malloc(sizeof(LogCallbackContext));
        gLogCallbackContext->callback = callback;
        gLogCallbackContext->callbackData = callbackData;
        
        int64_t logHandle = generateHandle();
        logCallbackHandle->value = logHandle;
        
        gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
        return gLastError;
    }
}

MSALMacErrorHandle MSALMACRUNTIME_ReleaseLogCallbackHandle(int64_t logCallbackHandle) {
    @synchronized(gSyncLock) {
        if (gLogCallbackContext != NULL) {
            free(gLogCallbackContext);
            gLogCallbackContext = NULL;
        }
    }
    gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
    return gLastError;
}

void MSALMACRUNTIME_SetIsPiiEnabled(int32_t enabled) {
    NSLog(@"[MSAL Broker] PII logging %s", enabled == 1 ? "enabled" : "disabled");
}
