package com.microsoft.aad.msal4j.runtime;

import com.microsoft.azure.javamsalruntime.*;
import com.sun.jna.ptr.IntByReference;
import com.sun.jna.ptr.LongByReference;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class MsalMacError {
    private static final Logger LOG = LoggerFactory.getLogger(MsalMacError.class);
    int msalRuntimeTag;
    long msalRuntimeErrorCode;
    MsalMacRuntimeResponseStatus msalRuntimeResponseStatus;
    String msalRuntimeContext;
    boolean isValidError = false;

    MsalMacError(MsalMacHandleBase handle) {
        // Error handles can be created in two ways: directly in the interop using a
        // LongByReference,
        //  or indirectly by JNA using the return value of most MSALRuntime APIs.
        // If created by the interop, the handle would have been set in the
        // ErrorHandle.msalRuntimeHandle field,
        //  however if created from a return value, the ErrorHandle object itself represents the
        //  handle
        long msalRuntimeErrorHandle;
        if (handle.msalRuntimeHandle != null && handle.msalRuntimeHandle.getValue() != 0) {
            msalRuntimeErrorHandle = handle.msalRuntimeHandle.getValue();
        } else {
            msalRuntimeErrorHandle = handle.getValue();
        }

        if (msalRuntimeErrorHandle != 0) {
            // MSALRuntime returns a 0 if the operation was a success, otherwise it returns a
            // non-zero number representing an MSALRUNTIME_ERROR_HANDLE
            LOG.warn("MSALRuntime returned a non-zero MSALRUNTIME_ERROR_HANDLE.");
            isValidError = true;

            LOG.info("Parsing MSALRuntime error response.");
            this.msalRuntimeTag = parseTag(msalRuntimeErrorHandle);
            this.msalRuntimeErrorCode = parseErrorCode(msalRuntimeErrorHandle);
            this.msalRuntimeResponseStatus = parseResponseStatus(msalRuntimeErrorHandle);
            this.msalRuntimeContext = parseContext(handle);
        }
    }

    static int parseTag(long handle) {
        IntByReference tagRef = new IntByReference();

        ignoreAndReleaseError(
                MsalRuntimeInterop.MSALRUNTIME_LIBRARY.MSALRUNTIME_GetTag(handle, tagRef));

        return tagRef.getValue();
    }

    static long parseErrorCode(long handle) {
        LongByReference errorCodeRef = new LongByReference();

        ignoreAndReleaseError(MsalRuntimeInterop.MSALRUNTIME_LIBRARY.MSALRUNTIME_GetErrorCode(
                handle, errorCodeRef));

        return errorCodeRef.getValue();
    }

    static MsalMacRuntimeResponseStatus parseResponseStatus(long handle) {
        IntByReference responseStatusRef = new IntByReference();

        ignoreAndReleaseError(MsalRuntimeInterop.MSALRUNTIME_LIBRARY.MSALRUNTIME_GetStatus(
                handle, responseStatusRef));

        try {
            return MsalMacRuntimeResponseStatus.values()[responseStatusRef.getValue()];
        } catch (ArrayIndexOutOfBoundsException e) {
            throw new MsalInteropException(
                    "MSALRuntime returned an unknown or invalid response status: "
                            + responseStatusRef.getValue(),
                    "msalruntime_error");
        }
    }

    static String parseContext(LongByReference handle) {
        return MsalMacHandleBase.getString(
                new MsalMacErrorHandle(handle),
                (error, context, bufferSize)
                        -> MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_GetContext(
                        (MsalMacErrorHandle) error, context, bufferSize));
    }

    /**
     * Used when an error can be ignored, mainly to avoid loops when parsing errors
     *
     * @param errorHandle the MSALRUNTIME_ERROR_HANDLE that can be released
     */
    static void ignoreAndReleaseError(LongByReference errorHandle) {
        try (MsalMacErrorHandle handle = new MsalMacErrorHandle(errorHandle)) {
            if (handle.isHandleValid()) {
                LOG.warn("Ignoring and releasing error without parsing.");
            }
        }
    }
}
