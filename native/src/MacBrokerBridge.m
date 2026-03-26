#import "MacBrokerBridge.h"

@interface MacBrokerBridge ()
@property (nonatomic, strong) ASWebAuthenticationSession *authSession;
@end

@implementation MacBrokerBridge

- (instancetype)initWithClientId:(NSString *)clientId
                        tenantId:(NSString *)tenantId
                     redirectUri:(NSString *)redirectUri
                          scopes:(NSArray<NSString *> *)scopes {
    self = [super init];
    if (self) {
        _clientId = clientId;
        _tenantId = tenantId;
        _redirectUri = redirectUri;
        _scopes = scopes;
    }
    return self;
}

- (void)loginWithCompletion:(BrokerAuthCompletion)completion {
    // 1. Construct the Scope String
    NSString *scopeString = [self.scopes componentsJoinedByString:@" "];
    NSString *encodedScopes = [scopeString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]];

    // 2. Build the Entra ID / Microsoft Auth URL
    NSString *urlPath = [NSString stringWithFormat:@"https://login.microsoftonline.com/%@/oauth2/v2.0/authorize?client_id=%@&response_type=code&redirect_uri=%@&scope=%@&response_mode=query",
                         self.tenantId, self.clientId, self.redirectUri, encodedScopes];

    NSURL *authURL = [NSURL URLWithString:urlPath];

    // 3. Extract the scheme from redirectUri for the callback
    // Usually "msauth.com.your.bundle.id"
    NSString *scheme = [[NSURL URLWithString:self.redirectUri] scheme];

    // 4. Initialize the session
    self.authSession = [[ASWebAuthenticationSession alloc]
                        initWithURL:authURL
                        callbackURLScheme:scheme
                        completionHandler:^(NSURL * _Nullable callbackURL, NSError * _Nullable error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(callbackURL, error);
        });
    }];

    self.authSession.presentationContextProvider = self;

    // CRITICAL: Set this to NO to allow the Enterprise SSO Extension (Broker)
    // to use shared cookies and system-level tokens.
    self.authSession.prefersEphemeralWebBrowserSession = NO;

    [self.authSession start];
}

#pragma mark - ASWebAuthenticationPresentationContextProviding

- (ASPresentationAnchor)presentationAnchorForWebAuthenticationSession:(ASWebAuthenticationSession *)session {
    // Returns the main window of your Mac App
    return [NSApplication sharedApplication].mainWindow;
}

@end