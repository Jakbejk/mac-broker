#ifndef MSAL4JTOKENEXCHANGE_H
#define MSAL4JTOKENEXCHANGE_H

#import <Foundation/Foundation.h>
#import "Msal4JTokenSet.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * Performs an OAuth2 authorization-code → token-set exchange against the
 * Microsoft identity platform token endpoint.
 *
 * Usage:
 * @code
 * Msal4JTokenExchange *exchange =
 *     [[Msal4JTokenExchange alloc] initWithTokenEndpoint:@"https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token"
 *                                               clientId:@"<client-id>"
 *                                            redirectURI:@"<redirect-uri>"];
 *
 * [exchange exchangeCode:authCode
 *          codeVerifier:pkceVerifier  // or nil if PKCE was not used
 *            completion:^(Msal4JTokenSet *tokenSet, NSError *error) { ... }];
 * @endcode
 */
@interface Msal4JTokenExchange : NSObject

/**
 * Designated initializer.
 *
 * @param tokenEndpoint  Full token endpoint URL, e.g.
 *                       @c https://login.microsoftonline.com/{tenant}/oauth2/v2.0/token
 * @param clientId       The application (client) ID.
 * @param redirectURI    The redirect URI used in the authorization request.
 */
- (instancetype)initWithTokenEndpoint:(NSString *)tokenEndpoint
                             clientId:(NSString *)clientId
                          redirectURI:(NSString *)redirectURI NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

/**
 * Exchanges an authorization code for a token set.
 *
 * The request is performed on a background NSURLSession data task.
 * The completion block is always called on the main queue.
 *
 * @param authCode      The authorization code received from the authorization endpoint.
 * @param codeVerifier  PKCE code verifier used when building the authorization URL,
 *                      or @c nil if PKCE was not used.
 * @param completion    Called with either a populated @c Msal4JTokenSet or an @c NSError.
 *                      Exactly one of the two will be non-nil.
 */
- (void)exchangeCode:(NSString *)authCode
        codeVerifier:(nullable NSString *)codeVerifier
          completion:(void (^)(Msal4JTokenSet *_Nullable tokenSet,
                               NSError        *_Nullable error))completion;

@end

NS_ASSUME_NONNULL_END

#endif // MSAL4JTOKENEXCHANGE_H
