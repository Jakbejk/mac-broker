#import "Msal4JRuntimeWindowController.h"

static NSString *const kErrorDomain = @"Msal4JRuntimeWindowController";
static const NSInteger kErrorCodeCancelled  = -1;
static const NSInteger kErrorCodeNoAuthCode = -2;

// ---------------------------------------------------------------------------
// Private interface
// ---------------------------------------------------------------------------

@interface Msal4JRuntimeWindowController ()

@property (nonatomic, copy) void (^completionHandler)(NSString *_Nullable, NSError *_Nullable);
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, assign) Msal4JPromptBehavior promptBehavior;
/** Guards against calling the completion handler more than once. */
@property (nonatomic, assign) BOOL didComplete;

@end

// ---------------------------------------------------------------------------
// Implementation
// ---------------------------------------------------------------------------

@implementation Msal4JRuntimeWindowController

#pragma mark - Initialisation

- (instancetype)initWithAuthURL:(NSString *)authURL
                    redirectURI:(NSString *)redirectURI
                 promptBehavior:(Msal4JPromptBehavior)promptBehavior
              completionHandler:(void (^)(NSString *_Nullable, NSError *_Nullable))completionHandler {
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 480, 640)
                  styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                    backing:NSBackingStoreBuffered
                      defer:NO];

    self = [super initWithWindow:window];
    if (!self) { return nil; }

    _authURL           = [authURL copy];
    _redirectURI       = [redirectURI copy];
    _promptBehavior    = promptBehavior;
    _completionHandler = [completionHandler copy];
    _didComplete       = NO;

    [self p_setupWebView];

    NSLog(@"[Msal4JRuntimeWindowController] Initialised. authURL=%@  redirectURI=%@", authURL, redirectURI);
    return self;
}

#pragma mark - Window lifecycle

// windowDidLoad is NOT invoked when the controller is created with initWithWindow:
// (no nib to load). We override showWindow: instead so the URL load is triggered
// exactly once, right before the window becomes visible.
- (void)showWindow:(id)sender {
    [NSApp activateIgnoringOtherApps:YES];
    [super showWindow:sender];
    [self.window makeFirstResponder:self.webView];

    NSString *urlString = self.authURL;
    NSString *promptValue = [self p_promptValueForBehavior:self.promptBehavior];
    if (promptValue) {
        NSString *separator = ([urlString containsString:@"?"] ? @"&" : @"?");
        urlString = [urlString stringByAppendingFormat:@"%@prompt=%@", separator, promptValue];
        NSLog(@"[Msal4JRuntimeWindowController] Appended prompt=%@.", promptValue);
    }

    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        NSLog(@"[Msal4JRuntimeWindowController] Invalid authURL: %@", urlString);
        NSError *error = [NSError errorWithDomain:kErrorDomain
                                             code:kErrorCodeNoAuthCode
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        @"Invalid authorization URL"}];
        [self p_finishWithAuthCode:nil error:error];
        return;
    }

    NSLog(@"[Msal4JRuntimeWindowController] Loading auth URL.");
    [self.webView loadRequest:[NSURLRequest requestWithURL:url]];
}

#pragma mark - WKNavigationDelegate

- (void)webView:(WKWebView *)webView
    decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction
                    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {

    NSString *urlString = navigationAction.request.URL.absoluteString;
    NSLog(@"[Msal4JRuntimeWindowController] Navigation requested: %@", urlString);

    if ([urlString hasPrefix:self.redirectURI]) {
        NSLog(@"[Msal4JRuntimeWindowController] Redirect URI detected.");
        decisionHandler(WKNavigationActionPolicyCancel);

        NSString *authCode = [self p_authCodeFromURL:navigationAction.request.URL];
        if (authCode) {
            NSLog(@"[Msal4JRuntimeWindowController] Auth code extracted successfully.");
            [self p_finishWithAuthCode:authCode error:nil];
        } else {
            NSLog(@"[Msal4JRuntimeWindowController] Redirect matched but no auth code found.");
            NSError *error = [NSError errorWithDomain:kErrorDomain
                                                 code:kErrorCodeNoAuthCode
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                            @"No authorization code in redirect URI"}];
            [self p_finishWithAuthCode:nil error:error];
        }
        return;
    }

    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView
    didFailNavigation:(WKNavigation *)navigation
            withError:(NSError *)error {
    NSLog(@"[Msal4JRuntimeWindowController] Navigation failed: %@", error);
    [self p_finishWithAuthCode:nil error:error];
}

