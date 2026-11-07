// SPDX-License-Identifier: GPL-3.0-or-later
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#include "shelf_edge.h"

static ShelfEdgeConfig g_config = {
    .trigger_ratio = 0.40f,
    .height_min = 280.0f,
    .height_max = 520.0f,
    .trigger_depth = 4.0f,
    .approach_range = 48.0f,
    .dwell_ms = 150,
    .glow_fade_in_ms = 150,
    .glow_fade_out_ms = 250,
    .edge_handle_idle = false
};

static void shelf_edge_log(const char *event_name) {
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    [df setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss.SSS"];
    NSString *ts = [df stringFromDate:[NSDate date]];
    NSLog(@"[ShelfEdge %@] %s", ts, event_name);
}

// ---------------------------------------------------------------------------
// ShelfGlowView
// ---------------------------------------------------------------------------
@interface ShelfGlowView : NSView
@property (nonatomic, assign) CGFloat cursorYInView;
@property (nonatomic, assign) CGFloat glowOpacity;
@end

@implementation ShelfGlowView

- (BOOL)isOpaque {
    return NO;
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    if (self.glowOpacity <= 0.001f) {
        return;
    }

    CGContextRef ctx = [[NSGraphicsContext currentContext] CGContext];
    if (!ctx) return;

    CGContextSaveGState(ctx);

    CGFloat cy = self.cursorYInView;
    CGFloat rx = 32.0f;
    CGFloat ry = 90.0f;

    // 1. Soft half-ellipse glow growing out of screen edge (x = 0)
    CGContextSaveGState(ctx);
    CGMutablePathRef ellipsePath = CGPathCreateMutable();
    CGPathAddEllipseInRect(ellipsePath, NULL, CGRectMake(-rx, cy - ry, rx * 2.0f, ry * 2.0f));
    CGContextAddPath(ctx, ellipsePath);
    CGContextClip(ctx);
    CGPathRelease(ellipsePath);

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGFloat colors[] = {
        1.00f, 0.97f, 0.92f, 0.85f * self.glowOpacity, // Warm white core
        0.95f, 0.66f, 0.23f, 0.65f * self.glowOpacity, // Amber #F2A93B
        0.85f, 0.47f, 0.02f, 0.25f * self.glowOpacity, // Deep amber #D97706
        0.85f, 0.47f, 0.02f, 0.00f                    // Fade out
    };
    CGFloat locations[] = { 0.0f, 0.25f, 0.70f, 1.0f };
    CGGradientRef grad = CGGradientCreateWithColorComponents(cs, colors, locations, 4);
    if (grad) {
        CGContextDrawRadialGradient(ctx, grad, CGPointMake(0, cy), 0, CGPointMake(0, cy), ry, kCGGradientDrawsAfterEndLocation);
        CGGradientRelease(grad);
    }
    CGContextRestoreGState(ctx);

    // 2. Thin bright line (2 pt) along the edge (at x = 0), ~50% opacity, inside the glow height
    CGFloat railColors[] = {
        1.00f, 0.96f, 0.88f, 0.00f,
        1.00f, 0.96f, 0.88f, 0.55f * self.glowOpacity,
        1.00f, 0.96f, 0.88f, 0.00f
    };
    CGFloat railLocs[] = { 0.0f, 0.5f, 1.0f };
    CGGradientRef railGrad = CGGradientCreateWithColorComponents(cs, railColors, railLocs, 3);
    if (railGrad) {
        CGContextDrawLinearGradient(ctx, railGrad, CGPointMake(0, cy - ry), CGPointMake(0, cy + ry), 0);
        CGGradientRelease(railGrad);
    }
    CGColorSpaceRelease(cs);

    CGContextRestoreGState(ctx);
}

@end

// ---------------------------------------------------------------------------
// ShelfEdgeController
// ---------------------------------------------------------------------------
@interface ShelfEdgeController : NSObject
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL isShelfOpen;
@property (nonatomic, assign) ShelfTriggerCallback onTrigger;
@property (nonatomic, assign) ShelfCloseCallback onClose;

- (void)start;
- (void)stop;
- (void)setRatio:(float)ratio;
- (void)updateOpenState:(BOOL)isOpen;
@end

@implementation ShelfEdgeController {
    id _globalMoveMonitor;
    id _localMoveMonitor;
    id _globalClickMonitor;
    id _localClickMonitor;

    NSWindow *_glowWindow;
    ShelfGlowView *_glowView;

    dispatch_source_t _dwellTimer;
    dispatch_source_t _fadeTimer;
    dispatch_source_t _shelfLeaveTimer;

    BOOL _inTriggerArea;
    BOOL _dwellActive;
    BOOL _dockWarningLogged;
    BOOL _shelfHoveredOnce;

    NSInteger _lastMouseDownDragChangeCount;
    CGFloat _targetOpacity;
    CGFloat _currentOpacity;
    CGFloat _targetCursorY;
    CGFloat _currentCursorY;
}

static ShelfEdgeController *s_instance = nil;
static __weak NSWindow *s_shelfWindow = nil;

- (instancetype)init {
    self = [super init];
    if (self) {
        _enabled = YES;
        _isShelfOpen = NO;
        _inTriggerArea = NO;
        _dwellActive = NO;
        _dockWarningLogged = NO;
        _shelfHoveredOnce = NO;
        _lastMouseDownDragChangeCount = 0;
        _targetOpacity = 0.0f;
        _currentOpacity = 0.0f;
        _targetCursorY = 0.0f;
        _currentCursorY = 0.0f;

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(screenParametersChanged:)
                                                     name:NSApplicationDidChangeScreenParametersNotification
                                                   object:nil];
        [[[NSWorkspace sharedWorkspace] notificationCenter] addObserver:self
                                                               selector:@selector(workspaceDidWake:)
                                                                   name:NSWorkspaceDidWakeNotification
                                                                 object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [[[NSWorkspace sharedWorkspace] notificationCenter] removeObserver:self];
    [self stop];
}

- (void)screenParametersChanged:(NSNotification *)note {
    (void)note;
    _dockWarningLogged = NO;
    [self hideGlowImmediately];
}

- (void)workspaceDidWake:(NSNotification *)note {
    (void)note;
    _dockWarningLogged = NO;
    [self hideGlowImmediately];
}

- (void)ensureGlowWindow {
    if (_glowWindow) return;

    NSRect initialFrame = NSMakeRect(0, 0, 48, 400);
    _glowWindow = [[NSWindow alloc] initWithContentRect:initialFrame
                                              styleMask:NSWindowStyleMaskBorderless
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    [_glowWindow setOpaque:NO];
    [_glowWindow setBackgroundColor:[NSColor clearColor]];
    [_glowWindow setHasShadow:NO];
    [_glowWindow setIgnoresMouseEvents:YES];
    [_glowWindow setLevel:NSFloatingWindowLevel];
    [_glowWindow setCollectionBehavior:(NSWindowCollectionBehaviorCanJoinAllSpaces |
                                        NSWindowCollectionBehaviorFullScreenAuxiliary |
                                        NSWindowCollectionBehaviorStationary)];
    [_glowWindow setHidesOnDeactivate:NO];

    _glowView = [[ShelfGlowView alloc] initWithFrame:initialFrame];
    [_glowWindow setContentView:_glowView];
    [_glowWindow orderOut:nil];
}

- (void)start {
    if (!self.enabled) return;
    [self stop];

    [self ensureGlowWindow];

    NSEventMask moveMask = NSEventMaskMouseMoved |
                           NSEventMaskLeftMouseDragged |
                           NSEventMaskRightMouseDragged |
                           NSEventMaskOtherMouseDragged;

    __weak ShelfEdgeController *weakSelf = self;
    _globalMoveMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:moveMask handler:^(NSEvent *event) {
        [weakSelf handleMouseEvent:event];
    }];

    _localMoveMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:moveMask handler:^NSEvent *(NSEvent *event) {
        [weakSelf handleMouseEvent:event];
        return event;
    }];

    NSEventMask clickMask = NSEventMaskLeftMouseDown | NSEventMaskLeftMouseUp;
    _globalClickMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:clickMask handler:^(NSEvent *event) {
        [weakSelf handleClickEvent:event];
    }];

    _localClickMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:clickMask handler:^NSEvent *(NSEvent *event) {
        [weakSelf handleClickEvent:event];
        return event;
    }];
}

