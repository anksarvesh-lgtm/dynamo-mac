// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <UserNotifications/UserNotifications.h>
#import <objc/runtime.h>
#include "mac_notifications.h"

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"

// Swizzle NSBundle.bundleIdentifier if running outside .app bundle so Cocoa notifications never fail
@implementation NSBundle (MacLinkBundleIdentifier)
- (NSString *)__maclink_bundleIdentifier {
    NSString *bundleId = [self __maclink_bundleIdentifier];
    if (bundleId != nil && bundleId.length > 0) {
        return bundleId;
    }
    return @"in.maclink.srv";
}
@end

static void ensure_bundle_identifier(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        if ([NSBundle mainBundle].bundleIdentifier == nil) {
            Method origMethod = class_getInstanceMethod([NSBundle class], @selector(bundleIdentifier));
            Method swizzledMethod = class_getInstanceMethod([NSBundle class], @selector(__maclink_bundleIdentifier));
            if (origMethod && swizzledMethod) {
                method_exchangeImplementations(origMethod, swizzledMethod);
            }
        }
    });
}

// ---------------------------------------------------------------------------
// Modern macOS 10.14+ UserNotifications (UNUserNotificationCenter)
// ---------------------------------------------------------------------------
API_AVAILABLE(macos(10.14))
@interface MacUNNotificationDelegate : NSObject <UNUserNotificationCenterDelegate>
@property (nonatomic, assign) MacNotificationCallback callback;
@end

@implementation MacUNNotificationDelegate

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
       willPresentNotification:(UNNotification *)notification
         withCompletionHandler:(void (^)(UNNotificationPresentationOptions options))completionHandler {
    // Ensure notifications always present as banners even when MacLink is frontmost/active.
    UNNotificationPresentationOptions opts = UNNotificationPresentationOptionBanner | UNNotificationPresentationOptionSound | UNNotificationPresentationOptionList;
    completionHandler(opts);
}

- (void)userNotificationCenter:(UNUserNotificationCenter *)center
didReceiveNotificationResponse:(UNNotificationResponse *)response
         withCompletionHandler:(void (^)(void))completionHandler {
    if (!self.callback) {
        completionHandler();
        return;
    }
    
    NSDictionary *userInfo = response.notification.request.content.userInfo;
    NSString *device = userInfo[@"device"] ?: @"";
    NSString *key = userInfo[@"key"] ?: @"";
    
    if ([response isKindOfClass:[UNTextInputNotificationResponse class]]) {
        UNTextInputNotificationResponse *textResp = (UNTextInputNotificationResponse *)response;
        NSString *replyAction = userInfo[@"reply_action"] ?: response.actionIdentifier ?: @"";
        NSString *text = textResp.userText ?: @"";
        self.callback("reply", device.UTF8String, key.UTF8String, replyAction.UTF8String, text.UTF8String);
    } else if ([response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier]) {
        self.callback("opened", device.UTF8String, key.UTF8String, "", "");
    } else if ([response.actionIdentifier isEqualToString:UNNotificationDismissActionIdentifier]) {
        self.callback("dismissed", device.UTF8String, key.UTF8String, "", "");
    } else {
        self.callback("action", device.UTF8String, key.UTF8String, response.actionIdentifier.UTF8String, "");
    }
    completionHandler();
}

@end

// ---------------------------------------------------------------------------
// Legacy macOS NSUserNotificationCenter fallback
// ---------------------------------------------------------------------------
@interface MacNotificationDelegate : NSObject <NSUserNotificationCenterDelegate>
@property (nonatomic, assign) MacNotificationCallback callback;
@end

@implementation MacNotificationDelegate

