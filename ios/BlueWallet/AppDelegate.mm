#import "AppDelegate.h"
#import <React/RCTLinkingManager.h>
#import <React/RCTBundleURLProvider.h>
#import <React/RCTI18nUtil.h>
#import <React/RCTBundleURLProvider.h>
#import "RNQuickActionManager.h"
#import <UserNotifications/UserNotifications.h>
#import <RNCPushNotificationIOS.h>
#import <React/RCTRootView.h>
#import <Bugsnag/Bugsnag.h>
#import "BlueWallet-Swift.h"

@interface AppDelegate() <UNUserNotificationCenterDelegate>

@property (nonatomic, strong) NSUserDefaults *userDefaultsGroup;

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  [self clearFilesIfNeeded];
  self.userDefaultsGroup = [[NSUserDefaults alloc] initWithSuiteName:@"group.io.bluewallet.bluewallet"];
  
  NSString *isDoNotTrackEnabled = [self.userDefaultsGroup stringForKey:@"donottrack"];
  if (![isDoNotTrackEnabled isEqualToString:@"1"]) {
      // Set the appType based on the current platform
#if TARGET_OS_MACCATALYST
  BugsnagConfiguration *config = [BugsnagConfiguration loadConfig];
  config.appType = @"macOS";
  // Start Bugsnag with the configuration
  [Bugsnag startWithConfiguration:config];
    [self copyDeviceUID];

#else
  [Bugsnag start];
  [self copyDeviceUID];

#endif
  } else {
    [NSUserDefaults.standardUserDefaults setValue:@"" forKey:@"deviceUIDCopy"];
  }

  self.moduleName = @"BlueWallet";
  // You can add your custom initial props in the dictionary below.
  // They will be passed down to the ViewController used by React Native.
  self.initialProps = @{};

  [[RCTI18nUtil sharedInstance] allowRTL:YES];

  UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
  center.delegate = self;

  [self setupUserDefaultsListener];
  [self registerNotificationCategories];

  return [super application:application didFinishLaunchingWithOptions:launchOptions];
}

- (NSURL *)sourceURLForBridge:(RCTBridge *)bridge
{
  return [self bundleURL];
}

- (NSURL *)bundleURL
{
#if DEBUG
  return [[RCTBundleURLProvider sharedSettings] jsBundleURLForBundleRoot:@"index"];
#else
  return [[NSBundle mainBundle] URLForResource:@"main" withExtension:@"jsbundle"];
#endif
}

