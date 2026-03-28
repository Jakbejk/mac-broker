package com.microsoft.aad.msal4j.runtime;

import com.microsoft.azure.javamsalruntime.AuthResult;
import com.microsoft.azure.javamsalruntime.MsalInteropException;
import com.sun.jna.Structure;
import com.sun.jna.ptr.IntByReference;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@Structure.FieldOrder({"unused"})
public class MsalMacAuthResult {

    private static final Logger LOG = LoggerFactory.getLogger(AuthResult.class);
    // JNA requires at least one public field to convert its Structure class to a native structure
    public int unused;
    private MsalMacAuthResultHandle resultHandle;
    private String idToken;
    private String accessToken;
    private long accessTokenExpirationTime;
    private MsalMacAccount account;
    private String authorizationHeader;
    private Boolean isPopAuthorization;

    public MsalMacAuthResult(MsalMacAuthResultHandle authResultHandle) {
        this.resultHandle = authResultHandle;
        parseAuthResult();
    }

    public String getIdToken() {
        return idToken;
    }

    public String getAccessToken() {
        return accessToken;
    }

    public long getAccessTokenExpirationTime() {
        return accessTokenExpirationTime;
    }

    public MsalMacAccount getAccount() {
        return account;
    }

    /**
     * Returns the authorization header, used to retrieve a proof-of-possession token
     */
    public String getAuthorizationHeader() {
        if (authorizationHeader == null) {
            authorizationHeader = MsalMacHandleBase.getString(this.resultHandle, (error, authHeader, bufferSize) ->
                    MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_GetAuthorizationHeader(this.resultHandle.value(), authHeader, bufferSize));
        }

        return authorizationHeader;
    }

    /**
     * Returns true if this authResult represents a proof-of-possession authorization
     */
    public boolean isPopAuthorization() {
        if (isPopAuthorization == null) {
            IntByReference isPop = new IntByReference(0);
            MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(
                    MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_IsPopAuthorization(this.resultHandle.value(), isPop));

            // MSALRUNTIME_IsPopAuthorization uses bool_t, which is an alias for an int as per
            // MSALRuntimeTypes.h, and passing an int pointer result in 1=true/0=false
            isPopAuthorization = isPop.getValue() == 1;
        }

        return isPopAuthorization;
    }

    /**
     * Calls various MSALRuntime APIs to retrieve data using the MSALRUNTIME_AUTH_RESULT_HANDLE
     * passed into the callback method
     */
    void parseAuthResult() {
        if (this.resultHandle.isHandleValid()) {
            LOG.info("Checking auth result error.");
            MsalMacErrorHandle error = new MsalMacErrorHandle();

            MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(
                    MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_GetError(this.resultHandle.value(), error));

            MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(error);

            LOG.info("Parsing auth result.");
            isPopAuthorization();
            parseAndSetAccessToken();
            parseAndSetIdToken();
            parseAndSetAccount();
        } else {
            throw new MsalInteropException("Auth result handle was invalid, could not parse.", "msalruntime_error");
        }
    }

    /**
     * If the auth result handle has an access token, retrieve and store it in this AuthResult
     */
    void parseAndSetAccessToken() {
        if (isPopAuthorization) {
            // POP tokens are returned as part of the authorization header,
            //   and is formatted as "pop {the signed access token}"
            this.accessToken = getAuthorizationHeader().split(" ")[1];
        } else {
            // If it is not a POP token, just get the token from the GetAccessToken API
            this.accessToken = MsalMacHandleBase.getString(resultHandle, (authResultHandle, accessToken, bufferSize) ->
                    MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_GetAccessToken(this.resultHandle.value(), accessToken, bufferSize));
        }
    }

    /**
     * If the auth result handle has an id token, retrieve and store it in this AuthResult
     */
    void parseAndSetIdToken() {
        this.idToken = MsalMacHandleBase.getString(resultHandle, (authResultHandle, rawIdToken, bufferSize) ->
                MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_GetRawIdToken(this.resultHandle.value(), rawIdToken, bufferSize));
    }

    /**
     * If the auth result handle has an account handle, parse and store it in this AuthResult
     */
    void parseAndSetAccount() {
        MsalMacAccountHandle accountHandle = new MsalMacAccountHandle();

        MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(
                MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_GetAccount(this.resultHandle.value(), accountHandle));

        this.account = new MsalMacAccount(accountHandle);
    }
}