- (BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(NSUserNotification *)notification {
    return YES;
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification {
    if (!self.callback) return;
    
    NSString *device = notification.userInfo[@"device"] ?: @"";
    NSString *key = notification.userInfo[@"key"] ?: @"";
    
    switch (notification.activationType) {
        case NSUserNotificationActivationTypeContentsClicked: {
            self.callback("opened", device.UTF8String, key.UTF8String, "", "");
            break;
        }
        case NSUserNotificationActivationTypeActionButtonClicked: {
            NSString *action = notification.userInfo[@"primary_action"] ?: @"";
            self.callback("action", device.UTF8String, key.UTF8String, action.UTF8String, "");
            break;
        }
        case NSUserNotificationActivationTypeReplied: {
            NSString *replyAction = notification.userInfo[@"reply_action"] ?: @"";
            NSString *text = notification.response.string ?: @"";
            self.callback("reply", device.UTF8String, key.UTF8String, replyAction.UTF8String, text.UTF8String);
            break;
        }
        case NSUserNotificationActivationTypeAdditionalActionClicked: {
            if (notification.additionalActivationAction) {
                NSString *action = notification.additionalActivationAction.identifier ?: @"";
                self.callback("action", device.UTF8String, key.UTF8String, action.UTF8String, "");
            }
            break;
        }
        default:
            break;
    }
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didDismissNotification:(NSUserNotification *)notification {
    if (!self.callback) return;
    NSString *device = notification.userInfo[@"device"] ?: @"";
    NSString *key = notification.userInfo[@"key"] ?: @"";
    self.callback("dismissed", device.UTF8String, key.UTF8String, "", "");
}

@end

static MacUNNotificationDelegate *s_un_delegate = nil;
static MacNotificationDelegate *s_ns_delegate = nil;

static void deliver_via_ns_user_notification(
    NSString *targetId,
    NSString *titleStr,
    NSString *subtitleStr,
    NSString *bodyStr,
    NSString *iconPathStr,
    NSString *imagePathStr,
    bool silent,
    bool has_reply,
    NSString *replyIdStr,
    NSString *replyTitleStr,
    NSArray<NSString *> *actionIds,
    NSArray<NSString *> *actionTitles,
    NSDictionary *userInfo
) {
    NSUserNotification *notif = [[NSUserNotification alloc] init];
    notif.identifier = targetId;
    if (titleStr.length > 0) {
        notif.title = titleStr;
    }
    if (subtitleStr.length > 0) {
        notif.subtitle = subtitleStr;
    }
    if (bodyStr.length > 0) {
        notif.informativeText = bodyStr;
    }
    if (silent) {
        notif.soundName = nil;
    } else {
        notif.soundName = NSUserNotificationDefaultSoundName;
    }

    // Set _identityImage: This is the key Cocoa property that replaces the application
    // bundle icon on the left of the notification banner with the phone app's icon or contact avatar!
    if (iconPathStr.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:iconPathStr]) {
        NSImage *iconImg = [[NSImage alloc] initWithContentsOfFile:iconPathStr];
        if (iconImg) {
            @try {
                [notif setValue:iconImg forKey:@"_identityImage"];
                [notif setValue:@YES forKey:@"_identityImageHasBorder"];
                [notif setValue:@(0) forKey:@"_identityImageStyle"]; // 0 = standard / rounded square
            } @catch (NSException *e) {
                NSLog(@"[MacLink] Could not set _identityImage: %@", e);
            }
        }
    }

    // Set contentImage: this is the attached picture (e.g. photo in message or big picture)
    // which appears on the right side of the notification banner.
    if (imagePathStr.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:imagePathStr]) {
        NSImage *img = [[NSImage alloc] initWithContentsOfFile:imagePathStr];
        if (img) {
            notif.contentImage = img;
        }
    }

    NSMutableDictionary *infoCopy = [userInfo mutableCopy];
    if (has_reply) {
        notif.hasReplyButton = YES;
        notif.responsePlaceholder = (replyTitleStr.length > 0) ? replyTitleStr : @"Type a message...";
        if (replyIdStr.length > 0) {
            infoCopy[@"reply_action"] = replyIdStr;
        }
    } else if (actionIds.count > 0 && actionTitles.count > 0) {
        notif.hasActionButton = YES;
        notif.actionButtonTitle = actionTitles[0];
        infoCopy[@"primary_action"] = actionIds[0];

        if (actionIds.count > 1) {
            NSMutableArray *moreActions = [NSMutableArray array];
            for (NSUInteger i = 1; i < actionIds.count && i < actionTitles.count; i++) {
                NSUserNotificationAction *action = [NSUserNotificationAction actionWithIdentifier:actionIds[i] title:actionTitles[i]];
                [moreActions addObject:action];
            }
            notif.additionalActions = moreActions;
        }
    } else {
        // Default action button: "Show" (matching native macOS companion look)
        notif.hasActionButton = YES;
        notif.actionButtonTitle = @"Show";
        infoCopy[@"primary_action"] = @"open";
    }

    @try {
        [notif setValue:@YES forKey:@"_showsButtons"];
    } @catch (NSException *e) {}

    notif.userInfo = infoCopy;
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notif];
}

