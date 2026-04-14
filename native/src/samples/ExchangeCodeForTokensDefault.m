#import <Cocoa/Cocoa.h>
#import "Msal4JRuntimeWindowController.h"
#import "Msal4JTokenExchange.h"
#import "SampleAuthCommon.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        SamplePrepareForegroundApp();
        NSString *authURL = SampleAuthURL();
        NSString *tokenEndpoint = SampleTokenEndpoint();

        Msal4JTokenExchange *exchange = [[Msal4JTokenExchange alloc]
                initWithTokenEndpoint:tokenEndpoint
                clientId:kSampleClientId
                redirectURI:kSampleRedirectURI];

        Msal4JRuntimeWindowController *controller =
            [[Msal4JRuntimeWindowController alloc]
              initWithAuthURL:authURL
              redirectURI:kSampleRedirectURI
              promptBehavior:Msal4JPromptBehaviorDefault
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
                        SampleLogTokenSet(tokenSet);
                    }
                    [NSApp stop:nil];
                }];
            }];

        [controller showWindow:nil];
        [NSApp run];
    }
    return 0;
}
