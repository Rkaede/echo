use crate::audio;
use crate::paste::paste;
use crate::whisper;
use cpal::{
    traits::{DeviceTrait, HostTrait, StreamTrait},
    SampleFormat,
};
use crossbeam_channel::Receiver;
use hound::WavReader;
use log::{error, info};
use samplerate_rs::{convert, ConverterType};
use std::{error::Error, path::Path};
use std::{
    panic,
    sync::{Arc, Mutex},
};
use tauri::{AppHandle, Manager};

pub struct Record {
    app_handle: AppHandle,
    enable_paste: bool
}

// the payload type must implement `Serialize` and `Clone`.
#[derive(Clone, serde::Serialize)]
struct Payload {
  status: String
}

impl Record {
    pub fn new(app_handle: AppHandle) -> Self {
        Self { app_handle, enable_paste: true }
    }

    pub fn start(&self, model: String, stop_record_rx: Receiver<()>) -> Result<(), Box<dyn Error>> {
        self.app_handle.emit_all("change_status", Payload { status: "recording".to_string()}).unwrap();
        let host = cpal::default_host();
        let device = host
            .default_input_device()
            .ok_or("No default input device")?;

        println!("[rust]: device {:?}", device.name());
        let config = device.default_input_config()?;

        println!("[rust]: config {:?}", config);

        let spec = audio::wav_spec_from_config(&config);
        let data_dir = self
            .app_handle
            .path_resolver()
            .app_data_dir()
            .ok_or("Failed to get app data directory")?;

        info!("[rust]: data_dir - {}", data_dir.to_str().unwrap());

        let wav_path = format!("{}/recorded.wav", data_dir.to_str().unwrap());

        let writer = hound::WavWriter::create(&wav_path, spec)?;

        // Allow safe shared access to the writer from multiple
        // threads.
        let writer = Arc::new(Mutex::new(Some(writer)));

        // By cloning writer, you create a new reference to the same
        // data that can be moved into the closure, allowing the
        // original writer to still be used elsewhere in the code.
        let writer_clone = writer.clone();

        info!("[rust]: start recording {}", config.sample_format());

        let err_fn = move |err| {
            error!("[rust]: an error occurred on stream: {}", err);
        };

        let stream = match config.sample_format() {
            SampleFormat::F32 => device.build_input_stream(
                &config.into(),
                move |data, _: &_| audio::write_input_data::<f32, f32>(data, &writer_clone),
                err_fn,
                None,
            ),
            SampleFormat::U16 => device.build_input_stream(
                &config.into(),
                move |data, _: &_| audio::write_input_data::<u16, i16>(data, &writer_clone),
                err_fn,
                None,
            ),
            SampleFormat::I16 => device.build_input_stream(
                &config.into(),
                move |data, _: &_| audio::write_input_data::<i16, i16>(data, &writer_clone),
                err_fn,
                None,
            ),
            _ => panic!("Unsupported sample format"),
        }
        .expect("Could not build stream");

        // start the audio stream, beginning the recording process
        stream.play().expect("Could not play stream");

        // thread will be blocked here until the message is received
        stop_record_rx
            .recv()
            .expect("failed to receive the message");

        // drop the stream and writer to close the file
        drop(stream);
        drop(writer);

        self.app_handle.emit_all("change_status", Payload { status: "transcribing".to_string()}).unwrap();

        let out_path = Path::new(&wav_path);

        // Check if the file exists and is accessible
        if !out_path.exists() || !out_path.is_file() {
            error!("[rust]: File does not exist or is not accessible");
        }

        // Check if the file is a valid, non-empty WAV file
        let reader = match WavReader::open(out_path) {
            Ok(reader) => reader,
            Err(e) => {
                error!("[rust]: Failed to read file: {}", e);
                return Err(Box::new(e));
            }
        };

        // Print out the specifications of the WAV file
        let spec = reader.spec();
        info!("[rust]: WAV file specifications: {:?}", spec);

        // Read the samples and handle any errors
        let audio_file_samples = reader
            .into_samples::<f32>()
            .map(|x| x.expect("sample"))
            .collect::<Vec<_>>();

        info!("[rust]: audio_file_samples: {:?}", audio_file_samples.len());

        let audio_data = convert(
            spec.sample_rate,
            16000,
            1,
            ConverterType::SincBestQuality,
            &audio_file_samples,
        )
        .unwrap();

        let model_path_base: &str = &format!("resources/models/ggml-{}.bin", model);
        println!("[rust]: model_path_base {}", model_path_base);

        let model_path_buf = self
            .app_handle
            .path_resolver()
            .resolve_resource(model_path_base)
            .expect("failed to resolve model path");
        let model_path = model_path_buf.to_str().unwrap();

        let text = whisper::transcribe(audio_data, model_path)?;
        if self.enable_paste {
            let _ = paste(&text);
        }
        self.app_handle.emit_all("change_status", Payload { status: "idle".to_string()}).unwrap();

        Ok(())
    }
}
