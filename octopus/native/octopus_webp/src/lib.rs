use std::ops::Deref;

use rustler::{NifResult, NifStruct, OwnedBinary};
use webp_animation::{ColorMode, Decoder};

type Frame = (Vec<Vec<u8>>, i32);

#[derive(Default, NifStruct)]
#[module = "Octopus.WebP"]
struct Animation {
    frames: Vec<Frame>,
    size: (u32, u32),
}

#[rustler::nif]
fn decode_animation(path: &str) -> Option<Animation> {
    let buffer = std::fs::read(path).ok()?;
    let decoder = Decoder::new(&buffer).ok()?;

    let mut animation = Animation::default();

    for frame in decoder.into_iter() {
        animation.size = frame.dimensions();
        match frame.color_mode() {
            ColorMode::Rgb => {
                let rgb = frame.data().chunks_exact(3).map(|x| x.to_vec()).collect();
                let frame = (rgb, frame.timestamp());
                animation.frames.push(frame);
            }
            ColorMode::Rgba => {
                let rgb = frame
                    .data()
                    .chunks_exact(4)
                    .map(|x| x[0..3].to_vec())
                    .collect();
                let frame = (rgb, frame.timestamp());
                animation.frames.push(frame);
            }
            ColorMode::Bgr => {
                let rgb = frame
                    .data()
                    .chunks_exact(3)
                    .map(|bgr| vec![bgr[2], bgr[1], bgr[0]])
                    .collect();
                let frame = (rgb, frame.timestamp());
                animation.frames.push(frame);
            }
            ColorMode::Bgra => {
                let rgb = frame
                    .data()
                    .chunks_exact(4)
                    .map(|bgr| vec![bgr[2], bgr[1], bgr[0]])
                    .collect();
                let frame = (rgb, frame.timestamp());
                animation.frames.push(frame);
            }
        }
    }

    Some(animation)
}

#[rustler::nif]
fn encode_rgb(rgb_pixels: Vec<u8>, width: usize, height: usize) -> NifResult<OwnedBinary> {
    let encoder = webp::Encoder::new(
        &rgb_pixels,
        webp::PixelLayout::Rgb,
        width as u32,
        height as u32,
    );
    let webp = encoder.encode_lossless();
    let webp_bytes = webp.deref();

    let mut binary = OwnedBinary::new(webp_bytes.len())
        .ok_or_else(|| rustler::Error::Term(Box::new("no mem")))?;

    for (i, byte) in binary.as_mut_slice().iter_mut().enumerate() {
        *byte = webp_bytes[i]
    }

    Ok(binary)
}

rustler::init!("Elixir.Octopus.WebP", [decode_animation, encode_rgb]);