extern "C" {

void mac_notification_start(const char *app_icon_path, MacNotificationCallback callback) {
    (void)app_icon_path;
    @autoreleasepool {
        ensure_bundle_identifier();
        
        if (@available(macOS 10.14, *)) {
            @try {
                s_un_delegate = [[MacUNNotificationDelegate alloc] init];
                s_un_delegate.callback = callback;
                UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
                center.delegate = s_un_delegate;
                [center requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound | UNAuthorizationOptionBadge)
                                      completionHandler:^(BOOL granted, NSError * _Nullable error) {
                    (void)granted;
                    (void)error;
                }];
            } @catch (NSException *e) {
                // When running outside an application bundle, UNUserNotificationCenter is not available
            }
        }
        
        s_ns_delegate = [[MacNotificationDelegate alloc] init];
        s_ns_delegate.callback = callback;
        [NSUserNotificationCenter defaultUserNotificationCenter].delegate = s_ns_delegate;
    }
}

void mac_notification_show(
    const char *device,
    const char *key,
    const char *title,
    const char *subtitle,
    const char *body,
    const char *icon_path,
    const char *image_path,
    bool silent,
    bool has_reply,
    const char *reply_id,
    const char *reply_title,
    int action_count,
    const char *const *action_ids,
    const char *const *action_titles
) {
    @autoreleasepool {
        ensure_bundle_identifier();
        
        NSString *deviceStr = (device && strlen(device) > 0) ? [NSString stringWithUTF8String:device] : @"";
        NSString *keyStr = (key && strlen(key) > 0) ? [NSString stringWithUTF8String:key] : @"";
        NSString *titleStr = (title && strlen(title) > 0) ? [NSString stringWithUTF8String:title] : @"";
        NSString *subtitleStr = (subtitle && strlen(subtitle) > 0) ? [NSString stringWithUTF8String:subtitle] : @"";
        NSString *bodyStr = (body && strlen(body) > 0) ? [NSString stringWithUTF8String:body] : @"";
        NSString *iconPathStr = (icon_path && strlen(icon_path) > 0) ? [NSString stringWithUTF8String:icon_path] : @"";
        NSString *imagePathStr = (image_path && strlen(image_path) > 0) ? [NSString stringWithUTF8String:image_path] : @"";
        NSString *replyIdStr = (reply_id && strlen(reply_id) > 0) ? [NSString stringWithUTF8String:reply_id] : @"reply";
        NSString *replyTitleStr = (reply_title && strlen(reply_title) > 0) ? [NSString stringWithUTF8String:reply_title] : @"Reply";

        NSMutableArray<NSString *> *actionIdList = [NSMutableArray array];
        NSMutableArray<NSString *> *actionTitleList = [NSMutableArray array];
        if (action_count > 0 && action_ids && action_titles) {
            for (int i = 0; i < action_count; i++) {
                if (action_ids[i]) {
                    [actionIdList addObject:[NSString stringWithUTF8String:action_ids[i]]];
                }
                if (action_titles[i]) {
                    [actionTitleList addObject:[NSString stringWithUTF8String:action_titles[i]]];
                }
            }
        }

        NSString *targetId = [NSString stringWithFormat:@"%@:%@", deviceStr, keyStr];
        
        // Resolve image or app icon
        NSString *imageFile = (iconPathStr.length > 0) ? iconPathStr : imagePathStr;

        NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
        userInfo[@"device"] = deviceStr;
        userInfo[@"key"] = keyStr;

        // If an app icon or sender avatar is provided, deliver via NSUserNotificationCenter
        // with _identityImage so macOS displays the mirrored app's icon on the left
        // rather than the host MacLink bundle icon.
        if (iconPathStr.length > 0) {
            deliver_via_ns_user_notification(targetId, titleStr, subtitleStr, bodyStr, iconPathStr, imagePathStr, silent, has_reply, replyIdStr, replyTitleStr, actionIdList, actionTitleList, userInfo);
            return;
        }

        // Deliver via UNUserNotificationCenter on modern macOS (for internal MacLink notices)
        if (@available(macOS 10.14, *)) {
            @try {
                UNMutableNotificationContent *content = [[UNMutableNotificationContent alloc] init];
                if (titleStr.length > 0) {
                    content.title = titleStr;
                }
                if (subtitleStr.length > 0) {
                    content.subtitle = subtitleStr;
                }
                if (bodyStr.length > 0) {
                    content.body = bodyStr;
                }
                if (silent) {
                    content.sound = nil;
                } else {
                    content.sound = [UNNotificationSound defaultSound];
                }

                if (imageFile.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:imageFile]) {
                    NSURL *fileUrl = [NSURL fileURLWithPath:imageFile];
                    NSError *attErr = nil;
                    UNNotificationAttachment *attachment = [UNNotificationAttachment attachmentWithIdentifier:@"icon" URL:fileUrl options:nil error:&attErr];
                    if (attachment) {
                        content.attachments = @[attachment];
                    }
                }

                NSString *categoryId = [NSString stringWithFormat:@"cat_%@_%@", deviceStr, keyStr];
                NSMutableArray<UNNotificationAction *> *unActions = [NSMutableArray array];

                if (has_reply) {
                    userInfo[@"reply_action"] = replyIdStr;
                    UNTextInputNotificationAction *replyAction = [UNTextInputNotificationAction actionWithIdentifier:replyIdStr
                                                                                                               title:replyTitleStr
                                                                                                             options:UNNotificationActionOptionNone
                                                                                                textInputButtonTitle:@"Send"
                                                                                                textInputPlaceholder:@"Type a message..."];
                    [unActions addObject:replyAction];
                } else if (actionIdList.count > 0 && actionTitleList.count > 0) {
                    userInfo[@"primary_action"] = actionIdList[0];
                    for (NSUInteger i = 0; i < actionIdList.count && i < actionTitleList.count; i++) {
                        UNNotificationActionOptions opt = UNNotificationActionOptionForeground;
                        if ([actionIdList[i] isEqualToString:@"decline"] || [actionIdList[i] isEqualToString:@"end"]) {
                            opt = UNNotificationActionOptionDestructive;
                        }
                        UNNotificationAction *action = [UNNotificationAction actionWithIdentifier:actionIdList[i]
                                                                                            title:actionTitleList[i]
                                                                                          options:opt];
                        [unActions addObject:action];
                    }
                }

                if (unActions.count > 0) {
                    UNNotificationCategory *category = [UNNotificationCategory categoryWithIdentifier:categoryId
                                                                                               actions:unActions
                                                                                     intentIdentifiers:@[]
                                                                                               options:UNNotificationCategoryOptionCustomDismissAction];
                    UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
                    [center setNotificationCategories:[NSSet setWithObject:category]];
                    content.categoryIdentifier = categoryId;
                }

                content.userInfo = userInfo;

                UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:targetId content:content trigger:nil];
                [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:^(NSError * _Nullable error) {
                    if (error) {
                        // Fallback to NSUserNotificationCenter if UNUserNotificationCenter encounters an issue
                        dispatch_async(dispatch_get_main_queue(), ^{
                            deliver_via_ns_user_notification(targetId, titleStr, subtitleStr, bodyStr, iconPathStr, imagePathStr, silent, has_reply, replyIdStr, replyTitleStr, actionIdList, actionTitleList, userInfo);
                        });
                    }
                }];
                return;
            } @catch (NSException *e) {
                // Fall through to NSUserNotificationCenter
            }
        }

        // Fallback for older macOS
        deliver_via_ns_user_notification(targetId, titleStr, subtitleStr, bodyStr, iconPathStr, imagePathStr, silent, has_reply, replyIdStr, replyTitleStr, actionIdList, actionTitleList, userInfo);
    }
}

