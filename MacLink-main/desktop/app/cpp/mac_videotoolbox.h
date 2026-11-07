// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <cstdint>
#include <cstddef>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*mac_vtd_frame_callback)(void *ctx, uint32_t width, uint32_t height, const uint8_t *bgrx, size_t bgrx_len);

void *mac_vtd_create(const char *codec);
bool mac_vtd_decode(void *decoder, const uint8_t *data, size_t len, uint64_t time_us, mac_vtd_frame_callback cb, void *ctx);
void mac_vtd_flush(void *decoder);
void mac_vtd_destroy(void *decoder);

#ifdef __cplusplus
}
#endif

