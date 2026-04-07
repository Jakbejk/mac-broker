#include "MacBrokerBridge.h"

#import <Cocoa/Cocoa.h>

static BOOL gMSALRuntimeStarted = NO;

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
static NSSet<NSString *> *kReservedAuthParameterKeys = nil;

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
            kReservedAuthParameterKeys = [[NSSet alloc] initWithArray:@[@"clientId", @"authority", @"scopes", @"redirectUri", @"claims", @"popParams"
            ]];
        } else if (gErrors == nil) {
            gErrors = [[NSMutableDictionary alloc] init];
        }
    }
}
