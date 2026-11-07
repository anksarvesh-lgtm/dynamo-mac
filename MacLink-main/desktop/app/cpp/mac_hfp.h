// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <cstdint>

#ifdef __cplusplus
extern "C" {
#endif

bool maclink_calls_hfp_publish_sdp(uint8_t rfcomm_channel);
void maclink_calls_hfp_unpublish_sdp();
bool maclink_calls_hfp_connect(const char* device_address);
void maclink_calls_hfp_disconnect();
bool maclink_calls_hfp_is_connected();
bool maclink_calls_hfp_is_sco_active();
void maclink_calls_hfp_route_audio(bool to_mac);
void maclink_calls_hfp_accept();
void maclink_calls_hfp_end();
bool maclink_calls_hfp_dial(const char* number);

#ifdef __cplusplus
}
#endif

