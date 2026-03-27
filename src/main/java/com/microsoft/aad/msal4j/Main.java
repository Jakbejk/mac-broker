package com.microsoft.aad.msal4j;

import com.microsoft.aad.msal4jbrokers.Broker;

import java.net.MalformedURLException;
import java.net.URI;

//TIP To <b>Run</b> code, press <shortcut actionId="Run"/> or
// click the <icon src="AllIcons.Actions.Execute"/> icon in the gutter.
public class Main {

    public static void main(String[] args) throws MalformedURLException {
        final String CLIENT_ID = "e98824f6-9015-4b9f-855e-0fa4f29e646f";
        final String TENANT_URL = "https://login.microsoftonline.com/8f862eed-9fbe-4938-bc19-c12025b13c2d";
        final String CALLBACK_URL = "http://localhost:8085";

        MacBroker macBroker = new MacBroker.Builder().supportMac(true).build();
        PublicClientApplication pca = PublicClientApplication.builder(CLIENT_ID).authority(TENANT_URL).broker(macBroker).build();
        InteractiveRequestParameters params = InteractiveRequestParameters.builder(URI.create(CALLBACK_URL)).build();
        IAuthenticationResult ar = pca.acquireToken(params).join();
        System.out.println("Access Token: " + ar.accessToken());
    }
}