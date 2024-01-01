use std::error::Error;
use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

pub fn transcribe(
    audio_file_samples: Vec<f32>,
    model_path: &str,
) -> Result<String, Box<dyn Error>> {
    let start_time = std::time::Instant::now();

    let mut whisper_params = WhisperContextParameters::new();
    whisper_params.use_gpu = false;
    let ctx =
        WhisperContext::new_with_params(model_path, whisper_params).expect("failed to load model");

    let mut state = ctx.create_state().expect("failed to create state");
    let mut params = FullParams::new(SamplingStrategy::default());

    params.set_suppress_blank(true);

    state
        .full(params, &audio_file_samples)
        .expect("failed to convert samples");

    let mut res: Vec<String> = Vec::new();

    println!(
        "[rust]: number of segments: {}",
        state.full_n_segments().unwrap()
    );

    let num_segments = state
        .full_n_segments()
        .expect("failed to get number of segments");

    for i in 0..num_segments {
        let segment = state
            .full_get_segment_text(i)
            .expect("failed to get segment");
        let start_timestamp = state
            .full_get_segment_t0(i)
            .expect("failed to get start timestamp");
        let end_timestamp = state
            .full_get_segment_t1(i)
            .expect("failed to get end timestamp");

        res.push(segment.clone());
        println!(
            "[whisper]: [{} - {}]: {}",
            start_timestamp, end_timestamp, segment
        );
    }

    let joined_res = res.join("");
    let end_time = std::time::Instant::now();

    println!(
        "[whisper]: transcription done in {}ms",
        (end_time - start_time).as_millis()
    );

    Ok(joined_res)
}
