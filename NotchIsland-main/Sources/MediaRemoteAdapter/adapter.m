// MediaRemote adapter: the system-wide Now Playing feed (TV, Music, Podcasts, QuickTime Player,
// browsers, anything that publishes to Control Center) for NotchIsland.
//
// Since macOS 15.4 MediaRemote answers only Apple's own processes. /usr/bin/perl is one, and its
// DynaLoader can load any dylib and call a function shaped like a perl XSUB. NotchIsland therefore
// runs `perl -e '<tiny loader>' <this dylib> stream`, and this code, inside perl, asks MediaRemote
// and writes one JSON object per line to stdout: every app that publishes something ("clients"),
// each with its own item and state. `command` sends a transport command to the elected app.
//
// Nothing here links MediaRemote at build time; every symbol is resolved with dlsym so the app
// still builds and runs where the framework changes. Where the per-app calls are missing the feed
// falls back to the one app macOS has elected as "now playing".
//
// Queues matter here. MediaRemote posts its notifications on the queue it is registered with and
// Foundation delivers a block observer bound to an NSOperationQueue synchronously, waiting for the
// block to finish. Running everything on one queue therefore deadlocks at the first notification
// (the 1.3.0/1.3.1 feed went silent that way). So: notifications land on `notifyQueue` and are
// only forwarded from there; the work (heartbeat, fetching, writing) runs on `emitQueue`;
// MediaRemote's replies arrive on `replyQueue`; and a watchdog on its own queue ends the process
// if nothing has been written for a while, which lets NotchIsland start a fresh one.

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetBoolFn)(dispatch_queue_t, void (^)(Boolean));
typedef void (*MRGetIntFn)(dispatch_queue_t, void (^)(int));
typedef void (*MRGetClientFn)(dispatch_queue_t, void (^)(id));
typedef void (*MRGetClientsFn)(dispatch_queue_t, void (^)(CFArrayRef));
typedef id (*MRGetOriginFn)(void);
typedef void (*MRGetInfoForClientFn)(id client, id origin, int withArtwork, dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetStateForClientFn)(id client, id origin, dispatch_queue_t, void (^)(unsigned int));
typedef CFStringRef (*MRClientStringFn)(id);
typedef int (*MRClientIntFn)(id);
typedef Boolean (*MRSendCommandFn)(int, CFDictionaryRef);
typedef void (*MRSetElapsedFn)(double);
typedef void (*MRRegisterFn)(dispatch_queue_t);

enum { kCommandPlay = 0, kCommandPause = 1, kCommandToggle = 2, kCommandStop = 3, kCommandNext = 4,
       kCommandPrevious = 5, kCommandSeekToPosition = 24 };   // MRMediaRemoteCopyCommandDescription

static void *mr = NULL;
static MRGetInfoFn getInfo;
static MRGetBoolFn getIsPlaying;
static MRGetIntFn getPID;
static MRGetClientFn getClient;
static MRGetClientsFn getClients;
static MRGetOriginFn localOrigin;
static MRGetInfoForClientFn infoForClient;
static MRGetStateForClientFn stateForClient;
static MRClientStringFn clientBundle, clientParent, clientName;
static MRClientIntFn clientPID;
static MRSendCommandFn sendCommand;
static MRSetElapsedFn setElapsed;
static MRRegisterFn registerNotifications;
static CFStringRef optionPlaybackPosition;
static BOOL perClient;   // the per-app calls are all there

static dispatch_queue_t emitQueue, replyQueue, notifyQueue, watchdogQueue;
static NSMutableDictionary<NSString *, NSString *> *lastArtworkKeys;   // bundle id → artwork key last written
static NSMutableArray *observers;
static BOOL fetchScheduled = NO;
static dispatch_source_t heartbeat, watchdog;   // globals: under ARC a local would be released, and with it the timer
static double lastWriteAt = 0;
static const double kTimeout = 1.5;             // per MediaRemote reply
static const double kHeartbeat = 2;
static const double kSilenceLimit = 12;         // the watchdog's patience

static NSString *str(CFStringRef s) { return s ? [(__bridge NSString *)s copy] : nil; }

