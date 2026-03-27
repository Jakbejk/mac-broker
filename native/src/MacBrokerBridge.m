#import "MacBrokerBridge.h"
#import <Foundation/Foundation.h>
#import <Security/Security.h>
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

// ============================================================================
// Helper Functions
// ============================================================================

static int64_t generateHandle(void) {
    @synchronized(gSyncLock) {
        return gHandleCounter++;
    }
}

static void logMessage(int32_t level, const wchar_t *message) {
    if (gLogCallbackContext != NULL && gLogCallbackContext->callback != NULL) {
        gLogCallbackContext->callback(level, message, gLogCallbackContext->callbackData);
    }
}

static void setError(MSALMacResponseStatus status, int64_t errorCode, int32_t tag, const char *context) {
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

// ============================================================================
// MSALRuntime Core API Implementation
// ============================================================================

MSALMacErrorHandle MSALMACRUNTIME_Startup(void) {
    @autoreleasepool {
        @synchronized(gSyncLock) {
            if (gAsyncOperations == nil) {
                gAsyncOperations = [NSMutableDictionary dictionary];
                gAuthParameters = [NSMutableDictionary dictionary];
                gAccounts = [NSMutableDictionary dictionary];
                gAuthResults = [NSMutableDictionary dictionary];
                gReadAccountResults = [NSMutableDictionary dictionary];
                gSignOutResults = [NSMutableDictionary dictionary];
                gErrors = [NSMutableDictionary dictionary];
                gSyncLock = [[NSObject alloc] init];
                gBrokerQueue = dispatch_queue_create("com.microsoft.msal.broker", DISPATCH_QUEUE_SERIAL);
                
                NSLog(@"[MSAL Broker] MSALRuntime startup completed successfully");
                gLastError.status = MSALMAC_RESPONSE_STATUS_SUCCESS;
                return gLastError;
            }
        }
    }
    
    return gLastError;
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
                        authResult[@"idToken"] = @"mock_id_token_for_signin";
                        authResult[@"accountId"] = accountHintStr;
                        authResult[@"scope"] = authParams[@"scopes"];
                        authResult[@"expiresOn"] = @([[NSDate date] timeIntervalSince1970] + 3600);
                        authResult[@"correlationId"] = correlationIdStr;
                        
                        NSMutableDictionary *accountInfo = [NSMutableDictionary dictionary];
                        accountInfo[@"accountId"] = accountHintStr;
                        accountInfo[@"displayName"] = @"Test User";
                        
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
                        authResult[@"idToken"] = @"mock_id_token_silent";
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
                    [NSThread sleepForTimeInterval:0.3];
                    
                    @synchronized(gSyncLock) {
                        NSMutableDictionary *authParams = gAuthParameters[@(authParametersHandle)];
                        NSMutableDictionary *authResult = [NSMutableDictionary dictionary];
                        
                        authResult[@"accessToken"] = @"mock_access_token_interactive";
                        authResult[@"idToken"] = @"mock_id_token_interactive";
                        authResult[@"accountId"] = accountHintStr;
                        authResult[@"scope"] = authParams[@"scopes"];
                        authResult[@"expiresOn"] = @([[NSDate date] timeIntervalSince1970] + 3600);
                        authResult[@"correlationId"] = correlationIdStr;
                        
                        NSMutableDictionary *accountInfo = [NSMutableDictionary dictionary];
                        accountInfo[@"accountId"] = accountHintStr;
                        accountInfo[@"displayName"] = @"Test User Interactive";
                        
                        authResult[@"account"] = accountInfo;
                        
                        int64_t authResultHandle = generateHandle();
                        gAuthResults[@(authResultHandle)] = authResult;
                        
                        callback(authResultHandle, callbackData, MSALMAC_RESPONSE_STATUS_SUCCESS);
                    }
                    
                    NSLog(@"[MSAL Broker] SignInInteractively completed for account: %@", accountHintStr);
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
                        authResult[@"idToken"] = @"mock_id_token_acquired_silent";
                        authResult[@"expiresOn"] = @([[NSDate date] timeIntervalSince1970] + 3600);
                        authResult[@"correlationId"] = correlationIdStr;
                        
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
                        authResult[@"idToken"] = @"mock_id_token_acquired_interactive";
                        authResult[@"expiresOn"] = @([[NSDate date] timeIntervalSince1970] + 3600);
                        authResult[@"correlationId"] = correlationIdStr;
                        
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
        if (context == NULL || bufferSize == NULL) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 24, 24, "Null context or buffer size pointer");
            return gLastError;
        }
        
        @synchronized(gSyncLock) {
            NSMutableDictionary *error = gErrors[@(errorHandle.status)];
            NSString *contextStr = error[@"context"] ?: @"";
            wchar_t *ctx = nsstringToWstring(contextStr);
            int32_t requiredSize = (int32_t)(wcslen(ctx) + 1) * sizeof(wchar_t);
            
            if (*bufferSize < requiredSize) {
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
        if (rawIdToken == NULL || bufferSize == NULL) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 27, 27, "Null token or buffer size pointer");
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
            
            if (*bufferSize < requiredSize) {
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
        if (accessToken == NULL || bufferSize == NULL) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 29, 29, "Null token or buffer size pointer");
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
            
            if (*bufferSize < requiredSize) {
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
        if (authHeader == NULL || bufferSize == NULL) {
            setError(MSALMAC_RESPONSE_STATUS_ERROR, 33, 33, "Null header or buffer size pointer");
            return gLastError;
        }
        
        @synchronized(gSyncLock) {
            NSMutableDictionary *result = gAuthResults[@(authResult.value)];
            NSString *token = result[@"accessToken"] ?: @"";
            NSString *headerStr = [NSString stringWithFormat:@"Bearer %@", token];
            wchar_t *header = nsstringToWstring(headerStr);
            int32_t requiredSize = (int32_t)(wcslen(header) + 1) * sizeof(wchar_t);
            
            if (*bufferSize < requiredSize) {
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
