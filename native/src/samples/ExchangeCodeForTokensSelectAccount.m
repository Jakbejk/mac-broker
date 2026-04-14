#import <Cocoa/Cocoa.h>
#import "Msal4JRuntimeWindowController.h"
#import "Msal4JTokenExchange.h"

static NSString *const kTenantId    = @"8f862eed-9fbe-4938-bc19-c12025b13c2d";
static NSString *const kClientId    = @"78548114-9254-4fd5-b3b2-77740a15d344";
static NSString *const kRedirectURI = @"msauth.78548114-9254-4fd5-b3b2-77740a15d344://auth";

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Command-line tools run as background processes by default.
        // This promotes the process to a foreground app so it receives keyboard events.
        ProcessSerialNumber psn = {0, kCurrentProcess};
        TransformProcessType(&psn, kProcessTransformToForegroundApplication);

        [NSApplication sharedApplication];

        NSString *authURL =
            [NSString stringWithFormat:
                @"https://login.microsoftonline.com/%@/oauth2/v2.0/authorize"
                @"?client_id=%@"
                @"&response_type=code"
                @"&redirect_uri=%@"
                @"&scope=openid%%20profile%%20offline_access",
                kTenantId, kClientId, kRedirectURI];

        NSString *tokenEndpoint = [NSString stringWithFormat: @"https://login.microsoftonline.com/%@/oauth2/v2.0/token", kTenantId];

        Msal4JTokenExchange *exchange = [[Msal4JTokenExchange alloc]
                initWithTokenEndpoint:tokenEndpoint
                clientId:kClientId
                redirectURI:kRedirectURI];

        Msal4JRuntimeWindowController *controller =
            [[Msal4JRuntimeWindowController alloc]
              initWithAuthURL:authURL
              redirectURI:kRedirectURI
              promptBehavior:Msal4JPromptBehaviorSelectAccount
              completionHandler:^(NSString *authCode, NSError *authError) {
                NSLog(@"[main] Auth code received: %@", authCode ?: @"(none)");
                if (authError) {
                    NSLog(@"[main] Sign-in failed or cancelled: %@", authError);
                    [NSApp stop:nil];
                    return;
                }

                NSLog(@"[main] Auth code received, exchanging for tokens...");
                [exchange exchangeCode:authCode codeVerifier:nil
                            completion:^(Msal4JTokenSet *tokenSet, NSError *tokenError) {
                    if (tokenError) {
                        NSLog(@"[main] Token exchange failed: %@", tokenError);
                    } else {
                        NSLog(@"[main] Access token : %@", tokenSet.accessToken);
                        NSLog(@"[main] Token type   : %@", tokenSet.tokenType);
                        NSLog(@"[main] Expires in   : %.0f s", tokenSet.expiresIn);
                        NSLog(@"[main] Expires at   : %@", tokenSet.expiresAt);
                        NSLog(@"[main] Refresh token: %@", tokenSet.refreshToken ?: @"(none)");
                        NSLog(@"[main] ID token     : %@", tokenSet.idToken      ?: @"(none)");
                        NSLog(@"[main] Scope        : %@", tokenSet.scope        ?: @"(none)");
                    }
                    [NSApp stop:nil];
                }];
            }];

        [controller showWindow:nil];
        [NSApp run];
    }
    return 0;
}
