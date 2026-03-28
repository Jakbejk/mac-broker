package com.microsoft.aad.msal4j.runtime;

import com.microsoft.azure.javamsalruntime.MsalInteropException;
import com.sun.jna.Structure;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class MsalMacReadAccountResult extends Structure {
    private static final Logger LOG = LoggerFactory.getLogger(MsalMacReadAccountResult.class);

    // JNA requires at least one public field to convert its Structure class to a native structure
    public int unused;

    private MsalMacAccount account;
    private MsalMacReadAccountResultHandle resultHandle;

    public MsalMacReadAccountResult(MsalMacReadAccountResultHandle readAccountResultHandle) {
        this.resultHandle = readAccountResultHandle;
        parseReadAccountResult();
    }

    public MsalMacAccount getAccount() {
        return account;
    }

    /**
     * Calls various MSALRuntime APIs to retrieve data using the
     * MSALRUNTIME_READ_ACCOUNT_RESULT_HANDLE passed into the callback method
     */
    void parseReadAccountResult() {
        if (this.resultHandle.isHandleValid()) {
            LOG.info("Checking read account result error.");
            MsalMacErrorHandle error = new MsalMacErrorHandle();

            MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(
                    MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_GetReadAccountError(this.resultHandle.value(), error));

            MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(error);

            LOG.info("Parsing read account result.");
            parseAndSetAccount();
        } else {
            throw new MsalInteropException("Read account result handle was invalid, could not parse.", "msalruntime_error");
        }
    }

    /**
     * If the auth result handle has an account handle, parse and store it in this ReadAccountResult
     */
    void parseAndSetAccount() {
        MsalMacAccountHandle accountHandle = new MsalMacAccountHandle();

        MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(
                MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_GetReadAccount(this.resultHandle.value(), accountHandle));
        this.account = new MsalMacAccount(accountHandle);
    }
}
