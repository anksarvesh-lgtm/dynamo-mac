// SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import <ServiceManagement/ServiceManagement.h>
#import <objc/runtime.h>
#include "mac_lifecycle.h"

static MacDockIconMode g_dockIconMode = DOCK_ICON_MODE_ACCESSORY_WHEN_HIDDEN;
static MacLifecycleCallback g_onActivate = nullptr;
static MacLifecycleCallback g_onQuit = nullptr;
static MacLifecycleCallback g_onWake = nullptr;
static MacLifecycleCallback g_onOpen = nullptr;
static MacLifecycleCallback g_onShelf = nullptr;
static MacLifecycleCallback g_onFindPhone = nullptr;
static MacLifecycleCallback g_onToggleLogin = nullptr;

static NSStatusItem *g_statusItem = nil;
static NSMenuItem *g_statusMenuItem = nil;
static NSMenuItem *g_shelfMenuItem = nil;
static NSMenuItem *g_findPhoneMenuItem = nil;
static NSMenuItem *g_loginMenuItem = nil;
static NSImage *g_iconConnected = nil;
static NSImage *g_iconDisconnected = nil;

static id<NSObject> g_phoneActivityAssertion = nil;
static id<NSObject> g_wakeObserver = nil;
static id<NSObject> g_reopenObserver = nil;

// ---------------------------------------------------------------------------
// Menu Bar Helper Target
// ---------------------------------------------------------------------------
@interface MacLifecycleMenuTarget : NSObject
- (void)openClicked:(id)sender;
- (void)shelfClicked:(id)sender;
- (void)findPhoneClicked:(id)sender;
- (void)toggleLoginClicked:(id)sender;
- (void)quitClicked:(id)sender;
@end

@implementation MacLifecycleMenuTarget
- (void)openClicked:(id)sender {
    if (g_onOpen) g_onOpen();
    else if (g_onActivate) g_onActivate();
}

- (void)shelfClicked:(id)sender {
    if (g_onShelf) g_onShelf();
}

- (void)findPhoneClicked:(id)sender {
    if (g_onFindPhone) g_onFindPhone();
}

- (void)toggleLoginClicked:(id)sender {
    if (g_onToggleLogin) {
        g_onToggleLogin();
    } else {
        // Default toggle handler
        MacLoginItemStatus status = mac_login_item_get_status();
        if (status == MAC_LOGIN_ITEM_ENABLED) {
            char err[256] = {0};
            mac_login_item_set_enabled(false, err, sizeof(err));
        } else if (status == MAC_LOGIN_ITEM_REQUIRES_APPROVAL) {
            mac_login_item_open_settings();
        } else {
            char err[256] = {0};
            mac_login_item_set_enabled(true, err, sizeof(err));
        }
    }
}

- (void)quitClicked:(id)sender {
    if (g_onQuit) g_onQuit();
    else [NSApp terminate:nil];
}
@end

static MacLifecycleMenuTarget *g_menuTarget = nil;

// ---------------------------------------------------------------------------
// Method Swizzling for applicationShouldHandleReopen:hasVisibleWindows:
// ---------------------------------------------------------------------------
static BOOL (*g_originalShouldHandleReopen)(id, SEL, NSApplication *, BOOL) = nullptr;

static BOOL MacLink_applicationShouldHandleReopen(id self, SEL _cmd, NSApplication *sender, BOOL hasVisibleWindows) {
    if (g_onActivate) {
        g_onActivate();
    }
    if (g_originalShouldHandleReopen) {
        return g_originalShouldHandleReopen(self, _cmd, sender, hasVisibleWindows);
    }
    return YES;
}