static BOOL load(void) {
    if (mr) return YES;
    mr = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_NOW);
    if (!mr) { fprintf(stderr, "adapter: dlopen MediaRemote failed: %s\n", dlerror()); return NO; }
    getInfo = dlsym(mr, "MRMediaRemoteGetNowPlayingInfo");
    getIsPlaying = dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    getPID = dlsym(mr, "MRMediaRemoteGetNowPlayingApplicationPID");
    getClient = dlsym(mr, "MRMediaRemoteGetNowPlayingClient");
    getClients = dlsym(mr, "MRMediaRemoteGetNowPlayingClients");
    localOrigin = dlsym(mr, "MRMediaRemoteGetLocalOrigin");
    infoForClient = dlsym(mr, "MRMediaRemoteGetNowPlayingInfoForClient");
    stateForClient = dlsym(mr, "MRMediaRemoteGetPlaybackStateForClient");
    clientBundle = dlsym(mr, "MRNowPlayingClientGetBundleIdentifier");
    clientParent = dlsym(mr, "MRNowPlayingClientGetParentAppBundleIdentifier");
    clientName = dlsym(mr, "MRNowPlayingClientGetDisplayName");
    clientPID = dlsym(mr, "MRNowPlayingClientGetProcessIdentifier");
    sendCommand = dlsym(mr, "MRMediaRemoteSendCommand");
    setElapsed = dlsym(mr, "MRMediaRemoteSetElapsedTime");
    registerNotifications = dlsym(mr, "MRMediaRemoteRegisterForNowPlayingNotifications");
    CFStringRef *key = dlsym(mr, "kMRMediaRemoteOptionPlaybackPosition");
    optionPlaybackPosition = key ? *key : CFSTR("kMRMediaRemoteOptionPlaybackPosition");
    if (!getInfo || !getIsPlaying || !getPID) { fprintf(stderr, "adapter: MediaRemote symbols missing\n"); return NO; }
    perClient = getClients && localOrigin && infoForClient && stateForClient && clientBundle;
    emitQueue = dispatch_queue_create("notchisland.mra.emit", DISPATCH_QUEUE_SERIAL);
    replyQueue = dispatch_queue_create("notchisland.mra.reply", DISPATCH_QUEUE_SERIAL);
    notifyQueue = dispatch_queue_create("notchisland.mra.notify", DISPATCH_QUEUE_SERIAL);
    watchdogQueue = dispatch_queue_create("notchisland.mra.watchdog", DISPATCH_QUEUE_SERIAL);
    lastArtworkKeys = [NSMutableDictionary dictionary];
    observers = [NSMutableArray array];
    return YES;
}

/// One asynchronous MediaRemote reply, waited for with a deadline. A reply that arrives after the
/// deadline is dropped rather than written into a value someone has moved on from.
@interface Reply : NSObject
@property (nonatomic, strong, readonly) id value;
- (void)deliver:(id)value;
- (BOOL)wait;
@end

@implementation Reply {
    dispatch_semaphore_t _done;
    NSLock *_lock;
    BOOL _closed, _arrived;
    id _value;
}
- (instancetype)init {
    if ((self = [super init])) { _done = dispatch_semaphore_create(0); _lock = [NSLock new]; }
    return self;
}
- (id)value { [_lock lock]; id v = _value; [_lock unlock]; return v; }
- (void)deliver:(id)value {
    [_lock lock];
    if (!_closed) { _value = value; _arrived = YES; }
    [_lock unlock];
    dispatch_semaphore_signal(_done);
}
- (BOOL)wait {
    dispatch_semaphore_wait(_done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTimeout * NSEC_PER_SEC)));
    [_lock lock];
    _closed = YES;
    BOOL ok = _arrived;
    [_lock unlock];
    return ok;
}
@end

static id value(NSDictionary *info, NSString *key) {
    id v = info[key];
    return (v == nil || v == [NSNull null]) ? nil : v;
}

