use rustler::NifStruct;
use webp_animation::{ColorMode, Decoder};

type Frame = (Vec<Vec<u8>>, i32);

#[derive(Default, NifStruct)]
#[module = "Octopus.WebP"]
struct Animation {
    frames: Vec<Frame>,
    size: (u32, u32),
}

#[rustler::nif]
fn decode(path: &str) -> Option<Animation> {
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

rustler::init!("Elixir.Octopus.WebP", [decode]);