void mac_notification_update_progress(const char *device, const char *key, double value, const char *status) {
    (void)value;
    @autoreleasepool {
        NSString *targetId = [NSString stringWithFormat:@"%s:%s", device, key];
        for (NSUserNotification *n in [NSUserNotificationCenter defaultUserNotificationCenter].deliveredNotifications) {
            if ([n.identifier isEqualToString:targetId]) {
                if (status && strlen(status) > 0) {
                    n.informativeText = [NSString stringWithUTF8String:status];
                }
                [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:n];
                break;
            }
        }
    }
}

void mac_notification_remove(const char *device, const char *key) {
    @autoreleasepool {
        NSString *targetId = [NSString stringWithFormat:@"%s:%s", device, key];
        if (@available(macOS 10.14, *)) {
            @try {
                [[UNUserNotificationCenter currentNotificationCenter] removeDeliveredNotificationsWithIdentifiers:@[targetId]];
                [[UNUserNotificationCenter currentNotificationCenter] removePendingNotificationRequestsWithIdentifiers:@[targetId]];
            } @catch (NSException *e) {}
        }
        
        NSString *devStr = [NSString stringWithUTF8String:device];
        NSString *keyStr = [NSString stringWithUTF8String:key];
        NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
        for (NSUserNotification *n in center.deliveredNotifications) {
            if ([n.userInfo[@"device"] isEqualToString:devStr] && [n.userInfo[@"key"] isEqualToString:keyStr]) {
                [center removeDeliveredNotification:n];
            }
        }
    }
}