/// The item fields of one Now Playing info dictionary. `withArtwork` adds the image (base64) when
/// it differs from the one last written for this app; the reader caches it by `artworkKey`.
static NSMutableDictionary *describe(NSDictionary *info, NSString *bundle, BOOL withArtwork) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    NSString *title = value(info, @"kMRMediaRemoteNowPlayingInfoTitle");
    if (title) out[@"title"] = title;
    NSString *artist = value(info, @"kMRMediaRemoteNowPlayingInfoArtist");
    if (artist) out[@"artist"] = artist;
    NSString *album = value(info, @"kMRMediaRemoteNowPlayingInfoAlbum");
    if (album) out[@"album"] = album;
    NSNumber *duration = value(info, @"kMRMediaRemoteNowPlayingInfoDuration");
    if (duration) out[@"duration"] = duration;
    NSNumber *elapsed = value(info, @"kMRMediaRemoteNowPlayingInfoElapsedTime");
    if (elapsed) out[@"elapsed"] = elapsed;
    NSNumber *rate = value(info, @"kMRMediaRemoteNowPlayingInfoPlaybackRate");
    if (rate) out[@"rate"] = rate;
    NSDate *stamp = value(info, @"kMRMediaRemoteNowPlayingInfoTimestamp");
    if ([stamp isKindOfClass:[NSDate class]]) out[@"timestamp"] = @([stamp timeIntervalSince1970]);
    NSString *mediaType = value(info, @"kMRMediaRemoteNowPlayingInfoMediaType");
    if (mediaType) out[@"mediaType"] = mediaType;
    id item = value(info, @"kMRMediaRemoteNowPlayingInfoContentItemIdentifier")
                  ?: value(info, @"kMRMediaRemoteNowPlayingInfoUniqueIdentifier");
    if ([item isKindOfClass:[NSNumber class]]) item = [item stringValue];
    if ([item isKindOfClass:[NSString class]]) out[@"id"] = item;

    NSString *slot = bundle ?: @"";
    NSData *art = value(info, @"kMRMediaRemoteNowPlayingInfoArtworkData");
    NSString *artKey = value(info, @"kMRMediaRemoteNowPlayingInfoArtworkIdentifier");
    if (![artKey isKindOfClass:[NSString class]]) artKey = nil;
    if ([art isKindOfClass:[NSData class]] && art.length > 0) {
        if (!artKey) artKey = [NSString stringWithFormat:@"%@|%lu", item ?: title ?: @"", (unsigned long)art.length];
        artKey = [slot stringByAppendingFormat:@"|%@", artKey];   // one app's key never names another's image
        out[@"artworkKey"] = artKey;
        if (withArtwork && ![artKey isEqualToString:lastArtworkKeys[slot]]) {
            out[@"artwork"] = [art base64EncodedStringWithOptions:0];
            NSString *mime = value(info, @"kMRMediaRemoteNowPlayingInfoArtworkMIMEType");
            if (mime) out[@"artworkMIME"] = mime;
            lastArtworkKeys[slot] = artKey;
        }
    } else {
        [lastArtworkKeys removeObjectForKey:slot];
    }
    return out;
}

/// The bundle id of the app macOS has elected as "now playing", if any.
static NSString *electedBundle(void) {
    if (!getClient || !clientBundle) return nil;
    Reply *reply = [Reply new];
    getClient(replyQueue, ^(id client) { [reply deliver:client ? str(clientBundle(client)) : nil]; });
    [reply wait];
    return reply.value;
}

/// The elected app alone, the way macOS 15.3 and earlier are read.
static NSDictionary *electedEntry(BOOL withArtwork) {
    Reply *info = [Reply new], *playing = [Reply new], *pid = [Reply new];
    getInfo(replyQueue, ^(CFDictionaryRef d) { [info deliver:d ? [(__bridge NSDictionary *)d copy] : @{}]; });
    getIsPlaying(replyQueue, ^(Boolean p) { [playing deliver:@(p)]; });
    getPID(replyQueue, ^(int p) { [pid deliver:@(p)]; });
    [info wait]; [playing wait]; [pid wait];
    NSString *bundle = electedBundle();
    NSMutableDictionary *entry = describe(info.value, bundle, withArtwork);
    if (bundle) entry[@"bundle"] = bundle;
    entry[@"pid"] = pid.value ?: @0;
    entry[@"playing"] = playing.value ?: @NO;
    return entry;
}

