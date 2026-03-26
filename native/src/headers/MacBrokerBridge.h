#import <Foundation/Foundation.h>
#import <AuthenticationServices/AuthenticationServices.h>

typedef void (^BrokerAuthCompletion)(NSURL * _Nullable callbackURL, NSError * _Nullable error);

@interface MacBrokerBridge : NSObject <ASWebAuthenticationPresentationContextProviding>

@property (nonatomic, strong) NSString *clientId;
@property (nonatomic, strong) NSString *tenantId; // e.g., "common" or your Directory ID
@property (nonatomic, strong) NSString *redirectUri;
@property (nonatomic, strong) NSArray<NSString *> *scopes;

- (instancetype)initWithClientId:(NSString *)clientId
                        tenantId:(NSString *)tenantId
                     redirectUri:(NSString *)redirectUri
                          scopes:(NSArray<NSString *> *)scopes;

- (void)loginWithCompletion:(BrokerAuthCompletion)completion;

@end