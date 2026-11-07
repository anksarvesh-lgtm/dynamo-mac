// SPDX-License-Identifier: GPL-3.0-or-later
//! macOS image conversion and scaling.

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Bitmap {
    pub width: u32,
    pub height: u32,
    pub bgra: Vec<u8>,
}

pub fn decode(bytes: &[u8]) -> Result<Bitmap, String> {
    if bytes.is_empty() {
        return Err("empty image data".into());
    }
    let out = crate::bridge::native::ffi::decode_image(bytes);
    if out.len() >= 8 {
        let width = u32::from_le_bytes(out[0..4].try_into().unwrap_or([0; 4]));
        let height = u32::from_le_bytes(out[4..8].try_into().unwrap_or([0; 4]));
        let bgra = out[8..].to_vec();
        Ok(Bitmap { width, height, bgra })
    } else {
        Err("failed to decode image".into())
    }
}

pub fn encode_png(bitmap: &Bitmap) -> Result<Vec<u8>, String> {
    Ok(create_png(bitmap.width, bitmap.height, &bitmap.bgra))
}

#[allow(dead_code)]
pub fn bmp_from_dib(dib: &[u8]) -> Option<Vec<u8>> {
    Some(dib.to_vec())
}

pub fn scale_to(bitmap: &Bitmap, max: u32) -> Bitmap {
    let longest = bitmap.width.max(bitmap.height);
    if longest <= max || longest == 0 {
        return bitmap.clone();
    }
    let scale = f64::from(max) / f64::from(longest);
    let width = ((f64::from(bitmap.width) * scale).round() as u32).max(1);
    let height = ((f64::from(bitmap.height) * scale).round() as u32).max(1);
    let mut bgra = Vec::with_capacity((width * height * 4) as usize);
    for y in 0..height {
        let (y0, y1) = (
            y * bitmap.height / height,
            ((y + 1) * bitmap.height / height).max(y * bitmap.height / height + 1),
        );
        for x in 0..width {
            let (x0, x1) = (
                x * bitmap.width / width,
                ((x + 1) * bitmap.width / width).max(x * bitmap.width / width + 1),
            );
            let mut sum = [0u32; 4];
            for sy in y0..y1 {
                for sx in x0..x1 {
                    let i = ((sy * bitmap.width + sx) * 4) as usize;
                    if i + 4 <= bitmap.bgra.len() {
                        for (total, &value) in sum.iter_mut().zip(&bitmap.bgra[i..i + 4]) {
                            *total += u32::from(value);
                        }
                    }
                }
            }
            let count = (y1 - y0) * (x1 - x0);
            if count > 0 {
                for total in sum {
                    bgra.push(total.checked_div(count).unwrap_or(0) as u8);
                }
            } else {
                bgra.extend_from_slice(&[0, 0, 0, 255]);
            }
        }
    }
    Bitmap { width, height, bgra }
}

fn create_png(width: u32, height: u32, bgra: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    out.extend_from_slice(b"\x89PNG\r\n\x1a\n");
    let mut ihdr = Vec::new();
    ihdr.extend_from_slice(&width.to_be_bytes());
    ihdr.extend_from_slice(&height.to_be_bytes());
    ihdr.push(8);
    ihdr.push(6); // RGBA
    ihdr.push(0);
    ihdr.push(0);
    ihdr.push(0);
    write_chunk(&mut out, b"IHDR", &ihdr);

    let mut raw = Vec::with_capacity((height * (width * 4 + 1)) as usize);
    for y in 0..height {
        raw.push(0);
        let row_start = (y * width * 4) as usize;
        let row_end = row_start + (width * 4) as usize;
        if row_end <= bgra.len() {
            for pixel in bgra[row_start..row_end].as_chunks::<4>().0 {
                raw.push(pixel[2]); // R
                raw.push(pixel[1]); // G
                raw.push(pixel[0]); // B
                raw.push(pixel[3]); // A
            }
        }
    }

    let mut zlib = Vec::new();
    zlib.push(0x78);
    zlib.push(0x01);

    for (i, chunk) in raw.chunks(65535).enumerate() {
        let is_last = i + 1 == raw.chunks(65535).len();
        zlib.push(if is_last { 0x01 } else { 0x00 });
        let len = chunk.len() as u16;
        let nlen = !len;
        zlib.extend_from_slice(&len.to_le_bytes());
        zlib.extend_from_slice(&nlen.to_le_bytes());
        zlib.extend_from_slice(chunk);
    }
    let mut s1: u32 = 1;
    let mut s2: u32 = 0;
    for &b in &raw {
        s1 = (s1 + b as u32) % 65521;
        s2 = (s2 + s1) % 65521;
    }
    let adler = (s2 << 16) | s1;
    zlib.extend_from_slice(&adler.to_be_bytes());

    write_chunk(&mut out, b"IDAT", &zlib);
    write_chunk(&mut out, b"IEND", &[]);
    out
}

fn write_chunk(out: &mut Vec<u8>, tag: &[u8; 4], data: &[u8]) {
    out.extend_from_slice(&(data.len() as u32).to_be_bytes());
    out.extend_from_slice(tag);
    out.extend_from_slice(data);
    let mut crc = 0xffff_ffff_u32;
    for &b in tag.iter().chain(data.iter()) {
        crc ^= b as u32;
        for _ in 0..8 {
            if crc & 1 != 0 {
                crc = (crc >> 1) ^ 0xedb8_8320;
            } else {
                crc >>= 1;
            }
        }
    }
    out.extend_from_slice(&(crc ^ 0xffff_ffff_u32).to_be_bytes());
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decode_rejects_empty_data() {
        assert!(decode(&[]).is_err());
    }

    #[test]
    fn encode_and_decode_roundtrip_preserves_pixels() {
        let original = Bitmap {
            width: 2,
            height: 2,
            bgra: vec![
                255, 0, 0, 255, // blue
                0, 255, 0, 255, // green
                0, 0, 255, 255, // red
                255, 255, 255, 255, // white
            ],
        };
        let png = encode_png(&original).expect("encode_png failed");
        let decoded = decode(&png).expect("decode failed");
        assert_eq!(decoded.width, 2);
        assert_eq!(decoded.height, 2);
        assert_eq!(decoded.bgra.len(), 16);
        assert_eq!(decoded.bgra, original.bgra);
    }
}
