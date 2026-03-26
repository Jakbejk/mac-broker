package com.microsoft.aad.msal4j.runtime;

import com.microsoft.aad.msal4j.IAccount;

public class MsalMacAccount implements AutoCloseable, IAccount {
    private MsalMacAccountHandle handle;
    private String accountId;
    private String accountClientInfo;

    MsalMacAccount(MsalMacAccountHandle accountHandle) {
        if (accountHandle.isHandleValid()) {
            this.handle = accountHandle;
        }
    }

    MsalMacAccountHandle getHandle() {
        return handle;
    }

    /**
     * Retrieves the account ID from MSALRuntime, and stores it in this Account instance
     */
    public String getAccountId() {
        if (accountId == null) {
            accountId = MsalMacHandleBase.getString(handle, (accountHandle, id, bufferSize) -> MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_GetAccountId(accountHandle.value(), id, bufferSize));
        }

        return accountId;
    }

    /**
     * Retrieves the client info String from MSALRuntime, and stores it in this Account instance
     */
    public String getClientInfo() {
        if (accountClientInfo == null) {
            accountClientInfo = MsalMacAccountHandle.getString(handle, (accountHandle, clientInfo, bufferSize) -> MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_GetClientInfo(accountHandle.value(), clientInfo, bufferSize));
        }

        return accountClientInfo;
    }

    @Override
    public void close() {
        if (handle != null) {
            handle.close();

            handle = null;
        }
    }
}
