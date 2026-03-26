package com.microsoft.aad.msal4j.runtime;

import com.microsoft.azure.javamsalruntime.MsalInteropException;
import com.sun.jna.ptr.IntByReference;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class MsalMacErrorHelper {

    private static final Logger LOG = LoggerFactory.getLogger(MsalMacErrorHelper.class);

    /**
     * Used in release() methods, where errors could lead to memory leaks but there isn't anything
     * we can do
     */
    void logUnknownErrorReleasingHandle(Exception e) {
        LOG.error("Exception when releasing MSALRuntime handle, this may lead to memory leaks: {}", e.getMessage());
    }

    /**
     * When an error is returned from MSALRuntime that the interop layer was not expecting, throw an
     * exception that will either be handled in the interop layer or passed back up to the MSAL Java
     * Broker layer
     *
     * @param handle error handle returned by an MSALRuntime API
     * @
     */
    void checkMsalRuntimeError(MsalMacErrorHandle handle) throws MsalInteropException {
        if (handle != null) {
            MsalMacError parsedError = new MsalMacError(handle);

            if (parsedError.isValidError) {
                throw new MsalInteropException(errorMessageWithContext(parsedError), "msalruntime_error");
            }
        }
    }

    /**
     * Used to provide more user-friendly error messages, by providing more context and workarounds
     * for a number of common errors
     * <p>
     * By default, it will simply return any info the interop layer received from MSALRuntime
     */
    String errorMessageWithContext(MsalMacError error) {
        switch (error.msalRuntimeResponseStatus) {
            case MSALRUNTIME_RESPONSE_STATUS_INTERACTIONREQUIRED:
                return String.format("User interaction required, re-try this request using an interactive flow. Context: %s | Response status: %s | Tag: %s | Error code: %s", error.msalRuntimeContext, error.msalRuntimeResponseStatus, error.msalRuntimeTag, error.msalRuntimeErrorCode);
            case MSALRUNTIME_RESPONSE_STATUS_NONETWORK:
            case MSALRUNTIME_RESPONSE_STATUS_NETWORKTEMPORARILYUNAVAILABLE:
                return String.format("Network unavailable, could not complete request. Context: %s | Response status: %s | Tag: %s | Error code: %s", error.msalRuntimeContext, error.msalRuntimeResponseStatus, error.msalRuntimeTag, error.msalRuntimeErrorCode);
            case MSALRUNTIME_RESPONSE_STATUS_SERVERTEMPORARILYUNAVAILABLE:
                return String.format("Server temporarily unavailable, could not complete request at this time. Context: %s | Response status: %s | Tag: %s | Error code: %s", error.msalRuntimeContext, error.msalRuntimeResponseStatus, error.msalRuntimeTag, error.msalRuntimeErrorCode);
            case MSALRUNTIME_RESPONSE_STATUS_AUTHORITYUNTRUSTED:
                return String.format("Authority is not trusted by MSALRuntime, will not perform request. Context: %s | Response status: %s | Tag: %s | Error code: %s", error.msalRuntimeContext, error.msalRuntimeResponseStatus, error.msalRuntimeTag, error.msalRuntimeErrorCode);
            case MSALRUNTIME_RESPONSE_STATUS_ACCOUNTNOTFOUND:
                return String.format("Account not found for client ID. Context: %s | Response status: %s | Tag: %s | Error code: %s", error.msalRuntimeContext, error.msalRuntimeResponseStatus, error.msalRuntimeTag, error.msalRuntimeErrorCode);
            default:
                return String.format("MSALRuntime exception: Context: %s | Response status: %s | Tag: %s | Error code: %s", error.msalRuntimeContext, error.msalRuntimeResponseStatus, error.msalRuntimeTag, error.msalRuntimeErrorCode);
        }
    }

    // One part of an MSALRuntime error is a 'response status' code, essentially an int from an enum
    //  This helper method will check if the code in an error matches a given
    //  MsalRuntimeResponseStatus
    boolean checkResponseStatus(MsalMacErrorHandle errorHandle, MsalMacRuntimeResponseStatus responseStatus) {
        IntByReference responseStatusRef = new IntByReference();

        MsalMacError.ignoreAndReleaseError(MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_GetStatus(errorHandle, responseStatusRef));

        if (responseStatus.status != responseStatusRef.getValue()) {
            LOG.warn("Unexpected response status from MSALRuntime. Expected: {} | Actual: {}", responseStatus.status, responseStatusRef.getValue());
        }

        return responseStatus.status == responseStatusRef.getValue();
    }
}
