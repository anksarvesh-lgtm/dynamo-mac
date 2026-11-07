// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Default Shelf edge trigger and cursor glow configuration
typedef struct {
    float trigger_ratio;        // 0.25 (Small), 0.40 (Medium, default), 0.60 (Large)
    float height_min;           // 280.0 pt
    float height_max;           // 520.0 pt
    float trigger_depth;        // 4.0 pt (within 4 pt of left edge counts as "at the edge")
    float approach_range;       // 48.0 pt (starts glow fade-in)
    uint32_t dwell_ms;          // 150 ms dwell required before opening
    uint32_t glow_fade_in_ms;   // 150 ms
    uint32_t glow_fade_out_ms;  // 250 ms
    bool edge_handle_idle;      // false (default off)
} ShelfEdgeConfig;

typedef void (*ShelfTriggerCallback)(void);
typedef void (*ShelfCloseCallback)(void);

/// Initializes the native macOS edge trigger and cursor glow monitor
void shelf_edge_init(ShelfTriggerCallback on_trigger);

/// Sets callback to automatically close shelf when cursor leaves shelf area
void shelf_edge_set_close_callback(ShelfCloseCallback on_close);

/// Sets whether the edge trigger is enabled
void shelf_edge_set_enabled(bool enabled);

/// Sets the edge trigger height ratio (0.25, 0.40, 0.60)
void shelf_edge_set_ratio(float ratio);

/// Notifies edge monitor when Shelf open state changes
void shelf_edge_set_shelf_open(bool is_open);

/// Applies native NSWindow collection behaviors and floating window level to the Shelf window
void shelf_edge_style_shelf_window(const char *window_title);

/// Cleans up monitors, timers, and glow window
void shelf_edge_cleanup(void);

#ifdef __cplusplus
}
#endif