static void swizzleAppDelegateReopen(void) {
    id delegate = [NSApp delegate];
    if (!delegate) return;
    
    Class delegateClass = [delegate class];
    SEL reopenSel = @selector(applicationShouldHandleReopen:hasVisibleWindows:);
    Method method = class_getInstanceMethod(delegateClass, reopenSel);
    
    if (method) {
        g_originalShouldHandleReopen = (BOOL (*)(id, SEL, NSApplication *, BOOL))method_getImplementation(method);
        method_setImplementation(method, (IMP)MacLink_applicationShouldHandleReopen);
    } else {
        class_addMethod(delegateClass, reopenSel, (IMP)MacLink_applicationShouldHandleReopen, "c@:@c");
    }
}

// ---------------------------------------------------------------------------
// Lifecycle & Reopen
// ---------------------------------------------------------------------------
void mac_lifecycle_init(MacLifecycleCallback on_activate, MacLifecycleCallback on_quit, MacLifecycleCallback on_wake) {
    g_onActivate = on_activate;
    g_onQuit = on_quit;
    g_onWake = on_wake;

    dispatch_async(dispatch_get_main_queue(), ^{
        swizzleAppDelegateReopen();
        
        // Also listen for applicationDidBecomeActive
        if (!g_reopenObserver) {
            g_reopenObserver = [[NSNotificationCenter defaultCenter]
                addObserverForName:NSApplicationDidBecomeActiveNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification * _Nonnull note) {
                            (void)note;
                            // If activated and no normal windows are visible, trigger activation
                            BOOL hasVisible = NO;
                            for (NSWindow *w in [NSApp windows]) {
                                if ([w isVisible] && [w canBecomeKeyWindow]) {
                                    hasVisible = YES;
                                    break;
                                }
                            }
                            if (!hasVisible && g_onActivate) {
                                g_onActivate();
                            }
                        }];
        }
        
        // Listen for system wake from sleep
        if (!g_wakeObserver) {
            g_wakeObserver = [[[NSWorkspace sharedWorkspace] notificationCenter]
                addObserverForName:NSWorkspaceDidWakeNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification * _Nonnull note) {
                            (void)note;
                            if (g_onWake) {
                                g_onWake();
                            }
                        }];
        }
    });
}

void mac_lifecycle_cleanup(void) {
    if (g_phoneActivityAssertion) {
        [[NSProcessInfo processInfo] endActivity:g_phoneActivityAssertion];
        g_phoneActivityAssertion = nil;
    }
    if (g_statusItem) {
        [[NSStatusBar systemStatusBar] removeStatusItem:g_statusItem];
        g_statusItem = nil;
    }
    if (g_wakeObserver) {
        [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:g_wakeObserver];
        g_wakeObserver = nil;
    }
    if (g_reopenObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:g_reopenObserver];
        g_reopenObserver = nil;
    }
}

// ---------------------------------------------------------------------------
// Dock Icon Policy
// ---------------------------------------------------------------------------
void mac_set_dock_icon_mode(MacDockIconMode mode) {
    g_dockIconMode = mode;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (mode == DOCK_ICON_MODE_NEVER_SHOW) {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        } else if (mode == DOCK_ICON_MODE_ALWAYS_SHOW) {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        }
    });
}

MacDockIconMode mac_get_dock_icon_mode(void) {
    return g_dockIconMode;
}

void mac_on_window_shown(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_dockIconMode == DOCK_ICON_MODE_ACCESSORY_WHEN_HIDDEN) {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        }
        [NSApp activateIgnoringOtherApps:YES];
    });
}

void mac_on_window_hidden(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_dockIconMode == DOCK_ICON_MODE_ACCESSORY_WHEN_HIDDEN) {
            [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        }
    });
}

