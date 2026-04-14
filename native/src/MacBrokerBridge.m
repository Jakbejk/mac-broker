#include "MacBrokerBridge.h"

#import <Cocoa/Cocoa.h>
#import "Msal4JRuntimeWindowController.h"
#import "Msal4JTokenExchange.h"

#include <dispatch/dispatch.h>
#include <wchar.h>
#include <string.h>
#include <ctype.h>

typedef NS_ENUM(int64_t, MBRuntimeErrorCode) {
    MBRuntimeErrorCodeInvalidArgument = -1000,
    MBRuntimeErrorCodeNotStarted = -1001,
    MBRuntimeErrorCodeNotFound = -1002,
    MBRuntimeErrorCodeCancelled = -1003,
    MBRuntimeErrorCodeInteractiveRequired = -1004,
    MBRuntimeErrorCodeInternal = -1099,
};

typedef NS_ENUM(int32_t, MBRuntimeErrorTag) {
    MBRuntimeErrorTagGeneral = 1,
    MBRuntimeErrorTagArguments = 2,
    MBRuntimeErrorTagOperation = 3,
    MBRuntimeErrorTagState = 4,
};

@interface MBError : NSObject
@property (nonatomic, assign) MSALMacResponseStatus responseStatus;
@property (nonatomic, assign) int64_t errorCode;
@property (nonatomic, assign) int32_t tag;
@property (nonatomic, copy) NSString *context;
@end

@implementation MBError

- (void)dealloc {
    [_context release];
    [super dealloc];
}

@end

@interface MBAccount : NSObject
@property (nonatomic, copy) NSString *accountId;
@property (nonatomic, copy) NSString *clientInfo;
@property (nonatomic, copy) NSString *username;
@end

@implementation MBAccount

- (void)dealloc {
    [_accountId release];
    [_clientInfo release];
    [_username release];
    [super dealloc];
}

@end

@interface MBAuthParameters : NSObject
@property (nonatomic, copy) NSString *clientId;
@property (nonatomic, copy) NSString *authority;
@property (nonatomic, copy) NSString *requestedScopes;
@property (nonatomic, copy) NSString *redirectUri;
@property (nonatomic, copy) NSString *decodedClaims;
@property (nonatomic, retain) NSMutableDictionary *additionalParameters;
@property (nonatomic, copy) NSString *popHttpMethod;
@property (nonatomic, copy) NSString *popUriHost;
@property (nonatomic, copy) NSString *popUriPath;
@property (nonatomic, copy) NSString *popNonce;
@end

@implementation MBAuthParameters

- (instancetype)init {
    self = [super init];
    if (!self) { return nil; }
    _additionalParameters = [[NSMutableDictionary alloc] init];
    return self;
}

- (void)dealloc {
    [_clientId release];
    [_authority release];
    [_requestedScopes release];
    [_redirectUri release];
    [_decodedClaims release];
    [_additionalParameters release];
    [_popHttpMethod release];
    [_popUriHost release];
    [_popUriPath release];
    [_popNonce release];
    [super dealloc];
}

@end

@interface MBAuthResult : NSObject
@property (nonatomic, retain) MBAccount *account;
@property (nonatomic, copy) NSString *rawIdToken;
@property (nonatomic, copy) NSString *accessToken;
@property (nonatomic, retain) MBError *error;
@property (nonatomic, assign) BOOL isPopAuthorization;
@property (nonatomic, copy) NSString *authorizationHeader;
@end

@implementation MBAuthResult

- (void)dealloc {
    [_account release];
    [_rawIdToken release];
    [_accessToken release];
    [_error release];
    [_authorizationHeader release];
    [super dealloc];
}

@end

@interface MBReadAccountResult : NSObject
@property (nonatomic, retain) MBAccount *account;
@property (nonatomic, retain) MBError *error;
@end

@implementation MBReadAccountResult

- (void)dealloc {
    [_account release];
    [_error release];
    [super dealloc];
}

@end

@interface MBSignOutResult : NSObject
@property (nonatomic, retain) MBError *error;
@end

@implementation MBSignOutResult

- (void)dealloc {
    [_error release];
    [super dealloc];
}

@end

@interface MBAsyncOperation : NSObject
@property (nonatomic, assign) int64_t handleValue;
@property (nonatomic, assign) BOOL cancelled;
@property (nonatomic, assign) BOOL completed;
@property (nonatomic, retain) Msal4JRuntimeWindowController *windowController;
@property (nonatomic, retain) Msal4JTokenExchange *tokenExchange;
@end

@implementation MBAsyncOperation

- (void)dealloc {
    [_windowController release];
    [_tokenExchange release];
    [super dealloc];
}

@end

@interface MBLogSubscription : NSObject
@property (nonatomic, assign) LogCallback callback;
@property (nonatomic, assign) int32_t callbackData;
@end

@implementation MBLogSubscription
@end

static dispatch_queue_t gStateQueue = nil;
static NSMutableDictionary *gHandleStore = nil;            // NSNumber(handle) -> NSObject
static NSMutableDictionary *gAccountsById = nil;           // NSString(accountId) -> MBAccount
static NSMutableDictionary *gAuthResultsByAccountId = nil; // NSString(accountId) -> MBAuthResult
static NSMutableDictionary *gLogSubscriptions = nil;       // NSNumber(handle) -> MBLogSubscription
static int64_t gNextHandleValue = 1;
static BOOL gStarted = NO;
static BOOL gPiiEnabled = NO;

static MSALMacErrorHandle MBStatusHandle(MSALMacResponseStatus status) {
    MSALMacErrorHandle handle;
    handle.status = (int32_t)status;
    return handle;
}

static MSALMacErrorHandle MBSuccessHandle(void) {
    return MBStatusHandle(MSALMAC_RESPONSE_STATUS_SUCCESS);
}

static MSALMacErrorHandle MBFailureHandle(void) {
    return MBStatusHandle(MSALMAC_RESPONSE_STATUS_ERROR);
}

static void MBInitializeState(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        gStateQueue = dispatch_queue_create("com.msal4j.macbroker.bridge.state", DISPATCH_QUEUE_SERIAL);
        gHandleStore = [[NSMutableDictionary alloc] init];
        gAccountsById = [[NSMutableDictionary alloc] init];
        gAuthResultsByAccountId = [[NSMutableDictionary alloc] init];
        gLogSubscriptions = [[NSMutableDictionary alloc] init];
    });
}

static BOOL MBIsStarted(void) {
    MBInitializeState();
    __block BOOL started = NO;
    dispatch_sync(gStateQueue, ^{
        started = gStarted;
    });
    return started;
}

static int64_t MBStoreHandleObject(id object) {
    if (!object) { return 0; }
    MBInitializeState();
    __block int64_t handleValue = 0;
    dispatch_sync(gStateQueue, ^{
        handleValue = gNextHandleValue++;
        [gHandleStore setObject:object forKey:[NSNumber numberWithLongLong:handleValue]];
    });
    return handleValue;
}

static id MBCopyHandleObject(int64_t handleValue, Class expectedClass) {
    if (handleValue == 0) { return nil; }
    MBInitializeState();
    __block id object = nil;
    dispatch_sync(gStateQueue, ^{
        object = [[gHandleStore objectForKey:[NSNumber numberWithLongLong:handleValue]] retain];
    });
    if (!object) { return nil; }
    if (expectedClass && ![object isKindOfClass:expectedClass]) {
        [object release];
        return nil;
    }
    return [object autorelease];
}