- (void)registerNotificationCategories {
    // Define two actions: "View Address in Browser" and "View Transaction in Browser"
    UNNotificationAction *viewAddressTransactionsAction = [UNNotificationAction actionWithIdentifier:@"VIEW_ADDRESS_TRANSACTIONS"
                                                                                               title:NSLocalizedString(@"VIEW_ADDRESS_TRANSACTIONS_TITLE", nil)
                                                                                             options:UNNotificationActionOptionForeground];

    UNNotificationAction *viewTransactionDetailsAction = [UNNotificationAction actionWithIdentifier:@"VIEW_TRANSACTION_DETAILS"
                                                                                            title:NSLocalizedString(@"VIEW_TRANSACTION_DETAILS_TITLE", nil)
                                                                                          options:UNNotificationActionOptionForeground];

    UNNotificationCategory *transactionCategory = [UNNotificationCategory categoryWithIdentifier:@"TRANSACTION_CATEGORY"
                                                                                        actions:@[viewAddressTransactionsAction, viewTransactionDetailsAction]
                                                                              intentIdentifiers:@[]
                                                                                        options:UNNotificationCategoryOptionCustomDismissAction];

    [[UNUserNotificationCenter currentNotificationCenter] setNotificationCategories:[NSSet setWithObject:transactionCategory]];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context
{
    if ([keyPath isEqualToString:@"deviceUID"] || [keyPath isEqualToString:@"deviceUIDCopy"]) {
        [self copyDeviceUID];
    }

    NSArray *keys = @[
        @"WidgetCommunicationAllWalletsSatoshiBalance",
        @"WidgetCommunicationAllWalletsLatestTransactionTime",
        @"WidgetCommunicationDisplayBalanceAllowed",
        @"WidgetCommunicationLatestTransactionIsUnconfirmed",
        @"preferredCurrency",
        @"preferredCurrencyLocale",
        @"electrum_host",
        @"electrum_tcp_port",
        @"electrum_ssl_port"
    ];

    if ([keys containsObject:keyPath]) {
        [WidgetHelper reloadAllWidgets];
    }
}

- (void)copyDeviceUID {
    [NSUserDefaults.standardUserDefaults addObserver:self
                                           forKeyPath:@"deviceUID"
                                              options:NSKeyValueObservingOptionNew
                                              context:NULL];
    [NSUserDefaults.standardUserDefaults addObserver:self
                                           forKeyPath:@"deviceUIDCopy"
                                              options:NSKeyValueObservingOptionNew
                                              context:NULL];
    NSString *deviceUID = [NSUserDefaults.standardUserDefaults stringForKey:@"deviceUID"];
    if (deviceUID && deviceUID.length > 0) {
        [NSUserDefaults.standardUserDefaults setValue:deviceUID forKey:@"deviceUIDCopy"];
    }
}

- (void)setupUserDefaultsListener {
    NSArray *keys = @[
        @"WidgetCommunicationAllWalletsSatoshiBalance",
        @"WidgetCommunicationAllWalletsLatestTransactionTime",
        @"WidgetCommunicationDisplayBalanceAllowed",
        @"WidgetCommunicationLatestTransactionIsUnconfirmed",
        @"preferredCurrency",
        @"preferredCurrencyLocale",
        @"electrum_host",
        @"electrum_tcp_port",
        @"electrum_ssl_port"
    ];
    
    for (NSString *key in keys) {
        [self.userDefaultsGroup addObserver:self forKeyPath:key options:NSKeyValueObservingOptionNew context:NULL];
    }
}

- (BOOL)application:(UIApplication *)application continueUserActivity:(nonnull NSUserActivity *)userActivity
 restorationHandler:(nonnull void (^)(NSArray<id<UIUserActivityRestoring>> * _Nullable))restorationHandler
{
  // Validate userActivity and its type
  if (!userActivity || !userActivity.activityType) {
    NSLog(@"[Handoff] Invalid or missing userActivity");
    return NO;
  }
  
  NSDictionary *userActivityData = @{@"activityType": userActivity.activityType ?: @"",
                                     @"userInfo": userActivity.userInfo ?: @{}};
  
  // Save activity data to userDefaults for potential later use
  [self.userDefaultsGroup setValue:userActivityData forKey:@"onUserActivityOpen"];
  
  // Check if the activity type matches one of the allowed types
  if ([userActivity.activityType isEqualToString:@"io.bluewallet.bluewallet.receiveonchain"] ||
      [userActivity.activityType isEqualToString:@"io.bluewallet.bluewallet.xpub"] ||
      [userActivity.activityType isEqualToString:@"io.bluewallet.bluewallet.blockexplorer"]) {
    
    if ([EventEmitter.shared respondsToSelector:@selector(sendUserActivity:)]) {
      [EventEmitter.shared sendUserActivity:userActivityData];
    } else {
      NSLog(@"[Handoff] EventEmitter does not implement sendUserActivity:");
    }
    return YES;
  }
  
  // Forward web browsing activities to LinkingManager
  if ([userActivity.activityType isEqualToString:NSUserActivityTypeBrowsingWeb]) {
    return [RCTLinkingManager application:application
                     continueUserActivity:userActivity
                       restorationHandler:restorationHandler];
  }
  
  NSLog(@"[Handoff] Unhandled user activity type: %@", userActivity.activityType);
  return NO;
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
  return [RCTLinkingManager application:app openURL:url options:options];
}

- (BOOL)application:(UIApplication *)application shouldAllowExtensionPointIdentifier:(UIApplicationExtensionPointIdentifier)extensionPointIdentifier {
  return NO;
}

- (void)applicationWillTerminate:(UIApplication *)application {
  [self.userDefaultsGroup removeObjectForKey:@"onUserActivityOpen"];
}

- (void)application:(UIApplication *)application performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL succeeded)) completionHandler {
  [RNQuickActionManager onQuickActionPress:shortcutItem completionHandler:completionHandler];
}