// ---------------------------------------------------------------------------
// Menu Bar Icon & Status Item
// ---------------------------------------------------------------------------
static NSImage *loadBrandImage(void) {
    // 1. App Bundle resources
    NSString *resPath = [[NSBundle mainBundle] pathForResource:@"maclink-liquid-logo" ofType:@"png"];
    if (resPath && [[NSFileManager defaultManager] fileExistsAtPath:resPath]) {
        NSImage *img = [[NSImage alloc] initWithContentsOfFile:resPath];
        if (img && img.isValid) return img;
    }

    // 2. Resources folder relative to bundle
    NSString *bundleRes = [[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"Contents/Resources"]
                           stringByAppendingPathComponent:@"maclink-liquid-logo.png"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:bundleRes]) {
        NSImage *img = [[NSImage alloc] initWithContentsOfFile:bundleRes];
        if (img && img.isValid) return img;
    }

    // 3. Next to executable
    NSString *exeDir = [[[NSBundle mainBundle] executablePath] stringByDeletingLastPathComponent];
    if (exeDir) {
        NSString *exeNeighbor = [exeDir stringByAppendingPathComponent:@"maclink-liquid-logo.png"];
        if ([[NSFileManager defaultManager] fileExistsAtPath:exeNeighbor]) {
            NSImage *img = [[NSImage alloc] initWithContentsOfFile:exeNeighbor];
            if (img && img.isValid) return img;
        }
    }

    // 4. File-system relative paths (development & test runs)
    NSArray<NSString *> *candidates = @[
        @"assets/brand/maclink-liquid-logo.png",
        @"../assets/brand/maclink-liquid-logo.png",
        @"../../assets/brand/maclink-liquid-logo.png",
        @"../../../assets/brand/maclink-liquid-logo.png",
        @"/Users/sarvesh/Documents/MacLink/nectarlink/assets/brand/maclink-liquid-logo.png"
    ];
    for (NSString *candidate in candidates) {
        if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
            NSImage *img = [[NSImage alloc] initWithContentsOfFile:candidate];
            if (img && img.isValid) return img;
        }
    }

    // 5. Look for MacLink.icns in bundle
    NSString *icnsPath = [[NSBundle mainBundle] pathForResource:@"MacLink" ofType:@"icns"];
    if (icnsPath && [[NSFileManager defaultManager] fileExistsAtPath:icnsPath]) {
        NSImage *img = [[NSImage alloc] initWithContentsOfFile:icnsPath];
        if (img && img.isValid) return img;
    }

    // 6. Application icon image fallback
    NSImage *appIcon = [NSApp applicationIconImage];
    if (appIcon && appIcon.isValid) return appIcon;

    return nil;
}

static NSImage *createBrandStatusBarIcon(CGFloat alpha) {
    NSImage *baseImage = loadBrandImage();
    NSSize size = NSMakeSize(18.0, 18.0);
    NSImage *image = [NSImage imageWithSize:size flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
        if (!ctx) return NO;

        CGContextSaveGState(ctx);
        CGContextSetAlpha(ctx, alpha);

        if (baseImage) {
            CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
            NSRect targetRect = NSInsetRect(dstRect, 0.5, 0.5);
            [baseImage drawInRect:targetRect
                         fromRect:NSZeroRect
                        operation:NSCompositingOperationSourceOver
                         fraction:alpha];
        }

        CGContextRestoreGState(ctx);
        return YES;
    }];

    return image;
}