/// Every app that publishes an item, each with its own state, the elected app first.
static NSArray *clientEntries(BOOL withArtwork, NSString *elected) {
    Reply *list = [Reply new];
    getClients(replyQueue, ^(CFArrayRef a) { [list deliver:a ? [(__bridge NSArray *)a copy] : @[]]; });
    [list wait];
    NSArray *clients = list.value ?: @[];
    id origin = localOrigin();
    NSMutableArray<Reply *> *states = [NSMutableArray array], *infos = [NSMutableArray array];
    for (id client in clients) {   // ask for everything first, then wait: one deadline covers them all
        Reply *state = [Reply new], *info = [Reply new];
        stateForClient(client, origin, replyQueue, ^(unsigned int s) { [state deliver:@(s)]; });
        infoForClient(client, origin, withArtwork ? 1 : 0, replyQueue, ^(CFDictionaryRef d) { [info deliver:d ? [(__bridge NSDictionary *)d copy] : @{}]; });
        [states addObject:state];
        [infos addObject:info];
    }
    NSMutableArray *entries = [NSMutableArray array];
    for (NSUInteger i = 0; i < clients.count; i++) {
        id client = clients[i];
        [states[i] wait];
        [infos[i] wait];
        NSString *bundle = str(clientBundle(client)) ?: (clientParent ? str(clientParent(client)) : nil);
        if (!bundle) continue;
        NSMutableDictionary *entry = describe(infos[i].value, bundle, withArtwork);
        entry[@"bundle"] = bundle;
        if (clientPID) entry[@"pid"] = @(clientPID(client));
        NSString *name = clientName ? str(clientName(client)) : nil;
        if (name) entry[@"name"] = name;
        NSString *parent = clientParent ? str(clientParent(client)) : nil;
        if (parent && ![parent isEqualToString:bundle]) entry[@"parent"] = parent;
        // MRPlaybackState: 1 playing, 2 paused, 3 stopped, 4 interrupted; nothing back → go by the rate.
        NSNumber *state = states[i].value;
        if (state) entry[@"state"] = state;
        BOOL playing = state ? state.unsignedIntValue == 1 : [entry[@"rate"] doubleValue] > 0;
        entry[@"playing"] = @(playing);
        if (elected && [bundle isEqualToString:elected]) [entries insertObject:entry atIndex:0];
        else [entries addObject:entry];
    }
    return entries;
}

/// One JSON object: the time, the elected app, and one entry per app that publishes an item.
static NSDictionary *feedSnapshot(BOOL withArtwork) {
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    out[@"ts"] = @([[NSDate date] timeIntervalSince1970]);
    NSString *elected = electedBundle();
    if (elected) out[@"elected"] = elected;
    out[@"clients"] = perClient ? clientEntries(withArtwork, elected) : @[electedEntry(withArtwork)];
    return out;
}

/// The reader is NotchIsland. When it is gone (quit, crashed, or replaced by an update through
/// `launchctl kickstart -k`, which gives no chance to tidy up) this process is reparented to launchd
/// and must not linger: it would keep MediaRemote busy and pile up once per relaunch.
static void exitIfOrphaned(void) {
    if (getppid() == 1) _exit(0);
}

static void writeLine(NSDictionary *object) {
    exitIfOrphaned();
    NSData *json = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    if (!json) return;
    if (fwrite(json.bytes, 1, json.length, stdout) != json.length) _exit(0);   // reader gone
    fputc('\n', stdout);
    if (fflush(stdout) != 0) _exit(0);
    lastWriteAt = [[NSDate date] timeIntervalSince1970];
}

/// Runs on `emitQueue`.
static void emit(void) {
    static int lines = 0;
    // Test aid: NOTCHISLAND_MRA_TEST_STALL=<n> wedges the feed after n lines, as a deadlock would,
    // to show the watchdog ending it.
    const char *stall = getenv("NOTCHISLAND_MRA_TEST_STALL");
    if (stall && ++lines > atoi(stall)) { fprintf(stderr, "adapter: test stall\n"); for (;;) pause(); }
    @autoreleasepool { writeLine(feedSnapshot(YES)); }
}

/// Notifications arrive in bursts; one fetch a little later covers them all. Runs on `emitQueue`.
static void scheduleEmit(void) {
    if (fetchScheduled) return;
    fetchScheduled = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), emitQueue, ^{
        fetchScheduled = NO;
        emit();
    });
}

