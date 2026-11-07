// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>

#include "mac_videotoolbox.h"
#include <vector>
#include <string>
#include <cstring>
#include <arpa/inet.h>

namespace {

struct FrameContext {
    mac_vtd_frame_callback callback;
    void *user_ctx;
    std::vector<uint8_t> row_buffer;
};

void decompressionCallback(
    void *decompressionOutputRefCon,
    void *,
    OSStatus status,
    VTDecodeInfoFlags,
    CVImageBufferRef imageBuffer,
    CMTime,
    CMTime)
{
    if (status != noErr || !imageBuffer) {
        return;
    }

    FrameContext *ctx = static_cast<FrameContext *>(decompressionOutputRefCon);
    if (!ctx || !ctx->callback) {
        return;
    }

    if (CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) {
        return;
    }

    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    const uint8_t *base = static_cast<const uint8_t *>(CVPixelBufferGetBaseAddress(imageBuffer));

    if (base && width > 0 && height > 0) {
        if (bytesPerRow == width * 4) {
            ctx->callback(ctx->user_ctx, (uint32_t)width, (uint32_t)height, base, width * height * 4);
        } else {
            size_t needed = width * height * 4;
            if (ctx->row_buffer.size() < needed) {
                ctx->row_buffer.resize(needed);
            }
            uint8_t *dst = ctx->row_buffer.data();
            for (size_t y = 0; y < height; ++y) {
                memcpy(dst + y * width * 4, base + y * bytesPerRow, width * 4);
            }
            ctx->callback(ctx->user_ctx, (uint32_t)width, (uint32_t)height, dst, needed);
        }
    }

    CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
}

struct NalUnit {
    const uint8_t *data;
    size_t size;
    uint8_t type;
};

std::vector<NalUnit> extractNalUnits(const uint8_t *data, size_t len)
{
    std::vector<NalUnit> nals;
    if (!data || len < 4) return nals;

    std::vector<size_t> startPositions;
    for (size_t i = 0; i + 3 <= len; ++i) {
        if (data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 1) {
            startPositions.push_back(i);
            i += 2;
        } else if (i + 4 <= len && data[i] == 0 && data[i + 1] == 0 && data[i + 2] == 0 && data[i + 3] == 1) {
            startPositions.push_back(i);
            i += 3;
        }
    }

    for (size_t k = 0; k < startPositions.size(); ++k) {
        size_t start = startPositions[k];
        size_t prefixLen = (data[start + 2] == 1) ? 3 : 4;
        size_t nalStart = start + prefixLen;
        size_t nalEnd = (k + 1 < startPositions.size()) ? startPositions[k + 1] : len;
        if (nalEnd > nalStart) {
            size_t size = nalEnd - nalStart;
            uint8_t type = data[nalStart] & 0x1F;
            nals.push_back(NalUnit{ data + nalStart, size, type });
        }
    }
    return nals;
}

} // namespace

struct MacVtDecoderImpl {
    std::string codec;
    VTDecompressionSessionRef session = nullptr;
    CMVideoFormatDescriptionRef formatDesc = nullptr;
    std::vector<uint8_t> sps;
    std::vector<uint8_t> pps;
    FrameContext frameCtx;

    ~MacVtDecoderImpl() {
        teardown();
    }

    void teardown() {
        if (session) {
            VTDecompressionSessionInvalidate(session);
            CFRelease(session);
            session = nullptr;
        }
        if (formatDesc) {
            CFRelease(formatDesc);
            formatDesc = nullptr;
        }
    }