- (void)stop {
    if (_globalMoveMonitor) {
        [NSEvent removeMonitor:_globalMoveMonitor];
        _globalMoveMonitor = nil;
    }
    if (_localMoveMonitor) {
        [NSEvent removeMonitor:_localMoveMonitor];
        _localMoveMonitor = nil;
    }
    if (_globalClickMonitor) {
        [NSEvent removeMonitor:_globalClickMonitor];
        _globalClickMonitor = nil;
    }
    if (_localClickMonitor) {
        [NSEvent removeMonitor:_localClickMonitor];
        _localClickMonitor = nil;
    }

    [self cancelDwellTimer];
    [self cancelShelfLeaveTimer];
    [self stopFadeTimer];
    [self hideGlowImmediately];
}

- (void)setRatio:(float)ratio {
    if (ratio > 0.05f && ratio <= 1.0f) {
        g_config.trigger_ratio = ratio;
    }
}

- (void)updateOpenState:(BOOL)isOpen {
    _isShelfOpen = isOpen;
    if (isOpen) {
        [self cancelDwellTimer];
        [self fadeGlowOut];
    } else {
        [self cancelShelfLeaveTimer];
        _shelfHoveredOnce = NO;
    }
}

- (void)handleClickEvent:(NSEvent *)event {
    if (event.type == NSEventTypeLeftMouseDown) {
        NSPasteboard *dragPb = [NSPasteboard pasteboardWithName:NSPasteboardNameDrag];
        _lastMouseDownDragChangeCount = [dragPb changeCount];
    }
}

