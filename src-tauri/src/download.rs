use futures_util::StreamExt;
use std::cmp::min;
use std::fs::File;
use std::io::Write;
use tauri::{AppHandle, Manager};

#[derive(Debug, Clone, serde::Serialize)]
pub struct Progress {
    pub model_id: String,
    pub progress: f64,
    pub in_progress: bool,
}

pub struct WhisperModelDownloader {
    app_handle: AppHandle,
}

impl WhisperModelDownloader {
    pub fn new(app_handle: AppHandle) -> Self {
        Self { app_handle }
    }

    #[tokio::main]
    pub async fn download(&self, url: &str, path: &str, model_id: &str) {
        println!("Downloading {}", model_id);
        let res = reqwest::get(url).await.unwrap();

        let total_size = res
            .content_length()
            .ok_or(format!("Failed to get content length from '{}'", url))
            .unwrap();

        let _ = &self.app_handle.emit_all(
            "downloadWhisperProgress",
            Progress {
                model_id: model_id.to_string(),
                progress: 0.0,
                in_progress: true,
            },
        );

        let mut file;
        let mut downloaded: u64 = 0;
        let mut stream = res.bytes_stream();

        println!("Seeking in file.");

        if std::path::Path::new(&path).exists() {
            println!("File exists. Removing...");
            let _ = std::fs::remove_file(&path);
        }

        file = File::create(&path)
            .or(Err(format!("Failed to create file '{}'", &path)))
            .unwrap();

        println!("Commencing transfer");
        let mut rate = 0.0;

        while let Some(item) = stream.next().await {
            let chunk = item
                .or(Err(format!("Error while downloading file")))
                .unwrap();
            file.write(&chunk)
                .or(Err(format!("Error while writing to file")))
                .unwrap();
            let new = min(downloaded + (chunk.len() as u64), total_size);
            downloaded = new;

            let current_rate = ((new as f64 * 100.0) / total_size as f64).round();
            if rate != current_rate {
                let _ = &self.app_handle.emit_all(
                    "download-progress",
                    Progress {
                        model_id: model_id.to_string(),
                        progress: current_rate,
                        in_progress: true,
                    },
                );
                rate = current_rate
            }
        }

        let _ = &self.app_handle.emit_all(
            "download-progress",
            Progress {
                model_id: model_id.to_string(),
                progress: rate,
                in_progress: false,
            },
        );
    }
}
