#pragma once

#import <Cocoa/Cocoa.h>
#import "Msal4JTokenSet.h"

static NSString *const kSampleTenantId = @"8f862eed-9fbe-4938-bc19-c12025b13c2d";
static NSString *const kSampleClientId = @"78548114-9254-4fd5-b3b2-77740a15d344";
static NSString *const kSampleRedirectURI = @"msauth.78548114-9254-4fd5-b3b2-77740a15d344://auth";

NS_INLINE void SamplePrepareForegroundApp(void) {
    // Command-line tools run as background processes by default.
    // This promotes the process to a foreground app so it receives keyboard events.
    ProcessSerialNumber psn = {0, kCurrentProcess};
    TransformProcessType(&psn, kProcessTransformToForegroundApplication);
    [NSApplication sharedApplication];
}

NS_INLINE NSString *SampleAuthURL() {
    return [NSString stringWithFormat:
        @"https://login.microsoftonline.com/%@/oauth2/v2.0/authorize"
        @"?client_id=%@"
        @"&response_type=code"
        @"&redirect_uri=%@"
        @"&scope=openid%%20profile%%20email%%20offline_access",
        kSampleTenantId, kSampleClientId, kSampleRedirectURI];
}

NS_INLINE NSString *SampleTokenEndpoint(void) {
    return [NSString stringWithFormat:
        @"https://login.microsoftonline.com/%@/oauth2/v2.0/token",
        kSampleTenantId];
}

NS_INLINE void SampleLogTokenSet(Msal4JTokenSet *tokenSet) {
    NSLog(@"[main] Access token : %@", tokenSet.accessToken);
    NSLog(@"[main] Token type   : %@", tokenSet.tokenType);
    NSLog(@"[main] Expires in   : %.0f s", tokenSet.expiresIn);
    NSLog(@"[main] Expires at   : %@", tokenSet.expiresAt);
    NSLog(@"[main] Refresh token: %@", tokenSet.refreshToken ?: @"(none)");
    NSLog(@"[main] ID token     : %@", tokenSet.idToken      ?: @"(none)");
    NSLog(@"[main] Scope        : %@", tokenSet.scope        ?: @"(none)");
}