- (void)webView:(WKWebView *)webView
    didFailProvisionalNavigation:(WKNavigation *)navigation
                       withError:(NSError *)error {
    NSLog(@"[Msal4JRuntimeWindowController] Provisional navigation failed: %@", error);
    [self p_finishWithAuthCode:nil error:error];
}

- (void)webView:(WKWebView *)webView
    didFinishNavigation:(WKNavigation *)navigation {
    NSLog(@"[Msal4JRuntimeWindowController] Navigation finished: %@",
          webView.URL.absoluteString);
}

#pragma mark - NSWindowDelegate

- (void)windowWillClose:(NSNotification *)notification {
    NSLog(@"[Msal4JRuntimeWindowController] Window closed by user.");
    NSError *error = [NSError errorWithDomain:kErrorDomain
                                         code:kErrorCodeCancelled
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"User cancelled sign-in"}];
    [self p_finishWithAuthCode:nil error:error];
}

#pragma mark - Private helpers

- (void)p_setupWebView {
    WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc] init];
    self.webView = [[WKWebView alloc] initWithFrame:self.window.contentView.bounds
                                      configuration:config];
    self.webView.navigationDelegate = self;
    self.webView.autoresizingMask   = NSViewWidthSizable | NSViewHeightSizable;
    [self.window.contentView addSubview:self.webView];

    // windowDidLoad is never called when using initWithWindow: (no nib),
    // so configure the window here instead.
    self.window.title    = @"Sign In";
    self.window.delegate = self;
    [self.window center];
}

/** Returns the OAuth2 prompt string for the given behavior, or nil to omit the parameter. */
- (nullable NSString *)p_promptValueForBehavior:(Msal4JPromptBehavior)behavior {
    switch (behavior) {
        case Msal4JPromptBehaviorLogin:         return @"login";
        case Msal4JPromptBehaviorSelectAccount: return @"select_account";
        case Msal4JPromptBehaviorConsent:       return @"consent";
        case Msal4JPromptBehaviorNone:          return @"none";
        case Msal4JPromptBehaviorCreate:        return @"create";
        case Msal4JPromptBehaviorDefault:
        default:                                return nil;
    }
}

/** Extracts the `code` query parameter from the redirect URL. */
- (nullable NSString *)p_authCodeFromURL:(NSURL *)url {
    NSURLComponents *components =
        [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"code"]) {
            return item.value;
        }
    }
    return nil;
}

/**
 * Delivers the result exactly once on the main queue, then closes the window.
 * Subsequent calls are silently ignored.
 */
- (void)p_finishWithAuthCode:(nullable NSString *)authCode
                       error:(nullable NSError *)error {
    if (self.didComplete) { return; }
    self.didComplete = YES;

    Msal4JRuntimeWindowController *retainedSelf = [self retain];
    void (^handler)(NSString *_Nullable, NSError *_Nullable) = [self.completionHandler copy];
    NSString *authCodeCopy = [authCode copy];
    NSError *errorCopy = [error retain];
    self.completionHandler = nil;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (handler) { handler(authCodeCopy, errorCopy); }
        // Close without triggering windowWillClose recursion.
        NSWindow *window = retainedSelf.window;
        window.delegate = nil;
        [window close];

        [handler release];
        [authCodeCopy release];
        [errorCopy release];
        [retainedSelf release];
    });
}

@end
