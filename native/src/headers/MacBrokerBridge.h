#ifndef MACBROKERBRIDGE_H
#define MACBROKERBRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ============================================================================
// Type Definitions and Structs
// ============================================================================

typedef struct {
    int32_t status;
} MSALMacErrorHandle;

typedef struct {
    int64_t value;
} MSALMacAsyncHandle;

typedef struct {
    int64_t value;
} MSALMacAuthResultHandle;

typedef struct {
    int64_t value;
} MSALMacAccountHandle;

typedef struct {
    int64_t value;
} MSALMacReadAccountResultHandle;

typedef struct {
    int64_t value;
} MSALMacSignOutResultHandle;

typedef struct {
    int64_t value;
} MSALMacErrorHandleValue;

typedef struct {
    int64_t value;
} AuthParametersHandle;

typedef struct {
    int64_t value;
} LogCallbackHandle;

// Response status enumeration
typedef enum {
    MSALMAC_RESPONSE_STATUS_SUCCESS = 0,
    MSALMAC_RESPONSE_STATUS_ERROR = 1,
    MSALMAC_RESPONSE_STATUS_CANCELLED = 2,
} MSALMacResponseStatus;

// ============================================================================
// Callback Function Pointers
// ============================================================================

typedef void (*AuthResultCallback)(
    int64_t authResultHandle,
    int32_t callbackData,
    MSALMacResponseStatus status
);

typedef void (*ReadAccountResultCallback)(
    int64_t readAccountResultHandle,
    int32_t callbackData,
    MSALMacResponseStatus status
);

typedef void (*SignOutResultCallback)(
    int64_t signOutResultHandle,
    int32_t callbackData,
    MSALMacResponseStatus status
);

typedef void (*LogCallback)(
    int32_t level,
    const wchar_t *message,
    int32_t callbackData
);

// ============================================================================
// MSALRuntime Core API (MSALRuntime.h)
// ============================================================================

/**
 * Initializes the MSALRuntime library. Must be called before any other API calls.
 * @return Error handle if initialization fails, NULL on success
 */
MSALMacErrorHandle MSALMACRUNTIME_Startup(void);

/**
 * Shuts down the MSALRuntime library and releases all resources.
 */
void MSALMACRUNTIME_Shutdown(void);

/**
 * Asynchronously reads account information by account ID.
 * @param accountId The account ID to retrieve
 * @param correlationId Unique correlation ID for tracing
 * @param callback Callback invoked when operation completes
 * @param callbackData User-provided data passed to callback
 * @param asyncHandle Handle to the async operation
 * @return Error handle if the operation fails to initiate
 */
MSALMacErrorHandle MSALMACRUNTIME_ReadAccountByIdAsync(
    const wchar_t *accountId,
    const wchar_t *correlationId,
    ReadAccountResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle
);

/**
 * Asynchronously signs in with automatic fallback to interactive if needed.
 * @param parentWindowHandle Parent window handle for UI display
 * @param authParametersHandle Handle to auth parameters
 * @param correlationId Unique correlation ID for tracing
 * @param accountHint Login hint (username or email)
 * @param callback Callback invoked when operation completes
 * @param callbackData User-provided data passed to callback
 * @param asyncHandle Handle to the async operation
 * @return Error handle if the operation fails to initiate
 */
MSALMacErrorHandle MSALMACRUNTIME_SignInAsync(
    int64_t parentWindowHandle,
    int64_t authParametersHandle,
    const wchar_t *correlationId,
    const wchar_t *accountHint,
    AuthResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle
);

/**
 * Asynchronously performs a silent sign in (no UI).
 * @param authParametersHandle Handle to auth parameters
 * @param correlationId Unique correlation ID for tracing
 * @param callback Callback invoked when operation completes
 * @param callbackData User-provided data passed to callback
 * @param asyncHandle Handle to the async operation
 * @return Error handle if the operation fails to initiate
 */
MSALMacErrorHandle MSALMACRUNTIME_SignInSilentlyAsync(
    int64_t authParametersHandle,
    const wchar_t *correlationId,
    AuthResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle
);

