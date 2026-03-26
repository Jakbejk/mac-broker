package com.microsoft.aad.msal4j.runtime;

import com.sun.jna.ptr.LongByReference;

public class MsalMacSignOutResultHandle extends MsalMacHandleBase {
    public MsalMacSignOutResultHandle() {
        super(MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY::MSALMACRUNTIME_ReleaseSignOutResult);
    }

    MsalMacSignOutResultHandle(LongByReference msalRuntimeHandle) {
        super(msalRuntimeHandle,
                MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY::MSALMACRUNTIME_ReleaseSignOutResult);
    }
}