//Called when a notification is delivered to a foreground app.
-(void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler
{
  NSDictionary *userInfo = notification.request.content.userInfo;
  completionHandler(UNNotificationPresentationOptionSound | UNNotificationPresentationOptionList | UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionBadge);
}

- (void)buildMenuWithBuilder:(id<UIMenuBuilder>)builder {
    [super buildMenuWithBuilder:builder];
    
    // Remove unnecessary menus
    [builder removeMenuForIdentifier:UIMenuServices];
    [builder removeMenuForIdentifier:UIMenuFormat];
    [builder removeMenuForIdentifier:UIMenuToolbar];
    
    // Remove the original Settings menu item
    [builder removeMenuForIdentifier:UIMenuPreferences];
    
    // File -> Add Wallet (Command + A)
    UIKeyCommand *addWalletCommand = [UIKeyCommand keyCommandWithInput:@"A"
                                                        modifierFlags:UIKeyModifierCommand | UIKeyModifierShift
                                                              action:@selector(addWalletAction:)];
    [addWalletCommand setTitle:@"Add Wallet"];
    
    // File -> Import Wallet
    UIKeyCommand *importWalletCommand = [UIKeyCommand keyCommandWithInput:@"I" modifierFlags:UIKeyModifierCommand action:@selector(importWalletAction:)];
    [importWalletCommand setTitle:@"Import Wallet"];
    
    // Group Add Wallet and Import Wallet in a displayInline menu
    UIMenu *walletOperationsMenu = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[addWalletCommand, importWalletCommand]];
    
    // Modify the existing File menu to include Wallet Operations
    UIMenu *fileMenu = [builder menuForIdentifier:UIMenuFile];
    if (fileMenu) {
        // Add "Reload Transactions"
        UIKeyCommand *reloadTransactionsCommand = [UIKeyCommand keyCommandWithInput:@"R" modifierFlags:UIKeyModifierCommand action:@selector(reloadTransactionsAction:)];
        [reloadTransactionsCommand setTitle:@"Reload Transactions"];
        
        // Combine wallet operations and Reload Transactions into the new File menu
        UIMenu *newFileMenu = [UIMenu menuWithTitle:fileMenu.title image:nil identifier:fileMenu.identifier options:fileMenu.options children:@[walletOperationsMenu, reloadTransactionsCommand]];
        [builder replaceMenuForIdentifier:UIMenuFile withMenu:newFileMenu];
    }
    
    // BlueWallet -> Settings (Command + ,)
    UIKeyCommand *settingsCommand = [UIKeyCommand keyCommandWithInput:@"," modifierFlags:UIKeyModifierCommand action:@selector(openSettings:)];
    [settingsCommand setTitle:@"Settings..."];
    UIMenu *settings = [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDisplayInline children:@[settingsCommand]];
    
    // Insert the new Settings menu after the About menu
    [builder insertSiblingMenu:settings afterMenuForIdentifier:UIMenuAbout];
}

- (void)openSettings:(UIKeyCommand *)keyCommand {
    // Safely access the MenuElementsEmitter
    MenuElementsEmitter *emitter = [MenuElementsEmitter shared];
    if (emitter) {
        NSLog(@"[MenuElements] AppDelegate: openSettings called, calling emitter");
        // Force on main thread for consistency
        dispatch_async(dispatch_get_main_queue(), ^{
            [emitter openSettings];
        });
    } else {
        NSLog(@"[MenuElements] AppDelegate: MenuElementsEmitter not available for openSettings");
    }
}

- (void)addWalletAction:(UIKeyCommand *)keyCommand {
    // Safely access the MenuElementsEmitter
    MenuElementsEmitter *emitter = [MenuElementsEmitter shared];
    if (emitter) {
        NSLog(@"[MenuElements] AppDelegate: addWalletAction called, calling emitter");
        // Force on main thread for consistency
        dispatch_async(dispatch_get_main_queue(), ^{
            [emitter addWalletMenuAction];
        });
    } else {
        NSLog(@"[MenuElements] AppDelegate: MenuElementsEmitter not available for addWalletAction");
    }
}

- (void)importWalletAction:(UIKeyCommand *)keyCommand {
    // Safely access the MenuElementsEmitter
    MenuElementsEmitter *emitter = [MenuElementsEmitter shared];
    if (emitter) {
        NSLog(@"[MenuElements] AppDelegate: importWalletAction called, calling emitter");
        // Force on main thread for consistency
        dispatch_async(dispatch_get_main_queue(), ^{
            [emitter importWalletMenuAction];
        });
    } else {
        NSLog(@"[MenuElements] AppDelegate: MenuElementsEmitter not available for importWalletAction");
    }
}

