package com.microsoft.aad.msal4j.runtime;

import com.microsoft.azure.javamsalruntime.MsalInteropException;
import com.sun.jna.Memory;
import com.sun.jna.Native;
import com.sun.jna.Pointer;
import com.sun.jna.ptr.IntByReference;
import com.sun.jna.ptr.LongByReference;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.lang.ref.PhantomReference;
import java.lang.ref.ReferenceQueue;

public class MsalMacHandleBase extends LongByReference implements AutoCloseable {
    private static final Logger LOG = LoggerFactory.getLogger(MsalMacHandleBase.class);
    /**
     * Thread that manages cleaning up Handles and their PhantomReferences
     */
    private final MsalMacHandleBase.HandleFinalizerThread HANDLE_FINALIZER_THREAD = new MsalMacHandleBase.HandleFinalizerThread();
    protected LongByReference msalRuntimeHandle;
    MsalMacHandleBase.ReleaseMethod releaseMethod;

    MsalMacHandleBase(MsalMacHandleBase.ReleaseMethod releaseMethod) {
        this.msalRuntimeHandle = new LongByReference();
        this.releaseMethod = releaseMethod;

        HANDLE_FINALIZER_THREAD.addReference(this, msalRuntimeHandle, releaseMethod);
    }

    MsalMacHandleBase(LongByReference msalRuntimeHandle, MsalMacHandleBase.ReleaseMethod releaseMethod) {
        this.msalRuntimeHandle = msalRuntimeHandle;
        this.releaseMethod = releaseMethod;

        HANDLE_FINALIZER_THREAD.addReference(this, msalRuntimeHandle, releaseMethod);
    }

    /**
     * Helper method for returning a String from MSALRuntime
     * <p>
     * Any MSALRuntime API that populates a String requires two calls: the first is needed to figure
     * out the size of the String, and the second call actually populates the String
     *
     * @param handle               a handle representing some block of data which (should) contain a
     *                             String
     * @param getMSALRuntimeString the MSALRuntime API that we will call in order to retrieve a
     *                             String
     * @return the String retrieved from MSALRuntime
     */
    static String getString(MsalMacHandleBase handle, MsalMacHandleBase.GetMsalRuntimeString getMSALRuntimeString) {
        IntByReference bufferSize = new IntByReference(0);
        // First call asks native code for required size.
        getMSALRuntimeString.getString(handle, null, bufferSize);
        if (bufferSize.getValue() <= 0) {
            return "";
        }

        // Second call copies the value into caller-managed memory.
        Pointer stringMemoryLocation = new Memory((long) Native.WCHAR_SIZE * bufferSize.getValue());
        MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(
                getMSALRuntimeString.getString(handle, stringMemoryLocation, bufferSize));

        return stringMemoryLocation.getWideString(0);
    }

    /**
     * Returns the handle value that this Handle instance represents. This value is generally set by
     * MSALRuntime, and is how the interop can access data managed by MSALRuntime
     */
    public long value() {
        return this.getValue();
    }

    /**
     * Handle objects extend LongByReference, so they will have a default value of 0
     * <p>
     * Various MSALRuntime APIs take a fresh (value = 0) Handle as a parameter and sets it to some
     * non-zero value, allowing it to act as a reference to some underlying data managed by
     * MSALRuntime
     *
     * @return boolean true if this handle was set to some non-zero value, false otherwise
     */
    boolean isHandleValid() {
        return value() != 0;
    }

    /**
     * All Java objects created by the interop will either be cleaned up by the JVM's garbage
     * collector or by the operating system if the JVM shuts down, however the MSALRuntime handles
     * and their underlying data won't be since the JVM doesn't actually know about that data <p>
     * So, to avoid memory leaks all MSALRuntime handles must eventually be 'released' by calling
     * the appropriate MSALRuntime MSALRuntime_RELEASE* API for that type of handle <p> In most
     * cases a handle can be released immediately after using it to retrieve some data, however
     * there are some scenarios where handles must be stored for an indefinite amount of time and we
     * must rely on Java's PhantomReference and our AsyncHandleFinalizerThread
     */
    public void release() {
        if (isHandleValid()) {
            try {
                // Release handle using the MSALRuntime API set when this object was created
                MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(
                        releaseMethod.release(this.value()));
                // Set local handle to null, to indicate that it has been released and prevent
                // attempts to use it again
                this.msalRuntimeHandle = null;
            } catch (MsalInteropException e) {
                throw e;
            } catch (Exception e) {
                MsalMacRuntimeInterop.ERROR_HELPER.logUnknownErrorReleasingHandle(e);
            }
        }
    }

    /**
     * Used to automatically release handles created in a try-with-resources block
     */
    @Override
    public void close() {
        release();
    }

    /**
     * Interface which allows an MSALRuntime_RELEASE* function to be passed as a parameter, allowing
     * all MSALRuntime release methods to be called by this class
     */
    @FunctionalInterface
    interface ReleaseMethod {
        MsalMacErrorHandle release(long handle);
    }

    /**
     * Interface which allows data to be retrieved from any MSALRuntime API which populates a String
     */
    @FunctionalInterface
    interface GetMsalRuntimeString {
        MsalMacErrorHandle getString(MsalMacHandleBase handle, Pointer stringReference, IntByReference bufferSize);
    }

