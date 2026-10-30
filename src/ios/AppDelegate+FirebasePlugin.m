#import "AppDelegate+FirebasePlugin.h"
#import "FirebasePlugin.h"
#import "FirebaseWrapper.h"
#import <objc/runtime.h>

@import UserNotifications;

// Implement UNUserNotificationCenterDelegate to receive display notification
// via APNS for devices running iOS 10 and above. Implement FIRMessagingDelegate
// to receive data message via FCM for devices running iOS 10 and above.
@interface AppDelegate () <UNUserNotificationCenterDelegate,
                           FIRMessagingDelegate>
@end

#define kApplicationInBackgroundKey @"applicationInBackground"

@implementation AppDelegate (FirebasePlugin)

static AppDelegate *instance;

/**
 * Returns the singleton instance of the AppDelegate.
 *
 * @return The active AppDelegate instance.
 */
+ (AppDelegate *)instance {
  return instance;
}

static NSDictionary *mutableUserInfo;

static __weak id<UNUserNotificationCenterDelegate>
    _prevUserNotificationCenterDelegate = nil;

/**
 * Automatically called when the category is loaded.
 * Performs method swizzling for didFinishLaunchingWithOptions.
 */
+ (void)load {
  Method original =
      class_getInstanceMethod(self, @selector(application:
                                        didFinishLaunchingWithOptions:));
  Method swizzled = class_getInstanceMethod(
      self, @selector(application:swizzledDidFinishLaunchingWithOptions:));
  method_exchangeImplementations(original, swizzled);
}

- (void)setApplicationInBackground:(NSNumber *)applicationInBackground {
  objc_setAssociatedObject(self, kApplicationInBackgroundKey,
                           applicationInBackground,
                           OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSNumber *)applicationInBackground {
  return objc_getAssociatedObject(self, kApplicationInBackgroundKey);
}

/**
 * Swizzled entry point for application launch.
 * Initializes Firebase SDK and sets up delegates.
 */
- (BOOL)application:(UIApplication *)application
    swizzledDidFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
  [self application:application
      swizzledDidFinishLaunchingWithOptions:launchOptions];

  @try {
    instance = self;

    if (![FIRApp defaultApp]) {
      NSString *filePath =
          [[NSBundle mainBundle] pathForResource:@"GoogleService-Info"
                                          ofType:@"plist"];

      if (filePath) {
        [FirebasePlugin.firebasePlugin
            _logMessage:@"GoogleService-Info.plist found, setup: [FIRApp configureWithOptions]"];
        FIROptions *options =
            [[FIROptions alloc] initWithContentsOfFile:filePath];
        [FIRApp configureWithOptions:options];
      } else {
        [FirebasePlugin.firebasePlugin
            _logError:@"GoogleService-Info.plist NOT FOUND, setup: [FIRApp defaultApp]"];
        [FIRApp configure];
      }
    }

    if (self.isFCMEnabled) {
      _prevUserNotificationCenterDelegate =
          [UNUserNotificationCenter currentNotificationCenter].delegate;
      [UNUserNotificationCenter currentNotificationCenter].delegate = self;

      [FIRMessaging messaging].delegate = self;
    } else {
      [[FIRMessaging messaging] setAutoInitEnabled:NO];
    }

    self.applicationInBackground = @(YES);

  } @catch (NSException *exception) {
    [FirebasePlugin.firebasePlugin
        handlePluginExceptionWithoutContext:exception];
  }

  return YES;
}

- (BOOL)isFCMEnabled {
  return FirebasePlugin.firebasePlugin.isFCMEnabled;
}

/**
 * Called when the app becomes active again.
 */
- (void)applicationDidBecomeActive:(UIApplication *)application {
  self.applicationInBackground = @(NO);
  @try {
    [FirebasePlugin.firebasePlugin _logMessage:@"Enter foreground"];
    [FirebasePlugin.firebasePlugin
        executeGlobalJavascript:
            @"FirebasePlugin._applicationDidBecomeActive()"];
    [FirebasePlugin.firebasePlugin sendPendingNotifications];
  } @catch (NSException *exception) {
    [FirebasePlugin.firebasePlugin
        handlePluginExceptionWithoutContext:exception];
  }
}

/**
 * Called when the app enters the background.
 */
- (void)applicationDidEnterBackground:(UIApplication *)application {
  self.applicationInBackground = @(YES);
  @try {
    [FirebasePlugin.firebasePlugin _logMessage:@"Enter background"];
    [FirebasePlugin.firebasePlugin
        executeGlobalJavascript:
            @"FirebasePlugin._applicationDidEnterBackground()"];
  } @catch (NSException *exception) {
    [FirebasePlugin.firebasePlugin
        handlePluginExceptionWithoutContext:exception];
  }
}