void mac_notification_remove_device(const char *device) {
    @autoreleasepool {
        NSString *devStr = [NSString stringWithUTF8String:device];
        
        if (@available(macOS 10.14, *)) {
            @try {
                UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
                [center getDeliveredNotificationsWithCompletionHandler:^(NSArray<UNNotification *> * _Nonnull notifications) {
                    NSMutableArray<NSString *> *toRemove = [NSMutableArray array];
                    for (UNNotification *n in notifications) {
                        if ([n.request.content.userInfo[@"device"] isEqualToString:devStr]) {
                            [toRemove addObject:n.request.identifier];
                        }
                    }
                    if (toRemove.count > 0) {
                        [center removeDeliveredNotificationsWithIdentifiers:toRemove];
                    }
                }];
            } @catch (NSException *e) {}
        }
        
        NSUserNotificationCenter *center = [NSUserNotificationCenter defaultUserNotificationCenter];
        for (NSUserNotification *n in center.deliveredNotifications) {
            if ([n.userInfo[@"device"] isEqualToString:devStr]) {
                [center removeDeliveredNotification:n];
            }
        }
    }
}

void mac_notification_unregister(void) {
    @autoreleasepool {
        if (@available(macOS 10.14, *)) {
            @try {
                [[UNUserNotificationCenter currentNotificationCenter] removeAllDeliveredNotifications];
                [[UNUserNotificationCenter currentNotificationCenter] removeAllPendingNotificationRequests];
                [UNUserNotificationCenter currentNotificationCenter].delegate = nil;
                s_un_delegate = nil;
            } @catch (NSException *e) {}
        }
        [[NSUserNotificationCenter defaultUserNotificationCenter] removeAllDeliveredNotifications];
        [NSUserNotificationCenter defaultUserNotificationCenter].delegate = nil;
        s_ns_delegate = nil;
    }
}

}

#pragma clang diagnostic pop
