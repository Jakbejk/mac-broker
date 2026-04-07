#import "Msal4JTokenExchange.h"

static NSString *const kErrorDomain = @"Msal4JTokenExchange";

// ── Error codes ────────────────────────────────────────────────────────────
static const NSInteger kErrInvalidEndpoint  = 1;
static const NSInteger kErrNetwork          = 2;
static const NSInteger kErrBadResponse      = 3;
static const NSInteger kErrServerError      = 4;
static const NSInteger kErrMissingToken     = 5;

// ── Msal4JTokenSet implementation ──────────────────────────────────────────
@implementation Msal4JTokenSet

- (instancetype)initWithAccessToken:(NSString *)accessToken
                          tokenType:(NSString *)tokenType
                          expiresIn:(NSTimeInterval)expiresIn
                       refreshToken:(nullable NSString *)refreshToken
                            idToken:(nullable NSString *)idToken
                              scope:(nullable NSString *)scope {
    self = [super init];
    if (!self) { return nil; }
    _accessToken  = [accessToken copy];
    _tokenType    = [tokenType copy];
    _expiresIn    = expiresIn;
    _expiresAt    = [NSDate dateWithTimeIntervalSinceNow:expiresIn];
    _refreshToken = [refreshToken copy];
    _idToken      = [idToken copy];
    _scope        = [scope copy];
    return self;
}

@end

// ── Msal4JTokenExchange implementation ────────────────────────────────────
@interface Msal4JTokenExchange ()
@property (nonatomic, copy) NSString *tokenEndpoint;
@property (nonatomic, copy) NSString *clientId;
@property (nonatomic, copy) NSString *redirectURI;
@property (nonatomic, strong) NSURLSession *session;
@end

@implementation Msal4JTokenExchange

- (instancetype)initWithTokenEndpoint:(NSString *)tokenEndpoint
                             clientId:(NSString *)clientId
                          redirectURI:(NSString *)redirectURI {
    self = [super init];
    if (!self) { return nil; }
    _tokenEndpoint = [tokenEndpoint copy];
    _clientId      = [clientId copy];
    _redirectURI   = [redirectURI copy];
    _session       = [NSURLSession sessionWithConfiguration:
                        [NSURLSessionConfiguration defaultSessionConfiguration]];
    return self;
}

// ── Public ─────────────────────────────────────────────────────────────────

- (void)exchangeCode:(NSString *)authCode
        codeVerifier:(nullable NSString *)codeVerifier
          completion:(void (^)(Msal4JTokenSet *_Nullable, NSError *_Nullable))completion {

    NSLog(@"[Msal4JTokenExchange] Starting code exchange.");

    NSURL *url = [NSURL URLWithString:self.tokenEndpoint];
    if (!url) {
        NSLog(@"[Msal4JTokenExchange] Invalid token endpoint: %@", self.tokenEndpoint);
        [self p_callCompletion:completion tokenSet:nil
                         error:[self p_errorWithCode:kErrInvalidEndpoint
                                        description:@"Invalid token endpoint URL"]];
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    request.HTTPBody = [self p_buildBodyWithCode:authCode codeVerifier:codeVerifier];

    NSURLSessionDataTask *task =
        [self.session dataTaskWithRequest:request
                        completionHandler:^(NSData *data, NSURLResponse *response, NSError *networkError) {
            if (networkError) {
                NSLog(@"[Msal4JTokenExchange] Network error: %@", networkError);
                [self p_callCompletion:completion tokenSet:nil
                                 error:[self p_errorWithCode:kErrNetwork
                                                description:networkError.localizedDescription]];
                return;
            }

            NSHTTPURLResponse *http = (NSHTTPURLResponse *)response;
            NSLog(@"[Msal4JTokenExchange] HTTP %ld", (long)http.statusCode);

            NSError *parseError = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                 options:0
                                                                   error:&parseError];
            if (!json) {
                NSLog(@"[Msal4JTokenExchange] Failed to parse response: %@", parseError);
                [self p_callCompletion:completion tokenSet:nil
                                 error:[self p_errorWithCode:kErrBadResponse
                                                description:@"Response is not valid JSON"]];
                return;
            }

            // The server returns error details in JSON even for non-2xx responses.
            if (http.statusCode < 200 || http.statusCode >= 300) {
                NSString *desc = json[@"error_description"] ?: json[@"error"] ?: @"Token endpoint error";
                NSLog(@"[Msal4JTokenExchange] Server error: %@", desc);
                [self p_callCompletion:completion tokenSet:nil
                                 error:[self p_errorWithCode:kErrServerError description:desc]];
                return;
            }

            NSString *accessToken = json[@"access_token"];
            if (!accessToken) {
                NSLog(@"[Msal4JTokenExchange] Response missing access_token.");
                [self p_callCompletion:completion tokenSet:nil
                                 error:[self p_errorWithCode:kErrMissingToken
                                                description:@"Response missing access_token"]];
                return;
            }

            Msal4JTokenSet *tokenSet =
                [[Msal4JTokenSet alloc]
                    initWithAccessToken:accessToken
                              tokenType:json[@"token_type"] ?: @"Bearer"
                              expiresIn:[json[@"expires_in"] doubleValue]
                           refreshToken:json[@"refresh_token"]
                                idToken:json[@"id_token"]
                                  scope:json[@"scope"]];

            NSLog(@"[Msal4JTokenExchange] Token exchange succeeded. expires_in=%.0fs",
                  tokenSet.expiresIn);
            [self p_callCompletion:completion tokenSet:tokenSet error:nil];
        }];

    [task resume];
}

// ── Private ────────────────────────────────────────────────────────────────

/** Builds the application/x-www-form-urlencoded POST body. */
- (NSData *)p_buildBodyWithCode:(NSString *)authCode
                   codeVerifier:(nullable NSString *)codeVerifier {
    NSMutableArray<NSString *> *pairs = [NSMutableArray array];

    void (^add)(NSString *, NSString *) = ^(NSString *key, NSString *value) {
        [pairs addObject:[NSString stringWithFormat:@"%@=%@",
                          key, [self p_urlEncode:value]]];
    };

    add(@"grant_type",   @"authorization_code");
    add(@"code",         authCode);
    add(@"client_id",    self.clientId);
    add(@"redirect_uri", self.redirectURI);

    if (codeVerifier) {
        add(@"code_verifier", codeVerifier);
    }

    NSString *body = [pairs componentsJoinedByString:@"&"];
    return [body dataUsingEncoding:NSUTF8StringEncoding];
}

/** Percent-encodes a string for use in an application/x-www-form-urlencoded body. */
- (NSString *)p_urlEncode:(NSString *)string {
    // RFC 3986 unreserved characters — everything else is encoded.
    NSCharacterSet *allowed =
        [NSCharacterSet characterSetWithCharactersInString:
            @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [string stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: string;
}

- (NSError *)p_errorWithCode:(NSInteger)code description:(NSString *)description {
    return [NSError errorWithDomain:kErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

- (void)p_callCompletion:(void (^)(Msal4JTokenSet *_Nullable, NSError *_Nullable))completion
                tokenSet:(nullable Msal4JTokenSet *)tokenSet
                   error:(nullable NSError *)error {
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(tokenSet, error);
    });
}

@end