void mac_status_item_init(MacLifecycleCallback on_open,
                          MacLifecycleCallback on_shelf,
                          MacLifecycleCallback on_find_phone,
                          MacLifecycleCallback on_toggle_login,
                          MacLifecycleCallback on_quit) {
    g_onOpen = on_open;
    g_onShelf = on_shelf;
    g_onFindPhone = on_find_phone;
    g_onToggleLogin = on_toggle_login;
    if (on_quit) g_onQuit = on_quit;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (g_statusItem) return;

        g_menuTarget = [[MacLifecycleMenuTarget alloc] init];
        g_iconConnected = createBrandStatusBarIcon(1.0f);
        g_iconDisconnected = createBrandStatusBarIcon(0.40f);

        g_statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSSquareStatusItemLength];
        if (g_statusItem.button) {
            g_statusItem.button.image = g_iconDisconnected;
            g_statusItem.button.imagePosition = NSImageOnly;
            g_statusItem.button.toolTip = @"MacLink";
        }

        NSMenu *menu = [[NSMenu alloc] initWithTitle:@"MacLink"];
        [menu setAutoenablesItems:NO];

        // 1. Status line (disabled, real data)
        g_statusMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"No phone connected", nil)
                                                      action:nil
                                               keyEquivalent:@""];
        [g_statusMenuItem setEnabled:NO];
        [menu addItem:g_statusMenuItem];

        [menu addItem:[NSMenuItem separatorItem]];

        // 2. Open MacLink
        NSMenuItem *openItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Open MacLink", nil)
                                                          action:@selector(openClicked:)
                                                   keyEquivalent:@""];
        [openItem setTarget:g_menuTarget];
        [openItem setEnabled:YES];
        [menu addItem:openItem];

        // 3. Open Shelf
        g_shelfMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Open Shelf", nil)
                                                     action:@selector(shelfClicked:)
                                              keyEquivalent:@""];
        [g_shelfMenuItem setTarget:g_menuTarget];
        [g_shelfMenuItem setEnabled:YES];
        [menu addItem:g_shelfMenuItem];

        // 4. Find phone
        g_findPhoneMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Find phone", nil)
                                                         action:@selector(findPhoneClicked:)
                                                  keyEquivalent:@""];
        [g_findPhoneMenuItem setTarget:g_menuTarget];
        [g_findPhoneMenuItem setEnabled:NO];
        [menu addItem:g_findPhoneMenuItem];

        [menu addItem:[NSMenuItem separatorItem]];

        // 5. Start MacLink at login
        g_loginMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Start MacLink at login", nil)
                                                     action:@selector(toggleLoginClicked:)
                                              keyEquivalent:@""];
        [g_loginMenuItem setTarget:g_menuTarget];
        [g_loginMenuItem setEnabled:YES];
        MacLoginItemStatus loginStatus = mac_login_item_get_status();
        [g_loginMenuItem setState:(loginStatus == MAC_LOGIN_ITEM_ENABLED ? NSControlStateValueOn : NSControlStateValueOff)];
        [menu addItem:g_loginMenuItem];

        [menu addItem:[NSMenuItem separatorItem]];

        // 6. Quit MacLink (⌘Q)
        NSMenuItem *quitItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Quit MacLink", nil)
                                                          action:@selector(quitClicked:)
                                                   keyEquivalent:@"q"];
        [quitItem setTarget:g_menuTarget];
        [quitItem setKeyEquivalentModifierMask:NSEventModifierFlagCommand];
        [quitItem setEnabled:YES];
        [menu addItem:quitItem];

        g_statusItem.menu = menu;
    });
}

void mac_status_item_update(const char *status_line,
                            bool phone_connected,
                            bool shelf_available,
                            bool find_phone_available) {
    NSString *lineStr = status_line ? [NSString stringWithUTF8String:status_line] : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!g_statusItem) return;

        if (g_statusItem.button) {
            g_statusItem.button.image = phone_connected ? g_iconConnected : g_iconDisconnected;
        }

        if (g_statusMenuItem && lineStr) {
            g_statusMenuItem.title = lineStr;
        }

        if (g_shelfMenuItem) {
            [g_shelfMenuItem setEnabled:shelf_available ? YES : NO];
        }

        if (g_findPhoneMenuItem) {
            [g_findPhoneMenuItem setEnabled:find_phone_available ? YES : NO];
        }

        if (g_loginMenuItem) {
            MacLoginItemStatus status = mac_login_item_get_status();
            [g_loginMenuItem setState:(status == MAC_LOGIN_ITEM_ENABLED ? NSControlStateValueOn : NSControlStateValueOff)];
            if (status == MAC_LOGIN_ITEM_REQUIRES_APPROVAL) {
                g_loginMenuItem.title = NSLocalizedString(@"Start MacLink at login (Approval Required)", nil);
            } else {
                g_loginMenuItem.title = NSLocalizedString(@"Start MacLink at login", nil);
            }
        }
    });
}