/// `stream`: a line now, a line on every change, and a heartbeat line every two seconds, until
/// the reader goes away, the watchdog gives up, or the process is killed.
void notchisland_mra_stream(void *interp, void *cv) {
    @autoreleasepool {
        if (!load()) exit(2);
        if (registerNotifications) registerNotifications(notifyQueue);
        NSArray *names = @[@"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
                           @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
                           @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
                           @"kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification",
                           @"kMRMediaRemoteNowPlayingApplicationPlaybackStateDidChangeNotification",
                           @"kMRMediaRemoteNowPlayingApplicationClientStateDidChange"];
        for (NSString *name in names) {
            // queue:nil → the block runs where the notification is posted and returns at once;
            // nothing here ever waits for another queue.
            id token = [[NSNotificationCenter defaultCenter] addObserverForName:name object:nil queue:nil
                                                                     usingBlock:^(NSNotification *n) { dispatch_async(emitQueue, ^{ scheduleEmit(); }); }];
            [observers addObject:token];
        }
        lastWriteAt = [[NSDate date] timeIntervalSince1970];
        dispatch_async(emitQueue, ^{ emit(); });

        heartbeat = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, emitQueue);
        dispatch_source_set_timer(heartbeat, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kHeartbeat * NSEC_PER_SEC)),
                                  (uint64_t)(kHeartbeat * NSEC_PER_SEC), (uint64_t)(0.2 * NSEC_PER_SEC));
        dispatch_source_set_event_handler(heartbeat, ^{ emit(); });
        dispatch_resume(heartbeat);

        // Independent of everything above: if the feed stops writing, end it; NotchIsland starts
        // a fresh one. Also the place the orphan check runs when nothing else does.
        watchdog = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, watchdogQueue);
        dispatch_source_set_timer(watchdog, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), NSEC_PER_SEC, (uint64_t)(0.2 * NSEC_PER_SEC));
        dispatch_source_set_event_handler(watchdog, ^{
            exitIfOrphaned();
            double silent = [[NSDate date] timeIntervalSince1970] - lastWriteAt;
            if (silent > kSilenceLimit) {
                fprintf(stderr, "adapter: nothing written for %.0f s, ending for a restart\n", silent);
                _exit(3);
            }
        });
        dispatch_resume(watchdog);
    }
    dispatch_main();   // parks the main thread; never returns
}

/// `get`: one line and out.
void notchisland_mra_get(void *interp, void *cv) {
    if (!load()) exit(2);
    emit();
}

/// `command`: NOTCHISLAND_MRA_COMMAND = play | pause | toggle | stop | next | previous | seek:<seconds>.
/// NOTCHISLAND_MRA_BUNDLE names the app it is for. mediaremoted delivers a command from a process
/// without Apple's entitlement to the elected app whatever player path it names (verified: a path
/// built for another client, with its player resolved, still lands on the elected app, and
/// electing another client is silently ignored), so a command for any other app is refused here,
/// exit 1, rather than sent to the wrong one. NotchIsland then scripts that app directly if it can.
void notchisland_mra_command(void *interp, void *cv) {
    @autoreleasepool {
        if (!load() || !sendCommand) exit(2);
        const char *raw = getenv("NOTCHISLAND_MRA_COMMAND");
        const char *rawBundle = getenv("NOTCHISLAND_MRA_BUNDLE");
        NSString *command = raw ? [NSString stringWithUTF8String:raw] : @"";
        NSString *bundle = rawBundle && *rawBundle ? [NSString stringWithUTF8String:rawBundle] : nil;
        int code = -1;
        double position = 0;
        if ([command isEqualToString:@"play"]) code = kCommandPlay;
        else if ([command isEqualToString:@"pause"]) code = kCommandPause;
        else if ([command isEqualToString:@"toggle"]) code = kCommandToggle;
        else if ([command isEqualToString:@"stop"]) code = kCommandStop;
        else if ([command isEqualToString:@"next"]) code = kCommandNext;
        else if ([command isEqualToString:@"previous"]) code = kCommandPrevious;
        else if ([command hasPrefix:@"seek:"]) { code = kCommandSeekToPosition; position = [[command substringFromIndex:5] doubleValue]; }
        if (code < 0) { fprintf(stderr, "adapter: unknown command %s\n", raw ? raw : "(none)"); exit(64); }

        if (bundle) {
            NSString *elected = electedBundle();
            if (![elected isEqualToString:bundle]) {
                fprintf(stderr, "adapter: %s: %s is not the elected app (%s), not sent\n", raw, rawBundle, elected ? elected.UTF8String : "none");
                exit(1);
            }
        }
        if (code == kCommandSeekToPosition) {
            if (!setElapsed) exit(2);
            setElapsed(position);
            [NSThread sleepForTimeInterval:0.15];   // let the XPC message leave before the process ends
            return;
        }
        Boolean ok = sendCommand(code, NULL);
        [NSThread sleepForTimeInterval:0.15];
        if (!ok) exit(1);
    }
}
