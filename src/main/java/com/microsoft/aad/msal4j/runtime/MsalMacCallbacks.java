package com.microsoft.aad.msal4j.runtime;

import com.microsoft.azure.javamsalruntime.MsalInteropException;
import com.sun.jna.Callback;
import com.sun.jna.WString;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class MsalMacCallbacks {

    private static final Logger LOG = LoggerFactory.getLogger(MsalMacCallbacks.class);

    /**
     * Performs any validation needed to ensure that a result from MSALRuntime can be parsed and
     * used to complete an MsalRuntimeFuture
     */
    static void validateResult(MsalMacHandleBase handle, Integer msalRuntimeFuturesKey) {
        if (!handle.isHandleValid()) {
            throw new MsalInteropException(
                    "Result handle sent to callback is invalid, cannot parse result.",
                    "msalinterop_error");
        }

        if (MsalMacRuntimeFuture.msalMacRuntimeFutures.get(msalRuntimeFuturesKey) == null) {
            throw new MsalInteropException(
                    "Future missing from msalRuntimeFutures table, cannot complete future.",
                    "msalinterop_error");
        }
    }

    // Use JNA's Callback interface to handle conversion between our callback classes and the
    // relevant native type
    interface AuthResultCallbackInterface extends Callback {
        void callback(MsalMacAuthResultHandle authResult, Integer callbackData);
    }

    interface ReadAccountResultCallbackInterface extends Callback {
        void callback(MsalMacReadAccountResultHandle readAccountResult, Integer callbackData);
    }

    interface SignOutResultCallbackInterface extends Callback {
        void callback(MsalMacSignOutResultHandle signOutResult, Integer callbackData);
    }

    interface LogCallbackInterface extends Callback {
        void callback(WString logMessage, Integer logLevel, Integer callbackData);
    }

    static class AuthResultCallback implements MsalMacCallbacks.AuthResultCallbackInterface {
        /**
         * This method will be passed to MSALRuntime as a parameter of the SignIn and AcquireToken
         * APIs <p> MSALRuntime will call this method to signal that a result is ready to be parsed,
         * and once parsed we can complete the future that is waiting for this AuthResult
         */
        @Override
        public void callback(MsalMacAuthResultHandle authResultHandle, Integer msalRuntimeFuturesKey) {
            try {
                LOG.info("Starting auth result callback.");
                MsalMacCallbacks.validateResult(authResultHandle, msalRuntimeFuturesKey);

                LOG.info("Auth result valid, parsing result and completing future.");
                MsalMacRuntimeFuture.msalMacRuntimeFutures.get(msalRuntimeFuturesKey)
                        .complete(new MsalMacAuthResult(authResultHandle));
            } catch (MsalInteropException msalInteropEx) {
                LOG.error(
                        "Could not complete future with auth result, completing with MsalInteropException.");
                MsalMacRuntimeFuture.msalMacRuntimeFutures.get(msalRuntimeFuturesKey)
                        .completeExceptionally(msalInteropEx);
            } catch (Exception e) {
                LOG.error("Could not complete future due to unknown exception, completing future with the exception.");
                MsalMacRuntimeFuture.msalMacRuntimeFutures.get(msalRuntimeFuturesKey).completeExceptionally(e);
            } finally {
                // Async operation completed, remove the related future from the global list of
                // uncompleted futures
                MsalMacRuntimeFuture.msalMacRuntimeFutures.remove(msalRuntimeFuturesKey);
            }
        }
    }

    public static class SignOutResultCallback implements MsalMacCallbacks.SignOutResultCallbackInterface {
        /**
         * This method will be passed to MSALRuntime as a parameter of the SignOut APIs
         * <p>
         * MSALRuntime will call this method to signal that a result is ready to be parsed, and once
         * parsed we can complete the future that is waiting for this SignOutResult
         */
        @Override
        public void callback(MsalMacSignOutResultHandle signOutResultHandle, Integer msalRuntimeFuturesKey) {
            try {
                LOG.info("Starting sign out result callback.");
                MsalMacCallbacks.validateResult(signOutResultHandle, msalRuntimeFuturesKey);

                LOG.info("Sign out result valid, parsing result and completing future.");
                MsalMacRuntimeFuture.msalMacRuntimeFutures.get(msalRuntimeFuturesKey)
                        .complete(new MsalMacSignOutResult(signOutResultHandle));
            } catch (MsalInteropException msalInteropEx) {
                LOG.error(
                        "Could not complete future with sign out result, completing with MsalInteropException.");
                MsalMacRuntimeFuture.msalMacRuntimeFutures.get(msalRuntimeFuturesKey)
                        .completeExceptionally(msalInteropEx);
            } catch (Exception e) {
                LOG.error("Could not complete future due to unknown exception, completing future with the exception.");
                MsalMacRuntimeFuture.msalMacRuntimeFutures.get(msalRuntimeFuturesKey).completeExceptionally(e);
            } finally {
                // Async operation completed, remove the related future from the global list of
                // uncompleted futures
                MsalMacRuntimeFuture.msalMacRuntimeFutures.remove(msalRuntimeFuturesKey);
            }
        }
    }

    public static class ReadAccountResultCallback implements MsalMacCallbacks.ReadAccountResultCallbackInterface {
        /**
         * This method will be passed to MSALRuntime as a parameter of the ReadAccount APIs
         * <p>
         * MSALRuntime will call this method to signal that a result is ready to be parsed, and once
         * parsed we can complete the future that is waiting for this ReadAccountResult
         */
        @Override
        public void callback(
                MsalMacReadAccountResultHandle readAccountResultHandle, Integer msalRuntimeFuturesKey) {
            try {
                LOG.info("Starting read account callback.");
                MsalMacCallbacks.validateResult(readAccountResultHandle, msalRuntimeFuturesKey);

                LOG.info("Read account result valid, parsing result and completing future.");
                MsalMacRuntimeFuture.msalMacRuntimeFutures.get(msalRuntimeFuturesKey)
                        .complete(new MsalMacReadAccountResult(readAccountResultHandle));
            } catch (MsalInteropException msalInteropEx) {
                LOG.error(
                        "Could not complete future with read account result, completing with MsalInteropException.");
                MsalMacRuntimeFuture.msalMacRuntimeFutures.get(msalRuntimeFuturesKey)
                        .completeExceptionally(msalInteropEx);
            } catch (Exception e) {
                LOG.error(
                        "Could not complete future due to unknown exception, completing future with the exception.");
                MsalMacRuntimeFuture.msalMacRuntimeFutures.get(msalRuntimeFuturesKey).completeExceptionally(e);
            } finally {
                // Async operation completed, remove the related future from the global list of
                // uncompleted futures
                MsalMacRuntimeFuture.msalMacRuntimeFutures.remove(msalRuntimeFuturesKey);
            }
        }
    }

    public static class LogCallback implements MsalMacCallbacks.LogCallbackInterface {
        @Override
        public void callback(WString logMessage, Integer logLevel, Integer callbackData) {
            // Just used to clearly mark any logs that are coming directly from MSALRuntime
            String indicateMsalRuntimeLog = "(MSALRuntime log) {}";

            try {
                // logLevel corresponds to MSALRuntime's MSALRuntimeTypes.MSALRUNTIME_LOG_LEVEL enum
                switch (logLevel) {
                    case 1:
                        LOG.trace(indicateMsalRuntimeLog, logMessage);
                        break;
                    case 2:
                        LOG.debug(indicateMsalRuntimeLog, logMessage);
                        break;
                    case 3:
                        LOG.info(indicateMsalRuntimeLog, logMessage);
                        break;
                    case 4:
                        LOG.warn(indicateMsalRuntimeLog, logMessage);
                        break;
                    case 5:
                    case 6:
                        LOG.error(indicateMsalRuntimeLog, logMessage); // Error (5) and Fatal (6)
                        break;
                    default:
                        LOG.debug("MSALRuntime log with no corresponding log level: {}", logMessage);
                        break;
                }
            } catch (Exception e) {
                try {
                    LOG.error("Exception during MSALRuntime log callback: {}", e.getMessage());
                } catch (Exception ignored) {
                    // If an exception gets thrown when trying to log a message, then MSALRuntime
                    // will call
                    //  this callback again to log the error, potentially leading to an infinite loop
                }
            }
        }
    }

}