// ---------------------------------------------------------------------------
// SMAppService Login Item
// ---------------------------------------------------------------------------
MacLoginItemStatus mac_login_item_get_status(void) {
    if (@available(macOS 13.0, *)) {
        SMAppServiceStatus s = [SMAppService.mainAppService status];
        switch (s) {
            case SMAppServiceStatusNotRegistered: return MAC_LOGIN_ITEM_NOT_REGISTERED;
            case SMAppServiceStatusEnabled: return MAC_LOGIN_ITEM_ENABLED;
            case SMAppServiceStatusRequiresApproval: return MAC_LOGIN_ITEM_REQUIRES_APPROVAL;
            case SMAppServiceStatusNotFound: return MAC_LOGIN_ITEM_NOT_FOUND;
            default: return MAC_LOGIN_ITEM_NOT_REGISTERED;
        }
    }
    return MAC_LOGIN_ITEM_UNSUPPORTED;
}

bool mac_login_item_set_enabled(bool enabled, char *err_buf, int err_buf_len) {
    if (@available(macOS 13.0, *)) {
        NSError *error = nil;
        BOOL success = NO;
        if (enabled) {
            success = [SMAppService.mainAppService registerAndReturnError:&error];
        } else {
            success = [SMAppService.mainAppService unregisterAndReturnError:&error];
        }
        if (!success && error) {
            NSLog(@"[MacLifecycle SMAppService error]: %@", error);
            if (err_buf && err_buf_len > 0) {
                snprintf(err_buf, err_buf_len, "%s", [[error localizedDescription] UTF8String]);
            }
        }
        // Update menu item checkmark immediately
        dispatch_async(dispatch_get_main_queue(), ^{
            if (g_loginMenuItem) {
                MacLoginItemStatus status = mac_login_item_get_status();
                [g_loginMenuItem setState:(status == MAC_LOGIN_ITEM_ENABLED ? NSControlStateValueOn : NSControlStateValueOff)];
            }
        });
        return success ? true : false;
    }
    if (err_buf && err_buf_len > 0) {
        snprintf(err_buf, err_buf_len, "SMAppService requires macOS 13 or later");
    }
    return false;
}

void mac_login_item_open_settings(void) {
    if (@available(macOS 13.0, *)) {
        [SMAppService openSystemSettingsLoginItems];
    } else {
        [[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:@"/System/Library/PreferencePanes/Accounts.prefPane"]];
    }
}

bool mac_was_launched_as_login_item(void) {
    NSAppleEventDescriptor *event = [[NSAppleEventManager sharedAppleEventManager] currentAppleEvent];
    if (event) {
        NSAppleEventDescriptor *prop = [event attributeDescriptorForKeyword:keyAELaunchedAsLogInItem];
        if (prop && [prop booleanValue]) {
            return true;
        }
    }
    return false;
}

// ---------------------------------------------------------------------------
// App Nap Prevention (Assertion while phone connected)
// ---------------------------------------------------------------------------
void mac_set_phone_activity(bool connected) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (connected) {
            if (!g_phoneActivityAssertion) {
                g_phoneActivityAssertion = [[NSProcessInfo processInfo]
                    beginActivityWithOptions:NSActivityUserInitiatedAllowingIdleSystemSleep
                                      reason:@"MacLink active phone connection"];
                NSLog(@"[MacLifecycle] Held activity assertion for active phone connection");
            }
        } else {
            if (g_phoneActivityAssertion) {
                [[NSProcessInfo processInfo] endActivity:g_phoneActivityAssertion];
                g_phoneActivityAssertion = nil;
                NSLog(@"[MacLifecycle] Released activity assertion (phone disconnected)");
            }
        }
    });
}