    bool initSession(const uint8_t *spsData, size_t spsLen, const uint8_t *ppsData, size_t ppsLen) {
        if (sps.size() == spsLen && pps.size() == ppsLen &&
            memcmp(sps.data(), spsData, spsLen) == 0 &&
            memcmp(pps.data(), ppsData, ppsLen) == 0 && session) {
            return true;
        }

        teardown();

        sps.assign(spsData, spsData + spsLen);
        pps.assign(ppsData, ppsData + ppsLen);

        const uint8_t *paramPointers[2] = { sps.data(), pps.data() };
        const size_t paramSizes[2] = { sps.size(), pps.size() };

        OSStatus st = CMVideoFormatDescriptionCreateFromH264ParameterSets(
            kCFAllocatorDefault,
            2,
            paramPointers,
            paramSizes,
            4,
            &formatDesc
        );

        if (st != noErr || !formatDesc) {
            return false;
        }

        NSDictionary *destAttrs = @{
            (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
            (id)kCVPixelBufferMetalCompatibilityKey: @YES,
            (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
        };

        VTDecompressionOutputCallbackRecord cbRecord;
        cbRecord.decompressionOutputCallback = decompressionCallback;
        cbRecord.decompressionOutputRefCon = &frameCtx;

        st = VTDecompressionSessionCreate(
            kCFAllocatorDefault,
            formatDesc,
            nullptr,
            (__bridge CFDictionaryRef)destAttrs,
            &cbRecord,
            &session
        );

        return (st == noErr && session);
    }
};

extern "C" {

void *mac_vtd_create(const char *codec)
{
    MacVtDecoderImpl *impl = new MacVtDecoderImpl();
    impl->codec = codec ? codec : "h264";
    return impl;
}

bool mac_vtd_decode(void *decoder, const uint8_t *data, size_t len, uint64_t time_us, mac_vtd_frame_callback cb, void *ctx)
{
    if (!decoder || !data || len == 0) return false;
    MacVtDecoderImpl *impl = static_cast<MacVtDecoderImpl *>(decoder);
    impl->frameCtx.callback = cb;
    impl->frameCtx.user_ctx = ctx;

    std::vector<NalUnit> nals = extractNalUnits(data, len);
    if (nals.empty()) return false;

    // Check for parameter sets (SPS=7, PPS=8)
    const NalUnit *newSps = nullptr;
    const NalUnit *newPps = nullptr;
    for (const auto &nal : nals) {
        if (nal.type == 7) newSps = &nal;
        else if (nal.type == 8) newPps = &nal;
    }

    if (newSps && newPps) {
        impl->initSession(newSps->data, newSps->size, newPps->data, newPps->size);
    }

    if (!impl->session || !impl->formatDesc) {
        return false;
    }

    // Build AVCC length-prefixed sample block
    size_t avccSize = 0;
    for (const auto &nal : nals) {
        if (nal.type != 7 && nal.type != 8) {
            avccSize += 4 + nal.size;
        }
    }
    if (avccSize == 0) {
        return true; // only headers, no video slice
    }

    std::vector<uint8_t> avccBuffer(avccSize);
    size_t offset = 0;
    for (const auto &nal : nals) {
        if (nal.type != 7 && nal.type != 8) {
            uint32_t beSize = htonl((uint32_t)nal.size);
            memcpy(avccBuffer.data() + offset, &beSize, 4);
            memcpy(avccBuffer.data() + offset + 4, nal.data, nal.size);
            offset += 4 + nal.size;
        }
    }

    CMBlockBufferRef blockBuffer = nullptr;
    OSStatus st = CMBlockBufferCreateWithMemoryBlock(
        kCFAllocatorDefault,
        avccBuffer.data(),
        avccBuffer.size(),
        kCFAllocatorNull,
        nullptr,
        0,
        avccBuffer.size(),
        0,
        &blockBuffer
    );
    if (st != noErr || !blockBuffer) return false;

    CMSampleBufferRef sampleBuffer = nullptr;
    CMSampleTimingInfo timing;
    timing.duration = kCMTimeInvalid;
    timing.presentationTimeStamp = CMTimeMake(time_us, 1000000);
    timing.decodeTimeStamp = kCMTimeInvalid;

    size_t sampleSize = avccBuffer.size();
    st = CMSampleBufferCreateReady(
        kCFAllocatorDefault,
        blockBuffer,
        impl->formatDesc,
        1,
        1,
        &timing,
        1,
        &sampleSize,
        &sampleBuffer
    );

    if (st == noErr && sampleBuffer) {
        VTDecodeFrameFlags flags = kVTDecodeFrame_1xRealTimePlayback;
        VTDecodeInfoFlags infoFlags = 0;
        VTDecompressionSessionDecodeFrame(impl->session, sampleBuffer, flags, nullptr, &infoFlags);
        CFRelease(sampleBuffer);
    }

    CFRelease(blockBuffer);
    return true;
}

void mac_vtd_flush(void *decoder)
{
    if (!decoder) return;
    MacVtDecoderImpl *impl = static_cast<MacVtDecoderImpl *>(decoder);
    if (impl->session) {
        VTDecompressionSessionWaitForAsynchronousFrames(impl->session);
    }
}

void mac_vtd_destroy(void *decoder)
{
    if (!decoder) return;
    delete static_cast<MacVtDecoderImpl *>(decoder);
}

} // extern "C"

