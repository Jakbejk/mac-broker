#ifndef MSAL4JRUNTIMEWINDOWCONTROLLER_H
#define MSAL4JRUNTIMEWINDOWCONTROLLER_H

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Controls the OAuth2 `prompt` query parameter sent to the authorization endpoint.
 * Maps directly to the values defined in the OAuth 2.0 / OpenID Connect specs and
 * supported by the Microsoft identity platform.
 */
typedef NS_ENUM(NSInteger, Msal4JPromptBehavior) {
    /** Omit the `prompt` parameter entirely — the server decides (may skip UI). */
    Msal4JPromptBehaviorDefault       = 0,
    /** `prompt=login`  — force the user to re-enter credentials. */
    Msal4JPromptBehaviorLogin         = 1,
    /** `prompt=select_account` — always show the account picker. */
    Msal4JPromptBehaviorSelectAccount = 2,
    /** `prompt=consent` — force the consent screen even if already granted. */
    Msal4JPromptBehaviorConsent       = 3,
    /** `prompt=none`  — silent only; the server returns an error if UI is needed. */
    Msal4JPromptBehaviorNone          = 4,
    /** `prompt=create` — Microsoft-specific: direct the user to the sign-up flow. */
    Msal4JPromptBehaviorCreate        = 5,
};

/**
 * Window controller that presents a WKWebView-based sign-in sheet for
 * interactive Microsoft authentication. Detects the redirect URI, extracts
 * the authorization code, and returns the result via a completion handler.
 */
@interface Msal4JRuntimeWindowController : NSWindowController <WKNavigationDelegate, NSWindowDelegate>

/** The authorization endpoint URL to load initially. */
@property (nonatomic, copy, readonly) NSString *authURL;

/** The redirect URI prefix used to detect the auth callback. */
@property (nonatomic, copy, readonly) NSString *redirectURI;

/**
 * Designated initializer.
 *
 * @param authURL           Full authorization URL (including query params).
 * @param redirectURI       Redirect URI prefix registered with the app.
 * @param promptBehavior    Controls the OAuth2 @c prompt parameter (see
 *                          @c Msal4JPromptBehavior). Pass
 *                          @c Msal4JPromptBehaviorDefault to omit it entirely.
 * @param completionHandler Called on the main queue with either an auth code
 *                          or an NSError. Exactly one of the two will be nil.
 */
- (instancetype)initWithAuthURL:(NSString *)authURL
                    redirectURI:(NSString *)redirectURI
                 promptBehavior:(Msal4JPromptBehavior)promptBehavior
              completionHandler:(void (^)(NSString *_Nullable authCode,
                                         NSError  *_Nullable error))completionHandler
    NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithWindow:(nullable NSWindow *)window NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

#endif // MSAL4JRUNTIMEWINDOWCONTROLLER_H
