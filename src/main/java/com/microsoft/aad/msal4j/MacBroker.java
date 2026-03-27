package com.microsoft.aad.msal4j;

import com.microsoft.aad.msal4j.runtime.MsalMacAuthParameters;
import com.microsoft.aad.msal4j.runtime.MsalMacAuthResult;
import com.microsoft.aad.msal4j.runtime.MsalMacRuntimeInterop;
import com.microsoft.azure.javamsalruntime.AuthParameters;
import com.microsoft.azure.javamsalruntime.MsalInteropException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.lang.reflect.Field;
import java.net.MalformedURLException;
import java.util.Objects;
import java.util.UUID;
import java.util.concurrent.CompletableFuture;

public class MacBroker implements IBroker {

    private static final Logger LOG = LoggerFactory.getLogger(MacBroker.class);

    private static MsalMacRuntimeInterop interop;
    private static Boolean brokerAvailable;

    static {
        try {
            //MsalRuntimeInterop performs various initialization steps in a similar static block,
            // so when an MsalRuntimeBroker is created this will cause the interop layer to initialize
            interop = new MsalMacRuntimeInterop();
        } catch (MsalInteropException e) {
            throw new MsalClientException(String.format("Could not initialize MSALRuntime: %s", e.getErrorMessage()), AuthenticationErrorCode.MSALRUNTIME_INTEROP_ERROR);
        }
    }

    private boolean supportMac;

    private MacBroker(MacBroker.Builder builder) {
        this.supportMac = builder.supportMac;

        //This will be expanded to cover other OS options, but for now it is only Windows. Since Windows is the only
        // option, if app developer doesn't want to use the broker on Windows then they shouldn't use the Broker at all
        if (!this.supportMac) {
            throw new MsalClientException("At least one operating system support option must be used when building the Broker instance", AuthenticationErrorCode.MSALJAVA_BROKERS_ERROR);
        }
    }

    @Override
    public boolean isBrokerAvailable() {
        //brokerAvailable is only set after the first attempt to call MSALRuntime's startup API
        if (brokerAvailable == null) {
            try {
                interop.startupMsalRuntime();

                LOG.info("MSALRuntime started successfully. MSAL Java will use MSALRuntime in all supported broker flows.");

                brokerAvailable = true;
            } catch (MsalInteropException e) {
                LOG.warn("Exception thrown when trying to start MSALRuntime: {}", e.getErrorMessage());
                LOG.warn("MSALRuntime could not be started. MSAL Java will fall back to non-broker flows.");

                brokerAvailable = false;
            }
        }

        return brokerAvailable;
    }

    @Override
    public CompletableFuture<IAuthenticationResult> acquireToken(PublicClientApplication application, SilentParameters parameters) {
        Objects.requireNonNull(parameters, "parameters");

        RequestContext context;
        if (parameters.account() != null) {
            context = new RequestContext(application, PublicApi.ACQUIRE_TOKEN_SILENTLY, parameters, UserIdentifier.fromHomeAccountId(parameters.account().homeAccountId()));

        } else {
            context = new RequestContext(application, PublicApi.ACQUIRE_TOKEN_SILENTLY, parameters);
        }

        SilentRequest silentRequest;
        try {
            silentRequest = new SilentRequest(parameters, application, context, null);
        } catch (MalformedURLException e) {
            throw new RuntimeException(e);
        }
        return application.executeRequest(silentRequest);
    }

    @Override
    public CompletableFuture<IAuthenticationResult> acquireToken(PublicClientApplication application, InteractiveRequestParameters parameters) {
        String correlationID = application.correlationId() == null ? generateCorrelationID() : application.correlationId();
        try {
            MsalMacAuthParameters.MsalMacAuthParametersBuilder authParamsBuilder = new MsalMacAuthParameters.MsalMacAuthParametersBuilder(application.clientId(), application.authority(), String.join(" ", parameters.scopes())).redirectUri(parameters.redirectUri().toString()).additionalParameters(parameters.extraQueryParameters());

            //If POP auth scheme configured, set parameters to get MSALRuntime to return POP tokens
            if (parameters.proofOfPossession() != null) {
                authParamsBuilder.popParameters(parameters.proofOfPossession().getHttpMethod().methodName, parameters.proofOfPossession().getUri(), parameters.proofOfPossession().getNonce());
            }

            AuthParameters authParameters = authParamsBuilder.build();

            return interop.signInInteractively(parameters.windowHandle(), authParameters, correlationID, parameters.loginHint()).thenCompose(acctResult -> interop.acquireTokenInteractively(parameters.windowHandle(), authParameters, correlationID, ((MsalMacAuthResult) acctResult).getAccount())).thenApply(authResult -> parseBrokerAuthResult(application.authority(), ((MsalMacAuthResult) authResult).getIdToken(), ((MsalMacAuthResult) authResult).getAccessToken(), ((MsalMacAuthResult) authResult).getAccount().getAccountId(), ((MsalMacAuthResult) authResult).getAccount().getClientInfo(), ((MsalMacAuthResult) authResult).getAccessTokenExpirationTime(), ((MsalMacAuthResult) authResult).isPopAuthorization()));
        } catch (MsalInteropException interopException) {
            throw new MsalClientException(interopException.getErrorMessage(), AuthenticationErrorCode.MSALRUNTIME_INTEROP_ERROR);
        }
    }

    /**
     * // TODO trosku cheating, zjistit jestli jde udelat i nejak hezceji
     *
     * @return true if setting of value success, otherwise false
     */
    private boolean setBrokerAvailable(PublicClientApplication client, boolean brokerAvailable) {
        Class<?> publicClientApplication = client.getClass();
        try {
            Field brokerEnabled = publicClientApplication.getDeclaredField("brokerEnabled");
            brokerEnabled.set(client, brokerAvailable);
            return true;
        } catch (NoSuchFieldException | IllegalAccessException e) {
            LOG.error("Could not set brokerEnabled field in PublicClientApplication class");
        }
        return false;
    }

    private String generateCorrelationID() {
        return UUID.randomUUID().toString();
    }

    public static class Builder {
        private boolean supportMac = false;

        public Builder() {
        }

        /**
         * When set to true, MSAL Java will attempt to use the broker when the application is running on a Windows OS
         */
        public MacBroker.Builder supportMac(boolean val) {
            supportMac = val;
            return this;
        }

        public MacBroker build() {
            return new MacBroker(this);
        }
    }
}
