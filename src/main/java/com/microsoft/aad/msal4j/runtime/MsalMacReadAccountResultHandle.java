package com.microsoft.aad.msal4j.runtime;

import com.sun.jna.ptr.LongByReference;

public class MsalMacReadAccountResultHandle extends MsalMacHandleBase {
    public MsalMacReadAccountResultHandle() {
        super(MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY::MSALMACRUNTIME_ReleaseReadAccountResult);
    }

    MsalMacReadAccountResultHandle(LongByReference msalRuntimeHandle) {
        super(msalRuntimeHandle, MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY::MSALMACRUNTIME_ReleaseReadAccountResult);
    }
}