static BOOL MBRemoveHandleObject(int64_t handleValue, Class expectedClass) {
    if (handleValue == 0) { return YES; }
    MBInitializeState();
    __block BOOL removed = NO;
    dispatch_sync(gStateQueue, ^{
        NSNumber *key = [NSNumber numberWithLongLong:handleValue];
        id object = [gHandleStore objectForKey:key];
        if (!object) { return; }
        if (expectedClass && ![object isKindOfClass:expectedClass]) { return; }
        [gHandleStore removeObjectForKey:key];
        removed = YES;
    });
    return removed;
}

static NSString *MBStringFromWide(const wchar_t *value) {
    if (!value) { return nil; }
    size_t len = wcslen(value);
    if (len == 0) { return @""; }
    NSData *data = [NSData dataWithBytes:value length:len * sizeof(wchar_t)];
    NSString *string = [[[NSString alloc] initWithData:data encoding:NSUTF32LittleEndianStringEncoding] autorelease];
    if (!string) {
        string = [[[NSString alloc] initWithData:data encoding:NSUTF32BigEndianStringEncoding] autorelease];
    }
    return string;
}

static NSString *MBNonNilStringFromWide(const wchar_t *value) {
    NSString *str = MBStringFromWide(value);
    return str ?: @"";
}

static MSALMacErrorHandle MBCopyStringToWideBuffer(NSString *value, wchar_t *buffer, int32_t *bufferSize) {
    if (!bufferSize) {
        return MBFailureHandle();
    }

    NSString *safeValue = value ?: @"";
    NSData *utf32Data = [safeValue dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
    if (!utf32Data) {
        utf32Data = [NSData data];
    }

    int32_t requiredLength = (int32_t)(utf32Data.length / sizeof(wchar_t)) + 1;
    if (!buffer || *bufferSize < requiredLength) {
        *bufferSize = requiredLength;
        return MBSuccessHandle();
    }

    if (utf32Data.length > 0) {
        memcpy(buffer, utf32Data.bytes, utf32Data.length);
    }
    buffer[requiredLength - 1] = L'\0';
    *bufferSize = requiredLength;
    return MBSuccessHandle();
}

static wchar_t *MBCreateWideHeapString(NSString *value) {
    NSString *safeValue = value ?: @"";
    NSData *utf32Data = [safeValue dataUsingEncoding:NSUTF32LittleEndianStringEncoding];
    if (!utf32Data) {
        utf32Data = [NSData data];
    }
    size_t charCount = utf32Data.length / sizeof(wchar_t);
    wchar_t *output = (wchar_t *)calloc(charCount + 1, sizeof(wchar_t));
    if (!output) { return NULL; }
    if (utf32Data.length > 0) {
        memcpy(output, utf32Data.bytes, utf32Data.length);
    }
    output[charCount] = L'\0';
    return output;
}

static MBError *MBCreateError(MSALMacResponseStatus status,
                              int64_t code,
                              int32_t tag,
                              NSString *context) {
    MBError *error = [[[MBError alloc] init] autorelease];
    error.responseStatus = status;
    error.errorCode = code;
    error.tag = tag;
    error.context = context ?: @"";
    return error;
}

static MBError *MBCreateCancelledError(NSString *context) {
    return MBCreateError(
        MSALMAC_RESPONSE_STATUS_CANCELLED,
        MBRuntimeErrorCodeCancelled,
        MBRuntimeErrorTagOperation,
        context ?: @"Operation cancelled"
    );
}

static MBError *MBCreateNSErrorWrappedError(NSError *error) {
    if (!error) {
        return MBCreateError(MSALMAC_RESPONSE_STATUS_ERROR,
                             MBRuntimeErrorCodeInternal,
                             MBRuntimeErrorTagGeneral,
                             @"Unknown runtime error");
    }
    BOOL cancelled = (error.code == NSUserCancelledError || error.code == -1);
    return MBCreateError(
        cancelled ? MSALMAC_RESPONSE_STATUS_CANCELLED : MSALMAC_RESPONSE_STATUS_ERROR,
        error.code,
        MBRuntimeErrorTagGeneral,
        error.localizedDescription ?: @"Unknown runtime error"
    );
}

static MBAuthResult *MBCreateAuthResultSuccess(MBAccount *account,
                                               NSString *accessToken,
                                               NSString *idToken,
                                               BOOL isPopAuthorization) {
    MBAuthResult *result = [[[MBAuthResult alloc] init] autorelease];
    result.account = account;
    result.accessToken = accessToken ?: @"";
    result.rawIdToken = idToken ?: @"";
    result.isPopAuthorization = isPopAuthorization;
    NSString *headerPrefix = isPopAuthorization ? @"PoP" : @"Bearer";
    if ((accessToken ?: @"").length > 0) {
        result.authorizationHeader = [NSString stringWithFormat:@"%@ %@", headerPrefix, accessToken];
    } else {
        result.authorizationHeader = @"";
    }
    return result;
}

static MBAuthResult *MBCreateAuthResultError(MBError *error) {
    MBAuthResult *result = [[[MBAuthResult alloc] init] autorelease];
    result.error = error;
    result.rawIdToken = @"";
    result.accessToken = @"";
    result.authorizationHeader = @"";
    result.isPopAuthorization = NO;
    return result;
}

static MBReadAccountResult *MBCreateReadAccountResult(MBAccount *account, MBError *error) {
    MBReadAccountResult *result = [[[MBReadAccountResult alloc] init] autorelease];
    result.account = account;
    result.error = error;
    return result;
}

static MBSignOutResult *MBCreateSignOutResult(MBError *error) {
    MBSignOutResult *result = [[[MBSignOutResult alloc] init] autorelease];
    result.error = error;
    return result;
}

static BOOL MBAsyncTryComplete(MBAsyncOperation *operation) {
    if (!operation) { return NO; }
    @synchronized (operation) {
        if (operation.completed) { return NO; }
        operation.completed = YES;
        return YES;
    }
}

static BOOL MBAsyncIsCancelled(MBAsyncOperation *operation) {
    if (!operation) { return YES; }
    @synchronized (operation) {
        return operation.cancelled;
    }
}

static void MBAsyncCancel(MBAsyncOperation *operation) {
    if (!operation) { return; }
    @synchronized (operation) {
        operation.cancelled = YES;
    }
}

static NSString *MBTrimTrailingSlash(NSString *value) {
    NSString *result = value ?: @"";
    while (result.length > 0 && [result hasSuffix:@"/"]) {
        result = [result substringToIndex:result.length - 1];
    }
    return result;
}

static NSString *MBAuthorizeEndpointFromAuthority(NSString *authority) {
    if (!authority.length) { return nil; }
    NSString *normalized = MBTrimTrailingSlash(authority);
    if ([normalized hasSuffix:@"/oauth2/v2.0/authorize"]) {
        return normalized;
    }
    if ([normalized hasSuffix:@"/oauth2/v2.0"]) {
        return [normalized stringByAppendingString:@"/authorize"];
    }
    return [normalized stringByAppendingString:@"/oauth2/v2.0/authorize"];
}

static NSString *MBTokenEndpointFromAuthority(NSString *authority) {
    if (!authority.length) { return nil; }
    NSString *normalized = MBTrimTrailingSlash(authority);
    if ([normalized hasSuffix:@"/oauth2/v2.0/token"]) {
        return normalized;
    }
    if ([normalized hasSuffix:@"/oauth2/v2.0"]) {
        return [normalized stringByAppendingString:@"/token"];
    }
    return [normalized stringByAppendingString:@"/oauth2/v2.0/token"];
}

static NSString *MBDefaultRedirectUriForClient(NSString *clientId) {
    if (!clientId.length) { return @""; }
    return [NSString stringWithFormat:@"msauth.%@://auth", clientId];
}

static NSDictionary *MBJWTClaims(NSString *idToken) {
    if (idToken.length == 0) { return nil; }
    NSArray *parts = [idToken componentsSeparatedByString:@"."];
    if (parts.count < 2) { return nil; }
    NSString *payload = [parts objectAtIndex:1];
    payload = [payload stringByReplacingOccurrencesOfString:@"-" withString:@"+"];
    payload = [payload stringByReplacingOccurrencesOfString:@"_" withString:@"/"];
    while ((payload.length % 4) != 0) {
        payload = [payload stringByAppendingString:@"="];
    }

    NSData *decoded = [[[NSData alloc] initWithBase64EncodedString:payload options:0] autorelease];
    if (!decoded) { return nil; }

    NSError *jsonError = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:decoded options:0 error:&jsonError];
    if (jsonError || ![obj isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    return (NSDictionary *)obj;
}

static NSString *MBNormalizedPrompt(NSString *prompt) {
    if (!prompt.length) { return nil; }
    return [[prompt stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
}

static Msal4JPromptBehavior MBPromptBehaviorFromAuthParameters(MBAuthParameters *authParameters,
                                                               Msal4JPromptBehavior fallback) {
    NSString *prompt = MBNormalizedPrompt([authParameters.additionalParameters objectForKey:@"prompt"]);
    if (!prompt.length) { return fallback; }
    if ([prompt isEqualToString:@"login"]) { return Msal4JPromptBehaviorLogin; }
    if ([prompt isEqualToString:@"select_account"]) { return Msal4JPromptBehaviorSelectAccount; }
    if ([prompt isEqualToString:@"consent"]) { return Msal4JPromptBehaviorConsent; }
    if ([prompt isEqualToString:@"none"]) { return Msal4JPromptBehaviorNone; }
    if ([prompt isEqualToString:@"create"]) { return Msal4JPromptBehaviorCreate; }
    return fallback;
}

static NSString *MBPreferredUsernameFromClaims(NSDictionary *claims) {
    NSString *preferred = [claims objectForKey:@"preferred_username"];
    if (preferred.length > 0) { return preferred; }
    NSString *upn = [claims objectForKey:@"upn"];
    if (upn.length > 0) { return upn; }
    NSString *email = [claims objectForKey:@"email"];
    if (email.length > 0) { return email; }
    return nil;
}

static MBAccount *MBAccountFromTokenSet(Msal4JTokenSet *tokenSet) {
    NSDictionary *claims = MBJWTClaims(tokenSet.idToken ?: @"");
    NSString *oid = [claims objectForKey:@"oid"];
    NSString *sub = [claims objectForKey:@"sub"];
    NSString *tid = [claims objectForKey:@"tid"];

    NSString *uidPart = oid.length > 0 ? oid : (sub.length > 0 ? sub : nil);
    NSString *utidPart = tid.length > 0 ? tid : nil;

    NSString *accountId = nil;
    if (uidPart.length > 0 && utidPart.length > 0) {
        accountId = [NSString stringWithFormat:@"%@.%@", uidPart, utidPart];
    } else if (uidPart.length > 0) {
        accountId = uidPart;
    } else {
        accountId = [[NSUUID UUID] UUIDString];
    }

    MBAccount *account = [[[MBAccount alloc] init] autorelease];
    account.accountId = accountId;
    account.username = MBPreferredUsernameFromClaims(claims);

    NSDictionary *clientInfoDict = [NSDictionary dictionaryWithObjectsAndKeys:
        uidPart ?: @"", @"uid",
        utidPart ?: @"", @"utid",
        nil
    ];
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:clientInfoDict options:0 error:nil];
    if (jsonData.length > 0) {
        account.clientInfo = [[[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] autorelease];
    } else {
        account.clientInfo = @"{}";
    }
    return account;
}

static void MBCacheAccountAndAuthResult(MBAccount *account, MBAuthResult *authResult) {
    if (!account.accountId.length || !authResult) { return; }
    MBInitializeState();
    dispatch_sync(gStateQueue, ^{
        [gAccountsById setObject:account forKey:account.accountId];
        [gAuthResultsByAccountId setObject:authResult forKey:account.accountId];
    });
}

static MBAccount *MBCopyCachedAccountById(NSString *accountId) {
    if (!accountId.length) { return nil; }
    MBInitializeState();
    __block MBAccount *account = nil;
    dispatch_sync(gStateQueue, ^{
        account = [[gAccountsById objectForKey:accountId] retain];
    });
    return [account autorelease];
}

static MBAuthResult *MBCopyCachedAuthResultByAccountId(NSString *accountId) {
    if (!accountId.length) { return nil; }
    MBInitializeState();
    __block MBAuthResult *result = nil;
    dispatch_sync(gStateQueue, ^{
        result = [[gAuthResultsByAccountId objectForKey:accountId] retain];
    });
    return [result autorelease];
}

static MBAuthResult *MBCopyAnyCachedAuthResult(void) {
    MBInitializeState();
    __block MBAuthResult *result = nil;
    dispatch_sync(gStateQueue, ^{
        NSString *key = [[gAuthResultsByAccountId allKeys] firstObject];
        if (key) {
            result = [[gAuthResultsByAccountId objectForKey:key] retain];
        }
    });
    return [result autorelease];
}

static MBAuthResult *MBCopyCachedAuthResultForHint(NSString *hint) {
    NSString *normalizedHint = [[hint ?: @"" lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (normalizedHint.length == 0) {
        return MBCopyAnyCachedAuthResult();
    }
    MBInitializeState();
    __block MBAuthResult *match = nil;
    dispatch_sync(gStateQueue, ^{
        for (MBAuthResult *result in [gAuthResultsByAccountId allValues]) {
            NSString *accountId = [[result.account.accountId ?: @"" lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSString *username = [[result.account.username ?: @"" lowercaseString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([accountId isEqualToString:normalizedHint] || [username isEqualToString:normalizedHint]) {
                match = [result retain];
                break;
            }
        }
    });
    return [match autorelease];
}

static void MBRemoveCachedStateForAccountId(NSString *accountId) {
    if (!accountId.length) { return; }
    MBInitializeState();
    dispatch_sync(gStateQueue, ^{
        [gAccountsById removeObjectForKey:accountId];
        [gAuthResultsByAccountId removeObjectForKey:accountId];
    });
}

static BOOL MBCreateAsyncOperation(MSALMacAsyncHandle *asyncHandle, MBAsyncOperation **operationOut) {
    MBAsyncOperation *operation = [[[MBAsyncOperation alloc] init] autorelease];
    int64_t handleValue = MBStoreHandleObject(operation);
    operation.handleValue = handleValue;
    if (asyncHandle) {
        asyncHandle->value = handleValue;
    }
    if (operationOut) {
        *operationOut = operation;
    }
    return YES;
}

static void MBEmitLog(int32_t level, NSString *message, BOOL containsPii) {
    MBInitializeState();

    __block BOOL piiEnabled = NO;
    __block NSArray *subscriptions = nil;
    dispatch_sync(gStateQueue, ^{
        piiEnabled = gPiiEnabled;
        subscriptions = [[gLogSubscriptions allValues] copy];
    });

    if (containsPii && !piiEnabled) {
        [subscriptions release];
        return;
    }

    wchar_t *wideMessage = MBCreateWideHeapString(message ?: @"");
    for (MBLogSubscription *subscription in subscriptions) {
        if (subscription.callback) {
            subscription.callback(level, wideMessage ?: L"", subscription.callbackData);
        }
    }
    if (wideMessage) { free(wideMessage); }

    NSLog(@"[MacBrokerBridge][%d] %@", level, message ?: @"");
    [subscriptions release];
}

static void MBDispatchAuthCallback(MBAsyncOperation *operation,
                                   AuthResultCallback callback,
                                   int32_t callbackData,
                                   MBAuthResult *authResult,
                                   MSALMacResponseStatus status) {
    if (!operation || !callback) { return; }
    if (!MBAsyncTryComplete(operation)) { return; }

    operation.windowController = nil;
    operation.tokenExchange = nil;

    int64_t authResultHandle = MBStoreHandleObject(authResult ?: [[[MBAuthResult alloc] init] autorelease]);
    dispatch_async(dispatch_get_main_queue(), ^{
        callback(authResultHandle, callbackData, status);
    });
}

static void MBDispatchReadAccountCallback(MBAsyncOperation *operation,
                                          ReadAccountResultCallback callback,
                                          int32_t callbackData,
                                          MBReadAccountResult *readResult,
                                          MSALMacResponseStatus status) {
    if (!operation || !callback) { return; }
    if (!MBAsyncTryComplete(operation)) { return; }

    int64_t readHandle = MBStoreHandleObject(readResult ?: [[[MBReadAccountResult alloc] init] autorelease]);
    dispatch_async(dispatch_get_main_queue(), ^{
        callback(readHandle, callbackData, status);
    });
}

static void MBDispatchSignOutCallback(MBAsyncOperation *operation,
                                      SignOutResultCallback callback,
                                      int32_t callbackData,
                                      MBSignOutResult *signOutResult,
                                      MSALMacResponseStatus status) {
    if (!operation || !callback) { return; }
    if (!MBAsyncTryComplete(operation)) { return; }

    int64_t signOutHandle = MBStoreHandleObject(signOutResult ?: [[[MBSignOutResult alloc] init] autorelease]);
    dispatch_async(dispatch_get_main_queue(), ^{
        callback(signOutHandle, callbackData, status);
    });
}

static NSString *MBBuildAuthorizationURL(MBAuthParameters *authParameters,
                                         NSString *accountHint) {
    NSString *authorizeEndpoint = MBAuthorizeEndpointFromAuthority(authParameters.authority);
    if (!authorizeEndpoint.length) { return nil; }

    NSURLComponents *components = [NSURLComponents componentsWithString:authorizeEndpoint];
    if (!components) { return nil; }

    NSMutableArray *items = [NSMutableArray array];
    [items addObject:[NSURLQueryItem queryItemWithName:@"client_id" value:authParameters.clientId ?: @""]];
    [items addObject:[NSURLQueryItem queryItemWithName:@"response_type" value:@"code"]];
    [items addObject:[NSURLQueryItem queryItemWithName:@"redirect_uri" value:authParameters.redirectUri ?: @""]];

    NSString *scopes = authParameters.requestedScopes.length > 0
                       ? authParameters.requestedScopes
                       : @"openid profile offline_access";
    [items addObject:[NSURLQueryItem queryItemWithName:@"scope" value:scopes]];

    if (accountHint.length > 0) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"login_hint" value:accountHint]];
    }
    if (authParameters.decodedClaims.length > 0) {
        [items addObject:[NSURLQueryItem queryItemWithName:@"claims" value:authParameters.decodedClaims]];
    }

    for (NSString *key in authParameters.additionalParameters) {
        NSString *lowerKey = [key lowercaseString];
        if ([lowerKey isEqualToString:@"prompt"] || [lowerKey isEqualToString:@"code_verifier"]) {
            continue;
        }
        NSString *value = [authParameters.additionalParameters objectForKey:key];
        if (value.length > 0) {
            [items addObject:[NSURLQueryItem queryItemWithName:key value:value]];
        }
    }

    components.queryItems = items;
    return components.URL.absoluteString;
}

static void MBStartInteractiveFlow(MBAsyncOperation *operation,
                                   MBAuthParameters *authParameters,
                                   NSString *accountHint,
                                   Msal4JPromptBehavior promptBehavior,
                                   AuthResultCallback callback,
                                   int32_t callbackData) {
    NSString *authURL = MBBuildAuthorizationURL(authParameters, accountHint);
    NSString *tokenEndpoint = MBTokenEndpointFromAuthority(authParameters.authority);

    if (!authURL.length || !tokenEndpoint.length || !authParameters.clientId.length || !authParameters.redirectUri.length) {
        MBError *error = MBCreateError(
            MSALMAC_RESPONSE_STATUS_ERROR,
            MBRuntimeErrorCodeInvalidArgument,
            MBRuntimeErrorTagArguments,
            @"Auth parameters are incomplete for interactive flow"
        );
        MBDispatchAuthCallback(operation, callback, callbackData, MBCreateAuthResultError(error), MSALMAC_RESPONSE_STATUS_ERROR);
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (MBAsyncIsCancelled(operation)) {
            MBDispatchAuthCallback(
                operation,
                callback,
                callbackData,
                MBCreateAuthResultError(MBCreateCancelledError(@"Interactive sign-in cancelled before start")),
                MSALMAC_RESPONSE_STATUS_CANCELLED
            );
            return;
        }

        [NSApplication sharedApplication];

        Msal4JRuntimeWindowController *controller =
            [[[Msal4JRuntimeWindowController alloc]
                initWithAuthURL:authURL
                    redirectURI:authParameters.redirectUri
                 promptBehavior:promptBehavior
              completionHandler:^(NSString *authCode, NSError *authError) {
            if (MBAsyncIsCancelled(operation)) {
                MBDispatchAuthCallback(
                    operation,
                    callback,
                    callbackData,
                    MBCreateAuthResultError(MBCreateCancelledError(@"Interactive sign-in cancelled")),
                    MSALMAC_RESPONSE_STATUS_CANCELLED
                );
                return;
            }

            if (authError || authCode.length == 0) {
                MBError *error = authError
                    ? MBCreateNSErrorWrappedError(authError)
                    : MBCreateError(MSALMAC_RESPONSE_STATUS_ERROR,
                                    MBRuntimeErrorCodeInternal,
                                    MBRuntimeErrorTagOperation,
                                    @"Authorization code was not returned");
                MBDispatchAuthCallback(
                    operation,
                    callback,
                    callbackData,
                    MBCreateAuthResultError(error),
                    error.responseStatus
                );
                return;
            }

            Msal4JTokenExchange *exchange =
                [[[Msal4JTokenExchange alloc]
                    initWithTokenEndpoint:tokenEndpoint
                                 clientId:authParameters.clientId
                              redirectURI:authParameters.redirectUri] autorelease];
            operation.tokenExchange = exchange;

            NSString *codeVerifier = [authParameters.additionalParameters objectForKey:@"code_verifier"];
            [exchange exchangeCode:authCode
                      codeVerifier:(codeVerifier.length > 0 ? codeVerifier : nil)
                        completion:^(Msal4JTokenSet *tokenSet, NSError *tokenError) {
                if (MBAsyncIsCancelled(operation)) {
                    MBDispatchAuthCallback(
                        operation,
                        callback,
                        callbackData,
                        MBCreateAuthResultError(MBCreateCancelledError(@"Token exchange cancelled")),
                        MSALMAC_RESPONSE_STATUS_CANCELLED
                    );
                    return;
                }

                if (tokenError || !tokenSet) {
                    MBError *wrapped = tokenError
                        ? MBCreateNSErrorWrappedError(tokenError)
                        : MBCreateError(MSALMAC_RESPONSE_STATUS_ERROR,
                                        MBRuntimeErrorCodeInternal,
                                        MBRuntimeErrorTagOperation,
                                        @"Token exchange failed");
                    MBDispatchAuthCallback(
                        operation,
                        callback,
                        callbackData,
                        MBCreateAuthResultError(wrapped),
                        wrapped.responseStatus
                    );
                    return;
                }

                MBAccount *account = MBAccountFromTokenSet(tokenSet);
                BOOL isPopAuthorization = (authParameters.popHttpMethod.length > 0);
                MBAuthResult *result = MBCreateAuthResultSuccess(
                    account,
                    tokenSet.accessToken ?: @"",
                    tokenSet.idToken ?: @"",
                    isPopAuthorization
                );

                MBCacheAccountAndAuthResult(account, result);
                MBDispatchAuthCallback(operation, callback, callbackData, result, MSALMAC_RESPONSE_STATUS_SUCCESS);
            }];
        }] autorelease];

        operation.windowController = controller;
        [controller showWindow:nil];
    });
}

MSALMacErrorHandle MSALMACRUNTIME_Startup(void) {
    MBInitializeState();
    dispatch_sync(gStateQueue, ^{
        gStarted = YES;
    });
    MBEmitLog(1, @"MSALMACRUNTIME_Startup completed", NO);
    return MBSuccessHandle();
}

void MSALMACRUNTIME_Shutdown(void) {
    MBInitializeState();

    __block NSArray *handleObjects = nil;
    dispatch_sync(gStateQueue, ^{
        gStarted = NO;
        handleObjects = [[gHandleStore allValues] copy];
        [gHandleStore removeAllObjects];
        [gAccountsById removeAllObjects];
        [gAuthResultsByAccountId removeAllObjects];
        [gLogSubscriptions removeAllObjects];
    });

    dispatch_async(dispatch_get_main_queue(), ^{
        for (id object in handleObjects) {
            if ([object isKindOfClass:[MBAsyncOperation class]]) {
                MBAsyncOperation *operation = (MBAsyncOperation *)object;
                operation.cancelled = YES;
                if (operation.windowController.window) {
                    [operation.windowController.window close];
                }
            }
        }
        [handleObjects release];
    });
}

MSALMacErrorHandle MSALMACRUNTIME_ReadAccountByIdAsync(
    const wchar_t *accountId,
    const wchar_t *correlationId,
    ReadAccountResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle
) {
    (void)correlationId;

    if (!MBIsStarted() || !callback || !accountId) {
        if (asyncHandle) { asyncHandle->value = 0; }
        return MBFailureHandle();
    }

    MBAsyncOperation *operation = nil;
    MBCreateAsyncOperation(asyncHandle, &operation);

    NSString *accountIdString = MBStringFromWide(accountId);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (MBAsyncIsCancelled(operation)) {
            MBDispatchReadAccountCallback(
                operation,
                callback,
                callbackData,
                MBCreateReadAccountResult(nil, MBCreateCancelledError(@"Read account request cancelled")),
                MSALMAC_RESPONSE_STATUS_CANCELLED
            );
            return;
        }

        MBAccount *account = MBCopyCachedAccountById(accountIdString ?: @"");
        if (account) {
            MBDispatchReadAccountCallback(
                operation,
                callback,
                callbackData,
                MBCreateReadAccountResult(account, nil),
                MSALMAC_RESPONSE_STATUS_SUCCESS
            );
            return;
        }

        MBError *error = MBCreateError(
            MSALMAC_RESPONSE_STATUS_ERROR,
            MBRuntimeErrorCodeNotFound,
            MBRuntimeErrorTagOperation,
            @"Account not found"
        );
        MBDispatchReadAccountCallback(
            operation,
            callback,
            callbackData,
            MBCreateReadAccountResult(nil, error),
            MSALMAC_RESPONSE_STATUS_ERROR
        );
    });

    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_SignInAsync(
    int64_t parentWindowHandle,
    int64_t authParametersHandle,
    const wchar_t *correlationId,
    const wchar_t *accountHint,
    AuthResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle
) {
    (void)parentWindowHandle;
    (void)correlationId;

    if (!MBIsStarted() || !callback) {
        if (asyncHandle) { asyncHandle->value = 0; }
        return MBFailureHandle();
    }

    MBAuthParameters *params = MBCopyHandleObject(authParametersHandle, [MBAuthParameters class]);
    if (!params) {
        if (asyncHandle) { asyncHandle->value = 0; }
        return MBFailureHandle();
    }

    MBAsyncOperation *operation = nil;
    MBCreateAsyncOperation(asyncHandle, &operation);
    NSString *hint = MBStringFromWide(accountHint);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (MBAsyncIsCancelled(operation)) {
            MBDispatchAuthCallback(
                operation,
                callback,
                callbackData,
                MBCreateAuthResultError(MBCreateCancelledError(@"Sign-in request cancelled")),
                MSALMAC_RESPONSE_STATUS_CANCELLED
            );
            return;
        }

        MBAuthResult *cached = MBCopyCachedAuthResultForHint(hint);
        if (cached) {
            MBDispatchAuthCallback(operation, callback, callbackData, cached, MSALMAC_RESPONSE_STATUS_SUCCESS);
            return;
        }

        Msal4JPromptBehavior promptBehavior = MBPromptBehaviorFromAuthParameters(params, Msal4JPromptBehaviorDefault);
        MBStartInteractiveFlow(operation, params, hint, promptBehavior, callback, callbackData);
    });

    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_SignInSilentlyAsync(
    int64_t authParametersHandle,
    const wchar_t *correlationId,
    AuthResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle
) {
    (void)authParametersHandle;
    (void)correlationId;

    if (!MBIsStarted() || !callback) {
        if (asyncHandle) { asyncHandle->value = 0; }
        return MBFailureHandle();
    }

    MBAsyncOperation *operation = nil;
    MBCreateAsyncOperation(asyncHandle, &operation);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (MBAsyncIsCancelled(operation)) {
            MBDispatchAuthCallback(
                operation,
                callback,
                callbackData,
                MBCreateAuthResultError(MBCreateCancelledError(@"Silent sign-in cancelled")),
                MSALMAC_RESPONSE_STATUS_CANCELLED
            );
            return;
        }

        MBAuthResult *cached = MBCopyAnyCachedAuthResult();
        if (cached) {
            MBDispatchAuthCallback(operation, callback, callbackData, cached, MSALMAC_RESPONSE_STATUS_SUCCESS);
            return;
        }

        MBError *error = MBCreateError(
            MSALMAC_RESPONSE_STATUS_ERROR,
            MBRuntimeErrorCodeInteractiveRequired,
            MBRuntimeErrorTagOperation,
            @"No cached account or tokens. Interactive authentication required."
        );
        MBDispatchAuthCallback(
            operation,
            callback,
            callbackData,
            MBCreateAuthResultError(error),
            MSALMAC_RESPONSE_STATUS_ERROR
        );
    });

    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_SignInInteractivelyAsync(
    int64_t parentWindowHandle,
    int64_t authParametersHandle,
    const wchar_t *correlationId,
    const wchar_t *accountHint,
    AuthResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle
) {
    (void)parentWindowHandle;
    (void)correlationId;

    if (!MBIsStarted() || !callback) {
        if (asyncHandle) { asyncHandle->value = 0; }
        return MBFailureHandle();
    }

    MBAuthParameters *params = MBCopyHandleObject(authParametersHandle, [MBAuthParameters class]);
    if (!params) {
        if (asyncHandle) { asyncHandle->value = 0; }
        return MBFailureHandle();
    }

    MBAsyncOperation *operation = nil;
    MBCreateAsyncOperation(asyncHandle, &operation);

    NSString *hint = MBStringFromWide(accountHint);
    Msal4JPromptBehavior promptBehavior = MBPromptBehaviorFromAuthParameters(params, Msal4JPromptBehaviorDefault);
    MBStartInteractiveFlow(operation, params, hint, promptBehavior, callback, callbackData);

    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_AcquireTokenSilentlyAsync(
    int64_t authParametersHandle,
    const wchar_t *correlationId,
    int64_t accountHandle,
    AuthResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle
) {
    (void)authParametersHandle;
    (void)correlationId;

    if (!MBIsStarted() || !callback) {
        if (asyncHandle) { asyncHandle->value = 0; }
        return MBFailureHandle();
    }

    MBAsyncOperation *operation = nil;
    MBCreateAsyncOperation(asyncHandle, &operation);

    MBAccount *account = MBCopyHandleObject(accountHandle, [MBAccount class]);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (MBAsyncIsCancelled(operation)) {
            MBDispatchAuthCallback(
                operation,
                callback,
                callbackData,
                MBCreateAuthResultError(MBCreateCancelledError(@"Silent token acquisition cancelled")),
                MSALMAC_RESPONSE_STATUS_CANCELLED
            );
            return;
        }

        MBAuthResult *cached = nil;
        if (account.accountId.length > 0) {
            cached = MBCopyCachedAuthResultByAccountId(account.accountId);
        } else {
            cached = MBCopyAnyCachedAuthResult();
        }

        if (cached) {
            MBDispatchAuthCallback(operation, callback, callbackData, cached, MSALMAC_RESPONSE_STATUS_SUCCESS);
            return;
        }

        MBError *error = MBCreateError(
            MSALMAC_RESPONSE_STATUS_ERROR,
            MBRuntimeErrorCodeInteractiveRequired,
            MBRuntimeErrorTagOperation,
            @"No cached token available for requested account."
        );
        MBDispatchAuthCallback(
            operation,
            callback,
            callbackData,
            MBCreateAuthResultError(error),
            MSALMAC_RESPONSE_STATUS_ERROR
        );
    });

    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_AcquireTokenInteractivelyAsync(
    int64_t parentWindowHandle,
    int64_t authParametersHandle,
    const wchar_t *correlationId,
    int64_t accountHandle,
    AuthResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle
) {
    (void)parentWindowHandle;
    (void)correlationId;

    if (!MBIsStarted() || !callback) {
        if (asyncHandle) { asyncHandle->value = 0; }
        return MBFailureHandle();
    }

    MBAuthParameters *params = MBCopyHandleObject(authParametersHandle, [MBAuthParameters class]);
    if (!params) {
        if (asyncHandle) { asyncHandle->value = 0; }
        return MBFailureHandle();
    }

    MBAsyncOperation *operation = nil;
    MBCreateAsyncOperation(asyncHandle, &operation);

    MBAccount *account = MBCopyHandleObject(accountHandle, [MBAccount class]);
    NSString *accountHint = account.username.length > 0 ? account.username : account.accountId;
    Msal4JPromptBehavior fallbackPrompt = accountHint.length > 0
        ? Msal4JPromptBehaviorDefault
        : Msal4JPromptBehaviorSelectAccount;
    Msal4JPromptBehavior promptBehavior = MBPromptBehaviorFromAuthParameters(params, fallbackPrompt);

    MBStartInteractiveFlow(operation, params, accountHint, promptBehavior, callback, callbackData);
    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_SignOutSilentlyAsync(
    const wchar_t *clientId,
    const wchar_t *correlationId,
    int64_t accountHandle,
    SignOutResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle
) {
    (void)clientId;
    (void)correlationId;

    if (!MBIsStarted() || !callback) {
        if (asyncHandle) { asyncHandle->value = 0; }
        return MBFailureHandle();
    }

    MBAsyncOperation *operation = nil;
    MBCreateAsyncOperation(asyncHandle, &operation);

    MBAccount *account = MBCopyHandleObject(accountHandle, [MBAccount class]);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (MBAsyncIsCancelled(operation)) {
            MBDispatchSignOutCallback(
                operation,
                callback,
                callbackData,
                MBCreateSignOutResult(MBCreateCancelledError(@"Sign-out cancelled")),
                MSALMAC_RESPONSE_STATUS_CANCELLED
            );
            return;
        }

        if (account.accountId.length > 0) {
            MBRemoveCachedStateForAccountId(account.accountId);
        }

        MBDispatchSignOutCallback(
            operation,
            callback,
            callbackData,
            MBCreateSignOutResult(nil),
            MSALMAC_RESPONSE_STATUS_SUCCESS
        );
    });

    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_ReleaseAccount(int64_t accountHandle) {
    if (!MBIsStarted()) { return MBFailureHandle(); }
    return MBRemoveHandleObject(accountHandle, [MBAccount class]) ? MBSuccessHandle() : MBFailureHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_GetAccountId(
    int64_t accountHandle,
    wchar_t *accountId,
    int32_t *bufferSize
) {
    if (!MBIsStarted() || !bufferSize) { return MBFailureHandle(); }
    MBAccount *account = MBCopyHandleObject(accountHandle, [MBAccount class]);
    if (!account) { return MBFailureHandle(); }
    return MBCopyStringToWideBuffer(account.accountId ?: @"", accountId, bufferSize);
}

MSALMacErrorHandle MSALMACRUNTIME_GetClientInfo(
    int64_t accountHandle,
    wchar_t *clientInfo,
    int32_t *bufferSize
) {
    if (!MBIsStarted() || !bufferSize) { return MBFailureHandle(); }
    MBAccount *account = MBCopyHandleObject(accountHandle, [MBAccount class]);
    if (!account) { return MBFailureHandle(); }
    return MBCopyStringToWideBuffer(account.clientInfo ?: @"{}", clientInfo, bufferSize);
}

MSALMacErrorHandle MSALMACRUNTIME_CreateAuthParameters(
    const wchar_t *clientId,
    const wchar_t *authority,
    AuthParametersHandle *authParametersHandle
) {
    if (!MBIsStarted() || !clientId || !authority || !authParametersHandle) {
        if (authParametersHandle) { authParametersHandle->value = 0; }
        return MBFailureHandle();
    }

    NSString *clientIdString = MBStringFromWide(clientId);
    NSString *authorityString = MBStringFromWide(authority);
    if (clientIdString.length == 0 || authorityString.length == 0) {
        authParametersHandle->value = 0;
        return MBFailureHandle();
    }

    MBAuthParameters *params = [[[MBAuthParameters alloc] init] autorelease];
    params.clientId = clientIdString;
    params.authority = authorityString;
    params.requestedScopes = @"openid profile offline_access";
    params.redirectUri = MBDefaultRedirectUriForClient(clientIdString);
    params.decodedClaims = @"";

    authParametersHandle->value = MBStoreHandleObject(params);
    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_ReleaseAuthParameters(int64_t authParametersHandle) {
    if (!MBIsStarted()) { return MBFailureHandle(); }
    return MBRemoveHandleObject(authParametersHandle, [MBAuthParameters class]) ? MBSuccessHandle() : MBFailureHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_SetRequestedScopes(
    int64_t authParametersHandle,
    const wchar_t *scopes
) {
    if (!MBIsStarted()) { return MBFailureHandle(); }
    MBAuthParameters *params = MBCopyHandleObject(authParametersHandle, [MBAuthParameters class]);
    if (!params) { return MBFailureHandle(); }
    params.requestedScopes = MBNonNilStringFromWide(scopes);
    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_SetRedirectUri(
    int64_t authParametersHandle,
    const wchar_t *redirectUri
) {
    if (!MBIsStarted()) { return MBFailureHandle(); }
    MBAuthParameters *params = MBCopyHandleObject(authParametersHandle, [MBAuthParameters class]);
    if (!params) { return MBFailureHandle(); }
    params.redirectUri = MBNonNilStringFromWide(redirectUri);
    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_SetDecodedClaims(
    int64_t authParametersHandle,
    const wchar_t *claims
) {
    if (!MBIsStarted()) { return MBFailureHandle(); }
    MBAuthParameters *params = MBCopyHandleObject(authParametersHandle, [MBAuthParameters class]);
    if (!params) { return MBFailureHandle(); }
    params.decodedClaims = MBNonNilStringFromWide(claims);
    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_SetAdditionalParameter(
    int64_t authParametersHandle,
    const wchar_t *key,
    const wchar_t *value
) {
    if (!MBIsStarted() || !key) { return MBFailureHandle(); }
    MBAuthParameters *params = MBCopyHandleObject(authParametersHandle, [MBAuthParameters class]);
    if (!params) { return MBFailureHandle(); }

    NSString *keyString = MBStringFromWide(key);
    if (keyString.length == 0) { return MBFailureHandle(); }

    NSString *valueString = MBStringFromWide(value);
    if (valueString.length > 0) {
        [params.additionalParameters setObject:valueString forKey:keyString];
    } else {
        [params.additionalParameters removeObjectForKey:keyString];
    }
    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_SetPopParams(
    int64_t authParametersHandle,
    const wchar_t *httpMethod,
    const wchar_t *uriHost,
    const wchar_t *uriPath,
    const wchar_t *nonce
) {
    if (!MBIsStarted()) { return MBFailureHandle(); }
    MBAuthParameters *params = MBCopyHandleObject(authParametersHandle, [MBAuthParameters class]);
    if (!params) { return MBFailureHandle(); }
    params.popHttpMethod = MBNonNilStringFromWide(httpMethod);
    params.popUriHost = MBNonNilStringFromWide(uriHost);
    params.popUriPath = MBNonNilStringFromWide(uriPath);
    params.popNonce = MBNonNilStringFromWide(nonce);
    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_ReleaseAsyncHandle(int64_t asyncHandle) {
    if (!MBIsStarted()) { return MBFailureHandle(); }
    return MBRemoveHandleObject(asyncHandle, [MBAsyncOperation class]) ? MBSuccessHandle() : MBFailureHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_CancelAsyncOperation(MSALMacAsyncHandle *asyncHandle) {
    if (!MBIsStarted() || !asyncHandle || asyncHandle->value == 0) {
        return MBFailureHandle();
    }

    MBAsyncOperation *operation = MBCopyHandleObject(asyncHandle->value, [MBAsyncOperation class]);
    if (!operation) {
        return MBFailureHandle();
    }

    MBAsyncCancel(operation);
    dispatch_async(dispatch_get_main_queue(), ^{
        if (operation.windowController.window) {
            [operation.windowController.window close];
        }
    });
    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_ReleaseError(int64_t errorHandle) {
    if (!MBIsStarted()) { return MBFailureHandle(); }
    return MBRemoveHandleObject(errorHandle, [MBError class]) ? MBSuccessHandle() : MBFailureHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_GetStatus(
    MSALMacErrorHandle errorHandle,
    MSALMacResponseStatus *responseStatus
) {
    if (!responseStatus) { return MBFailureHandle(); }
    int32_t rawStatus = errorHandle.status;
    if (rawStatus < MSALMAC_RESPONSE_STATUS_SUCCESS || rawStatus > MSALMAC_RESPONSE_STATUS_CANCELLED) {
        *responseStatus = MSALMAC_RESPONSE_STATUS_ERROR;
    } else {
        *responseStatus = (MSALMacResponseStatus)rawStatus;
    }
    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_GetStatusFromInt64(
    int64_t errorHandle,
    MSALMacResponseStatus *responseStatus
) {
    if (!MBIsStarted() || !responseStatus) { return MBFailureHandle(); }
    if (errorHandle == 0) {
        *responseStatus = MSALMAC_RESPONSE_STATUS_SUCCESS;
        return MBSuccessHandle();
    }
    MBError *error = MBCopyHandleObject(errorHandle, [MBError class]);
    if (!error) { return MBFailureHandle(); }
    *responseStatus = error.responseStatus;
    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_GetErrorCode(
    int64_t errorHandle,
    int64_t *responseErrorCode
) {
    if (!MBIsStarted() || !responseErrorCode) { return MBFailureHandle(); }
    if (errorHandle == 0) {
        *responseErrorCode = 0;
        return MBSuccessHandle();
    }
    MBError *error = MBCopyHandleObject(errorHandle, [MBError class]);
    if (!error) { return MBFailureHandle(); }
    *responseErrorCode = error.errorCode;
    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_GetTag(
    int64_t errorHandle,
    int32_t *responseErrorTag
) {
    if (!MBIsStarted() || !responseErrorTag) { return MBFailureHandle(); }
    if (errorHandle == 0) {
        *responseErrorTag = 0;
        return MBSuccessHandle();
    }
    MBError *error = MBCopyHandleObject(errorHandle, [MBError class]);
    if (!error) { return MBFailureHandle(); }
    *responseErrorTag = error.tag;
    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_GetContext(
    MSALMacErrorHandle errorHandle,
    wchar_t *context,
    int32_t *bufferSize
) {
    if (!bufferSize) { return MBFailureHandle(); }
    NSString *statusText = nil;
    switch (errorHandle.status) {
        case MSALMAC_RESPONSE_STATUS_SUCCESS:
            statusText = @"success";
            break;
        case MSALMAC_RESPONSE_STATUS_CANCELLED:
            statusText = @"cancelled";
            break;
        case MSALMAC_RESPONSE_STATUS_ERROR:
        default:
            statusText = @"error";
            break;
    }
    return MBCopyStringToWideBuffer(statusText, context, bufferSize);
}

MSALMacErrorHandle MSALMACRUNTIME_ReleaseAuthResult(int64_t authResultHandle) {
    if (!MBIsStarted()) { return MBFailureHandle(); }
    return MBRemoveHandleObject(authResultHandle, [MBAuthResult class]) ? MBSuccessHandle() : MBFailureHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_GetAccount(
    MSALMacAuthResultHandle authResultHandle,
    MSALMacAccountHandle *accountHandle
) {
    if (!MBIsStarted() || !accountHandle) { return MBFailureHandle(); }
    MBAuthResult *result = MBCopyHandleObject(authResultHandle.value, [MBAuthResult class]);
    if (!result || !result.account) {
        accountHandle->value = 0;
        return MBFailureHandle();
    }
    accountHandle->value = MBStoreHandleObject(result.account);
    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_GetRawIdToken(
    MSALMacAuthResultHandle authResultHandle,
    wchar_t *rawIdToken,
    int32_t *bufferSize
) {
    if (!MBIsStarted() || !bufferSize) { return MBFailureHandle(); }
    MBAuthResult *result = MBCopyHandleObject(authResultHandle.value, [MBAuthResult class]);
    if (!result) { return MBFailureHandle(); }
    return MBCopyStringToWideBuffer(result.rawIdToken ?: @"", rawIdToken, bufferSize);
}

MSALMacErrorHandle MSALMACRUNTIME_GetAccessToken(
    MSALMacAuthResultHandle authResultHandle,
    wchar_t *accessToken,
    int32_t *bufferSize
) {
    if (!MBIsStarted() || !bufferSize) { return MBFailureHandle(); }
    MBAuthResult *result = MBCopyHandleObject(authResultHandle.value, [MBAuthResult class]);
    if (!result) { return MBFailureHandle(); }
    return MBCopyStringToWideBuffer(result.accessToken ?: @"", accessToken, bufferSize);
}

MSALMacErrorHandle MSALMACRUNTIME_GetError(
    MSALMacAuthResultHandle authResultHandle,
    MSALMacErrorHandleValue *errorHandle
) {
    if (!MBIsStarted() || !errorHandle) { return MBFailureHandle(); }
    MBAuthResult *result = MBCopyHandleObject(authResultHandle.value, [MBAuthResult class]);
    if (!result) {
        errorHandle->value = 0;
        return MBFailureHandle();
    }
    errorHandle->value = result.error ? MBStoreHandleObject(result.error) : 0;
    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_IsPopAuthorization(
    MSALMacAuthResultHandle authResult,
    int32_t *isPopAuthorization
) {
    if (!MBIsStarted() || !isPopAuthorization) { return MBFailureHandle(); }
    MBAuthResult *result = MBCopyHandleObject(authResult.value, [MBAuthResult class]);
    if (!result) { return MBFailureHandle(); }
    *isPopAuthorization = result.isPopAuthorization ? 1 : 0;
    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_GetAuthorizationHeader(
    MSALMacAuthResultHandle authResult,
    wchar_t *authHeader,
    int32_t *bufferSize
) {
    if (!MBIsStarted() || !bufferSize) { return MBFailureHandle(); }
    MBAuthResult *result = MBCopyHandleObject(authResult.value, [MBAuthResult class]);
    if (!result) { return MBFailureHandle(); }
    return MBCopyStringToWideBuffer(result.authorizationHeader ?: @"", authHeader, bufferSize);
}

MSALMacErrorHandle MSALMACRUNTIME_ReleaseReadAccountResult(int64_t readAccountResultHandle) {
    if (!MBIsStarted()) { return MBFailureHandle(); }
    return MBRemoveHandleObject(readAccountResultHandle, [MBReadAccountResult class]) ? MBSuccessHandle() : MBFailureHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_GetReadAccount(
    MSALMacReadAccountResultHandle readAccountResultHandle,
    MSALMacAccountHandle *account
) {
    if (!MBIsStarted() || !account) { return MBFailureHandle(); }
    MBReadAccountResult *result = MBCopyHandleObject(readAccountResultHandle.value, [MBReadAccountResult class]);
    if (!result || !result.account) {
        account->value = 0;
        return MBFailureHandle();
    }
    account->value = MBStoreHandleObject(result.account);
    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_GetReadAccountError(
    MSALMacReadAccountResultHandle readAccountResultHandle,
    MSALMacErrorHandleValue *errorHandle
) {
    if (!MBIsStarted() || !errorHandle) { return MBFailureHandle(); }
    MBReadAccountResult *result = MBCopyHandleObject(readAccountResultHandle.value, [MBReadAccountResult class]);
    if (!result) {
        errorHandle->value = 0;
        return MBFailureHandle();
    }
    errorHandle->value = result.error ? MBStoreHandleObject(result.error) : 0;
    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_ReleaseSignOutResult(int64_t signOutResultHandle) {
    if (!MBIsStarted()) { return MBFailureHandle(); }
    return MBRemoveHandleObject(signOutResultHandle, [MBSignOutResult class]) ? MBSuccessHandle() : MBFailureHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_GetSignOutError(
    MSALMacSignOutResultHandle signOutResultHandle,
    MSALMacErrorHandleValue *errorHandle
) {
    if (!MBIsStarted() || !errorHandle) { return MBFailureHandle(); }
    MBSignOutResult *result = MBCopyHandleObject(signOutResultHandle.value, [MBSignOutResult class]);
    if (!result) {
        errorHandle->value = 0;
        return MBFailureHandle();
    }
    errorHandle->value = result.error ? MBStoreHandleObject(result.error) : 0;
    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_RegisterLogCallback(
    LogCallback callback,
    int32_t callbackData,
    LogCallbackHandle *logCallbackHandle
) {
    if (!MBIsStarted() || !callback || !logCallbackHandle) {
        if (logCallbackHandle) { logCallbackHandle->value = 0; }
        return MBFailureHandle();
    }

    MBLogSubscription *subscription = [[[MBLogSubscription alloc] init] autorelease];
    subscription.callback = callback;
    subscription.callbackData = callbackData;

    int64_t handleValue = MBStoreHandleObject(subscription);
    logCallbackHandle->value = handleValue;

    MBInitializeState();
    dispatch_sync(gStateQueue, ^{
        [gLogSubscriptions setObject:subscription forKey:[NSNumber numberWithLongLong:handleValue]];
    });

    MBEmitLog(1, @"Log callback registered", NO);
    return MBSuccessHandle();
}

MSALMacErrorHandle MSALMACRUNTIME_ReleaseLogCallbackHandle(int64_t logCallbackHandle) {
    if (!MBIsStarted()) { return MBFailureHandle(); }

    MBInitializeState();
    dispatch_sync(gStateQueue, ^{
        [gLogSubscriptions removeObjectForKey:[NSNumber numberWithLongLong:logCallbackHandle]];
    });

    return MBRemoveHandleObject(logCallbackHandle, [MBLogSubscription class]) ? MBSuccessHandle() : MBFailureHandle();
}

void MSALMACRUNTIME_SetIsPiiEnabled(int32_t enabled) {
    MBInitializeState();
    dispatch_sync(gStateQueue, ^{
        gPiiEnabled = (enabled != 0);
    });
    MBEmitLog(1, [NSString stringWithFormat:@"PII logging %@", enabled ? @"enabled" : @"disabled"], NO);
}