#pragma mark - FIRMessagingDelegate
/**
 * FIRMessagingDelegate method called when a new FCM registration token is
 * generated.
 */
- (void)messaging:(FIRMessaging *)messaging
    didReceiveRegistrationToken:(NSString *)fcmToken {
  @try {
    [FirebasePlugin.firebasePlugin
        _logMessage:[NSString
                        stringWithFormat:@"didReceiveRegistrationToken: %@",
                        fcmToken]];
    [FirebasePlugin.firebasePlugin sendToken:fcmToken];
  } @catch (NSException *exception) {
    [FirebasePlugin.firebasePlugin
        handlePluginExceptionWithoutContext:exception];
  }
}

/**
 * Called when the app successfully registers for remote notifications with
 * APNS.
 */
- (void)application:(UIApplication *)application
    didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
  if (!self.isFCMEnabled) {
    return;
  }
  [FIRMessaging messaging].APNSToken = deviceToken;
  [FirebasePlugin.firebasePlugin
      _logMessage:[NSString stringWithFormat:@"didRegisterForRemoteNotificationsWithDeviceToken: %@",
                                             deviceToken]];
  [FirebasePlugin.firebasePlugin
      sendApnsToken:[FirebasePlugin.firebasePlugin
                        hexadecimalStringFromData:deviceToken]];
}

/**
 * Called when a remote notification is received while the app is in the
 * background or foreground.
 */
- (void)application:(UIApplication *)application
    didReceiveRemoteNotification:(NSDictionary *)userInfo
          fetchCompletionHandler:
              (void (^)(UIBackgroundFetchResult))completionHandler {

  if (!self.isFCMEnabled) {
    return;
  }

  @try {
    [[FIRMessaging messaging] appDidReceiveMessage:userInfo];
    mutableUserInfo = [userInfo mutableCopy];
    NSDictionary *aps = [mutableUserInfo objectForKey:@"aps"];
    bool isContentAvailable = [self isContentAvailable:userInfo];
    if ([aps objectForKey:@"alert"] != nil) {
      [mutableUserInfo setValue:@"notification" forKey:@"messageType"];
      NSString *tap;
      if ([self.applicationInBackground
              isEqual:[NSNumber numberWithBool:YES]] &&
          !isContentAvailable) {
        tap = @"background";
      }
      [mutableUserInfo setValue:tap forKey:@"tap"];
    } else {
      [mutableUserInfo setValue:@"data" forKey:@"messageType"];
    }

    [FirebasePlugin.firebasePlugin
        _logMessage:[NSString
                        stringWithFormat:@"didReceiveRemoteNotification: %@",
                        mutableUserInfo]];

    completionHandler(UIBackgroundFetchResultNewData);
    if ([self.applicationInBackground isEqual:[NSNumber numberWithBool:YES]] &&
        isContentAvailable) {
      [FirebasePlugin.firebasePlugin
          _logError:
              @"didReceiveRemoteNotification: omitting foreground notification as content-available:1 so system notification will be shown"];
    } else {
      [self processMessageForForegroundNotification:mutableUserInfo];
    }
    if ([self.applicationInBackground isEqual:[NSNumber numberWithBool:YES]] ||
        !isContentAvailable) {
      [FirebasePlugin.firebasePlugin sendNotification:mutableUserInfo];
    }
  } @catch (NSException *exception) {
    [FirebasePlugin.firebasePlugin
        handlePluginExceptionWithoutContext:exception];
  }
}

