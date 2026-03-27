package com.microsoft.aad.msal4j.runtime;

import com.sun.jna.ptr.LongByReference;

public class MsalMacAuthParametersHandle extends MsalMacHandleBase {
    public MsalMacAuthParametersHandle() {
        super(MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY::MSALMACRUNTIME_ReleaseAuthParameters);
    }

    MsalMacAuthParametersHandle(LongByReference msalRuntimeHandle) {
        super(msalRuntimeHandle,
                MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY::MSALMACRUNTIME_ReleaseAuthParameters);
    }
}
