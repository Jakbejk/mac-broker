package com.microsoft.aad.msal4j.runtime;

import com.microsoft.azure.javamsalruntime.LogCallbackHandle;
import com.sun.jna.Library;
import com.sun.jna.Pointer;
import com.sun.jna.WString;
import com.sun.jna.ptr.IntByReference;
import com.sun.jna.ptr.LongByReference;

public interface MsalMacRuntimeLibrary extends Library {

    // MSALRuntime.h
    MsalMacErrorHandle MSALMACRUNTIME_Startup();

    void MSALMACRUNTIME_Shutdown();

    MsalMacErrorHandle MSALMACRUNTIME_ReadAccountByIdAsync(
            WString accountId, WString correlationId, MsalMacCallbacks.ReadAccountResultCallback callback,
            Integer callbackData, MsalMacAsyncHandle asyncHandle);

    MsalMacErrorHandle MSALMACRUNTIME_SignInAsync(
            long parentWindowHandle, long authParametersHandle, WString correlationId,
            WString accountHint, MsalMacCallbacks.AuthResultCallback callback, Integer callbackData,
            MsalMacAsyncHandle asyncHandle);

    MsalMacErrorHandle MSALMACRUNTIME_SignInSilentlyAsync(
            long authParametersHandle, WString correlationId, MsalMacCallbacks.AuthResultCallback callback,
            Integer callbackData, MsalMacAsyncHandle asyncHandle);

    MsalMacErrorHandle MSALMACRUNTIME_SignInInteractivelyAsync(
            long parentWindowHandle, long authParametersHandle, WString correlationId,
            WString accountHint, MsalMacCallbacks.AuthResultCallback callback, Integer callbackData,
            MsalMacAsyncHandle asyncHandle);

    MsalMacErrorHandle MSALMACRUNTIME_AcquireTokenSilentlyAsync(
            long authParametersHandle, WString correlationId, long accountHandle,
            MsalMacCallbacks.AuthResultCallback callback, Integer callbackData, MsalMacAsyncHandle asyncHandle);

    MsalMacErrorHandle MSALMACRUNTIME_AcquireTokenInteractivelyAsync(
            long parentWindowHandle, long authParametersHandle, WString correlationId,
            long accountHandle, MsalMacCallbacks.AuthResultCallback callback, Integer callbackData,
            MsalMacAsyncHandle asyncHandle);

    MsalMacErrorHandle MSALMACRUNTIME_SignOutSilentlyAsync(
            WString clientId, WString correlationId, long accountHandle,
            MsalMacCallbacks.SignOutResultCallback callback, Integer callbackData, MsalMacAsyncHandle asyncHandle);

    // MSALRuntimeAccount.h
    MsalMacErrorHandle MSALMACRUNTIME_ReleaseAccount(long accountHandle);

    MsalMacErrorHandle MSALMACRUNTIME_GetAccountId(
            long accountHandle, Pointer accountId, IntByReference bufferSize);

    MsalMacErrorHandle MSALMACRUNTIME_GetClientInfo(
            long accountHandle, Pointer clientInfo, IntByReference bufferSize);

    // MSALRuntimeAuthParameters.h
    MsalMacErrorHandle MSALMACRUNTIME_CreateAuthParameters(
            WString clientId, WString authority, MsalMacAuthParametersHandle authParametersHandle);

    MsalMacErrorHandle MSALMACRUNTIME_ReleaseAuthParameters(long authParametersHandle);

    MsalMacErrorHandle MSALMACRUNTIME_SetRequestedScopes(long authParametersHandle, WString scopes);

    MsalMacErrorHandle MSALMACRUNTIME_SetRedirectUri(long authParametersHandle, WString redirectUri);

    MsalMacErrorHandle MSALMACRUNTIME_SetDecodedClaims(long authParametersHandle, WString claims);

    MsalMacErrorHandle MSALMACRUNTIME_SetAdditionalParameter(long authParametersHandle, WString key, WString value);

