package com.microsoft.aad.msal4j.runtime;

import com.microsoft.azure.javamsalruntime.MsalInteropException;
import com.sun.jna.Structure;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

@Structure.FieldOrder({"unused"})
public class MsalMacSignOutResult extends Structure {
    private static final Logger LOG = LoggerFactory.getLogger(MsalMacSignOutResult.class);
    // JNA requires at least one public field to convert its Structure class to a native structure
    public int unused;
    private MsalMacSignOutResultHandle resultHandle;

    public MsalMacSignOutResult(MsalMacSignOutResultHandle signOutResultHandle) {
        this.resultHandle = signOutResultHandle;
        parseSignOutResult();
    }

    /**
     * Calls various MSALRuntime APIs to retrieve data using the MSALRUNTIME_SIGNOUT_RESULT_HANDLE
     * passed into the callback method <p> NOTE: Currently, there is nothing for us to parse from a
     * sign out result <p> This is just here to complete the mapping to MSALRuntime's SignOut API in
     * a way that's consistent with the other result types, and to allow easy addition of any future
     * parsing
     */
    void parseSignOutResult() {
        if (this.resultHandle.isHandleValid()) {
            LOG.info("Checking sign out result error.");
            MsalMacErrorHandle error = new MsalMacErrorHandle();

            MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(
                    MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_GetSignOutError(this.resultHandle.value(), error));

            MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(error);

            LOG.info("Parsing sign out result.");
            // Nothing for us to actually parse, this is just for consistency with the other result
            // classes
        } else {
            throw new MsalInteropException(
                    "Sign out result handle was invalid, could not parse.", "msalruntime_error");
        }
    }
}
