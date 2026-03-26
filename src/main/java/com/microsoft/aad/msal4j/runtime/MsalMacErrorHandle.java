package com.microsoft.aad.msal4j.runtime;

import com.sun.jna.ptr.LongByReference;

public class MsalMacErrorHandle extends MsalMacHandleBase {

    public MsalMacErrorHandle() {
        super(MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY::MSALMACRUNTIME_ReleaseError);
    }

    MsalMacErrorHandle(LongByReference msalRuntimeHandle) {
        super(msalRuntimeHandle, MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY::MSALMACRUNTIME_ReleaseError);
    }
}