/**
 * Asynchronously performs an interactive sign in with UI.
 * @param parentWindowHandle Parent window handle for UI display
 * @param authParametersHandle Handle to auth parameters
 * @param correlationId Unique correlation ID for tracing
 * @param accountHint Login hint (username or email)
 * @param callback Callback invoked when operation completes
 * @param callbackData User-provided data passed to callback
 * @param asyncHandle Handle to the async operation
 * @return Error handle if the operation fails to initiate
 */
MSALMacErrorHandle MSALMACRUNTIME_SignInInteractivelyAsync(
    int64_t parentWindowHandle,
    int64_t authParametersHandle,
    const wchar_t *correlationId,
    const wchar_t *accountHint,
    AuthResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle
);

/**
 * Asynchronously acquires tokens silently (no UI).
 * @param authParametersHandle Handle to auth parameters
 * @param correlationId Unique correlation ID for tracing
 * @param accountHandle Handle to the account
 * @param callback Callback invoked when operation completes
 * @param callbackData User-provided data passed to callback
 * @param asyncHandle Handle to the async operation
 * @return Error handle if the operation fails to initiate
 */
MSALMacErrorHandle MSALMACRUNTIME_AcquireTokenSilentlyAsync(
    int64_t authParametersHandle,
    const wchar_t *correlationId,
    int64_t accountHandle,
    AuthResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle
);

/**
 * Asynchronously acquires tokens interactively with UI.
 * @param parentWindowHandle Parent window handle for UI display
 * @param authParametersHandle Handle to auth parameters
 * @param correlationId Unique correlation ID for tracing
 * @param accountHandle Handle to the account
 * @param callback Callback invoked when operation completes
 * @param callbackData User-provided data passed to callback
 * @param asyncHandle Handle to the async operation
 * @return Error handle if the operation fails to initiate
 */
MSALMacErrorHandle MSALMACRUNTIME_AcquireTokenInteractivelyAsync(
    int64_t parentWindowHandle,
    int64_t authParametersHandle,
    const wchar_t *correlationId,
    int64_t accountHandle,
    AuthResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle
);

/**
 * Asynchronously signs out an account silently.
 * @param clientId The client ID
 * @param correlationId Unique correlation ID for tracing
 * @param accountHandle Handle to the account
 * @param callback Callback invoked when operation completes
 * @param callbackData User-provided data passed to callback
 * @param asyncHandle Handle to the async operation
 * @return Error handle if the operation fails to initiate
 */
MSALMacErrorHandle MSALMACRUNTIME_SignOutSilentlyAsync(
    const wchar_t *clientId,
    const wchar_t *correlationId,
    int64_t accountHandle,
    SignOutResultCallback callback,
    int32_t callbackData,
    MSALMacAsyncHandle *asyncHandle
);

// ============================================================================
// MSALRuntimeAccount API (MSALRuntimeAccount.h)
// ============================================================================

