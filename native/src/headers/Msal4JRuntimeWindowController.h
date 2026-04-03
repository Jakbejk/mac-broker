#ifndef MSAL4JRUNTIMEWINDOWCONTROLLER_H
#define MSAL4JRUNTIMEWINDOWCONTROLLER_H

#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>

NS_ASSUME_NONNULL_BEGIN

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
 * @param completionHandler Called on the main queue with either an auth code
 *                          or an NSError. Exactly one of the two will be nil.
 */
- (instancetype)initWithAuthURL:(NSString *)authURL
                    redirectURI:(NSString *)redirectURI
              completionHandler:(void (^)(NSString *_Nullable authCode,
                                         NSError  *_Nullable error))completionHandler
    NS_DESIGNATED_INITIALIZER;

- (instancetype)initWithWindow:(nullable NSWindow *)window NS_UNAVAILABLE;
- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END

#endif // MSAL4JRUNTIMEWINDOWCONTROLLER_H