    MsalMacErrorHandle MSALMACRUNTIME_SetPopParams(
            long authParametersHandle, WString httpMethod, WString uriHost, WString uriPath,
            WString nonce);

    // MSALRuntimeCancel.h
    MsalMacErrorHandle MSALMACRUNTIME_ReleaseAsyncHandle(long asyncHandle);

    MsalMacErrorHandle MSALMACRUNTIME_CancelAsyncOperation(MsalMacAsyncHandle asyncHandle);

    // MSALRuntimeError.h
    MsalMacErrorHandle MSALMACRUNTIME_ReleaseError(long errorHandle);

    MsalMacErrorHandle MSALMACRUNTIME_GetStatus(MsalMacErrorHandle errorHandle, IntByReference responseStatus);

    MsalMacErrorHandle MSALMACRUNTIME_GetStatus(long errorHandle, IntByReference responseStatus);

    MsalMacErrorHandle MSALMACRUNTIME_GetErrorCode(long errorHandle, LongByReference responseErrorCode);

    MsalMacErrorHandle MSALMACRUNTIME_GetTag(long errorHandle, IntByReference responseErrorTag);

    MsalMacErrorHandle MSALMACRUNTIME_GetContext(
            MsalMacErrorHandle errorHandle, Pointer context, IntByReference bufferSize);

    // MSALRuntimeAuthResult.h
    MsalMacErrorHandle MSALMACRUNTIME_ReleaseAuthResult(long authResultHandle);

    MsalMacErrorHandle MSALMACRUNTIME_GetAccount(MsalMacAuthResultHandle authResultHandle, MsalMacAccountHandle accountHandle);

    MsalMacErrorHandle MSALMACRUNTIME_GetRawIdToken(
            MsalMacAuthResultHandle authResultHandle, Pointer rawIdToken, IntByReference bufferSize);

    MsalMacErrorHandle MSALMACRUNTIME_GetAccessToken(
            MsalMacAuthResultHandle authResultHandle, Pointer accessToken, IntByReference bufferSize);

    MsalMacErrorHandle MSALMACRUNTIME_GetError(MsalMacAuthResultHandle authResultHandle, MsalMacErrorHandle errorHandle);

    MsalMacErrorHandle MSALMACRUNTIME_IsPopAuthorization(
            MsalMacAuthResultHandle authResult, IntByReference isPopAuthorization);

    MsalMacErrorHandle MSALMACRUNTIME_GetAuthorizationHeader(
            MsalMacAuthResultHandle authResult, Pointer authHeader, IntByReference bufferSize);

    // MSALRuntimeReadAccountResult.h
    MsalMacErrorHandle MSALMACRUNTIME_ReleaseReadAccountResult(long readAccountResultHandle);

    MsalMacErrorHandle MSALMACRUNTIME_GetReadAccount(
            MsalMacReadAccountResultHandle readAccountResultHandle, MsalMacAccountHandle account);

    MsalMacErrorHandle MSALMACRUNTIME_GetReadAccountError(
            MsalMacReadAccountResultHandle readAccountResultHandle, MsalMacErrorHandle errorHandle);

    // MSALRuntimeSignoutResult.h
    MsalMacErrorHandle MSALMACRUNTIME_ReleaseSignOutResult(long signOutResultHandle);

    MsalMacErrorHandle MSALMACRUNTIME_GetSignOutError(
            MsalMacSignOutResultHandle signOutResultHandle, MsalMacErrorHandle errorHandle);

    // MSALRuntimeLogging.h
    MsalMacErrorHandle MSALMACRUNTIME_RegisterLogCallback(
            MsalMacCallbacks.LogCallback callback, Integer callbackdata,
            LogCallbackHandle logCallbackHandle);

    MsalMacErrorHandle MSALMACRUNTIME_ReleaseLogCallbackHandle(long logCallbackHandle);

    void MSALMACRUNTIME_SetIsPiiEnabled(int enabled); // 1 = PII enabled, anything else = disabled
}