    /**
     * Class used to represent a phantom reference to a Handle instance, allowing handles to be
     * released via AsyncHandleFinalizerThread when the phantom reference is the instance's only
     * reference
     * <p>
     * This class cannot have reference to the actual Handle instance, since that would create a
     * strong reference that is never removed, so it must hold copies of any Handle data needed for
     * calling the MSALRuntime release API
     */
    class HandleFinalizer extends PhantomReference<MsalMacHandleBase> {
        private final Logger LOG = LoggerFactory.getLogger(MsalMacHandleBase.HandleFinalizer.class);

        private LongByReference finalizerMsalRuntimeHandle;
        private MsalMacHandleBase.ReleaseMethod finalizerReleaseMethod;

        private HandleFinalizer(
                MsalMacHandleBase handle, LongByReference msalRuntimeHandle, MsalMacHandleBase.ReleaseMethod releaseMethod,
                ReferenceQueue<MsalMacHandleBase> queue) {
            super(handle, queue);

            // Copy Handle's value and release methods, so the
            this.finalizerMsalRuntimeHandle = msalRuntimeHandle;
            this.finalizerReleaseMethod = releaseMethod;
        }

        private void release() {
            LOG.debug("Releasing a handle via PhantomReference");

            if (finalizerMsalRuntimeHandle != null && finalizerMsalRuntimeHandle.getValue() != 0) {
                try {
                    // Release handle using the MSALRuntime API set when this object was created
                    MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(
                            finalizerReleaseMethod.release(finalizerMsalRuntimeHandle.getValue()));
                    // Set local handle to null, to indicate that it has been released and prevent
                    // attempts to use it again
                    this.finalizerMsalRuntimeHandle = null;
                } catch (MsalInteropException e) {
                    throw e;
                } catch (Exception e) {
                    MsalMacRuntimeInterop.ERROR_HELPER.logUnknownErrorReleasingHandle(e);
                }
            }
        }
    }

    /**
     * Thread which will start when the first Handle is created.
     * <p>
     * This thread will be responsible for releasing handles in scenarios where we can't release
     * them immediately, and as a fail-safe in case a handle isn't released properly
     */
    class HandleFinalizerThread extends Thread {
        private final Logger LOG = LoggerFactory.getLogger(MsalMacHandleBase.HandleFinalizerThread.class);

        private ReferenceQueue<MsalMacHandleBase> handleReferenceQueue = new ReferenceQueue<>();

        HandleFinalizerThread() {
            setDaemon(true);
        }

        /**
         * Create a new PhantomReference to a give Handle by creating a HandleFinalizer with this
         * Handle's value and release method <p> When the PhantomReference is the only remaining
         * reference to the Handle, the HandleFinalizer will appear in handleReferenceQueue and the
         * Handle will be released
         */
        void addReference(
                MsalMacHandleBase handle, LongByReference msalRuntimeHandle, MsalMacHandleBase.ReleaseMethod releaseMethod) {
            // When the first Handle is created, start the finalizer thread that all Handles share
            if (!HANDLE_FINALIZER_THREAD.isAlive()) {
                // Set up unknown exception handling for the thread, to ensure as much as possible
                // gets released cleanly
                HANDLE_FINALIZER_THREAD.setUncaughtExceptionHandler((th, ex) -> {
                    LOG.error(
                            "Unexpected exception in HandleFinalizerThread with {} open async handles. Will attempt to cancel any async operations before stopping thread.",
                            MsalMacRuntimeFuture.msalMacRuntimeFutures.size());

                    for (MsalMacRuntimeFuture future : MsalMacRuntimeFuture.msalMacRuntimeFutures.values()) {
                        future.cancelAsyncOperation();
                        future.handle.release();
                    }
                });

                HANDLE_FINALIZER_THREAD.start();
            }

            new MsalMacHandleBase.HandleFinalizer(handle, msalRuntimeHandle, releaseMethod, handleReferenceQueue);
        }

        @Override
        public void run() {
            try {
                while (true) {
                    // Although this is an infinite loop, ReferenceQueue's remove() method causes it
                    // to wait until an entry appears in handleReferenceQueue. This will only happen
                    // when a Handle is reachable only through a PhantomReference, and can therefore
                    // be released
                    MsalMacHandleBase.HandleFinalizer handleFinalizer = (MsalMacHandleBase.HandleFinalizer) handleReferenceQueue.remove();
                    LOG.info("Found Handle with no references, closing.");
                    handleFinalizer.release();
                }
            } catch (InterruptedException e) {
                // Ideally, this will only run when the entire program shuts down, and most handles
                // will be released via their close() method if their in a try-with-resources block
                //
                // MsalRuntimeFuture.msalRuntimeFutures allows us to track async handles, so we can
                // at least guarantee they always get canceled/released

                LOG.error(
                        "HandleFinalizerThread interrupted with {} open async handles. Will attempt to cancel any async operations before stopping thread.",
                        MsalMacRuntimeFuture.msalMacRuntimeFutures.size());

                for (MsalMacRuntimeFuture future : MsalMacRuntimeFuture.msalMacRuntimeFutures.values()) {
                    future.cancelAsyncOperation();
                    future.handle.release();
                }
            }
        }
    }
}
