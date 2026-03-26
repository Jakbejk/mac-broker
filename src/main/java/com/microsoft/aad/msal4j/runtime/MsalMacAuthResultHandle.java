package com.microsoft.aad.msal4j.runtime;

import com.sun.jna.ptr.LongByReference;

public class MsalMacAuthResultHandle extends MsalMacHandleBase {
    public MsalMacAuthResultHandle() {
        super(MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY::MSALMACRUNTIME_ReleaseAuthResult);
    }

    MsalMacAuthResultHandle(LongByReference msalRuntimeHandle) {
        super(msalRuntimeHandle,
                MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY::MSALMACRUNTIME_ReleaseAuthResult);
    }
}