- (void)processMessageForForegroundNotification:(NSDictionary *)messageData {
  bool showForegroundNotification =
      [messageData objectForKey:@"notification_foreground"];
  if (!showForegroundNotification) {
    return;
  }

  NSString *title = nil;
  NSString *body = nil;
  NSString *sound = nil;
  NSNumber *badge = nil;

  NSDictionary *aps = [messageData objectForKey:@"aps"];
  if ([aps objectForKey:@"alert"] != nil) {
    NSDictionary *alert = [aps objectForKey:@"alert"];
    if ([alert objectForKey:@"title"] != nil) {
      title = [alert objectForKey:@"title"];
    }
    if ([alert objectForKey:@"body"] != nil) {
      body = [alert objectForKey:@"body"];
    }
    if ([aps objectForKey:@"sound"] != nil) {
      sound = [aps objectForKey:@"sound"];
    }
    if ([aps objectForKey:@"badge"] != nil) {
      badge = [aps objectForKey:@"badge"];
    }
  }

  if ([messageData objectForKey:@"notification_title"] != nil) {
    title = [messageData objectForKey:@"notification_title"];
  }
  if ([messageData objectForKey:@"notification_body"] != nil) {
    body = [messageData objectForKey:@"notification_body"];
  }
  if ([messageData objectForKey:@"notification_ios_sound"] != nil) {
    sound = [messageData objectForKey:@"notification_ios_sound"];
  }
  if ([messageData objectForKey:@"notification_ios_badge"] != nil) {
    badge = [messageData objectForKey:@"notification_ios_badge"];
  }

  if (title == nil || body == nil) {
    return;
  }

  [[UNUserNotificationCenter currentNotificationCenter]
      getNotificationSettingsWithCompletionHandler:^(
          UNNotificationSettings *_Nonnull settings) {
        @try {
          if (settings.alertSetting == UNNotificationSettingEnabled) {
            UNMutableNotificationContent *objNotificationContent =
                [[UNMutableNotificationContent alloc] init];
            objNotificationContent.title =
                [NSString localizedUserNotificationStringForKey:title
                                                      arguments:nil];
            objNotificationContent.body =
                [NSString localizedUserNotificationStringForKey:body
                                                      arguments:nil];

            NSDictionary *alert = [[NSDictionary alloc]
                initWithObjectsAndKeys:title, @"title", body, @"body", nil];
            NSMutableDictionary *aps = [[NSMutableDictionary alloc]
                initWithObjectsAndKeys:alert, @"alert", nil];

            if (![sound isKindOfClass:[NSString class]] ||
                [sound isEqualToString:@"default"]) {
              objNotificationContent.sound = [UNNotificationSound defaultSound];
              [aps setValue:sound forKey:@"sound"];
            } else if (sound != nil) {
              objNotificationContent.sound =
                  [UNNotificationSound soundNamed:sound];
              [aps setValue:sound forKey:@"sound"];
            }

            if (badge != nil) {
              [aps setValue:badge forKey:@"badge"];
            }

            NSString *messageType = @"data";
            if ([mutableUserInfo objectForKey:@"messageType"] != nil) {
              messageType = [mutableUserInfo objectForKey:@"messageType"];
            }

            NSDictionary *userInfo = [[NSDictionary alloc]
                initWithObjectsAndKeys:@"true", @"notification_foreground",
                                       messageType, @"messageType", aps, @"aps",
                                       nil];

            objNotificationContent.userInfo = userInfo;

            UNTimeIntervalNotificationTrigger *trigger =
                [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:0.1f
                                                                   repeats:NO];
            UNNotificationRequest *request = [UNNotificationRequest
                requestWithIdentifier:@"local_notification"
                              content:objNotificationContent
                              trigger:trigger];
            [[UNUserNotificationCenter currentNotificationCenter]
                addNotificationRequest:request
                 withCompletionHandler:^(NSError *_Nullable error) {
                   if (!error) {
                     [FirebasePlugin.firebasePlugin
                         _logMessage:@"Local Notification succeeded"];
                   } else {
                     [FirebasePlugin.firebasePlugin
                         _logError:[NSString
                                       stringWithFormat:
                                           @"Local Notification failed: %@",
                                           error.description]];
                   }
                 }];
          } else {
            [FirebasePlugin.firebasePlugin
                _logError:@"processMessageForForegroundNotification: cannot show notification as permission denied"];
          }
        } @catch (NSException *exception) {
          [FirebasePlugin.firebasePlugin
              handlePluginExceptionWithoutContext:exception];
        }
      }];
}

