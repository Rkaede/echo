use cpal::{FromSample, Sample};
use log::info;
use rodio::{Decoder, OutputStream, Sink};
use serde_json::Value;
use std::{
    fs::File,
    io::{BufReader, BufWriter},
    sync::{Arc, Mutex},
};

use crate::{config::get, APP};

pub fn wav_spec_from_config(config: &cpal::SupportedStreamConfig) -> hound::WavSpec {
    hound::WavSpec {
        channels: config.channels() as _,
        sample_rate: config.sample_rate().0 as _,
        bits_per_sample: (config.sample_format().sample_size() * 8) as _,
        sample_format: sample_format(config.sample_format()),
    }
}

pub fn sample_format(format: cpal::SampleFormat) -> hound::SampleFormat {
    if format.is_float() {
        hound::SampleFormat::Float
    } else {
        hound::SampleFormat::Int
    }
}

// Arc & Mutex is used to allow the WavWriter to be shared across
// multiple threads, and it ensures that the WavWriter gets cleaned up
// once the last reference is dropped.
type WavWriterHandle = Arc<Mutex<Option<hound::WavWriter<BufWriter<File>>>>>;

// Writes the input data to the WAV writer.
// This function is generic over the input and output sample types.
pub fn write_input_data<T, U>(input: &[T], writer: &WavWriterHandle)
where
    T: Sample,
    U: Sample + hound::Sample + FromSample<T>,
{
    if let Ok(mut guard) = writer.try_lock() {
        if let Some(writer) = guard.as_mut() {
            for &sample in input.iter() {
                let sample: U = U::from_sample(sample);
                writer.write_sample(sample).ok();
            }
        }
    }
}

pub fn play_sound(sound_name: &str) {
    if let Some(value) = get("sound-effects") {
        if value == false {
            info!("[rust]: sound effects turned off");
            return;
        }
    }

    info!("[rust]: playing sound {}", sound_name);

    if let Some(value) = get(sound_name) {
        if value == "none" {
            return;
        }

        let handle = APP.get().unwrap();
        let filename = value.as_str().unwrap();
        let volume_value = get("sound-volume").unwrap_or(Value::from(1));
        let volume = volume_value.as_f64().unwrap_or(1.0) as f32;

        info!("[rust]: playing sound {} with volume {}", filename, volume);

        let file_path = handle
            .path_resolver()
            .resolve_resource(&format!("resources/audio/{}", filename));

        if let None = file_path {
            info!("[rust]: file not found");
            return;
        }

        let file_path = file_path.unwrap().to_owned();

        std::thread::spawn(move || {
            let (_stream, stream_handle) = OutputStream::try_default().unwrap();
            let file = BufReader::new(File::open(file_path).unwrap());
            let source = Decoder::new_mp3(file).unwrap();
            let sink = Sink::try_new(&stream_handle).unwrap();
            sink.set_volume(volume);
            sink.append(source);
            sink.sleep_until_end();
        });
    } else {
        info!("[rust]: sound not found");
    }
}
