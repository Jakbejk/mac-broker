#ifndef MSAL4JTOKENSET_H
#define MSAL4JTOKENSET_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Immutable value object holding the tokens returned by a successful
 * OAuth2 authorization-code token exchange.
 */
@interface Msal4JTokenSet : NSObject

/** Bearer access token for calling protected APIs. */
@property (nonatomic, copy, readonly) NSString *accessToken;

/** Token type — typically @c "Bearer". */
@property (nonatomic, copy, readonly) NSString *tokenType;

/** Lifetime of the access token in seconds as reported by the server. */
@property (nonatomic, assign, readonly) NSTimeInterval expiresIn;

/** Absolute expiry time derived from @c expiresIn at the moment of receipt. */
@property (nonatomic, strong, readonly) NSDate *expiresAt;

/** Refresh token for obtaining new access tokens silently. May be nil. */
@property (nonatomic, copy, readonly, nullable) NSString *refreshToken;

/** Raw ID token (JWT) containing user identity claims. May be nil. */
@property (nonatomic, copy, readonly, nullable) NSString *idToken;

/** Space-separated scopes actually granted by the server. May be nil. */
@property (nonatomic, copy, readonly, nullable) NSString *scope;

/**
 * Designated initializer — used by @c Msal4JTokenExchange to build the result.
 */
- (instancetype)initWithAccessToken:(NSString *)accessToken
                          tokenType:(NSString *)tokenType
                          expiresIn:(NSTimeInterval)expiresIn
                       refreshToken:(nullable NSString *)refreshToken
                            idToken:(nullable NSString *)idToken
                              scope:(nullable NSString *)scope NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

#endif // MSAL4JTOKENSET_H
