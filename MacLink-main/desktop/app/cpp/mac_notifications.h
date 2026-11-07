// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*MacNotificationCallback)(
    const char *event_type, // "opened", "action", "reply", "dismissed"
    const char *device,
    const char *key,
    const char *action_id,
    const char *reply_text
);

void mac_notification_start(const char *app_icon_path, MacNotificationCallback callback);

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
);

void mac_notification_update_progress(const char *device, const char *key, double value, const char *status);

void mac_notification_remove(const char *device, const char *key);

void mac_notification_remove_device(const char *device);

void mac_notification_unregister(void);

#ifdef __cplusplus
}
#endif

