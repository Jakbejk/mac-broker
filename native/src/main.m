self.bridge = [[MacBrokerBridge alloc] initWithClientId:@"your-client-id"
                                               tenantId:@"common"
                                            redirectUri:@"msauth.com.company.app://auth"
                                                 scopes:@[@"User.Read", @"offline_access"]];

[self.bridge loginWithCompletion:^(NSURL * _Nullable callbackURL, NSError * _Nullable error) {
    if (error) {
        NSLog(@"Broker Error: %@", error.localizedDescription);
    } else {
        NSLog(@"Success! Parse the code from: %@", callbackURL.absoluteString);
        // You can now extract the 'code' parameter and exchange it for a token
    }
}];