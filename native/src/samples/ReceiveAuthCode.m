#import <Cocoa/Cocoa.h>
#import "Msal4JRuntimeWindowController.h"

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        // Command-line tools run as background processes by default.
        // This promotes the process to a foreground app so it receives keyboard events.
        ProcessSerialNumber psn = {0, kCurrentProcess};
        TransformProcessType(&psn, kProcessTransformToForegroundApplication);

        [NSApplication sharedApplication];

        NSString *authURL    = @"https://login.microsoftonline.com/8f862eed-9fbe-4938-bc19-c12025b13c2d/oauth2/v2.0/authorize"
                               @"?client_id=78548114-9254-4fd5-b3b2-77740a15d344"
                               @"&response_type=code"
                               @"&redirect_uri=msauth.78548114-9254-4fd5-b3b2-77740a15d344://auth"
                               @"&scope=openid%20profile";
        NSString *redirectURI = @"msauth.78548114-9254-4fd5-b3b2-77740a15d344://auth";

        Msal4JRuntimeWindowController *controller =
            [[Msal4JRuntimeWindowController alloc]
                initWithAuthURL:authURL
                redirectURI:redirectURI
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