#import <Cocoa/Cocoa.h>
#import "Msal4JRuntimeWindowController.h"
#import "SampleAuthCommon.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        SamplePrepareForegroundApp();
        NSString *authURL = SampleAuthURL(NO);

        Msal4JRuntimeWindowController *controller =
            [[Msal4JRuntimeWindowController alloc]
                initWithAuthURL:authURL
                    redirectURI:kSampleRedirectURI
                 promptBehavior:Msal4JPromptBehaviorDefault
              completionHandler:^(NSString *authCode, NSError *error) {
                if (authCode) {
                    NSLog(@"[main] Auth code received: %@", authCode);
                } else {
                    NSLog(@"[main] Sign-in failed or cancelled: %@", error);
                }
                [NSApp stop:nil];
            }];

        [controller showWindow:nil];
        [NSApp run];
    }
    return 0;
}
