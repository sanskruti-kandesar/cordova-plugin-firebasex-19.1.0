#import "AppDelegate.h"
#import "FirebaseWrapper.h"
#import <Cordova/CDV.h>

/**
 * Main plugin class for Firebase Cloud Messaging in Cordova for iOS.
 */
@interface FirebasePlugin : CDVPlugin

+ (FirebasePlugin *)firebasePlugin;

@property(nonatomic, copy) NSString *notificationCallbackId;
@property(nonatomic, copy) NSString *openSettingsCallbackId;
@property(nonatomic, copy) NSString *tokenRefreshCallbackId;
@property(nonatomic, copy) NSString *apnsTokenRefreshCallbackId;
@property(nonatomic, retain) NSMutableArray *notificationStack;
@property(nonatomic, assign) BOOL isFCMEnabled;

- (void)setAutoInitEnabled:(CDVInvokedUrlCommand *)command;
- (void)isAutoInitEnabled:(CDVInvokedUrlCommand *)command;
- (void)sendPendingNotifications;
- (void)sendNotification:(NSDictionary *)userInfo;
- (void)sendToken:(NSString *)token;
- (void)sendApnsToken:(NSString *)token;
- (void)sendOpenNotificationSettings;

- (void)getId:(CDVInvokedUrlCommand *)command;
- (void)getToken:(CDVInvokedUrlCommand *)command;
- (void)getAPNSToken:(CDVInvokedUrlCommand *)command;
- (void)onMessageReceived:(CDVInvokedUrlCommand *)command;
- (void)onTokenRefresh:(CDVInvokedUrlCommand *)command;
- (void)onApnsTokenReceived:(CDVInvokedUrlCommand *)command;
- (void)onOpenSettings:(CDVInvokedUrlCommand *)command;
- (void)subscribe:(CDVInvokedUrlCommand *)command;
- (void)unsubscribe:(CDVInvokedUrlCommand *)command;
- (void)unregister:(CDVInvokedUrlCommand *)command;

- (void)grantPermission:(CDVInvokedUrlCommand *)command;
- (void)hasPermission:(CDVInvokedUrlCommand *)command;
- (void)grantCriticalPermission:(CDVInvokedUrlCommand *)command;
- (void)hasCriticalPermission:(CDVInvokedUrlCommand *)command;
- (void)setBadgeNumber:(CDVInvokedUrlCommand *)command;
- (void)getBadgeNumber:(CDVInvokedUrlCommand *)command;
- (void)clearAllNotifications:(CDVInvokedUrlCommand *)command;

- (void)getInstallationId:(CDVInvokedUrlCommand *)command;
- (void)getInstallationToken:(CDVInvokedUrlCommand *)command;
- (void)deleteInstallationId:(CDVInvokedUrlCommand *)command;

// Channel stubs for cross-platform compatibility
- (void)createChannel:(CDVInvokedUrlCommand *)command;
- (void)setDefaultChannel:(CDVInvokedUrlCommand *)command;
- (void)deleteChannel:(CDVInvokedUrlCommand *)command;
- (void)listChannels:(CDVInvokedUrlCommand *)command;

- (void)logMessage:(CDVInvokedUrlCommand *)command;

- (void)_logError:(NSString *)msg;
- (void)_logInfo:(NSString *)msg;
- (void)_logMessage:(NSString *)msg;
- (void)executeGlobalJavascript:(NSString *)jsString;
- (void)handlePluginExceptionWithContext:(NSException *)exception;
- (void)handlePluginExceptionWithoutContext:(NSException *)exception;
- (NSString *)hexadecimalStringFromData:(NSData *)data;

@end
