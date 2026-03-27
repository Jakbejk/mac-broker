package com.microsoft.aad.msal4j.runtime;

import com.microsoft.azure.javamsalruntime.AuthParameters;
import com.microsoft.azure.javamsalruntime.MsalInteropException;
import com.sun.jna.WString;

import java.net.URI;
import java.util.Map;

public class MsalMacAuthParameters implements AutoCloseable {
    private MsalMacAuthParametersHandle handle;

    private MsalMacAuthParameters(MsalMacAuthParameters.MsalMacAuthParametersBuilder builder) {
        this.handle = builder.handle;
    }

    public MsalMacAuthParametersHandle getHandle() {
        return handle;
    }

    public static class MsalMacAuthParametersBuilder {
        private MsalMacAuthParametersHandle handle = new MsalMacAuthParametersHandle();

        public MsalMacAuthParametersBuilder(String clientId, String authority, String scopes) {
            MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(
                    MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_CreateAuthParameters(
                            new WString(clientId), new WString(authority), handle));

            if (handle.isHandleValid()) {
                MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(
                        MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_SetRequestedScopes(
                                handle.value(), new WString(scopes)));
            } else {
                throw new MsalInteropException(
                        "MSALRUNTIME_CreateAuthParameters did not return an error but AuthParameters handle is invalid and cannot be used.",
                        "msalruntime_error");
            }
        }

        /**
         * Sets the redirect URI which is used when authorization is complete.
         *
         * This is a required parameter for interactive flows.
         */
        public MsalMacAuthParameters.MsalMacAuthParametersBuilder redirectUri(String redirectUri) {
            if (redirectUri != null) {
                MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(
                        MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_SetRedirectUri(
                                handle.value(), new WString(redirectUri)));
            }
            return this;
        }

        public MsalMacAuthParameters.MsalMacAuthParametersBuilder claims(String claims) {
            if (claims != null) {
                MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(
                        MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_SetDecodedClaims(
                                handle.value(), new WString(claims)));
            }
            return this;
        }

        /**
         * Set the auth scheme for the request. This is required to obtain a proof-of-possession
         * token.
         *
         * @param httpMethod a valid HTTP method, such as "GET" or "POST"
         * @param uri URI to associate with the token
         * @param nonce optional nonce value for the token, can be left empty
         */
        public MsalMacAuthParameters.MsalMacAuthParametersBuilder popParameters(String httpMethod, URI uri, String nonce) {
            if (httpMethod == null || uri == null || uri.getHost() == null) {
                throw new MsalInteropException(
                        "HTTP method and URI host must be non-null", "msalinteropexception");
            }

            // HTTP method must be uppercase, like "GET" or "POST"
            httpMethod = httpMethod.toUpperCase();
            String host = uri.getHost();
            // Path and nonce are optional, set to blank String if null
            String path = uri.getPath() != null ? uri.getPath() : "";
            nonce = nonce != null ? nonce : "";

            MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(
                    MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_SetPopParams(
                            handle.value(), new WString(httpMethod), new WString(host),
                            new WString(path), new WString(nonce)));

            return this;
        }

        public MsalMacAuthParameters.MsalMacAuthParametersBuilder additionalParameters(Map<String, String> parameters) {
            if (parameters != null) {
                for (Map.Entry<String, String> param : parameters.entrySet()) {
                    MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(
                            MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_SetAdditionalParameter(
                                    handle.value(), new WString(param.getKey()),
                                    new WString(param.getValue())));
                }
            }
            return this;
        }

        public MsalMacAuthParameters build() {
            return new MsalMacAuthParameters(this);
        }
    }

    /**
     * Used to set the username/password auth params, which are needed for the username/password
     * flow, and is here to assist integrating this project into existing applications that may
     * require the username/password flow <p> However, that flow is not recommended and we may stop
     * supporting it, which is why this method is separate from the AuthParametersBuilder and is
     * already marked as deprecated
     *
     * @deprecated
     */
    @Deprecated
    public void setUsernamePassword(String username, String password) {
        MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(
                MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_SetAdditionalParameter(
                        handle.value(), new WString("MSALRuntime_Username"), new WString(username)));
        MsalMacRuntimeInterop.ERROR_HELPER.checkMsalRuntimeError(
                MsalMacRuntimeInterop.MSALRUNTIME_LIBRARY.MSALMACRUNTIME_SetAdditionalParameter(
                        handle.value(), new WString("MSALRuntime_Password"), new WString(password)));
    }

    @Override
    public void close() {
        if (handle != null) {
            handle.close();

            handle = null;
        }
    }
}