- (void)handleMouseEvent:(NSEvent *)event {
    (void)event;
    if (!self.enabled) {
        if (_targetOpacity > 0.0f) [self fadeGlowOut];
        return;
    }

    NSPoint mouseLocation = [NSEvent mouseLocation];

    if (_isShelfOpen) {
        if (_targetOpacity > 0.0f) [self fadeGlowOut];

        NSRect shelfFrame = NSZeroRect;
        if (s_shelfWindow && [s_shelfWindow isVisible]) {
            shelfFrame = s_shelfWindow.frame;
        } else {
            NSScreen *scr = [NSScreen mainScreen];
            for (NSScreen *s in [NSScreen screens]) {
                if (NSPointInRect(mouseLocation, s.frame)) {
                    scr = s;
                    break;
                }
            }
            NSRect sf = scr ? scr.frame : NSMakeRect(0, 0, 1920, 1080);
            CGFloat availH = scr ? scr.visibleFrame.size.height : 1080;
            CGFloat h = fminf(620.0f, fmaxf(420.0f, availH - 48.0f));
            CGFloat y_center = sf.origin.y + (sf.size.height / 2.0f);
            shelfFrame = NSMakeRect(sf.origin.x, y_center - (h / 2.0f), 360.0f, h);
        }

        // Active area: shelf rect with 40 pt margin on top/bottom/right, and flush to screen left edge
        NSRect activeArea = NSInsetRect(shelfFrame, -40.0f, -40.0f);
        if (activeArea.origin.x > 0) activeArea.origin.x = 0;
        activeArea.size.width += 40.0f;

        if (NSPointInRect(mouseLocation, activeArea)) {
            _shelfHoveredOnce = YES;
            [self cancelShelfLeaveTimer];
        } else {
            // Mouse has moved away from the shelf area
            if (_shelfHoveredOnce && [NSEvent pressedMouseButtons] == 0) {
                [self startShelfLeaveTimer];
            }
        }
        return;
    }

    // Find screen containing cursor
    NSScreen *screen = nil;
    for (NSScreen *s in [NSScreen screens]) {
        if (NSPointInRect(mouseLocation, s.frame)) {
            screen = s;
            break;
        }
    }
    if (!screen) {
        [self cancelDwellTimer];
        [self fadeGlowOut];
        return;
    }

    NSRect frame = screen.frame;

    // First line optimization: if cursor is farther than approach range (48 pt) from left edge, return at once
    CGFloat dist = mouseLocation.x - frame.origin.x;
    if (dist > g_config.approach_range || dist < -1.0f) {
        if (_inTriggerArea) {
            _inTriggerArea = NO;
        }
        [self cancelDwellTimer];
        [self fadeGlowOut];
        return;
    }

    // Outer left edge check: no screen immediately to the left
    BOOL hasLeftNeighbor = NO;
    for (NSScreen *s in [NSScreen screens]) {
        if (s == screen) continue;
        NSRect sf = s.frame;
        if (fabs((sf.origin.x + sf.size.width) - frame.origin.x) < 4.0f) {
            if (sf.origin.y < frame.origin.y + frame.size.height &&
                sf.origin.y + sf.size.height > frame.origin.y) {
                hasLeftNeighbor = YES;
                break;
            }
        }
    }
    if (hasLeftNeighbor) {
        [self cancelDwellTimer];
        [self fadeGlowOut];
        return;
    }

    // Dock on the left check: visibleFrame.minX > frame.minX means Dock is on the left
    if (screen.visibleFrame.origin.x > frame.origin.x + 2.0f) {
        if (!_dockWarningLogged) {
            shelf_edge_log("edge-disabled(dock-left)");
            _dockWarningLogged = YES;
        }
        [self cancelDwellTimer];
        [self fadeGlowOut];
        return;
    }

    // Trigger area height clamped between 280 and 520 pt, centered vertically
    CGFloat H = frame.size.height;
    CGFloat h = fmaxf(g_config.height_min, fminf(H * g_config.trigger_ratio, g_config.height_max));
    CGFloat y_center = frame.origin.y + (H / 2.0f);
    CGFloat y_min = y_center - (h / 2.0f);
    CGFloat y_max = y_center + (h / 2.0f);

    // Outside trigger area height
    if (mouseLocation.y < y_min || mouseLocation.y > y_max) {
        if (_inTriggerArea) {
            shelf_edge_log("edge-ignored(outside-area)");
            _inTriggerArea = NO;
        }
        [self cancelDwellTimer];
        [self fadeGlowOut];
        return;
    }

    // Entered the trigger area
    if (!_inTriggerArea) {
        shelf_edge_log("edge-enter");
        _inTriggerArea = YES;
    }

    // Window drag vs Item drag check
    BOOL isItemDrag = NO;
    if ([NSEvent pressedMouseButtons] != 0) {
        NSPasteboard *dragPb = [NSPasteboard pasteboardWithName:NSPasteboardNameDrag];
        NSInteger currentChangeCount = [dragPb changeCount];
        if (currentChangeCount == _lastMouseDownDragChangeCount || [dragPb pasteboardItems].count == 0) {
            shelf_edge_log("edge-ignored(window-drag)");
            [self cancelDwellTimer];
            [self fadeGlowOut];
            return;
        } else {
            isItemDrag = YES;
        }
    }

    // Position the glow window at the screen's trigger area
    NSRect targetWindowFrame = NSMakeRect(frame.origin.x, y_min, 48.0f, h);
    if (!NSEqualRects(_glowWindow.frame, targetWindowFrame)) {
        [_glowWindow setFrame:targetWindowFrame display:NO];
        [_glowView setFrame:NSMakeRect(0, 0, 48.0f, h)];
    }

    // Cursor Y position relative to trigger area (clamped so glow never renders outside bounds)
    CGFloat cursorYInView = mouseLocation.y - y_min;
    _targetCursorY = fmaxf(90.0f, fminf(cursorYInView, h - 90.0f));
    if (_currentCursorY == 0.0f) {
        _currentCursorY = _targetCursorY;
    } else {
        _currentCursorY += (_targetCursorY - _currentCursorY) * 0.45f;
    }
    _glowView.cursorYInView = _currentCursorY;

    // Calculate proximity opacity: 0 at 48 pt, 1.0 at 4 pt
    CGFloat proximity = (g_config.approach_range - fmaxf(dist, g_config.trigger_depth)) /
                        (g_config.approach_range - g_config.trigger_depth);
    proximity = fmaxf(0.0f, fminf(proximity, 1.0f));

    if (_dwellActive) {
        proximity = fminf(1.15f, proximity * 1.15f);
    }
    if (isItemDrag) {
        proximity = fminf(1.30f, proximity * 1.30f);
    }
    _targetOpacity = proximity;

    [self startFadeTimer];

    // Trigger depth reached
    if (dist <= g_config.trigger_depth) {
        if (isItemDrag) {
            // Immediate open on item drag!
            shelf_edge_log("shelf-open(item-drag)");
            [self triggerShelf];
            return;
        }

        if (!_isShelfOpen && !_dwellActive) {
            shelf_edge_log("dwell-start");
            [self startDwellTimer];
        }
    } else {
        if (_dwellActive) {
            shelf_edge_log("dwell-cancel");
            [self cancelDwellTimer];
        }
    }
}

