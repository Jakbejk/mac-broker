package com.microsoft.aad.msal4j.runtime;

import com.sun.jna.ptr.LongByReference;

public class MsalMacAsyncHandle extends MsalMacHandleBase {

    public MsalMacAsyncHandle() {
        super(MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY::MSALMACRUNTIME_ReleaseAsyncHandle);
    }

    MsalMacAsyncHandle(LongByReference msalRuntimeHandle) {
        super(msalRuntimeHandle, MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY::MSALMACRUNTIME_ReleaseAsyncHandle);
    }
}