- (void)reloadTransactionsAction:(UIKeyCommand *)keyCommand {
    // Safely access the MenuElementsEmitter
    MenuElementsEmitter *emitter = [MenuElementsEmitter shared];
    if (emitter) {
        NSLog(@"[MenuElements] AppDelegate: reloadTransactionsAction called, calling emitter");
        // Force on main thread for consistency
        dispatch_async(dispatch_get_main_queue(), ^{
            [emitter reloadTransactionsMenuAction];
        });
    } else {
        NSLog(@"[MenuElements] AppDelegate: MenuElementsEmitter not available for reloadTransactionsAction");
    }
}

- (void)showHelp:(id)sender {
  [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"https://bluewallet.io/docs"] options:@{} completionHandler:nil];
}

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
  if (action == @selector(showHelp:)) {
    return true;
  } else {
    return [super canPerformAction:action withSender:sender];
  }
}

// Required for the register event.
- (void)application:(UIApplication *)application didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken
{
 [RNCPushNotificationIOS didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
}

// Required for the registrationError event.
- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error
{
 [RNCPushNotificationIOS didFailToRegisterForRemoteNotificationsWithError:error];
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
    didReceiveNotificationResponse:(UNNotificationResponse *)response
             withCompletionHandler:(void (^)(void))completionHandler
{
    NSDictionary *userInfo = response.notification.request.content.userInfo;
  NSString *blockExplorer = [[[NSUserDefaults standardUserDefaults] initWithSuiteName:@"group.io.bluewallet.bluewallet"] stringForKey:@"blockExplorer"];
    if (blockExplorer == nil || [blockExplorer length] == 0) {
        blockExplorer = @"https://www.mempool.space";
    }
    
    NSString *address = userInfo[@"data"][@"address"];
    NSString *txid = userInfo[@"data"][@"txid"];

    if ([response.actionIdentifier isEqualToString:@"VIEW_ADDRESS_TRANSACTIONS"] && address) {
        NSString *urlString = [NSString stringWithFormat:@"%@/address/%@", blockExplorer, address];
        NSURL *url = [NSURL URLWithString:urlString];
        if ([[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    }
    else if ([response.actionIdentifier isEqualToString:@"VIEW_TRANSACTION_DETAILS"] && txid) {
        NSString *urlString = [NSString stringWithFormat:@"%@/tx/%@", blockExplorer, txid];
        NSURL *url = [NSURL URLWithString:urlString];
        if ([[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    }

    [RNCPushNotificationIOS didReceiveNotificationResponse:response];
    completionHandler();
}

// Clear cache on app launch
- (void)clearFilesIfNeeded {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL shouldClearFiles = [defaults boolForKey:@"clearFilesOnLaunch"];

    if (shouldClearFiles) {
        [self clearDocumentDirectory];
        [self clearCacheDirectory];
        [self clearTempDirectory];

        // Reset the switch
        [defaults setBool:NO forKey:@"clearFilesOnLaunch"];
        [defaults synchronize];

        // Show an alert
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Cache Cleared"
                                                                       message:@"The document, cache, and temp directories have been cleared."
                                                                preferredStyle:UIAlertControllerStyleAlert];
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil];
        [alert addAction:okAction];

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
        });
    }
}

- (void)clearDocumentDirectory {
    NSURL *documentsDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
    [self clearDirectoryAtURL:documentsDirectory];
}

- (void)clearCacheDirectory {
    NSURL *cacheDirectory = [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] lastObject];
    [self clearDirectoryAtURL:cacheDirectory];
}

- (void)clearTempDirectory {
    NSURL *tempDirectory = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
    [self clearDirectoryAtURL:tempDirectory];
}

- (void)clearDirectoryAtURL:(NSURL *)directoryURL {
    NSError *error;
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:directoryURL includingPropertiesForKeys:nil options:0 error:&error];

    if (error) {
        NSLog(@"Error reading contents of directory: %@", error.localizedDescription);
        return;
    }

    for (NSURL *fileURL in contents) {
        [[NSFileManager defaultManager] removeItemAtURL:fileURL error:&error];
        if (error) {
            NSLog(@"Error removing file: %@", error.localizedDescription);
        }
    }
}

- (UIInterfaceOrientationMask)application:(UIApplication *)application supportedInterfaceOrientationsForWindow:(UIWindow *)window {
  UITraitCollection *traitCollection = window.traitCollection;
  if (traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassRegular ||
      traitCollection.verticalSizeClass == UIUserInterfaceSizeClassRegular) {
    // iPad or large iPhone
    return UIInterfaceOrientationMaskAll;
  }
  // Regular iPhone
  return UIInterfaceOrientationMaskPortrait | UIInterfaceOrientationMaskPortraitUpsideDown;
}

@end