- (void)startDwellTimer {
    [self cancelDwellTimer];
    _dwellActive = YES;

    dispatch_queue_t queue = dispatch_get_main_queue();
    _dwellTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    uint64_t nsec = (uint64_t)g_config.dwell_ms * NSEC_PER_MSEC;
    dispatch_source_set_timer(_dwellTimer, dispatch_time(DISPATCH_TIME_NOW, nsec), DISPATCH_TIME_FOREVER, 5 * NSEC_PER_MSEC);

    __weak ShelfEdgeController *weakSelf = self;
    dispatch_source_set_event_handler(_dwellTimer, ^{
        [weakSelf dwellTimerFired];
    });
    dispatch_resume(_dwellTimer);
}

- (void)cancelDwellTimer {
    if (_dwellTimer) {
        dispatch_source_cancel(_dwellTimer);
        _dwellTimer = nil;
    }
    _dwellActive = NO;
}

- (void)dwellTimerFired {
    [self cancelDwellTimer];
    shelf_edge_log("shelf-open");
    [self triggerShelf];
}

- (void)triggerShelf {
    [self cancelDwellTimer];
    [self fadeGlowOut];
    _shelfHoveredOnce = YES;
    if (self.onTrigger) {
        self.onTrigger();
    }
}

- (void)startShelfLeaveTimer {
    if (_shelfLeaveTimer) return;

    dispatch_queue_t queue = dispatch_get_main_queue();
    _shelfLeaveTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    uint64_t nsec = 400 * NSEC_PER_MSEC;
    dispatch_source_set_timer(_shelfLeaveTimer, dispatch_time(DISPATCH_TIME_NOW, nsec), DISPATCH_TIME_FOREVER, 10 * NSEC_PER_MSEC);

    __weak ShelfEdgeController *weakSelf = self;
    dispatch_source_set_event_handler(_shelfLeaveTimer, ^{
        [weakSelf shelfLeaveTimerFired];
    });
    dispatch_resume(_shelfLeaveTimer);
}