/**
 * Releases account resources.
 * @param accountHandle Handle to the account to release
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_ReleaseAccount(int64_t accountHandle);

/**
 * Retrieves the account ID.
 * @param accountHandle Handle to the account
 * @param accountId Output buffer for account ID
 * @param bufferSize Input/output size of buffer
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_GetAccountId(
    int64_t accountHandle,
    wchar_t *accountId,
    int32_t *bufferSize
);

/**
 * Retrieves client information.
 * @param accountHandle Handle to the account
 * @param clientInfo Output buffer for client info
 * @param bufferSize Input/output size of buffer
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_GetClientInfo(
    int64_t accountHandle,
    wchar_t *clientInfo,
    int32_t *bufferSize
);

// ============================================================================
// MSALRuntimeAuthParameters API (MSALRuntimeAuthParameters.h)
// ============================================================================

/**
 * Creates authentication parameters.
 * @param clientId The client ID
 * @param authority The authority URL
 * @param authParametersHandle Output handle for auth parameters
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_CreateAuthParameters(
    const wchar_t *clientId,
    const wchar_t *authority,
    AuthParametersHandle *authParametersHandle
);

/**
 * Releases authentication parameters.
 * @param authParametersHandle Handle to release
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_ReleaseAuthParameters(int64_t authParametersHandle);

/**
 * Sets requested scopes.
 * @param authParametersHandle Handle to auth parameters
 * @param scopes Space-separated scopes
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_SetRequestedScopes(
    int64_t authParametersHandle,
    const wchar_t *scopes
);

/**
 * Sets redirect URI.
 * @param authParametersHandle Handle to auth parameters
 * @param redirectUri Redirect URI
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_SetRedirectUri(
    int64_t authParametersHandle,
    const wchar_t *redirectUri
);

/**
 * Sets decoded claims.
 * @param authParametersHandle Handle to auth parameters
 * @param claims Claims JSON
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_SetDecodedClaims(
    int64_t authParametersHandle,
    const wchar_t *claims
);

/**
 * Sets an additional parameter.
 * @param authParametersHandle Handle to auth parameters
 * @param key Parameter key
 * @param value Parameter value
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_SetAdditionalParameter(
    int64_t authParametersHandle,
    const wchar_t *key,
    const wchar_t *value
);

/**
 * Sets Proof-of-Possession (PoP) parameters.
 * @param authParametersHandle Handle to auth parameters
 * @param httpMethod HTTP method
 * @param uriHost URI host
 * @param uriPath URI path
 * @param nonce Nonce value
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_SetPopParams(
    int64_t authParametersHandle,
    const wchar_t *httpMethod,
    const wchar_t *uriHost,
    const wchar_t *uriPath,
    const wchar_t *nonce
);

// ============================================================================
// MSALRuntimeCancel API (MSALRuntimeCancel.h)
// ============================================================================

/**
 * Releases an async operation handle.
 * @param asyncHandle Handle to release
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_ReleaseAsyncHandle(int64_t asyncHandle);

/**
 * Cancels an async operation.
 * @param asyncHandle Handle to the async operation
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_CancelAsyncOperation(MSALMacAsyncHandle *asyncHandle);

// ============================================================================
// MSALRuntimeError API (MSALRuntimeError.h)
// ============================================================================

/**
 * Releases an error handle.
 * @param errorHandle Handle to release
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_ReleaseError(int64_t errorHandle);

/**
 * Gets the status from an error handle.
 * @param errorHandle Handle to the error
 * @param responseStatus Output status
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_GetStatus(
    MSALMacErrorHandle errorHandle,
    MSALMacResponseStatus *responseStatus
);

/**
 * Gets the status from a raw error handle.
 * @param errorHandle Raw error handle
 * @param responseStatus Output status
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_GetStatusFromInt64(
    int64_t errorHandle,
    MSALMacResponseStatus *responseStatus
);

/**
 * Gets the error code.
 * @param errorHandle Raw error handle
 * @param responseErrorCode Output error code
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_GetErrorCode(
    int64_t errorHandle,
    int64_t *responseErrorCode
);

/**
 * Gets the error tag.
 * @param errorHandle Raw error handle
 * @param responseErrorTag Output error tag
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_GetTag(
    int64_t errorHandle,
    int32_t *responseErrorTag
);

/**
 * Gets error context.
 * @param errorHandle Error handle
 * @param context Output buffer for context
 * @param bufferSize Input/output size of buffer
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_GetContext(
    MSALMacErrorHandle errorHandle,
    wchar_t *context,
    int32_t *bufferSize
);

// ============================================================================
// MSALRuntimeAuthResult API (MSALRuntimeAuthResult.h)
// ============================================================================

/**
 * Releases an auth result handle.
 * @param authResultHandle Handle to release
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_ReleaseAuthResult(int64_t authResultHandle);

/**
 * Gets the account from an auth result.
 * @param authResultHandle Auth result handle
 * @param accountHandle Output account handle
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_GetAccount(
    MSALMacAuthResultHandle authResultHandle,
    MSALMacAccountHandle *accountHandle
);

/**
 * Gets the raw ID token from an auth result.
 * @param authResultHandle Auth result handle
 * @param rawIdToken Output buffer for token
 * @param bufferSize Input/output size of buffer
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_GetRawIdToken(
    MSALMacAuthResultHandle authResultHandle,
    wchar_t *rawIdToken,
    int32_t *bufferSize
);

/**
 * Gets the access token from an auth result.
 * @param authResultHandle Auth result handle
 * @param accessToken Output buffer for token
 * @param bufferSize Input/output size of buffer
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_GetAccessToken(
    MSALMacAuthResultHandle authResultHandle,
    wchar_t *accessToken,
    int32_t *bufferSize
);

/**
 * Gets error from an auth result.
 * @param authResultHandle Auth result handle
 * @param errorHandle Output error handle
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_GetError(
    MSALMacAuthResultHandle authResultHandle,
    MSALMacErrorHandleValue *errorHandle
);

/**
 * Checks if the auth result is for Proof-of-Possession authorization.
 * @param authResult Auth result handle
 * @param isPopAuthorization Output flag
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_IsPopAuthorization(
    MSALMacAuthResultHandle authResult,
    int32_t *isPopAuthorization
);

/**
 * Gets the authorization header.
 * @param authResult Auth result handle
 * @param authHeader Output buffer for header
 * @param bufferSize Input/output size of buffer
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_GetAuthorizationHeader(
    MSALMacAuthResultHandle authResult,
    wchar_t *authHeader,
    int32_t *bufferSize
);

// ============================================================================
// MSALRuntimeReadAccountResult API (MSALRuntimeReadAccountResult.h)
// ============================================================================

/**
 * Releases a read account result handle.
 * @param readAccountResultHandle Handle to release
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_ReleaseReadAccountResult(int64_t readAccountResultHandle);

/**
 * Gets the account from a read account result.
 * @param readAccountResultHandle Read account result handle
 * @param account Output account handle
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_GetReadAccount(
    MSALMacReadAccountResultHandle readAccountResultHandle,
    MSALMacAccountHandle *account
);

/**
 * Gets error from a read account result.
 * @param readAccountResultHandle Read account result handle
 * @param errorHandle Output error handle
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_GetReadAccountError(
    MSALMacReadAccountResultHandle readAccountResultHandle,
    MSALMacErrorHandleValue *errorHandle
);

// ============================================================================
// MSALRuntimeSignoutResult API (MSALRuntimeSignoutResult.h)
// ============================================================================

/**
 * Releases a sign out result handle.
 * @param signOutResultHandle Handle to release
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_ReleaseSignOutResult(int64_t signOutResultHandle);

/**
 * Gets error from a sign out result.
 * @param signOutResultHandle Sign out result handle
 * @param errorHandle Output error handle
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_GetSignOutError(
    MSALMacSignOutResultHandle signOutResultHandle,
    MSALMacErrorHandleValue *errorHandle
);

// ============================================================================
// MSALRuntimeLogging API (MSALRuntimeLogging.h)
// ============================================================================

/**
 * Registers a logging callback.
 * @param callback Callback function for logs
 * @param callbackData User-provided callback data
 * @param logCallbackHandle Output log callback handle
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_RegisterLogCallback(
    LogCallback callback,
    int32_t callbackData,
    LogCallbackHandle *logCallbackHandle
);

/**
 * Releases a log callback handle.
 * @param logCallbackHandle Handle to release
 * @return Error handle if the operation fails
 */
MSALMacErrorHandle MSALMACRUNTIME_ReleaseLogCallbackHandle(int64_t logCallbackHandle);

/**
 * Enables or disables PII (Personally Identifiable Information) logging.
 * @param enabled 1 to enable PII logging, 0 to disable
 */
void MSALMACRUNTIME_SetIsPiiEnabled(int32_t enabled);

#ifdef __cplusplus
}
#endif

#endif // MACBROKERBRIDGE_H
