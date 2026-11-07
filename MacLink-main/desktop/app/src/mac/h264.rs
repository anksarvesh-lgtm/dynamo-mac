// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS H.264 video decoding using VideoToolbox hardware acceleration.
#![allow(unsafe_code)]

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub struct Colors {
    pub bt601: bool,
    pub full_range: bool,
}

#[derive(Debug, Clone)]
#[allow(dead_code)]
pub struct Picture {
    pub width: u32,
    pub height: u32,
    pub stride: usize,
    pub plane_rows: usize,
    pub nv12: Vec<u8>,
    pub colors: Colors,
    pub bgrx: Vec<u8>,
}

unsafe extern "C" {
    fn mac_vtd_create(codec: *const std::ffi::c_char) -> *mut std::ffi::c_void;
    fn mac_vtd_decode(
        decoder: *mut std::ffi::c_void,
        data: *const u8,
        len: usize,
        time_us: u64,
        cb: extern "C" fn(*mut std::ffi::c_void, u32, u32, *const u8, usize),
        ctx: *mut std::ffi::c_void,
    ) -> bool;
    fn mac_vtd_flush(decoder: *mut std::ffi::c_void);
    fn mac_vtd_destroy(decoder: *mut std::ffi::c_void);
}

pub struct Decoder {
    codec: String,
    raw: *mut std::ffi::c_void,
}

unsafe impl Send for Decoder {}

impl Default for Decoder {
    fn default() -> Self {
        Self::new_for_codec("h264")
            .unwrap_or_else(|_| Self { codec: "h264".into(), raw: std::ptr::null_mut() })
    }
}

impl Decoder {
    pub fn new_for_codec(codec: &str) -> Result<Decoder, String> {
        let c_codec = std::ffi::CString::new(codec).map_err(|e| e.to_string())?;
        let raw = unsafe { mac_vtd_create(c_codec.as_ptr()) };
        if raw.is_null() {
            return Err("failed to create VideoToolbox decoder".into());
        }
        Ok(Decoder { codec: codec.to_string(), raw })
    }

    pub fn new_gpu(codec: &str) -> Result<Decoder, String> {
        Self::new_for_codec(codec)
    }

    pub fn on_gpu(&self) -> bool {
        true
    }

    pub fn codec(&self) -> &str {
        &self.codec
    }

    pub fn decode(&mut self, data: &[u8], time_us: u64) -> Result<Vec<Picture>, String> {
        if self.raw.is_null() {
            return Err("decoder not initialized".into());
        }
        let mut pictures: Vec<Picture> = Vec::new();

        extern "C" fn on_frame(
            ctx: *mut std::ffi::c_void,
            width: u32,
            height: u32,
            bgrx_ptr: *const u8,
            bgrx_len: usize,
        ) {
            let out = unsafe { &mut *(ctx as *mut Vec<Picture>) };
            let slice = unsafe { std::slice::from_raw_parts(bgrx_ptr, bgrx_len) };
            out.push(Picture {
                width,
                height,
                stride: (width * 4) as usize,
                plane_rows: height as usize,
                nv12: Vec::new(),
                colors: Colors::default(),
                bgrx: slice.to_vec(),
            });
        }

        let ok = unsafe {
            mac_vtd_decode(
                self.raw,
                data.as_ptr(),
                data.len(),
                time_us,
                on_frame,
                &mut pictures as *mut Vec<Picture> as *mut std::ffi::c_void,
            )
        };
        if !ok {
            return Err("VideoToolbox decode failed".into());
        }
        Ok(pictures)
    }

    pub fn flush(&mut self) {
        if !self.raw.is_null() {
            unsafe { mac_vtd_flush(self.raw) };
        }
    }
}

impl Drop for Decoder {
    fn drop(&mut self) {
        if !self.raw.is_null() {
            unsafe { mac_vtd_destroy(self.raw) };
            self.raw = std::ptr::null_mut();
        }
    }
}

pub fn to_bgrx(picture: &Picture, width: u32, height: u32) -> Vec<u8> {
    if !picture.bgrx.is_empty() {
        return picture.bgrx.clone();
    }
    let (w, h) = (width.min(picture.width) as usize, height.min(picture.height) as usize);
    vec![0; w * h * 4]
}

#[allow(dead_code)]
pub fn ensure_mf_started() -> Result<(), String> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn h264_decoder_creates_successfully_on_macos() {
        let dec = Decoder::new_for_codec("h264");
        assert!(dec.is_ok(), "VideoToolbox decoder creation should succeed on macOS");
        let dec = dec.unwrap();
        assert!(dec.on_gpu());
        assert_eq!(dec.codec(), "h264");
    }

    #[test]
    fn h264_decode_handles_empty() {
        let mut decoder = Decoder::default();
        assert!(decoder.decode(&[], 0).is_err());
    }
}