- (void)cancelShelfLeaveTimer {
    if (_shelfLeaveTimer) {
        dispatch_source_cancel(_shelfLeaveTimer);
        _shelfLeaveTimer = nil;
    }
}

- (void)shelfLeaveTimerFired {
    [self cancelShelfLeaveTimer];
    if (!_isShelfOpen) return;

    shelf_edge_log("shelf-auto-hide(mouse-leave)");
    if (self.onClose) {
        self.onClose();
    }
}

- (void)startFadeTimer {
    if (_fadeTimer) return;

    dispatch_queue_t queue = dispatch_get_main_queue();
    _fadeTimer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);
    // 60 fps step interval ~ 16ms
    dispatch_source_set_timer(_fadeTimer, dispatch_time(DISPATCH_TIME_NOW, 0), 16 * NSEC_PER_MSEC, 2 * NSEC_PER_MSEC);

    __weak ShelfEdgeController *weakSelf = self;
    dispatch_source_set_event_handler(_fadeTimer, ^{
        [weakSelf stepFade];
    });
    dispatch_resume(_fadeTimer);
}

- (void)stopFadeTimer {
    if (_fadeTimer) {
        dispatch_source_cancel(_fadeTimer);
        _fadeTimer = nil;
    }
}

- (void)stepFade {
    CGFloat delta = _targetOpacity - _currentOpacity;
    CGFloat rate = (_targetOpacity > _currentOpacity) ? (16.0f / (CGFloat)g_config.glow_fade_in_ms)
                                                     : (16.0f / (CGFloat)g_config.glow_fade_out_ms);

    if (fabs(delta) < 0.015f) {
        _currentOpacity = _targetOpacity;
    } else {
        _currentOpacity += delta * rate * 3.0f;
    }

    _glowView.glowOpacity = _currentOpacity;

    if (_currentOpacity > 0.005f) {
        if (![_glowWindow isVisible]) {
            [_glowWindow orderFrontRegardless];
        }
        [_glowView setNeedsDisplay:YES];
    } else {
        _currentOpacity = 0.0f;
        _glowView.glowOpacity = 0.0f;
        [_glowWindow orderOut:nil];
        [self stopFadeTimer];
    }
}