- (void)application:(UIApplication *)application
    didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
  if (!self.isFCMEnabled) {
    return;
  }
  [FirebasePlugin.firebasePlugin
      _logError:[NSString
                    stringWithFormat:
                        @"didFailToRegisterForRemoteNotificationsWithError: %@",
                        error.description]];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    openSettingsForNotification:(UNNotification *)notification {
  @try {
    [FirebasePlugin.firebasePlugin sendOpenNotificationSettings];
  } @catch (NSException *exception) {
    [FirebasePlugin.firebasePlugin
        handlePluginExceptionWithoutContext:exception];
  }
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:
             (void (^)(UNNotificationPresentationOptions options))
                 completionHandler {

  @try {
    if (![notification.request.trigger
            isKindOfClass:UNPushNotificationTrigger.class] &&
        ![notification.request.trigger
            isKindOfClass:UNTimeIntervalNotificationTrigger.class]) {
      if (_prevUserNotificationCenterDelegate) {
        [_prevUserNotificationCenterDelegate
             userNotificationCenter:center
            willPresentNotification:notification
              withCompletionHandler:completionHandler];
        return;
      } else {
        [FirebasePlugin.firebasePlugin
            _logError:@"willPresentNotification: aborting as not a supported UNNotificationTrigger"];
        return;
      }
    }

    [[FIRMessaging messaging]
        appDidReceiveMessage:notification.request.content.userInfo];

    mutableUserInfo = [notification.request.content.userInfo mutableCopy];

    NSString *messageType = [mutableUserInfo objectForKey:@"messageType"];
    if (![messageType isEqualToString:@"data"]) {
      [mutableUserInfo setValue:@"notification" forKey:@"messageType"];
    }

    [FirebasePlugin.firebasePlugin
        _logMessage:[NSString stringWithFormat:@"willPresentNotification: %@",
                                               mutableUserInfo]];

    NSDictionary *aps = [mutableUserInfo objectForKey:@"aps"];
    bool showForegroundNotification =
        [mutableUserInfo objectForKey:@"notification_foreground"];
    bool hasAlert = [aps objectForKey:@"alert"] != nil;
    bool hasBadge = [aps objectForKey:@"badge"] != nil;
    bool hasSound = [aps objectForKey:@"sound"] != nil;

    bool isContentAvailable = [self isContentAvailable:mutableUserInfo];

    if (showForegroundNotification && isContentAvailable) {
      if (hasAlert && hasBadge && hasSound) {
        completionHandler(UNNotificationPresentationOptionAlert +
                          UNNotificationPresentationOptionBadge +
                          UNNotificationPresentationOptionSound);
      } else if (hasAlert && hasBadge) {
        completionHandler(UNNotificationPresentationOptionAlert +
                          UNNotificationPresentationOptionBadge);
      } else if (hasAlert && hasSound) {
        completionHandler(UNNotificationPresentationOptionAlert +
                          UNNotificationPresentationOptionSound);
      } else if (hasBadge && hasSound) {
        completionHandler(UNNotificationPresentationOptionBadge +
                          UNNotificationPresentationOptionSound);
      } else if (hasAlert) {
        completionHandler(UNNotificationPresentationOptionAlert);
      } else if (hasBadge) {
        completionHandler(UNNotificationPresentationOptionBadge);
      } else if (hasSound) {
        completionHandler(UNNotificationPresentationOptionSound);
      }
    } else {
      [FirebasePlugin.firebasePlugin
          _logMessage:@"willPresentNotification: foreground notification not set"];
    }

    if (![messageType isEqualToString:@"data"]) {
      [FirebasePlugin.firebasePlugin sendNotification:mutableUserInfo];
    }

  } @catch (NSException *exception) {
    [FirebasePlugin.firebasePlugin
        handlePluginExceptionWithoutContext:exception];
  }
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler {
  @try {
    if (![response.notification.request.trigger
            isKindOfClass:UNPushNotificationTrigger.class] &&
        ![response.notification.request.trigger
            isKindOfClass:UNTimeIntervalNotificationTrigger.class]) {
      if (_prevUserNotificationCenterDelegate) {
        [_prevUserNotificationCenterDelegate
                    userNotificationCenter:center
            didReceiveNotificationResponse:response
                     withCompletionHandler:completionHandler];
        return;
      } else {
        [FirebasePlugin.firebasePlugin
            _logMessage:@"didReceiveNotificationResponse: aborting as not a supported UNNotificationTrigger"];
        return;
      }
    }

    [[FIRMessaging messaging]
        appDidReceiveMessage:response.notification.request.content.userInfo];

    mutableUserInfo =
        [response.notification.request.content.userInfo mutableCopy];

    NSString *tap;
    if ([self.applicationInBackground isEqual:[NSNumber numberWithBool:YES]]) {
      tap = @"background";
    } else {
      tap = @"foreground";
    }
    [mutableUserInfo setValue:tap forKey:@"tap"];
    if ([mutableUserInfo objectForKey:@"messageType"] == nil) {
      [mutableUserInfo setValue:@"notification" forKey:@"messageType"];
    }

    if (response.actionIdentifier &&
        ![response.actionIdentifier
            isEqual:UNNotificationDefaultActionIdentifier]) {
      [mutableUserInfo setValue:response.actionIdentifier forKey:@"action"];
    }

    [FirebasePlugin.firebasePlugin
        _logInfo:[NSString
                     stringWithFormat:@"didReceiveNotificationResponse: %@",
                                      mutableUserInfo]];

    [FirebasePlugin.firebasePlugin sendNotification:mutableUserInfo];

    completionHandler();

  } @catch (NSException *exception) {
    [FirebasePlugin.firebasePlugin
        handlePluginExceptionWithoutContext:exception];
  }
}

- (bool)isContentAvailable:(NSDictionary *)userInfo {
  if (userInfo == nil) {
    return false;
  }

  NSDictionary *aps = [userInfo objectForKey:@"aps"];
  if (aps == nil) {
    return false;
  }

  return ([aps objectForKey:@"'content-available'"] != nil &&
          [[aps objectForKey:@"'content-available'"]
              isEqualToNumber:[NSNumber numberWithInt:1]]) ||
         ([aps objectForKey:@"content-available"] != nil &&
          [[aps objectForKey:@"content-available"]
              isEqualToNumber:[NSNumber numberWithInt:1]]);
}

@end
