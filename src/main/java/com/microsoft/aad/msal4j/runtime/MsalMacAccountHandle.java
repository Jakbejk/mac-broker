package com.microsoft.aad.msal4j.runtime;

import com.sun.jna.ptr.LongByReference;

public class MsalMacAccountHandle extends MsalMacHandleBase {
    public MsalMacAccountHandle() {
        super(MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY::MSALMACRUNTIME_ReleaseAccount);
    }

    MsalMacAccountHandle(LongByReference msalRuntimeHandle) {
        super(msalRuntimeHandle, MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY::MSALMACRUNTIME_ReleaseAccount);
    }
}