- (void)fadeGlowOut {
    _targetOpacity = 0.0f;
    if (_currentOpacity > 0.0f) {
        [self startFadeTimer];
    } else {
        [self hideGlowImmediately];
    }
}

- (void)hideGlowImmediately {
    _targetOpacity = 0.0f;
    _currentOpacity = 0.0f;
    [self stopFadeTimer];
    if (_glowView) {
        _glowView.glowOpacity = 0.0f;
    }
    if (_glowWindow) {
        [_glowWindow orderOut:nil];
    }
}

@end

// ---------------------------------------------------------------------------
// C API Export implementations
// ---------------------------------------------------------------------------
void shelf_edge_init(ShelfTriggerCallback on_trigger) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!s_instance) {
            s_instance = [[ShelfEdgeController alloc] init];
        }
        s_instance.onTrigger = on_trigger;
        [s_instance start];
    });
}

void shelf_edge_set_close_callback(ShelfCloseCallback on_close) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (s_instance) {
            s_instance.onClose = on_close;
        }
    });
}

void shelf_edge_set_enabled(bool enabled) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (s_instance) {
            s_instance.enabled = enabled;
            if (enabled) {
                [s_instance start];
            } else {
                [s_instance stop];
            }
        }
    });
}

void shelf_edge_set_ratio(float ratio) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (s_instance) {
            [s_instance setRatio:ratio];
        }
    });
}

void shelf_edge_set_shelf_open(bool is_open) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (s_instance) {
            [s_instance updateOpenState:is_open];
        }
    });
}

void shelf_edge_style_shelf_window(const char *window_title) {
    if (!window_title) return;
    NSString *title = [NSString stringWithUTF8String:window_title];
    dispatch_async(dispatch_get_main_queue(), ^{
        for (NSWindow *win in [NSApp windows]) {
            if ([win.title isEqualToString:title]) {
                s_shelfWindow = win;
                [win setCollectionBehavior:(NSWindowCollectionBehaviorCanJoinAllSpaces |
                                            NSWindowCollectionBehaviorFullScreenAuxiliary |
                                            NSWindowCollectionBehaviorStationary)];
                [win setLevel:NSFloatingWindowLevel];
                [win setHidesOnDeactivate:NO];
                break;
            }
        }
    });
}

void shelf_edge_cleanup(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (s_instance) {
            [s_instance stop];
            s_instance = nil;
        }
    });
}
