// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import <IOBluetooth/IOBluetooth.h>
#include "mac_hfp.h"

@interface MacLinkHfpController : NSObject <IOBluetoothHandsFreeDeviceDelegate>
@property (nonatomic, strong) IOBluetoothHandsFreeDevice *hfDevice;
@property (nonatomic, strong) IOBluetoothDevice *targetDevice;
@property (nonatomic, strong) IOBluetoothSDPServiceRecord *sdpRecord;
@property (nonatomic, assign) BOOL isConnected;
@property (nonatomic, assign) BOOL isScoActive;
@property (nonatomic, assign) BOOL isCallActive;
@property (nonatomic, assign) BOOL isSdpPublished;
+ (instancetype)shared;
- (BOOL)publishSdp:(uint8_t)rfcommChannel;
- (void)unpublishSdp;
- (BOOL)connectAddress:(NSString *)address;
- (void)disconnect;
- (void)acceptCall;
- (void)endCall;
- (BOOL)dialNumber:(NSString *)number;
- (void)routeAudioToMac;
- (void)routeAudioToPhone;
@end

@implementation MacLinkHfpController

+ (instancetype)shared {
    static MacLinkHfpController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MacLinkHfpController alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    return self;
}

- (BOOL)publishSdp:(uint8_t)rfcommChannel {
    if (self.isSdpPublished) return YES;

    NSDictionary *sdpDict = @{
        @"0001 - ServiceClassIDList": @[
            [NSData dataWithBytes:(const uint8_t[]){0x11, 0x1E} length:2],
            [NSData dataWithBytes:(const uint8_t[]){0x12, 0x03} length:2],
        ],
        @"0004 - ProtocolDescriptorList": @[
            @[ [NSData dataWithBytes:(const uint8_t[]){0x01, 0x00} length:2] ],
            @[ [NSData dataWithBytes:(const uint8_t[]){0x00, 0x03} length:2], @(rfcommChannel) ],
        ],
        @"0009 - BluetoothProfileDescriptorList": @[
            @[ [NSData dataWithBytes:(const uint8_t[]){0x11, 0x1E} length:2], @(0x0107) ],
        ],
        @"0100 - ServiceName": @"MacLink Hands-Free Audio",
        @"0311 - SupportedFeatures": @(0x00A0),
        @"LocalAttributes": @{
            @"Persistent": @NO,
        },
    };

    IOBluetoothSDPServiceRecord *rec = [IOBluetoothSDPServiceRecord publishedServiceRecordWithDictionary:sdpDict];
    if (rec) {
        self.sdpRecord = rec;
        self.isSdpPublished = YES;
        return YES;
    }
    return NO;
}

- (void)unpublishSdp {
    if (self.sdpRecord) {
        [self.sdpRecord removeServiceRecord];
        self.sdpRecord = nil;
    }
    self.isSdpPublished = NO;
}

- (BOOL)connectAddress:(NSString *)address {
    NSString *normalized = [[address stringByReplacingOccurrencesOfString:@":" withString:@"-"] lowercaseString];
    IOBluetoothDevice *device = [IOBluetoothDevice deviceWithAddressString:normalized];
    if (!device) return NO;

    [self disconnect];
    self.targetDevice = device;

    uint32_t features =
        IOBluetoothHandsFreeDeviceFeatureECAndOrNRFunction |
        IOBluetoothHandsFreeDeviceFeatureThreeWayCalling |
        IOBluetoothHandsFreeDeviceFeatureCLIPresentation |
        IOBluetoothHandsFreeDeviceFeatureRemoteVolumeControl |
        IOBluetoothHandsFreeDeviceFeatureEnhancedCallStatus |
        IOBluetoothHandsFreeDeviceFeatureCodecNegotiation;

    IOBluetoothHandsFreeDevice *hf = [[IOBluetoothHandsFreeDevice alloc] initWithDevice:device delegate:self];
    if (!hf) return NO;

    hf.supportedFeatures = features;
    self.hfDevice = hf;
    [hf connect];
    return YES;
}

