// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    DOCK_ICON_MODE_ACCESSORY_WHEN_HIDDEN = 0, // Option A (default)
    DOCK_ICON_MODE_ALWAYS_SHOW = 1,          // Option B
    DOCK_ICON_MODE_NEVER_SHOW = 2            // Option C
} MacDockIconMode;

typedef enum {
    MAC_LOGIN_ITEM_NOT_REGISTERED = 0,
    MAC_LOGIN_ITEM_ENABLED = 1,
    MAC_LOGIN_ITEM_REQUIRES_APPROVAL = 2,
    MAC_LOGIN_ITEM_NOT_FOUND = 3,
    MAC_LOGIN_ITEM_UNSUPPORTED = 4
} MacLoginItemStatus;

typedef void (*MacLifecycleCallback)(void);

// Lifecycle & Reopen
void mac_lifecycle_init(MacLifecycleCallback on_activate, MacLifecycleCallback on_quit, MacLifecycleCallback on_wake);
void mac_lifecycle_cleanup(void);

// Dock Icon Policy
void mac_set_dock_icon_mode(MacDockIconMode mode);
MacDockIconMode mac_get_dock_icon_mode(void);
void mac_on_window_shown(void);
void mac_on_window_hidden(void);

// Menu Bar Status Item
void mac_status_item_init(MacLifecycleCallback on_open,
                          MacLifecycleCallback on_shelf,
                          MacLifecycleCallback on_find_phone,
                          MacLifecycleCallback on_toggle_login,
                          MacLifecycleCallback on_quit);
void mac_status_item_update(const char *status_line,
                            bool phone_connected,
                            bool shelf_available,
                            bool find_phone_available);

// SMAppService Login Item
MacLoginItemStatus mac_login_item_get_status(void);
bool mac_login_item_set_enabled(bool enabled, char *err_buf, int err_buf_len);
void mac_login_item_open_settings(void);
bool mac_was_launched_as_login_item(void);

// App Nap Assertion
void mac_set_phone_activity(bool connected);

#ifdef __cplusplus
}
#endif

