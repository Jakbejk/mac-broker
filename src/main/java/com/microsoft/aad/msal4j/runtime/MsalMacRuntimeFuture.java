package com.microsoft.aad.msal4j.runtime;

import com.microsoft.azure.javamsalruntime.MsalInteropException;
import com.sun.jna.Callback;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.util.HashMap;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.atomic.AtomicInteger;

public class MsalMacRuntimeFuture extends CompletableFuture<Object> {

    private static final Logger LOG = LoggerFactory.getLogger(MsalMacRuntimeFuture.class);

    // This table and counter are used to keep track of uncompleted futures, and offer a way for the
    // callback methods to find the right future to complete
    static HashMap<Integer, MsalMacRuntimeFuture> msalMacRuntimeFutures = new HashMap<>();
    static AtomicInteger asyncHandleCounter = new AtomicInteger();
    // Generate unique keys, used by callback methods to identify the correct future to complete
    final Integer msalRuntimeFuturesKey = asyncHandleCounter.incrementAndGet();
    MsalMacAsyncHandle handle = new MsalMacAsyncHandle();
    // We only know a future is ready to complete when MSALRuntime calls the associated callback
    // reference,
    //  so keeping a reference to the object here will prevent premature garbage collection of that
    //  callback
    Callback callback;

    public MsalMacRuntimeFuture(Callback callback) {
        this.callback = callback;

        // Add this future to handles table, so the callback methods can find and complete them
        msalMacRuntimeFutures.putIfAbsent(this.msalRuntimeFuturesKey, this);
    }

    /**
     * Calls MSALRuntime's cancel API to cancel the related async operation, and releases the async
     * handle
     */
    public void cancelAsyncOperation() {
        if (handle.isHandleValid()) {
            try {
                LOG.info("Canceling async operation.");
                // Tells MSALRuntime to cancel the async operation, and releases the handle
                MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(
                        MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_CancelAsyncOperation(handle));
            } catch (MsalInteropException msalInteropEx) {
                throw msalInteropEx;
            } catch (Exception e) {
                MsalMacRuntimeInterop.ERROR_HELPER.logUnknownErrorReleasingHandle(e);
            } finally {
                handle.release();

                // Set local handle to null, to indicate that it has been released and prevent
                // attempts to use it again
                this.handle = null;
            }
        }
    }
}