- (void)disconnect {
    if (self.hfDevice) {
        if ([self.hfDevice isSCOConnected]) {
            [self.hfDevice disconnectSCO];
        }
        if ([self.hfDevice isConnected]) {
            [self.hfDevice disconnect];
        }
    }
    self.hfDevice = nil;
    self.targetDevice = nil;
    self.isConnected = NO;
    self.isScoActive = NO;
    self.isCallActive = NO;
}

- (void)acceptCall {
    if (self.hfDevice && self.isConnected) {
        [self.hfDevice acceptCall];
        [self routeAudioToMac];
    }
}

- (void)endCall {
    if (self.hfDevice && self.isConnected) {
        [self.hfDevice endCall];
        [self routeAudioToPhone];
    }
}

- (BOOL)dialNumber:(NSString *)number {
    if (!self.hfDevice || !self.isConnected) return NO;
    NSString *clean = [number stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (clean.length == 0) return NO;
    [self.hfDevice dialNumber:clean];
    [self routeAudioToMac];
    return YES;
}

- (void)routeAudioToMac {
    if (self.hfDevice && self.isConnected) {
        if (![self.hfDevice isSCOConnected]) {
            [self.hfDevice connectSCO];
        }
        [self.hfDevice transferAudioToComputer];
    }
}

- (void)routeAudioToPhone {
    if (self.hfDevice && self.isConnected) {
        [self.hfDevice transferAudioToPhone];
        if ([self.hfDevice isSCOConnected]) {
            [self.hfDevice disconnectSCO];
        }
    }
}

// IOBluetoothHandsFreeDelegate
- (void)handsFree:(IOBluetoothHandsFree *)device isConnected:(NSNumber *)status {
    self.isConnected = (status && [status intValue] == kIOReturnSuccess);
}

- (void)handsFree:(IOBluetoothHandsFree *)device disconnected:(NSNumber *)status {
    self.isConnected = NO;
    self.isScoActive = NO;
    self.isCallActive = NO;
}

- (void)handsFree:(IOBluetoothHandsFree *)device scoConnectionOpened:(NSNumber *)status {
    self.isScoActive = (status && [status intValue] == kIOReturnSuccess);
}

- (void)handsFree:(IOBluetoothHandsFree *)device scoConnectionClosed:(NSNumber *)status {
    self.isScoActive = NO;
}

// IOBluetoothHandsFreeDeviceDelegate
- (void)handsFree:(IOBluetoothHandsFreeDevice *)device isCallActive:(NSNumber *)isCallActive {
    self.isCallActive = (isCallActive && [isCallActive intValue] != 0);
}

- (void)handsFree:(IOBluetoothHandsFreeDevice *)device callSetupMode:(NSNumber *)callSetupMode {
    int mode = callSetupMode ? [callSetupMode intValue] : 0;
    if (mode != 0) {
        self.isCallActive = YES;
    }
}

@end

extern "C" {

bool maclink_calls_hfp_publish_sdp(uint8_t rfcomm_channel) {
    return [[MacLinkHfpController shared] publishSdp:rfcomm_channel];
}

void maclink_calls_hfp_unpublish_sdp() {
    [[MacLinkHfpController shared] unpublishSdp];
}

bool maclink_calls_hfp_connect(const char* device_address) {
    if (!device_address) return false;
    NSString *addr = [NSString stringWithUTF8String:device_address];
    return [[MacLinkHfpController shared] connectAddress:addr];
}

void maclink_calls_hfp_disconnect() {
    [[MacLinkHfpController shared] disconnect];
}

bool maclink_calls_hfp_is_connected() {
    return [MacLinkHfpController shared].isConnected;
}

bool maclink_calls_hfp_is_sco_active() {
    return [MacLinkHfpController shared].isScoActive;
}

void maclink_calls_hfp_route_audio(bool to_mac) {
    if (to_mac) {
        [[MacLinkHfpController shared] routeAudioToMac];
    } else {
        [[MacLinkHfpController shared] routeAudioToPhone];
    }
}

void maclink_calls_hfp_accept() {
    [[MacLinkHfpController shared] acceptCall];
}

void maclink_calls_hfp_end() {
    [[MacLinkHfpController shared] endCall];
}

bool maclink_calls_hfp_dial(const char* number) {
    if (!number) return false;
    NSString *num = [NSString stringWithUTF8String:number];
    return [[MacLinkHfpController shared] dialNumber:num];
}

}

