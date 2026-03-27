package com.microsoft.aad.msal4j.runtime;

import com.microsoft.azure.javamsalruntime.AuthParameters;
import com.microsoft.azure.javamsalruntime.LogCallbackHandle;
import com.microsoft.azure.javamsalruntime.MsalInteropException;
import com.sun.jna.Native;
import com.sun.jna.Platform;
import com.sun.jna.Pointer;
import com.sun.jna.WString;
import com.sun.jna.platform.win32.Kernel32;
import com.sun.jna.platform.win32.User32;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public class MsalMacRuntimeInterop {
    // This static instance of MsalMacRuntimeLibrary helps to ensure that startup is called on a
    // per-process basis, and to simplify the many calls to MsalMacRuntimeLibrary's API
    public static final MsalMacRuntimeLibrary MSALRUNTIME_LIBRARY;
    // Used to simplify the many calls made to ErrorHandler during error checking and exception
    // handling
    public static final MsalMacErrorHelper ERROR_HELPER;
    private static final Logger LOG = LoggerFactory.getLogger(MsalMacRuntimeInterop.class);
    private static final String LIB_BASENAME = "MacBrokerBridge";
    private static final String LIB_FILENAME = System.mapLibraryName(LIB_BASENAME);
    private static final String LIB_PATH_PROPERTY = "msalmacruntime.dll.path";
    private static final String LIB_PATH_ENV = "MSALMACRUNTIME_DLL_PATH";
    private static LogCallbackHandle logCallbackHandle;
    private static MsalMacCallbacks.LogCallback logCallback = new MsalMacCallbacks.LogCallback();

    static {
        LOG.info("Setting up MSALRuntime.");
        MSALRUNTIME_LIBRARY = loadMsalRuntimeLibrary();
        ERROR_HELPER = new MsalMacErrorHelper();

        // Add shutdown hook to call the MSALRuntime shutdown API when the JVM process exits
        Runtime.getRuntime().addShutdownHook(new Thread(MsalMacRuntimeInterop::shutdownMsalRuntime));
    }

    /**
     * Calls MSALRuntime's shutdown API
     * <p>
     * Also completes any remaining futures, and performs any necessary cleanup steps to avoid
     * memory leaks
     */
    public static void shutdownMsalRuntime() {
        LOG.info("Shutting down MSALRuntime.");

        for (Map.Entry<Integer, MsalMacRuntimeFuture> entry : MsalMacRuntimeFuture.msalMacRuntimeFutures.entrySet()) {
            entry.getValue().completeExceptionally(new MsalInteropException("MSALRuntime shutdown API called before operation could complete", "msalruntime_shutdown"));
            entry.getValue().handle.release();
            MsalMacRuntimeFuture.msalMacRuntimeFutures.entrySet().remove(entry);
        }

        if (logCallbackHandle != null) logCallbackHandle.release();

        // MSALMACRUNTIME_Shutdown doesn't return an error handle, nothing for us to check
        MSALRUNTIME_LIBRARY.MSALMACRUNTIME_Shutdown();
        LOG.info("MSALRuntime shutdown API called successfully.");
    }

    /**
     * Sets up the necessary callbacks and handles to integrate MSALRuntime logs into MSAL Java's
     * logging framework, allowing detailed logs from MSALRuntime's native code to appear in
     * javamsalruntime's logs
     * <p>
     * By default, detailed logs from MSALRuntime will not be shown, though some MSALRuntime error
     * messages may appear as part of a thrown exception
     *
     * @param enableLogging true enables MSALRuntime logging, false disables it
     */
    public static synchronized void enableLogging(boolean enableLogging) {
        if (enableLogging) {
            // Avoid calling logging APIs if logging is already enabled
            if (logCallbackHandle == null) {
                LogCallbackHandle handle = new LogCallbackHandle();

                ERROR_HELPER.checkMsalRuntimeError(MSALRUNTIME_LIBRARY.MSALMACRUNTIME_RegisterLogCallback(logCallback, null, handle));

                // Assign the handle to the global variable only after a successful call to
                // RegisterLogCallback
                logCallbackHandle = handle;
            }

        } else {
            // According to comments in MSALRuntime's MSALRuntimeLogging.h, releasing the log
            // callback handle will de-register it
            logCallbackHandle.release();
            logCallbackHandle = null;
        }
    }

    /**
     * Allows PII data to appear in MSALRuntime error messages and logs
     * <p>
     * By default, PII logging is disabled
     *
     * @param enablePIILogging true enables PII logging, false disables it
     */
    public static synchronized void enableLoggingPii(boolean enablePIILogging) {
        // The MSALMACRUNTIME_SetIsPiiEnabled API enables PII logging if sent a value of '1', otherwise
        // it disables PII logging
        if (enablePIILogging) {
            MSALRUNTIME_LIBRARY.MSALMACRUNTIME_SetIsPiiEnabled(1);
        } else {
            MSALRUNTIME_LIBRARY.MSALMACRUNTIME_SetIsPiiEnabled(0);
        }
    }

    /**
     * Performs any checks necessary to identify the system architecture and chose the correct
     * MSALRuntime dll, and uses JNA to associate that dll with our MsalMacRuntimeLibrary interface
     *
     * @return an MsalMacRuntimeLibrary instance that can be used to call into a C++ dll from Java
     */
    static MsalMacRuntimeLibrary loadMsalRuntimeLibrary() {
        LOG.info("Loading native library for MSALRuntime interop.");
        try {
            if (!Platform.isMac()) {
                throw new MsalInteropException("Could not detect platform, or platform was not supported.", "msalruntime_initialization_error");
            }

            for (Path candidateFile : resolveLibraryCandidates()) {
                if (Files.exists(candidateFile) && Files.isRegularFile(candidateFile)) {
                    Path absoluteFile = candidateFile.toAbsolutePath().normalize();
                    Path parentDir = absoluteFile.getParent();

                    if (parentDir != null) {
                        System.setProperty("jna.library.path", parentDir.toString());
                    }

                    LOG.info("Loading native library from {}", absoluteFile);
                    return Native.load(absoluteFile.toString(), MsalMacRuntimeLibrary.class);
                }
            }

            LOG.info("No explicit native file found, falling back to JNA name-based lookup for {}", LIB_BASENAME);
            return Native.load(LIB_BASENAME, MsalMacRuntimeLibrary.class);
        } catch (UnsatisfiedLinkError e) {
            LOG.error("Could not find or load MSALRuntime dylib.", e);
            throw new MsalInteropException("Could not find or load MSALRuntime dylib.", "msalruntime_initialization_error");
        }
    }

    private static List<Path> resolveLibraryCandidates() {
        List<Path> candidates = new ArrayList<>();
        addPathCandidate(candidates, System.getProperty(LIB_PATH_PROPERTY));
        addPathCandidate(candidates, System.getenv(LIB_PATH_ENV));

        Path workingDir = Paths.get("").toAbsolutePath().normalize();
        candidates.add(workingDir.resolve("native").resolve("build").resolve(LIB_FILENAME));
        candidates.add(workingDir.resolve("native").resolve("build").resolve("MacBrokerBridge.dylib"));
        candidates.add(workingDir.resolve("build").resolve("native").resolve(LIB_FILENAME));

        return candidates;
    }

    private static void addPathCandidate(List<Path> candidates, String configuredPath) {
        if (configuredPath == null || configuredPath.isBlank()) {
            return;
        }

        Path path = Paths.get(configuredPath).toAbsolutePath().normalize();
        if (Files.isDirectory(path)) {
            candidates.add(path.resolve(LIB_FILENAME));
            candidates.add(path.resolve("MacBrokerBridge.dylib"));
        } else {
            candidates.add(path);
        }
    }

    /**
     * Calls MSALRuntime's startup API
     */
    public void startupMsalRuntime() {
        ERROR_HELPER.checkMsalRuntimeError(MSALRUNTIME_LIBRARY.MSALMACRUNTIME_Startup());
        LOG.info("MSALRuntime startup API called successfully.");
    }

    /**
     * Retrieves any cached account information for a given account ID
     *
     * @param accountId     the ID of the account we will retrieve data for
     * @param correlationId unique ID used to identify a certain request throughout various
     *                      telemetry and logs
     * @return an AsyncHandler instance, which can be treated as a CompletableFuture
     */
    public MsalMacRuntimeFuture readAccountById(String accountId, String correlationId) {
        MsalMacRuntimeFuture msalRuntimeFuture = new MsalMacRuntimeFuture(new MsalMacCallbacks.ReadAccountResultCallback());

        msalRuntimeFuture.callback = new MsalMacCallbacks.ReadAccountResultCallback();

        ERROR_HELPER.checkMsalRuntimeError(MSALRUNTIME_LIBRARY.MSALMACRUNTIME_ReadAccountByIdAsync(new WString(accountId), new WString(correlationId), (MsalMacCallbacks.ReadAccountResultCallback) msalRuntimeFuture.callback, msalRuntimeFuture.msalRuntimeFuturesKey, msalRuntimeFuture.handle));

        return msalRuntimeFuture;
    }

    /**
     * Calls MSALRuntime's SignIn API, which will attempt a silent sign in and fall back to
     * interactive if needed <p> This API essentially combines the behavior signInSilently and
     * signInInteractively
     *
     * @param windowHandle   the parent window handle that will be used to coordinate UI elements
     *                       shown to the user
     * @param authParameters a number of parameters to be used in this request
     * @param correlationId  unique ID used to identify a certain request throughout various
     *                       telemetry and logs
     * @param loginHint      a login hint (such as a username) that may be shown to the user
     * @return an AsyncHandler instance, which can be treated as a CompletableFuture
     */
    public MsalMacRuntimeFuture signIn(long windowHandle, AuthParameters authParameters, String correlationId, String loginHint) {
        MsalMacRuntimeFuture msalRuntimeFuture = new MsalMacRuntimeFuture(new MsalMacCallbacks.AuthResultCallback());

        windowHandle = checkWindowHandle(windowHandle);

        ERROR_HELPER.checkMsalRuntimeError(MSALRUNTIME_LIBRARY.MSALMACRUNTIME_SignInAsync(windowHandle, authParameters.getHandle().value(), new WString(correlationId), new WString(loginHint == null ? "" : loginHint), (MsalMacCallbacks.AuthResultCallback) msalRuntimeFuture.callback, msalRuntimeFuture.msalRuntimeFuturesKey, msalRuntimeFuture.handle));

        return msalRuntimeFuture;
    }

    /**
     * Calls MSALRuntime's SignInSilently API to attempt a sign in without showing a UI to the user
     *
     * @param authParameters a number of parameters to be used in this request
     * @param correlationId  unique ID used to identify a certain request throughout various
     *                       telemetry and logs
     * @return an AsyncHandler instance, which can be treated as a CompletableFuture
     */
    public MsalMacRuntimeFuture signInSilently(AuthParameters authParameters, String correlationId) {
        MsalMacRuntimeFuture msalRuntimeFuture = new MsalMacRuntimeFuture(new MsalMacCallbacks.AuthResultCallback());
        ERROR_HELPER.checkMsalRuntimeError(MSALRUNTIME_LIBRARY.MSALMACRUNTIME_SignInSilentlyAsync(authParameters.getHandle().value(), new WString(correlationId), (MsalMacCallbacks.AuthResultCallback) msalRuntimeFuture.callback, msalRuntimeFuture.msalRuntimeFuturesKey, msalRuntimeFuture.handle));

        return msalRuntimeFuture;
    }

    /**
     * Calls MSALRuntime's SignInInteractively API to attempt a sign in by showing a UI to the user
     *
     * @param windowHandle   the parent window handle that will be used to coordinate UI elements
     *                       shown to the user
     * @param authParameters a number of parameters to be used in this request
     * @param correlationId  unique ID used to identify a certain request throughout various
     *                       telemetry and logs
     * @param loginHint      a login hint (such as a username) that may be shown to the user
     * @return an AsyncHandler instance, which can be treated as a CompletableFuture
     */
    public MsalMacRuntimeFuture signInInteractively(long windowHandle, MsalMacAuthParameters authParameters, String correlationId, String loginHint) {
        MsalMacRuntimeFuture msalRuntimeFuture = new MsalMacRuntimeFuture(new MsalMacCallbacks.AuthResultCallback());

        windowHandle = checkWindowHandle(windowHandle);

        ERROR_HELPER.checkMsalRuntimeError(MSALRUNTIME_LIBRARY.MSALMACRUNTIME_SignInInteractivelyAsync(windowHandle, authParameters.getHandle().value(), new WString(correlationId), new WString(loginHint == null ? "" : loginHint), (MsalMacCallbacks.AuthResultCallback) msalRuntimeFuture.callback, msalRuntimeFuture.msalRuntimeFuturesKey, msalRuntimeFuture.handle));

        return msalRuntimeFuture;
    }

    /**
     * Calls MSALRuntime's AcquireTokenSilently API to retrieve tokens for a given account, without
     * showing a UI to the user
     *
     * @param authParameters a number of parameters to be used in this request
     * @param correlationId  unique ID used to identify a certain request throughout various
     *                       telemetry and logs
     * @param account        a ReadAccountResult instance, which must already be populated with a
     *                       ReadAccountResultHandle
     * @return an AsyncHandler instance, which can be treated as a CompletableFuture
     */
    public MsalMacRuntimeFuture acquireTokenSilently(AuthParameters authParameters, String correlationId, MsalMacAccount account) {
        if (account.getHandle() == null) {
            throw new MsalInteropException("Account handle is null, sign in or account discovery failed. Cannot retrieve tokens.", "msalruntime_account_error");
        }

        MsalMacRuntimeFuture msalRuntimeFuture = new MsalMacRuntimeFuture(new MsalMacCallbacks.AuthResultCallback());

        ERROR_HELPER.checkMsalRuntimeError(MSALRUNTIME_LIBRARY.MSALMACRUNTIME_AcquireTokenSilentlyAsync(authParameters.getHandle().value(), new WString(correlationId), account.getHandle().value(), (MsalMacCallbacks.AuthResultCallback) msalRuntimeFuture.callback, msalRuntimeFuture.msalRuntimeFuturesKey, msalRuntimeFuture.handle));

        return msalRuntimeFuture;
    }

    /**
     * Calls MSALRuntime's AcquireTokenInteractively API to retrieve tokens for a given account, by
     * showing a UI to the user
     *
     * @param windowHandle   the parent window handle that will be used to coordinate UI elements
     *                       shown to the user
     * @param authParameters a number of parameters to be used in this request
     * @param account        a ReadAccountResult instance, which must already be populated with a
     *                       ReadAccountResultHandle
     * @param correlationId  unique ID used to identify a certain request throughout various
     *                       telemetry and logs
     * @return an AsyncHandler instance, which can be treated as a CompletableFuture
     */
    public MsalMacRuntimeFuture acquireTokenInteractively(long windowHandle, MsalMacAuthParameters authParameters, String correlationId, MsalMacAccount account) {
        if (account.getHandle() == null) {
            throw new MsalInteropException("Account handle is null, sign in or account discovery failed. Cannot retrieve tokens.", "msalruntime_account_error");
        }

        MsalMacRuntimeFuture msalRuntimeFuture = new MsalMacRuntimeFuture(new MsalMacCallbacks.AuthResultCallback());

        windowHandle = checkWindowHandle(windowHandle);

        ERROR_HELPER.checkMsalRuntimeError(MSALRUNTIME_LIBRARY.MSALMACRUNTIME_AcquireTokenInteractivelyAsync(windowHandle, authParameters.getHandle().value(), new WString(correlationId), account.getHandle().value(), (MsalMacCallbacks.AuthResultCallback) msalRuntimeFuture.callback, msalRuntimeFuture.msalRuntimeFuturesKey, msalRuntimeFuture.handle));

        return msalRuntimeFuture;
    }

    /**
     * Calls MSALRuntime's SignOut API, which will delete cached tokens for a given account and
     * require this account to perform a new sign in
     *
     * @param clientId      client ID used in the call that created the account information
     * @param correlationId unique ID used to identify a certain request throughout various
     *                      telemetry and logs
     * @param account       an Account object, which must be populated with a valid handle
     * @return an AsyncHandler instance, which can be treated as a CompletableFuture
     */
    public MsalMacRuntimeFuture signOutSilently(String clientId, String correlationId, MsalMacAccount account) {
        if (account.getHandle() == null) {
            throw new MsalInteropException("Account handle is null, cannot sign out.", "msalruntime_account_error");
        }

        MsalMacRuntimeFuture msalRuntimeFuture = new MsalMacRuntimeFuture(new MsalMacCallbacks.SignOutResultCallback());

        ERROR_HELPER.checkMsalRuntimeError(MSALRUNTIME_LIBRARY.MSALMACRUNTIME_SignOutSilentlyAsync(new WString(clientId), new WString(correlationId), account.getHandle().value(), (MsalMacCallbacks.SignOutResultCallback) msalRuntimeFuture.callback, msalRuntimeFuture.msalRuntimeFuturesKey, msalRuntimeFuture.handle));

        return msalRuntimeFuture;
    }

    long checkWindowHandle(long windowHandle) {
        if (windowHandle == 0) {
            try {
                return Pointer.nativeValue(User32.INSTANCE.GetAncestor(Kernel32.INSTANCE.GetConsoleWindow(), 3).getPointer());
            } catch (NullPointerException e) {
                throw new MsalInteropException("Window handle not provided, and could not retrieve console's window handle. Window handles must be provided if the application is not running in a Windows terminal.", "msalruntime_client_error");
            }
        } else {
            return windowHandle;
        }
    }
}
